local addonName, ns = ...
local T = ns.L
local active, eventFrame

local function Say(text, ...)
  print("|cff66ccffBMPerf|r " .. string.format(text, ...))
end

local function ValidNumber(value)
  if issecretvalue and issecretvalue(value) then return false end
  return type(value) == "number" and value == value and value >= 0 and value < math.huge
end


-- Keep one bounded, plain-data report per kind in the existing account save.
-- WoW writes it to disk on reload/logout, not continuously. Never serialize
-- frame handles, callback functions, event payloads or an unbounded history.
function ns.SavePerfReport(kind, result)
  if kind ~= "startup" and kind ~= "idle" and kind ~= "native" and kind ~= "top" and kind ~= "rotation" and kind ~= "root" then return end
  local seen, budget = {}, 20000
  local omit = {frame=true, task=true, original=true, wrapper=true, timer=true, stack=true}
  local function Copy(value, depth)
    if budget <= 0 or depth > 9 or (issecretvalue and issecretvalue(value)) then return end
    local t = type(value)
    if t == "number" then if ValidNumber(value) then return value end
    elseif t == "boolean" then return value
    elseif t == "string" then return value:sub(1, 256)
    elseif t == "table" and not seen[value] and not getmetatable(value) then
      seen[value] = true
      local out, count = {}, 0
      for k, v in pairs(value) do
        if (type(k) == "string" or type(k) == "number") and not omit[k] then
          count, budget = count + 1, budget - 1
          if count > 512 or budget <= 0 then break end
          out[k] = Copy(v, depth + 1)
        end
      end
      seen[value] = nil
      return out
    end
  end
  local db = ns.GetDB("_diagnostics", {startup=false})
  if type(db.reports) ~= "table" then db.reports = {} end
  db.reports[kind] = {schema=1, revision=kind == "root" and "observer-isolation-v1" or kind == "rotation" and "rotation-cooldown-v1" or "cpu-attribution-v1", kind=kind, capturedAt=time and time() or nil, report=Copy(result, 0)}
end

