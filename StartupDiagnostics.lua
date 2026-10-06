-- Opt-in startup capture. SavedVariables are only ready at ADDON_LOADED.
-- Before then retain explicit watch registrations, but install no probes and
-- read no clocks/metrics. Disabled sessions discard this short-lived registry.
local addonName, ns = ...
-- Explicit addon-owned frame metadata only. No clocks, hooks or timers until
-- a capture is requested. Reuse entries when a script is installed again.
ns.PerfFrames = {}
function ns.PerfWatchFrame(name, target, script)
  if not target then return end
  local found = false
  for _, entry in ipairs(ns.PerfFrames) do
    if entry.frame == target and entry.script == script then found = true; break end
  end
  if not found and #ns.PerfFrames < 64 then
    ns.PerfFrames[#ns.PerfFrames + 1] = {name=name, frame=target, script=script}
  end
  if ns.StartupWatchFrame then ns.StartupWatchFrame(name, target, script) end
end
-- Owned local functions only; registration itself never reads clocks or wraps calls.
-- Accessors let a bounded manual capture restore the exact original closure.
ns.PerfFunctions = {}
function ns.PerfWatchFunction(name, get, set)
  if type(name) ~= "string" or type(get) ~= "function" or type(set) ~= "function" then return end
  for _, entry in ipairs(ns.PerfFunctions) do if entry.name == name then return end end
  if #ns.PerfFunctions < 64 then ns.PerfFunctions[#ns.PerfFunctions + 1] = {name=name, get=get, set=set} end
end
local bootstrap
local pending = {}
for _, method in ipairs({"StartupWatchFrame", "StartupWatchSlot", "StartupTimerScope"}) do
  local key = method
  ns[key] = function(name, target, argument)
    pending[#pending + 1] = {method=key, name=name, target=target, argument=argument}
  end
end

local function StartCapture(queued)
if type(debugprofilestop) ~= "function" then return end

local function Number(v)
  if issecretvalue and issecretvalue(v) then return false end
  return type(v) == "number" and v == v and v >= 0 and v < math.huge
end

local epoch, lastClock = 0, nil
local function Stamp()
  local ok, value = pcall(function()
    local n = debugprofilestop()
    if Number(n) then return n end
  end)
  if not ok or value == nil then epoch = epoch + 1; return end
  if lastClock and value < lastClock then epoch = epoch + 1 end
  lastClock = value
  return value
end
local first = Stamp()
if first == nil then return end
local result = {status="loading", load={}, init={}, native={}, callbacks={}, slow={}, skipped={},
  traceSkipped=0, traceChanged=0, traceDropped=0}
result.loadUnavailable = true -- no timing before the saved opt-in was known
ns.StartupResult = result
local live, frame, ticker = true, bootstrap, nil
local Stop, pendingStop
local tickActive, callbackDepth = false, 0
local interval, previousInterval, previousValid, pendingSample
local tickTrace = {status="waiting-login", observations=0, slowObserved=0, slow={},
  probeCalls=0, probeTotal=0, probeMax=0, probeInvalid=0}
result.tickTrace = tickTrace
local loadStart = {at=first, epoch=epoch}
local ticks, worldTick, loginSeen = 0, nil, false
local loginAt, worldAt
-- Precise wall time advances within long frames; never mix its units with
-- debugprofilestop durations. GetTime is the older-client fallback.
local wallClock = GetTimePreciseSec or GetTime
local function WallTime()
  local ok, value = pcall(function() local n = wallClock(); if Number(n) then return n end end)
  if ok then return value end
end
local wallOrigin = WallTime()
local function Since(now, origin)
  if now and origin and now >= origin then return now - origin end
end

local function Begin()
  local at = Stamp()
  return {at=at, epoch=epoch}
end
local function End(token, ok)
  local at = Stamp()
  local row = {ok=ok}
  if token and token.at and at and token.epoch == epoch and at >= token.at then
    row.ms = at - token.at
  else row.invalid = true end
  return row
end
function ns.StartupCheckpoint(name)
  if not live then return end
  local row = End(loadStart)
  row.name = name
  if #result.load < 32 then result.load[#result.load + 1] = row end
  loadStart = Begin()
end
ns.StartupBegin = Begin
function ns.StartupEnd(name, token, ok)
  if not live then return end
  local row = End(token, ok)
  row.name = name
  if name == "PLAYER_LOGIN" then
    result.login = row
    if pendingStop then Stop(pendingStop) end
  elseif #result.init < 32 then result.init[#result.init + 1] = row end
end

-- Temporary, explicit addon-owned entry points. No enumeration, global API
-- replacement or secure-script hooks. Stop restores originals by identity.
local watches, timerScopes, callbackIndex = {}, {}, {}
local function Skip(name, reason)
  result.traceSkipped = result.traceSkipped + 1
  -- Keep only bounded labels/reasons, never frame references or error payloads.
  name = type(name) == "string" and name:sub(1, 128) or "?"
  for _, row in ipairs(result.skipped) do
    if row.name == name and row.reason == reason then row.count = row.count + 1; return end
  end
  if #result.skipped >= 16 then result.traceDropped = result.traceDropped + 1; return end
  result.skipped[#result.skipped + 1] = {name=name, reason=reason, count=1}
end
local function CallbackRow(name)
  local row = callbackIndex[name]
  if row then return row end
  if #result.callbacks >= 128 then result.traceDropped = result.traceDropped + 1; return end
  row = {name=name, calls=0, completed=0, errors=0, invalid=0, total=0, maximum=0,
    windowCalls=0, windowMax=0}
  callbackIndex[name] = row
  result.callbacks[#result.callbacks + 1] = row
  return row
end
local function Record(row, token, at, ok, duration)
  if not live or not row then return end
  duration = duration or End(token, ok)
  row.completed = row.completed + 1
  if not ok then row.errors = row.errors + 1 end
  if not duration.ms then row.invalid = row.invalid + 1; return end
  local ms = duration.ms
  row.total = row.total + ms
  if ms >= row.maximum then row.maximum, row.maxAt = ms, at end
  row.windowCalls = row.windowCalls + 1
  if ms >= row.windowMax then row.windowMax, row.windowAt = ms, at end
  if ms >= 5 then
    local slow = result.slow
    if #slow < 12 or ms > slow[#slow].ms then
      slow[#slow + 1] = {name=row.name, ms=ms, at=at, ok=ok}
      table.sort(slow, function(a,b) return a.ms > b.ms end)
      if #slow > 12 then slow[#slow] = nil end
    end
  end
end
-- Sum only outermost covered entries, not a parent plus its nested children.
-- Intervals are bounded by OUR observations, not claimed native/UI frame IDs.
local function RecordOuter(row, duration, at)
  if not tickActive then return end
  interval.calls = interval.calls + 1
  if not duration.ms then interval.invalid = interval.invalid + 1; return end
  interval.total = interval.total + duration.ms
  if duration.ms >= interval.maximum then
    interval.maximum, interval.maxName, interval.maxAt = duration.ms, row.name, at
  end
end
local function Pack(...) return {n=select("#", ...), ...} end
local function Wrap(name, original, isEvent)
  return function(...)
    if not live then return original(...) end
    local label = name
    if isEvent then
      local event = select(2, ...)
      -- Never keep event payloads (units, names, items or secret values).
      if not (issecretvalue and issecretvalue(event)) and type(event) == "string" and #event <= 64 then
        label = name .. "/" .. event
      end
    end
    local row = CallbackRow(label)
    if not row then return original(...) end
    row.calls = row.calls + 1
    local at = Since(WallTime(), wallOrigin)
    local token = Begin()
    local outer = callbackDepth == 0
    callbackDepth = callbackDepth + 1
    local returns = Pack(pcall(original, ...))
    callbackDepth = callbackDepth - 1
    if live then
      local duration = End(token, returns[1])
      Record(row, token, at, returns[1], duration)
      if outer then RecordOuter(row, duration, at) end
    end
    if not returns[1] then error(returns[2], 0) end
    return unpack(returns, 2, returns.n)
  end
end
local function Watch(name, get, set, isEvent)
  if not live then return end
  local ok, original = pcall(get)
  if not ok or type(original) ~= "function" then return end
  for _, entry in ipairs(watches) do if entry.wrapper == original then return end end
  if #watches >= 64 then result.traceDropped = result.traceDropped + 1; return end
  local wrapper = Wrap(name, original, isEvent)
  if pcall(set, wrapper) then
    watches[#watches + 1] = {name=name, get=get, set=set, original=original, wrapper=wrapper}
  else Skip(name, "install-failed") end
end
function ns.StartupWatchFrame(name, target, script)
  if not live or not target then return end
  local label = name .. "/" .. script
  local ok, protected = pcall(function() return target.IsProtected and target:IsProtected() end)
  if not ok then Skip(label, "protection-check-failed"); return end
  if protected then Skip(label, "protected"); return end
  Watch(label, function() return target:GetScript(script) end, function(fn)
    if target.IsProtected and target:IsProtected() then error("protected startup script") end
    target:SetScript(script, fn)
  end, script == "OnEvent")
end
function ns.StartupWatchSlot(name, target, key)
  if not live or not target then return end
  Watch(name, function() return target[key] end, function(fn) target[key] = fn end)
end
function ns.StartupTimerScope(name, api, replace)
  if not live or not api or type(api.After) ~= "function" then return end
  if #timerScopes >= 8 then result.traceDropped = result.traceDropped + 1; return end
  local proxy = setmetatable({}, {__index=api})
  proxy.After = function(delay, fn)
    if not live or type(fn) ~= "function" then return api.After(delay, fn) end
    -- One-shot callbacks expire naturally. Their original delay is unchanged;
    -- pending callbacks still run normally if capture ends before they fire.
    local label = name .. "/After(" .. (Number(delay) and tostring(delay) or "?") .. ")"
    return api.After(delay, Wrap(label, fn))
  end
  replace(proxy)
  timerScopes[#timerScopes + 1] = {replace=replace, original=api}
end
local function RestoreWatches()
  for i=#watches,1,-1 do
    local entry = watches[i]
    local ok, current = pcall(entry.get)
    if ok and current == entry.wrapper then
      if not pcall(entry.set, entry.original) then Skip(entry.name, "restore-failed") end
    else result.traceChanged = result.traceChanged + 1 end
    watches[i] = nil
  end
  for i=#timerScopes,1,-1 do
    local entry = timerScopes[i]
    pcall(entry.replace, entry.original)
    timerScopes[i] = nil
  end
  callbackIndex = nil
end
local function WindowRows()
  local rows = {}
  for _, row in ipairs(result.callbacks) do
    if row.windowCalls > 0 then
      rows[#rows + 1] = {name=row.name, calls=row.windowCalls, ms=row.windowMax, at=row.windowAt}
    end
    row.windowCalls, row.windowMax, row.windowAt = 0, 0, nil
  end
  table.sort(rows, function(a,b) return a.ms > b.ms end)
  for i=#rows,4,-1 do rows[i] = nil end
  return rows
end

local function NativePercent(name)
  local api, metrics = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
  local metric = metrics and metrics[name]
  if not api or metric == nil or (api.IsEnabled and not api.IsEnabled()) then return end
  local app, overall, own = api.GetApplicationMetric(metric), api.GetOverallMetric(metric), api.GetAddOnMetric(addonName, metric)
  if not Number(app) or not Number(overall) or not Number(own) then return end
  local denominator = app - overall + own
  if denominator > 0 and denominator < math.huge then
    return {own=own, denominator=denominator, percent=own / denominator * 100}
  end
end
local function NativeOwn(name)
  local api, metrics = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
  local metric = metrics and metrics[name]
  if not api or metric == nil or (api.IsEnabled and not api.IsEnabled()) then return end
  local value = api.GetAddOnMetric(addonName, metric)
  if Number(value) then return value end
end
-- LastTime is "total time in the most recent tick" (milliseconds). The API
-- supplies no tick ID or documented alignment to our OnUpdate. Keep adjacent
-- observation intervals as context; NEVER subtract or call them attribution.
-- Two reusable work rows; only the largest eight slow observations are copied.
local function ClearInterval(row, at)
  row.fromAt, row.toAt = at, nil
  row.calls, row.total, row.invalid, row.maximum = 0, 0, 0, 0
  row.maxName, row.maxAt = nil, nil
end
local function CopyInterval(row)
  local copy = {}
  for k,v in pairs(row) do copy[k] = v end
  return copy
end
local function StopTickTrace(status)
  if not tickActive then
    if tickTrace.status == "waiting-login" then tickTrace.status = status end
    return
  end
  tickActive = false
  tickTrace.status = status
  if frame then frame:SetScript("OnUpdate", nil) end
  interval, previousInterval, pendingSample = nil, nil, nil
end
local function TickTraceDeadline(now)
  if not tickActive then return end
  local worldSeconds, loginSeconds = Since(now, worldAt), Since(now, loginAt)
  if worldSeconds and worldSeconds >= 5 then return "complete" end
  if loginSeconds and loginSeconds >= 20 then return "login-timeout" end
  if tickTrace.observations >= 2048 then return "observation-limit" end
end
local function ObserveTick()
  local now = WallTime()
  local deadline = TickTraceDeadline(now)
  if deadline then StopTickTrace(deadline); return end
  local at = Since(now, wallOrigin)
  interval.toAt = at
  -- Finish the following context of the previous retained slow observation.
  if pendingSample then pendingSample.after = CopyInterval(interval); pendingSample = nil end
  tickTrace.observations = tickTrace.observations + 1
  local ms = NativeOwn("LastTime")
  if ms == nil then StopTickTrace("unavailable"); return end
  local sample
  if ms >= 5 then
    tickTrace.slowObserved = tickTrace.slowObserved + 1
    local slow = tickTrace.slow
    if #slow < 8 or ms > slow[#slow].ms then
      sample = {observation=tickTrace.observations, at=at, worldSeconds=Since(now, worldAt), ms=ms,
        before=previousValid and CopyInterval(previousInterval) or nil, near=CopyInterval(interval)}
      slow[#slow + 1] = sample
      table.sort(slow, function(a,b) return a.ms > b.ms end)
      if #slow > 8 then slow[#slow] = nil end
      pendingSample = sample
    end
  end
  interval, previousInterval = previousInterval, interval
  previousValid = true
  ClearInterval(interval, at)
  return sample
end
local function OnTickUpdate()
  if not tickActive then return end
  local token = Begin()
  -- Diagnostic/API failures must never escape into addon business callbacks.
  local ok, sample = pcall(ObserveTick)
  local duration = End(token, ok)
  tickTrace.probeCalls = tickTrace.probeCalls + 1
  if duration.ms then
    tickTrace.probeTotal = tickTrace.probeTotal + duration.ms
    tickTrace.probeMax = math.max(tickTrace.probeMax, duration.ms)
  else tickTrace.probeInvalid = tickTrace.probeInvalid + 1 end
  if ok and sample then sample.probeMs = duration.ms end
  if not ok then StopTickTrace("error") end
end
local function StartTickTrace()
  local ok, available = pcall(function()
    return C_AddOnProfiler and type(C_AddOnProfiler.GetAddOnMetric) == "function"
      and Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.LastTime ~= nil
      and (not C_AddOnProfiler.IsEnabled or C_AddOnProfiler.IsEnabled())
  end)
  if not ok or not available then tickTrace.status = "unavailable"; return end
  interval, previousInterval = {}, {}
  ClearInterval(interval, Since(loginAt, wallOrigin))
  ClearInterval(previousInterval)
  previousValid = false
  tickActive, tickTrace.status = true, "running"
  frame:SetScript("OnUpdate", OnTickUpdate)
end

local ownMetrics = {peak="PeakTime", over1="CountTimeOver1Ms", over5="CountTimeOver5Ms", over10="CountTimeOver10Ms"}
local function Snapshot(name)
  if not live or #result.native >= 64 then return end
  local now = WallTime()
  local row = {name=name, tick=ticks, at=Since(now, wallOrigin), worldSeconds=Since(now, worldAt)}
  -- This callback window ends BEFORE reading native metrics. Metric reads may
  -- affect a later tick, not necessarily the observation being read here.
  row.window = WindowRows()
  local probe = CallbackRow("Probe/NativeRead")
  if probe then probe.calls = probe.calls + 1 end
  local readStamp = Begin()
  for key, metric in pairs({session="SessionAverageTime", recent="RecentAverageTime"}) do
    local ok, value = pcall(NativePercent, metric)
    if ok then row[key] = value end
  end
  for key, metric in pairs(ownMetrics) do
    local ok, value = pcall(NativeOwn, metric)
    if ok then row[key] = value end
  end
  local readDuration = End(readStamp, true)
  row.readMs, row.readInvalid = readDuration.ms, readDuration.invalid
  Record(probe, readStamp, row.at, true, readDuration)
  local previous = result.native[#result.native]
  if previous then
    row.delta = {}
    for _, key in ipairs({"over1", "over5", "over10"}) do
      if row[key] ~= nil and previous[key] ~= nil then
        if row[key] >= previous[key] then row.delta[key] = row[key] - previous[key]
        else row.reset = true end
      end
    end
    if row.peak and previous.peak then
      if row.peak < previous.peak then row.reset = true
      elseif row.peak > previous.peak then row.newPeak = true end
    end
  end
  result.native[#result.native + 1] = row
end

-- Reporting retains only plain measurements; no module/frame/callback references.
local function Value(n, decimals)
  return n ~= nil and string.format("%." .. (decimals or 3) .. "f", n) or "N/A"
end
local function Say(text, ...)
  print("|cff66ccffBMPerf|r " .. string.format(text, ...))
end
local function PrintResult(full)
  local T = ns.L
  if not T then return end
  Say(T["启动诊断：%s；登录后采样 %d 次，采样结束后不再后台运行。"], result.status, ticks)
  if result.loadUnavailable then Say(T["采集从存档加载完成后开始；未测量本次文件加载耗时。"]) end
  local function Rows(label, rows)
    local sorted = {}
    for _, row in ipairs(rows) do sorted[#sorted + 1] = row end
    table.sort(sorted, function(a, b) return (a.ms or -1) > (b.ms or -1) end)
    for i, row in ipairs(sorted) do
      if full or i <= 3 or row.invalid or row.ok == false then
        Say("Boot/%s/%s: %s ms%s%s", label, row.name, Value(row.ms), row.invalid and " (clock invalid/reset)" or "", row.ok == false and " (error)" or "")
      end
    end
  end
  Rows("Load", result.load)
  Say("Boot/Login/total: %s ms%s", Value(result.login and result.login.ms), result.login and result.login.invalid and " (clock invalid/reset)" or "")
  Rows("Init", result.init)
  local callbacks = {}
  for _, row in ipairs(result.callbacks) do callbacks[#callbacks + 1] = row end
  table.sort(callbacks, function(a,b) return a.maximum > b.maximum end)
  for i, row in ipairs(callbacks) do
    if full or i <= 5 or row.name == "Probe/NativeRead" or row.errors > 0 or row.invalid > 0 then
      Say("Boot/Callback/%s: %d calls; total=%s ms; max=%s ms @t=%ss; errors=%d; invalid=%d; incomplete=%d",
        row.name, row.calls, Value(row.total), Value(row.maximum), Value(row.maxAt), row.errors, row.invalid, row.calls - row.completed)
    end
  end
  -- The slowest individual callback and the largest accumulated cost are
  -- different questions. Keep both rankings; inclusive totals must not be added.
  table.sort(callbacks, function(a,b) return a.total > b.total end)
  for i, row in ipairs(callbacks) do
    if i <= 8 then
      Say("Boot/Total/%s: %d calls; inclusive=%s ms; max=%s ms", row.name, row.calls, Value(row.total), Value(row.maximum))
    end
  end
  for i, row in ipairs(result.slow) do
    if full or i <= 4 then Say("Boot/Slow/%s: %s ms @t=%ss%s", row.name, Value(row.ms), Value(row.at), row.ok == false and " (error)" or "") end
  end
  Say("Boot/Trace: skipped=%d; changed=%d; dropped=%d", result.traceSkipped, result.traceChanged, result.traceDropped)
  for _, row in ipairs(result.skipped) do
    Say("Boot/Skipped/%s: %s; count=%d", row.name, row.reason, row.count)
  end
  Say("Boot/TickTrace: %s; observations=%d; slowObservations=%d; kept=%d; probe=%s ms total, %s ms max (%d calls, %d invalid)",
    tickTrace.status, tickTrace.observations, tickTrace.slowObserved, #tickTrace.slow,
    Value(tickTrace.probeTotal), Value(tickTrace.probeMax), tickTrace.probeCalls, tickTrace.probeInvalid)
  for i, sample in ipairs(tickTrace.slow) do
    if full or i <= 4 then
      Say("Boot/Tick/%d @t=%ss world=%ss: LastTime=%s ms; observer=%s ms", sample.observation,
        Value(sample.at), Value(sample.worldSeconds), Value(sample.ms), Value(sample.probeMs))
      for _, key in ipairs({"before", "near", "after"}) do
        local context = sample[key]
        if context then
          Say("Boot/Near/%d/%s t=%s..%ss: outer=%s ms; calls=%d; invalid=%d; max=%s ms (%s)",
            sample.observation, key, Value(context.fromAt), Value(context.toAt), Value(context.total),
            context.calls, context.invalid, Value(context.maximum), context.maxName or "none")
        else Say("Boot/Near/%d/%s: N/A", sample.observation, key) end
      end
    end
  end
  Say(T["Tick 是 LastTime 慢观测，非唯一 tick 计数。Near 为相邻观测区间内不重复嵌套的外层回调总耗时，不保证与原生 tick 对齐，不能相减归因；observer 为探针自身耗时。短时记录自动停止。"])
  -- Automatic report: anchor snapshots, first post-world sample, largest peak rise
  -- and final sample, plus counter changes/resets. Quiet samples stay available
  -- through the read-only command.
  local peakIndex
  for i, row in ipairs(result.native) do
    if row.newPeak and (not peakIndex or row.peak > result.native[peakIndex].peak) then peakIndex = i end
  end
  for i, row in ipairs(result.native) do
    local changed = row.delta and ((row.delta.over1 or 0) > 0 or (row.delta.over5 or 0) > 0 or (row.delta.over10 or 0) > 0)
    if full or changed or row.reset or row.tick == 0 or row.name == "PLAYER_ENTERING_WORLD" or row.name == "world#1" or i == peakIndex or i == #result.native then
      Say("Boot/Native/%s @t=%ss world=%ss read=%sms: session=%s%% (own=%s ms, denominator=%s ms); recent=%s%% (own=%s ms, denominator=%s ms); peak=%s ms; total>1/5/10=%s/%s/%s; delta=%s/%s/%s%s%s",
        row.name, Value(row.at), Value(row.worldSeconds), Value(row.readMs), Value(row.session and row.session.percent, 4), Value(row.session and row.session.own, 6), Value(row.session and row.session.denominator, 6),
        Value(row.recent and row.recent.percent, 4), Value(row.recent and row.recent.own, 6), Value(row.recent and row.recent.denominator, 6), Value(row.peak),
        tostring(row.over1 or "N/A"), tostring(row.over5 or "N/A"), tostring(row.over10 or "N/A"),
        tostring(row.delta and row.delta.over1 or "N/A"), tostring(row.delta and row.delta.over5 or "N/A"), tostring(row.delta and row.delta.over10 or "N/A"),
        row.newPeak and " (new peak)" or "", row.reset and " (counter reset)" or "")
      -- A historical peak must not hide new slow ticks' existing callback windows.
      if full or changed or row.newPeak then
        for _, entry in ipairs(row.window or {}) do
          Say("Boot/Window/%s/%s: %d calls; max=%s ms @t=%ss", row.name, entry.name, entry.calls, Value(entry.ms), Value(entry.at))
        end
      end
    end
  end
  Say(T["Callback/Slow 是指定入口的同步耗时（含子调用与探针开销，不可相加）；After 不含等待时间。t 为采集起点后的秒数，world 为进世界后的秒数，# 为采样序号。Window 仅列两次观测间最大回调，不代表原生尖峰归属；read 为本次指标读取耗时。未覆盖安全按钮、原生异步工作与其他插件。"])
  Say(T["Load 是文件读取/编译/执行之间的经过时间，非独占CPU；Init 是同步初始化，包含在 Login total 中。Native 为累计峰值/计数及滚动平均，事件快照可能尚未计入当前tick；delta 相对上一采样，不能精确归因到模块。/bmperf startup 查看完整结果。"])
end
ns.PrintStartupResult = function() PrintResult(true) end

Stop = function(status, quiet)
  if not live then return end
  live = false
  StopTickTrace(status)
  RestoreWatches()
  ns.StartupWatchFrame, ns.StartupWatchSlot, ns.StartupTimerScope = nil, nil, nil
  result.status = status
  if ticker then pcall(function() ticker:Cancel() end); ticker = nil end
  if frame then frame:UnregisterAllEvents(); frame:SetScript("OnEvent", nil) end
  ns.StartupCheckpoint, ns.StartupBegin, ns.StartupEnd, ns.StopStartupCapture = nil, nil, nil, nil
  if ns.SavePerfReport then pcall(ns.SavePerfReport, "startup", result) end
  if not quiet then pcall(PrintResult, false) end
end
ns.StopStartupCapture = function(quiet) Stop("cancelled", quiet == true) end

-- A temporary one-second ticker only after login, bounded even without a world
-- event. Callback count also bounds capture if the wall clock becomes unusable.
local function Tick()
  if not live then return end
  ticks = ticks + 1
  local now = WallTime()
  local deadline = TickTraceDeadline(now)
  if deadline then StopTickTrace(deadline) end
  local elapsed = worldTick and (ticks - worldTick) or ticks
  Snapshot((worldTick and "world#" or "login#") .. elapsed)
  if worldTick and (elapsed >= 15 or (now and worldAt and now - worldAt >= 15)) then Stop("complete")
  elseif not worldTick and (ticks >= 45 or (now and loginAt and now - loginAt >= 45)) then Stop("world-timeout")
  elseif ticks >= 60 then Stop("capture-timeout") end
end
local function OnEvent(_, event, name)
  if not live then return end
  if event == "PLAYER_LOGIN" and not loginSeen then
    loginSeen = true
    result.status = "waiting-world"
    loginAt = WallTime()
    StartTickTrace()
    Snapshot("PLAYER_LOGIN")
    frame:UnregisterEvent("PLAYER_LOGIN")
    local ok, value = pcall(function() return C_Timer.NewTicker(1, Tick) end)
    if ok and value then ticker = value
    elseif result.login then Stop("timer-unavailable")
    else pendingStop = "timer-unavailable" end
  elseif event == "PLAYER_ENTERING_WORLD" and not result.worldSeen then
    result.worldSeen = true
    result.status = "post-world"
    worldTick, worldAt = ticks, WallTime()
    Snapshot("PLAYER_ENTERING_WORLD")
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
  elseif event == "PLAYER_LOGOUT" then Stop("logout", true) end
end
for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", OnEvent)
for _, entry in ipairs(queued) do
  ns[entry.method](entry.name, entry.target, entry.argument)
end
Snapshot("ADDON_LOADED")
end -- StartCapture

bootstrap = CreateFrame("Frame", "BaimiaoStartupDiagnostics")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(self, _, name)
  if name ~= addonName then return end
  self:UnregisterAllEvents()
  self:SetScript("OnEvent", nil)
  local queued = pending
  pending = nil
  ns.StartupWatchFrame, ns.StartupWatchSlot, ns.StartupTimerScope = nil, nil, nil
  if ns.IsStartupDiagnosticsEnabled and ns.IsStartupDiagnosticsEnabled() then
    StartCapture(queued)
  end
end)
