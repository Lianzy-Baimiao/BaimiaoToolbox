local addonName, ns = ...
local T = ns.L
local active, eventFrame

local function Say(text, ...)
  print("|cff66ccffBMPerf|r " .. string.format(text, ...))
end

-- Native addon-list denominator, not process CPU or share of all addons.
local function NativePercent()
  local api = C_AddOnProfiler
  local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
  if not api or not metric then return end
  if api.IsEnabled and not api.IsEnabled() then return end
  local app = api.GetApplicationMetric(metric)
  local overall = api.GetOverallMetric(metric)
  local own = api.GetAddOnMetric(addonName, metric)
  if type(app) ~= "number" or type(overall) ~= "number" or type(own) ~= "number" then return end
  local denominator = app - overall + own
  if denominator > 0 then
    return {percent=own / denominator * 100, own=own, app=app, overall=overall, denominator=denominator}
  end
end

-- Raw RecentAverageTime values are milliseconds, not callback ms/s.
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

local function Finish(cancelled)
  local s = active
  if not s then return end
  active = nil
  s.running = false
  s.timer:Cancel()
  eventFrame:UnregisterAllEvents()
  eventFrame:SetScript("OnEvent", nil)
  s.seconds = s.instrumentedAt and math.max(0, GetTime() - s.instrumentedAt) or 0
  s.cancelled = cancelled
  for _, row in ipairs(s.rows) do
    local current
    if row.task then current = row.task.run else current = row.frame:GetScript(row.script) end
    if current == row.wrapper then
      if row.task then row.task.run = row.original
      else row.frame:SetScript(row.script, row.original) end
    else
      s.changed = s.changed + 1
    end
    -- Results retain aggregates only, never UI objects or closures.
    row.frame, row.task, row.original, row.wrapper = nil, nil, nil, nil
  end
  s.timer = nil
  ns.IdleProfileResult = s
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
  ReportNative("instrumented", s.instrumentedNative)
  table.sort(s.rows, function(a,b) return a.total > b.total end)
  for _, row in ipairs(s.rows) do
    Say("%s/%s: %d calls, %.3f ms/s, total %.3f ms, max %.3f ms; incomplete %d, reset %d",
      row.name, row.script, row.calls, s.seconds > 0 and row.total / s.seconds or 0,
      row.total, row.maximum, row.calls - row.completed, row.invalid)
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
  Say(T["覆盖指定脚本、坐标/嗜血计时器及快捷冷却内部刷新，不含安全按钮逐帧节流及其他回调。事件明细已包含在父项中。Native 为 RecentAverageTime：own=插件耗时，denominator=百分比分母；baseline=插桩前，instrumented=插桩中。计时含探针开销；原生滚动窗口重叠，不能与回调 ms/s 相减。"])
end

local function Instrument(s)
  s.instrumentedAt = GetTime()
  local function Add(frame, name, script, task)
    if not frame and not task then return end
    local original
    if task then original = task.run else original = frame:GetScript(script) end
    if not original then return end
    if frame and frame.IsProtected and frame:IsProtected() then s.skipped = s.skipped + 1; return end
    local row = {frame=frame, task=task, name=name, script=script, original=original,
      calls=0, completed=0, total=0, maximum=0, invalid=0}
    if script == "OnEvent" then row.events = {} end
    row.wrapper = function(self, ...)
      if not s.running then return original(self, ...) end
      row.calls = row.calls + 1
      local event
      if row.events then
        local name = ...
        -- Only the event identifier is retained; never its unit/player payload.
        if type(name) == "string" then
          event = row.events[name]
          if not event then
            event = {calls=0, completed=0, total=0, invalid=0}
            row.events[name] = event
          end
          event.calls = event.calls + 1
        end
      end
      local start = debugprofilestop()
      -- Preserve error propagation and never reset the global clock.
      original(self, ...)
      local elapsed = debugprofilestop() - start
      row.completed = row.completed + 1
      if event then event.completed = event.completed + 1 end
      if elapsed < 0 then
        row.invalid = row.invalid + 1
        if event then event.invalid = event.invalid + 1 end
        return
      end
      if event then event.total = event.total + elapsed end
      row.total = row.total + elapsed
      if elapsed > row.maximum then row.maximum = elapsed end
    end
    s.rows[#s.rows + 1] = row
    if task then task.run = row.wrapper else frame:SetScript(script, row.wrapper) end
  end
  for name, task in pairs(ns.IdleTasks or {}) do
    if task.timer then Add(nil, name, "Ticker", task)
    elseif task.profileRefresh then Add(nil, name, "Refresh", task) end
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

SLASH_BAIMIAOPERF1 = "/bmperf"
SlashCmdList.BAIMIAOPERF = function(msg)
  if (msg or ""):lower():match("^%s*cancel%s*$") then Finish(true); return end
  if active then Say(T["诊断正在运行；/bmperf cancel 可取消。"]); return end
  if InCombatLockdown() then Say(T["请脱离战斗后运行诊断。"]); return end
  if not debugprofilestop or not C_Timer or not C_Timer.NewTicker then return end
  -- No frame, ticker, hooks or result arrays exist until explicitly requested.
  local s = {running=true, started=GetTime(), rows={}, native={}, nativeRaw={}, instrumentedNative={}, skipped=0, changed=0}
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
    elseif not s.instrumentedAt then
      Instrument(s)
    else
      local ok, value = pcall(NativePercent)
      if ok and value then s.instrumentedNative[#s.instrumentedNative + 1] = value end
    end
  end)
  Say(T["开始30秒挂机诊断：前10秒原生采样，后20秒回调计时；请保持当前开关不变，进入战斗自动结束。"])
end