-- One synchronous inventory, using the SAME native metrics for every addon.
-- Zero, a small positive value and unavailable data remain distinct.
local function NativeTop()
  ns.NativeCPUListResult = nil
  local api, addons = C_AddOnProfiler, C_AddOns
  local ok, count = pcall(function()
    if not api or not addons or (api.IsEnabled and not api.IsEnabled()) then return end
    return addons.GetNumAddOns()
  end)
  if not ok or not ValidNumber(count) then Say(T["原生CPU数据不可用；未自动开启CPU分析。"]); return end
  local names, result = {}, {at=GetTime(), loaded=0, metrics={}, truncated=count>512}
  for i=1, math.min(count, 512) do
    local valid, name = pcall(function()
      if addons.IsAddOnLoaded(i) then return addons.GetAddOnInfo(i) end
    end)
    if valid and type(name) == "string" then names[#names+1] = name end
  end
  result.loaded = #names
  for _, spec in ipairs({{"session", "SessionAverageTime"}, {"recent", "RecentAverageTime"}}) do
    local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[spec[2]]
    local valid, app, overall = pcall(function()
      if metric == nil then return end
      return api.GetApplicationMetric(metric), api.GetOverallMetric(metric)
    end)
    local sample = {rows={}, zero=0, positive=0, unavailable=0,
      app=valid and ValidNumber(app) and app or nil, overall=valid and ValidNumber(overall) and overall or nil}
    result.metrics[spec[1]] = sample
    for _, name in ipairs(names) do
      local readOK, own = pcall(function() if metric ~= nil then return api.GetAddOnMetric(name, metric) end end)
      local row = {name=name}
      if readOK and ValidNumber(own) then
        row.own = own
        if own == 0 then sample.zero = sample.zero + 1 else sample.positive = sample.positive + 1 end
        if valid and ValidNumber(app) and ValidNumber(overall) then
          local denominator = app - overall + own
          if denominator > 0 and denominator < math.huge then row.percent=own/denominator*100; row.denominator=denominator end
        end
      else sample.unavailable = sample.unavailable + 1 end
      sample.rows[#sample.rows+1] = row
    end
    table.sort(sample.rows, function(a,b)
      local x,y = a.own or -1, b.own or -1
      if x == y then return a.name < b.name end
      return x > y
    end)
  end
  ns.NativeCPUListResult = result
  ns.SavePerfReport("top", result)
  Say(T["原生插件排名：一次性读取；零值、非零值与不可用分别统计，不是系统CPU百分比。"])
  for _, key in ipairs({"session", "recent"}) do
    local sample = result.metrics[key]
    Say("Top/%s: loaded=%d; rawZero=%d; positive=%d; unavailable=%d; truncated=%s", key, result.loaded, sample.zero, sample.positive, sample.unavailable, tostring(result.truncated))
    for i, row in ipairs(sample.rows) do
      if i <= 10 or row.name == addonName then
        Say("Top/%s/%d/%s: own=%s ms; percent=%s%%", key, i, row.name,
          row.own and string.format("%.9f",row.own) or "N/A", row.percent and string.format("%.6f",row.percent) or "N/A")
      end
    end
  end
  Say(T["报告已存入插件存档内存；重载或退出后写入磁盘。每类只保留最近一次，不持续采集。"])
end

-- Use the same metric for all three values in the native addon-list formula.
-- SessionAverageTime (list average) is distinct from RecentAverageTime (60 ticks).
local function NativePercent(metricName)
  local api = C_AddOnProfiler
  local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[metricName or "RecentAverageTime"]
  if not api or not metric then return end
  if api.IsEnabled and not api.IsEnabled() then return end
  local app = api.GetApplicationMetric(metric)
  local overall = api.GetOverallMetric(metric)
  local own = api.GetAddOnMetric(addonName, metric)
  if not ValidNumber(app) or not ValidNumber(overall) or not ValidNumber(own) then return end
  local denominator = app - overall + own
  if denominator > 0 and denominator < math.huge then
    return {percent=own / denominator * 100, own=own, app=app, overall=overall, denominator=denominator}
  end
end

-- One-shot reads only: no script replacement, timers, memory scan, reset or CVar change.
local function NativeOwn(metricName)
  local api = C_AddOnProfiler
  local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[metricName]
  if not api or metric == nil or (api.IsEnabled and not api.IsEnabled()) then return end
  local value = api.GetAddOnMetric(addonName, metric)
  if ValidNumber(value) then return value end
end

local function NativeSnapshot()
  local s = {at=GetTime()}
  local ok, value = pcall(NativePercent, "SessionAverageTime")
  if ok then s.session = value end
  ok, value = pcall(NativePercent, "RecentAverageTime")
  if ok then s.recent = value end
  ns.NativeCPUResult = nil
  if not s.session and not s.recent then Say(T["原生CPU数据不可用；未自动开启CPU分析。"]); return end
  for key, metric in pairs({peak="PeakTime", over1="CountTimeOver1Ms", over5="CountTimeOver5Ms", over10="CountTimeOver10Ms"}) do
    ok, value = pcall(NativeOwn, metric)
    if ok then s[key] = value end
  end
  -- Only the latest fixed-size numeric snapshot is retained, never history.
  ns.NativeCPUResult = s
  ns.SavePerfReport("native", s)
  Say(T["原生快照（未插桩）：session=列表平均，recent=最近60个tick；百分比保留4位小数。"])
  for _, key in ipairs({"session", "recent"}) do
    local sample = s[key]
    if sample then
      Say("Native/%s: %.4f%%; own %.6f ms; denominator %.6f ms", key, sample.percent, sample.own, sample.denominator)
    else Say("Native/%s: N/A", key) end
  end
  Say(T["累计记录（非本次新增）：peak=%s ms；>1ms=%s，>5ms=%s，>10ms=%s ticks。"],
    s.peak and string.format("%.4f", s.peak) or "N/A", tostring(s.over1 or "N/A"), tostring(s.over5 or "N/A"), tostring(s.over10 or "N/A"))
end

-- Raw native time metrics are milliseconds, not callback ms/s.
local function ReportNative(label, samples)
  if #samples == 0 then return end
  for _, key in ipairs({"percent", "own", "denominator"}) do
    local values = {}
    for i, sample in ipairs(samples) do values[i] = sample[key] end
    table.sort(values)
    local n = #values
    local median = (values[math.floor((n+1)/2)] + values[math.ceil((n+1)/2)]) / 2
    Say("Native/%s/%s: median %.4f, range %.4f ~ %.4f %s; n=%d",
      label, key, median, values[1], values[n], key == "percent" and "%" or "ms", n)
  end
end

-- Compare callback bodies without profiling wrappers. Timers/events stay registered.
local function RestoreCompare(s)
  if s.task then
    if s.task.run == s.noop then s.task.run = s.original end
    s.task, s.original = nil, nil
  end
end

local function FinishCompare(s, cancelled)
  RestoreCompare(s)
  for _, watch in pairs(s.watch) do
    if watch.lockedCadence and watch.task.freezeCadence == true then
      watch.task.freezeCadence = watch.freezeCadence
    end
  end
  s.timer:Cancel()
  eventFrame:UnregisterAllEvents()
  eventFrame:SetScript("OnEvent", nil)
  s.running, s.cancelled = false, cancelled
  s.timer, s.noop, s.watch = nil, nil, nil
  ns.IdleCompareResult = s
  Say(T["自动对照结束；刷新已恢复。取消：%s。"], tostring(cancelled))
  for _, phase in ipairs(s.phases) do
    if phase.skipped then
      Say("%s: %s", phase.label, T["未运行，跳过"])
    elseif #phase.samples > 0 then
      ReportNative(phase.label, phase.samples)
    end
  end
  Say(T["只暂停指定刷新函数，不停事件和计时器调度。own 为插件毫秒耗时；需比较前后基线，滚动样本并非独立测量，不能当作模块精确占比。"])
end

local function RestoreInstrumentation(s)
  s.running = false
  for _, row in ipairs(s.rows) do
    local current
    if row.entry then
      local ok, value = pcall(row.entry.get)
      if ok then current = value end
    elseif row.task then current = row.task.run else current = row.frame:GetScript(row.script) end
    if current == row.wrapper then
      if row.entry then
        if not pcall(row.entry.set, row.original) then s.changed = s.changed + 1 end
      elseif row.task then row.task.run = row.original
      else
        local ok = pcall(function()
          if row.frame.IsProtected and row.frame:IsProtected() then error("protected diagnostic script") end
          row.frame:SetScript(row.script, row.original)
        end)
        if not ok then s.changed = s.changed + 1 end
      end
    else
      s.changed = s.changed + 1
    end
    -- Results retain aggregates only, never UI objects or closures.
    row.frame, row.task, row.original, row.wrapper, row.entry = nil, nil, nil, nil, nil
  end
  s.stack = nil
end

local function Finish(cancelled)
  local s = active
  if not s then return end
  if s.replay or s.root then s.cancel("cancelled");return end
  active = nil
  if s.compare then FinishCompare(s, cancelled); return end
  s.running = false
  s.timer:Cancel()
  eventFrame:UnregisterAllEvents()
  eventFrame:SetScript("OnEvent", nil)
  s.seconds = s.instrumentedAt and math.max(0, GetTime() - s.instrumentedAt) or 0
  s.cancelled = cancelled
  RestoreInstrumentation(s)
  s.timer = nil
  s.stack = nil
  ns.IdleProfileResult = s
  ns.SavePerfReport("idle", s)
  table.sort(s.native)
  Say(T["诊断结束：回调采样 %.1f 秒，跳过 %d 个受保护脚本，变化 %d 项。"], s.seconds, s.skipped, s.changed)
  if #s.native > 0 then
    local n = #s.native
    local median = (s.native[math.floor((n + 1) / 2)] + s.native[math.ceil((n + 1) / 2)]) / 2
    Say(T["原生近期CPU（未插桩）：中位 %.3f%%，范围 %.3f%% ~ %.3f%%，%d 次。"], median, s.native[1], s.native[n], n)
  else
    Say(T["原生CPU数据不可用；未自动开启CPU分析。"])
  end
  ReportNative("baseline", s.nativeRaw)
  ReportNative("session/baseline", s.sessionRaw)
  ReportNative("instrumented", s.instrumentedNative)
  ReportNative("session/instrumented", s.instrumentedSessionRaw)
  Say("Functions/%s: skipped=%d; parent edges are inclusive, not additive", s.traceRevision or "none", s.functionSkipped or 0)
  table.sort(s.rows, function(a,b) return a.selfTotal > b.selfTotal end)
  for _, row in ipairs(s.rows) do
    Say("%s/%s: %d calls, self %.3f ms/s, selfTotal %.3f ms, inclusive %.3f ms, max %.3f ms; errors %d, incomplete %d, reset %d",
      row.name, row.script, row.calls, s.seconds > 0 and row.selfTotal / s.seconds or 0,
      row.selfTotal, row.total, row.maximum, row.errors, row.calls - row.completed, row.invalid)
    if row.events then
      local names = {}
      for name in pairs(row.events) do names[#names+1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        local event = row.events[name]
        Say("  %s/%s/%s: %d calls, %.3f ms/s; incomplete %d, reset %d",
          row.name, row.script, name, event.calls, s.seconds > 0 and event.total / s.seconds or 0,
          event.calls - event.completed, event.invalid)
      end
    end
  end
  Say(T["累计排行按 selfTotal 排序，仅扣除已覆盖的嵌套子回调；inclusive 含子调用，事件明细不可重复相加。覆盖已登记事件、常驻刷新和循环冷却，不含安全脚本、其他计时器及原生异步工作。计时含探针开销，不能与 Native 滚动均值相减。"])
  Say(T["报告已存入插件存档内存；重载或退出后写入磁盘。每类只保留最近一次，不持续采集。"])
end

local function Instrument(s)
  local function Pack(...) return {n=select("#", ...), ...} end
  s.instrumentedAt = GetTime()
  s.traceRevision, s.functionSkipped = s.entriesOnly and "entries-v1" or "functions-v1", 0
  local function Add(frame, name, script, task, entry)
    if not frame and not task and not entry then return end
    local original
    if entry then
      local ok, value = pcall(entry.get)
      if not ok then s.functionSkipped = s.functionSkipped + 1; return end
      original = value
    elseif task then original = task.run else original = frame:GetScript(script) end
    if type(original) ~= "function" then return end
    for _, row in ipairs(s.rows) do
      if (task and row.task == task) or (frame and row.frame == frame and row.script == script) then return end
    end
    if frame and frame.IsProtected and frame:IsProtected() then s.skipped = s.skipped + 1; return end
    local row = {frame=frame, task=task, entry=entry, name=name, script=script, original=original, parents={},
      calls=0, completed=0, total=0, selfTotal=0, maximum=0, invalid=0, errors=0}
    if script == "OnEvent" then row.events = {} end
    row.wrapper = function(...)
      if not s.running then return original(...) end
      row.calls = row.calls + 1
      local event
      if row.events then
        local name = select(2, ...)
        if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then
          event = row.events[name]
          if not event then
            event = {calls=0, completed=0, total=0, invalid=0}
            row.events[name] = event
          end
          event.calls = event.calls + 1
        end
      end
      local parent = s.stack
      local node = {children=0, label=name .. "/" .. script}
      s.stack = node
      local start = debugprofilestop()
      local returns = Pack(pcall(original, ...))
      local elapsed = debugprofilestop() - start
      if not s.running then
        if not returns[1] then error(returns[2], 0) end
        return unpack(returns, 2, returns.n)
      end
      s.stack = parent
      row.completed = row.completed + 1
      if not returns[1] then row.errors = row.errors + 1; row.completed = row.completed - 1 end
      if event and returns[1] then event.completed = event.completed + 1 end
      if not ValidNumber(elapsed) or node.invalid or elapsed < node.children then
        row.invalid = row.invalid + 1
        if event then event.invalid = event.invalid + 1 end
        if parent then parent.invalid = true end
      else
        if parent then parent.children = parent.children + elapsed end
        if event then event.total = event.total + elapsed end
        row.total = row.total + elapsed
        row.selfTotal = row.selfTotal + elapsed - node.children
        if elapsed > row.maximum then row.maximum = elapsed end
        -- Edges are inclusive: a caller and its child must never be summed.
        -- Store labels/aggregates only, never arguments or return values.
        local key = parent and parent.label or "<entry>"
        local edge = row.parents[key]
        if not edge then edge = {calls=0, total=0}; row.parents[key] = edge end
        edge.calls, edge.total = edge.calls + 1, edge.total + elapsed
      end
      if not returns[1] then error(returns[2], 0) end
      return unpack(returns, 2, returns.n)
    end
    if entry then
      if not pcall(entry.set, row.wrapper) then s.functionSkipped = s.functionSkipped + 1; return end
    elseif task then task.run = row.wrapper else frame:SetScript(script, row.wrapper) end
    s.rows[#s.rows + 1] = row
  end
  for name, task in pairs(ns.IdleTasks or {}) do
    if task.timer then Add(nil, name, "Ticker", task)
    elseif task.profileRefresh then Add(nil, name, "Refresh", task) end
  end
  if not s.entriesOnly then
    for _, entry in ipairs(ns.PerfFunctions or {}) do
      Add(nil, entry.name, "Function", nil, entry)
    end
  end
  for _, entry in ipairs(ns.PerfFrames or {}) do
    Add(entry.frame, entry.name, entry.script)
  end
  Add(_G.BaimiaoCoordShoutButton, "Coord", "OnUpdate")
  Add(_G.BaimiaoRaidCDPoll, "RaidCD", "OnUpdate")
  Add(_G.BaimiaoRaidCDPoll, "RaidCD", "OnEvent")
  Add(_G.BaimiaoReminderFrame, "Reminder", "OnUpdate")
  Add(_G.BaimiaoQuickMountCollapse, "QuickCollapse", "OnUpdate")
  local i = 1
  while _G["BaimiaoQuickMountExtra" .. i] do
    -- Cooldown work is measured through the internal slot, never secure scripts.
    local button = _G["BaimiaoQuickMountExtra" .. i]
    if button:GetScript("OnUpdate") and button.IsProtected and button:IsProtected() then
      s.skipped = s.skipped + 1
    end
    i = i + 1
  end
  Add(ns.AuctionHouse and ns.AuctionHouse.panel, "Auction", "OnUpdate")
end

-- Diagnose the observer, not gameplay: raw -> entries -> raw -> functions -> raw.
-- No module is paused, no secure handler is replaced, and no CVar is changed.
-- Four seconds per phase are excluded from native samples to reduce rolling-window
-- carryover; this is NOT a guarantee of 60 profiler ticks on a stalled client.
local function StartRoot()
  local ok, sample = pcall(NativePercent)
  if not ok or not sample then Say(T["原生CPU数据不可用；未自动开启CPU分析。"]); return end
  if not debugprofilestop or not C_Timer or not C_Timer.NewTicker then return end
  local s = {root=true, running=true, started=GetTime(), phases={}, reads=0,
    phaseSeconds=18, warmupSeconds=4, nativeReadMs=0, nativeReadMax=0, invalidReadClocks=0}
  local specs = {{"raw-before"}, {"entries", true}, {"raw-middle"}, {"functions", false}, {"raw-after"}}
  local phase, trace, index, lastTick = nil, nil, 0, s.started
  local function ClosePhase()
    if not phase then return end
    phase.seconds = GetTime() - phase.started
    if trace then
      RestoreInstrumentation(trace)
      trace.seconds = GetTime() - trace.instrumentedAt
      trace = nil
    end
  end
  local function Stop(reason)
    if not s.running then return end
    s.running = false
    ClosePhase()
    if s.timer then s.timer:Cancel() end
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    s.timer, s.cancel = nil, nil
    s.status, s.seconds = reason, GetTime() - s.started
    if active == s then active = nil end
    ns.RootCPUResult = s
    ns.SavePerfReport("root", s)
    Say("Root/%s: %.1fs; reads=%d; read=%.3fms total, %.3fms max", reason, s.seconds, s.reads, s.nativeReadMs, s.nativeReadMax)
    for _, p in ipairs(s.phases) do
      ReportNative("root/" .. p.label, p.recent)
      if p.trace then
        local t = p.trace
        Say("Root/%s: rows=%d; skipped=%d; functionSkipped=%d; changed=%d", p.label, #t.rows, t.skipped, t.functionSkipped or 0, t.changed)
      end
      Say("Root/%s: missingRecent=%d; missingSession=%d", p.label, p.missingRecent, p.missingSession)
    end
    Say(T["定位实验结束；原生窗口与回调耗时不可相减。探针阶段不是正常CPU；恢复期用于检验探针影响，不能自动归因到模块。"])
    Say(T["报告已存入插件存档内存；重载或退出后写入磁盘。每类只保留最近一次，不持续采集。"])
  end
  s.cancel = Stop
  local function NextPhase()
    ClosePhase()
    if phase and phase.trace and phase.trace.changed > 0 then Stop("restore-changed"); return end
    index = index + 1
    local spec = specs[index]
    if not spec then Stop("complete"); return end
    phase = {label=spec[1], started=GetTime(), recent={}, session={}, missingRecent=0, missingSession=0}
    s.phases[#s.phases + 1] = phase
    if spec[2] ~= nil then
      trace = {running=true, rows={}, skipped=0, changed=0, entriesOnly=spec[2]}
      phase.trace = trace
      local installed = pcall(Instrument, trace)
      if not installed then Stop("install-failed"); return end
    end
  end
  active = s
  eventFrame = eventFrame or CreateFrame("Frame")
  for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT", "PLAYER_STARTED_MOVING", "ZONE_CHANGED_NEW_AREA"}) do
    eventFrame:RegisterEvent(event)
  end
  eventFrame:SetScript("OnEvent", function(_, event) Stop(event) end)
  NextPhase()
  s.timer = C_Timer.NewTicker(1, function()
    local now = GetTime()
    if now - lastTick > 3 or now < lastTick then Stop("timing-gap"); return end
    lastTick = now
    if InCombatLockdown() then Stop("combat"); return end
    if now - phase.started >= s.phaseSeconds then NextPhase(); return end
    local elapsed = now - phase.started
    if elapsed < s.warmupSeconds then return end
    local before = debugprofilestop()
    local readOK, recent = pcall(NativePercent)
    local sessionOK, session = pcall(NativePercent, "SessionAverageTime")
    local readMs = debugprofilestop() - before
    s.reads = s.reads + 1
    if ValidNumber(readMs) then
      s.nativeReadMs, s.nativeReadMax = s.nativeReadMs + readMs, math.max(s.nativeReadMax, readMs)
    else s.invalidReadClocks = s.invalidReadClocks + 1 end
    if readOK and recent then recent.at=elapsed; phase.recent[#phase.recent+1]=recent
    else phase.missingRecent=phase.missingRecent+1 end
    if sessionOK and session then session.at=elapsed; phase.session[#phase.session+1]=session
    else phase.missingSession=phase.missingSession+1 end
  end)
  Say(T["开始90秒定位实验：未插桩、仅入口、恢复、完整函数、再恢复；每段18秒，前4秒不采原生窗口。不要移动、操作界面或改变设置；战斗/移动自动取消。/bmperf cancel 可停止。"])
end

local function StartCompare()
  local ok, sample = pcall(NativePercent)
  if not ok or not sample then Say(T["原生CPU数据不可用；未自动开启CPU分析。"]); return end
  local s = {compare=true, running=true, phases={}, watch={}, index=1, phaseAt=GetTime(), noop=function()end}
  for i, name in ipairs({"baseline-1", "Coord", "baseline-2", "RaidCD", "baseline-3", "QuickCooldown", "baseline-4"}) do
    s.phases[i] = {label=i % 2 == 0 and ("paused-" .. name) or name,
      target=i % 2 == 0 and name or nil, samples={}}
  end
  for _, name in ipairs({"Coord", "RaidCD", "QuickCooldown"}) do
    local task = ns.IdleTasks and ns.IdleTasks[name]
    if task then
      s.watch[name] = {task=task, run=task.run, timer=task.timer,
        lockedCadence=task.adaptiveCadence, freezeCadence=task.freezeCadence}
      -- Pausing a callback must not itself change an adaptive timer cadence.
      -- Real show/hide/event changes still invalidate the controlled run.
      if task.adaptiveCadence then task.freezeCadence = true end
    end
  end
  active = s
  eventFrame = eventFrame or CreateFrame("Frame")
  for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT", "PLAYER_STARTED_MOVING", "ZONE_CHANGED_NEW_AREA"}) do
    eventFrame:RegisterEvent(event)
  end
  eventFrame:SetScript("OnEvent", function() Finish(true) end)
  s.timer = C_Timer.NewTicker(1, function()
    if active ~= s then return end
    if InCombatLockdown() then Finish(true); return end
    for name, watch in pairs(s.watch) do
      if not ns.IdleTasks or ns.IdleTasks[name] ~= watch.task or watch.task.timer ~= watch.timer
          or watch.task.run ~= (watch.task == s.task and s.noop or watch.run) then
        Finish(true); return
      end
    end
    local elapsed = GetTime() - s.phaseAt
    local phase = s.phases[s.index]
    -- Allow 20 seconds of settling, then keep ten 1-second rolling samples.
    if elapsed > 20 and not phase.skipped then
      local valid, value = pcall(NativePercent)
      if not valid or not value then Finish(true); return end
      phase.samples[#phase.samples+1] = value
    end
    if elapsed < 30 then return end
    RestoreCompare(s)
    s.index = s.index + 1
    phase = s.phases[s.index]
    if not phase then Finish(false); return end
    s.phaseAt = GetTime()
    if phase.target then
      local watch = s.watch[phase.target]
      if watch and watch.timer and type(watch.run) == "function" then
        s.task, s.original = watch.task, watch.run
        s.task.run = s.noop
      else phase.skipped = true end
    end
    Say(T["对照阶段 %d/7：%s"], s.index, phase.label)
  end)
  Say(T["开始210秒自动对照：保持原地，不操作、不改设置。临时暂停坐标、嗜血与快捷冷却刷新，完成后恢复；移动或战斗自动取消。/bmperf cancel 可取消。"])
end

-- [DEBUG-rotation-cooldown] Opt-in snapshot only. No event/timer hooks, no
-- changes to live icons or profiler settings. Remove after live diagnosis.
local rotationProbe
function ns.CaptureRotationSnapshot()
  local function Scalar(value)
    if issecretvalue and issecretvalue(value) then return "secret" end
    local kind = type(value)
    if kind == "string" then return value:sub(1, 256) end
    if kind == "boolean" or (kind == "number" and value == value and math.abs(value) < math.huge) then return value end
    if kind == "nil" then return "nil" end
    return kind
  end
  local function Read(fn, ...)
    if type(fn) ~= "function" then return {status="missing"} end
    local ok, value = pcall(fn, ...)
    if not ok then return {status="error", error=Scalar(value)} end
    if issecretvalue and issecretvalue(value) then return {status="secret"} end
    if value == nil then return {status="nil"} end
    return {status="ok", value=Scalar(value)}, value
  end
  local function Fields(fn, id, names)
    local out, value = Read(fn, id)
    if type(value) == "table" then
      for _, name in ipairs(names) do out[name] = Scalar(value[name]) end
    end
    return out
  end
  local function Method(object, name)
    local result = Read(object and object[name], object)
    if result.status == "ok" then return result.value end
    return result.status
  end
  local function Widget(cd)
    return {shown=Method(cd, "IsShown"), visible=Method(cd, "IsVisible"),
      durationMS=Method(cd, "GetCooldownDuration"), displayDurationMS=Method(cd, "GetCooldownDisplayDuration"),
      drawSwipe=Method(cd, "GetDrawSwipe"), hideNumbers=Method(cd, "GetHideCountdownNumbers")}
  end
  local function Duration(fn, id, ignoreGCD)
    local out, object
    if ignoreGCD == nil then out, object = Read(fn, id) else out, object = Read(fn, id, ignoreGCD) end
    if out.status ~= "ok" or (type(object) ~= "table" and type(object) ~= "userdata") then return out end
    out.zero = Method(object, "IsZero")
    -- Apply to an isolated, hidden native cooldown, never to a gameplay icon.
    if not rotationProbe then
      local parent = CreateFrame("Frame");parent:Hide()
      rotationProbe = CreateFrame("Cooldown", nil, parent)
    end
    rotationProbe:Clear()
    local applied = Read(rotationProbe.SetCooldownFromDurationObject, rotationProbe, object)
    out.applied = applied.status == "ok" or applied.status == "nil"
    out.setterStatus, out.error = applied.status, applied.error
    out.widgetDurationMS = Method(rotationProbe, "GetCooldownDuration")
    rotationProbe:Clear()
    return out
  end
  local api = C_Spell or {}
  local function Spell(id)
    return {id=id,
      info=Fields(api.GetSpellInfo,id,{"spellID","name","iconID"}),
      cooldown=Fields(api.GetSpellCooldown,id,{"isEnabled","isActive","isOnGCD","startTime","duration","modRate"}),
      charges=Fields(api.GetSpellCharges,id,{"currentCharges","maxCharges","cooldownStartTime","cooldownDuration","chargeModRate"}),
      chargeDuration=Duration(api.GetSpellChargeDuration,id),
      cooldownDuration=Duration(api.GetSpellCooldownDuration,id,false),
      ignoreGCDDuration=Duration(api.GetSpellCooldownDuration,id,true)}
  end
  local report = {revision="rotation-cooldown-v1", at=GetTime(), combat=InCombatLockdown(), spells={}}
  -- Snapshot existing widgets BEFORE any API probes, and retain only scalars.
  for _, id in ipairs({184575,255937,31884,375576}) do
    local sample = {id=id,cells={}}
    for row=1,6 do
      local f = _G["BaimiaoRotationGuide"..row]
      if f then
        for column, cell in ipairs(f.cells or {}) do
          if not (issecretvalue and issecretvalue(cell.sourceSpell)) and cell.sourceSpell == id and #sample.cells < 48 then
            sample.cells[#sample.cells+1] = {row=row,column=column,source=Scalar(cell.sourceSpell),spell=Scalar(cell.spell),
              shown=Method(cell,"IsShown"),visible=Method(cell,"IsVisible"),mode=Scalar(cell._cooldownMode),
              cachedStart=Scalar(cell._cooldownStart),cachedLength=Scalar(cell._cooldownLength),widget=Widget(cell.cooldown)}
          end
        end
      end
    end
    report.spells[#report.spells+1] = sample
  end
  for _, sample in ipairs(report.spells) do
    sample.base = Spell(sample.id)
    local result, override = Read(api.GetOverrideSpell,sample.id)
    sample.overrideStatus, sample.overrideID = result.status, result.value or result.status
    if type(override) == "number" and override > 0 and override ~= sample.id then sample.override = Spell(override) end
  end
  return report
end
local function RotationSnapshot()
  local result = ns.CaptureRotationSnapshot()
  ns.RotationSnapshotResult = result
  ns.SavePerfReport("rotation", result)
  Say("[DEBUG-rotation-cooldown] one-shot; no background sampling; combat=%s", tostring(result.combat))
  for _, sample in ipairs(result.spells) do
    local base = sample.base
    Say("Rotation/%d: cells=%d; override=%s; charge=%s/zero=%s; spell=%s/zero=%s; setter=%s",
      sample.id,#sample.cells,tostring(sample.overrideID),base.chargeDuration.status,tostring(base.chargeDuration.zero),
      base.cooldownDuration.status,tostring(base.cooldownDuration.zero),tostring(base.cooldownDuration.applied))
  end
  Say(T["技能冷却快照已记录，无后台采样。重载界面后写入存档；无需再跑CPU采集。"])
end

SLASH_BAIMIAOPERF1 = "/bmperf"
SlashCmdList.BAIMIAOPERF = function(msg)
  -- Allowed during combat: a one-shot read plus a private, non-secure probe.
  if (msg or ""):lower():match("^%s*rotation%s*$") then RotationSnapshot(); return end
  if (msg or ""):lower():match("^%s*startup%s*$") then
    if ns.PrintStartupResult then ns.PrintStartupResult()
    elseif ns.IsStartupDiagnosticsEnabled and not ns.IsStartupDiagnosticsEnabled() then
      Say(T["启动诊断默认关闭；可在工作台总览中开启，重载界面后生效。"])
    else Say(T["本次没有启动诊断数据；开启后需重载界面，且计时接口必须可用。"]) end
    return
  end
  if (msg or ""):lower():match("^%s*cancel%s*$") then
    if ns.StopStartupCapture then ns.StopStartupCapture() end
    Finish(true); return
  end
  if active then Say(T["诊断正在运行；/bmperf cancel 可取消。"]); return end
  if InCombatLockdown() then Say(T["请脱离战斗后运行诊断。"]); return end
  if (msg or ""):lower():match("^%s*auto%s*$") then
    local s
    s=ns.StartUIReplay({say=Say,percent=NativePercent,own=NativeOwn,done=function(result)
      ns.AutoUIResult=result;if active==s then active=nil end
    end})
    active=s;return
  end
  if (msg or ""):lower():match("^%s*result%s*$") then ns.PrintUIReplay(ns.AutoUIResult,Say);return end
  if (msg or ""):lower():match("^%s*native%s*$") then NativeSnapshot(); return end
  if (msg or ""):lower():match("^%s*top%s*$") then NativeTop(); return end
  if ns.StopStartupCapture then Say(T["启动采集尚未结束；请等结束后再运行挂机归因，避免探针叠加。"]); return end
  if (msg or ""):lower():match("^%s*root%s*$") then StartRoot(); return end
  if (msg or ""):lower():match("^%s*compare%s*$") then
    if C_Timer and C_Timer.NewTicker then StartCompare() end
    return
  end
  if not debugprofilestop or not C_Timer or not C_Timer.NewTicker then return end
  if (msg or ""):lower():match("^%s*who%s*$") then NativeTop() end
  -- Callback probes below remain opt-in; the separate startup capture is bounded.
  local s = {running=true, started=GetTime(), rows={}, native={}, nativeRaw={}, instrumentedNative={}, sessionRaw={}, instrumentedSessionRaw={}, skipped=0, changed=0}
  active = s
  eventFrame = eventFrame or CreateFrame("Frame")
  eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  eventFrame:RegisterEvent("PLAYER_LOGOUT")
  eventFrame:SetScript("OnEvent", function() Finish(true) end)
  s.timer = C_Timer.NewTicker(1, function()
    local elapsed = GetTime() - s.started
    if elapsed >= 30 then Finish(false); return end
    if InCombatLockdown() then Finish(true); return end
    if elapsed < 10 then
      local ok, value = pcall(NativePercent)
      if ok and value then
        s.native[#s.native + 1] = value.percent
        s.nativeRaw[#s.nativeRaw + 1] = value
      end
      ok, value = pcall(NativePercent, "SessionAverageTime")
      if ok and value then s.sessionRaw[#s.sessionRaw + 1] = value end
    elseif not s.instrumentedAt then
      Instrument(s)
    else
      local ok, value = pcall(NativePercent)
      if ok and value then s.instrumentedNative[#s.instrumentedNative + 1] = value end
      ok, value = pcall(NativePercent, "SessionAverageTime")
      if ok and value then s.instrumentedSessionRaw[#s.instrumentedSessionRaw + 1] = value end
    end
  end)
  Say(T["开始30秒挂机诊断：前10秒原生采样，后20秒回调计时；请保持当前开关不变，进入战斗自动结束。"])
end

if ns.StartupCheckpoint then ns.StartupCheckpoint("Diagnostics.lua") end
