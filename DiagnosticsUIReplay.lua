-- Opt-in UI workload replay. No timers, hooks or UI objects until /bmperf auto.
-- Measures actual display calls once; never clicks buttons or fakes game events.
local _, ns = ...
local T, replayFrame = ns.L
local function shown(f) return f and f:IsShown() end
local function protected(f) return f and f.IsProtected and f:IsProtected() end
local function number(n) return type(n)=="number" and n==n and n>=0 and n<math.huge end
local function fmt(n) return number(n) and string.format("%.3f",n) or "N/A" end
local function count(n) return number(n) and tostring(n) or "N/A" end

function ns.PrintUIReplay(r, say)
  if not r then say(T["暂无自动回放结果；/bmperf auto 开始。"]);return end
  say(T["自动界面回放结束：%s，%.1f 秒。"],r.status,r.seconds)
  for _,c in ipairs(r.cases) do
    if c.status=="skipped" then say("Auto/%s: SKIP (%s)",c.name,c.reason)
    else
      say("Auto/%s: %s; first=%s ms; repeatMax=%s ms (%d); close=%s ms; >1/5/10ms=+%s/+%s/+%s%s",
        c.name,c.status,fmt(c.firstOpen),fmt(c.repeatMax),c.repeats or 0,fmt(c.closeTotal),
        count(c.over1),count(c.over5),count(c.over10),
        (c.reset and " (counter reset)" or "")..(c.reason and " ("..c.reason..")" or ""))
    end
  end
  for _,key in ipairs({"before","after"}) do
    local sample=r[key]
    if sample then for _,metric in ipairs({"session","recent"}) do
      local v=sample[metric]
      if v then say("Auto/%s/%s: %.4f%%; own %.6f ms; denominator %.6f ms",key,metric,v.percent,v.own,v.denominator) end
    end end
  end
  if r.error then say("Auto/error: %s",r.error) end
  say(T["first=本轮首次（不保证冷启动），repeatMax=重复打开最大同步耗时；计数为该阶段新增原生慢tick，含后台与诊断开销，非该窗口独占。拍卖行仅预览，不测交易；异步工作不计入同步耗时。/bmperf result 重看。"])
end

function ns.StartUIReplay(api)
  if not debugprofilestop or not C_Timer or not C_Timer.NewTicker then
    api.say(T["自动回放所需的计时接口不可用。"]);return
  end
  local result={cases={},status="running"}
  local s={replay=true}
  local actions, restorers={},{}
  local index, stage, deadline=1,"begin",GetTime()
  local started=GetTime()
  local row, before, touchedSettings, touchedAuction, touchedMythic
  local stopped, waiting, timer
  local function snapshot()
    local v={}
    for _,metric in ipairs({"SessionAverageTime","RecentAverageTime"}) do
      local ok,data=pcall(api.percent,metric)
      if ok then v[metric=="SessionAverageTime" and "session" or "recent"]=data end
    end
    for key,metric in pairs({over1="CountTimeOver1Ms",over5="CountTimeOver5Ms",over10="CountTimeOver10Ms"}) do
      local ok,data=pcall(api.own,metric);if ok then v[key]=data end
    end
    return v
  end
  local function delta(c,a,b)
    for _,key in ipairs({"over1","over5","over10"}) do
      if number(a[key]) and number(b[key]) and b[key]<a[key] then c.reset=true end
    end
    for _,key in ipairs({"over1","over5","over10"}) do
      if not c.reset and number(a[key]) and number(b[key]) then c[key]=b[key]-a[key] end
    end
  end
  local function add(name,open,close,reason,idle)
    local c={name=name,status=reason and "skipped" or "pending",reason=reason,idle=idle,opens=0,repeats=0}
    result.cases[#result.cases+1]=c;actions[#actions+1]={open=open,close=close}
    return actions[#actions]
  end
  local A=ns.AuctionHouse
  local oldPage=ns.UI.GetWorkspacePage and ns.UI.GetWorkspacePage() or "overview"
  local settingsBlocked=shown(BaimiaoToolboxWorkspace) or (A and (A.IsBusy() or A.IsPurchasing() or shown(A.panel)))
  local auctionBlocked=settingsBlocked or not A or A.IsOpen() or shown(AuctionHouseFrame)
    or (A and not ns.IsModuleEnabled("auctionhouse"))
  local oldAuction=A and A.panel and {tab=A.panel.tab,group=A.panel.group,page=A.panel.page}
  local mythicBlocked=not ns.IsModuleEnabled("mythicplus") or not ns.MythicPlus or not ns.MythicPlus.GetDB().show
    or not PVEFrame or not ChallengesFrame or not PVEFrame_ShowFrame or not HideUIPanel
    or shown(PVEFrame) or protected(PVEFrame) or protected(ChallengesFrame)
  -- Opening a native UIPanel can displace another one. Do not take over that UI.
  if GetUIPanel then for _,slot in ipairs({"left","center","right","doublewide","fullscreen"}) do
    if GetUIPanel(slot) then mythicBlocked=true end
  end end
  if shown(AuctionHouseFrame) or shown(SettingsPanel) then mythicBlocked=true end
  local oldMythic=PVEFrame and {selectedTab=PVEFrame.selectedTab,width=PVEFrame:GetWidth(),height=PVEFrame:GetHeight(),scale=PVEFrame:GetScale(),tab=PVEFrame.activeTabIndex,challengeShown=shown(ChallengesFrame)}
  local nativeRegions={}
  if not mythicBlocked then
    -- Pinned Blizzard PVEFrame_ShowFrame changes these regions and the selected tab.
    -- Capture their shown state, not visible state (the parent starts hidden).
    for _,name in ipairs({"GroupFinderFrame","PVPUIFrame","ChallengesFrame","PVEFrameLeftInset","PVEFrameBlueBg",
      "PVEFrameTLCorner","PVEFrameTRCorner","PVEFrameBRCorner","PVEFrameBLCorner","PVEFrameLLVert","PVEFrameRLVert",
      "PVEFrameBottomLine","PVEFrameTopLine","PVEFrameTopFiligree","PVEFrameBottomFiligree"}) do
      local f=_G[name];if f then nativeRegions[#nativeRegions+1]={frame=f,shown=f:IsShown()} end
    end
    if PVEFrame.shadows then nativeRegions[#nativeRegions+1]={frame=PVEFrame.shadows,shown=PVEFrame.shadows:IsShown()} end
    if PVEFrame.GetNumPoints then
      oldMythic.points={}
      for i=1,PVEFrame:GetNumPoints() do oldMythic.points[i]={PVEFrame:GetPoint(i)} end
    end
  end
  local function closeSettings() if BaimiaoToolboxWorkspace then BaimiaoToolboxWorkspace:Hide() end end
  local function closeAuction() if A and A.panel then A.panel.pendingShow=nil;A.panel:Hide() end end
  local function closeMythic() if PVEFrame then HideUIPanel(PVEFrame) end end
  restorers[#restorers+1]=function()
    if touchedSettings then
      closeSettings()
      -- Restore navigation as well as visibility; do not change theme or settings.
      ns.UI.RestoreClosedWorkspacePage(oldPage)
    end
  end
  restorers[#restorers+1]=function()
    if touchedAuction then
      closeAuction()
      if oldAuction and A.panel then A.panel.tab=oldAuction.tab;A.panel.group=oldAuction.group;A.panel.page=oldAuction.page end
    end
  end
  restorers[#restorers+1]=function()
    if touchedMythic then
      closeMythic()
      if oldMythic then
        PVEFrame:SetSize(oldMythic.width,oldMythic.height);PVEFrame:SetScale(oldMythic.scale)
        PVEFrame.activeTabIndex=oldMythic.tab
        if PanelTemplates_SetTab and oldMythic.selectedTab then PanelTemplates_SetTab(PVEFrame,oldMythic.selectedTab)
        else PVEFrame.selectedTab=oldMythic.selectedTab end
        for _,entry in ipairs(nativeRegions) do entry.frame:SetShown(entry.shown) end
        if oldMythic.points then
          PVEFrame:ClearAllPoints();for _,point in ipairs(oldMythic.points) do PVEFrame:SetPoint(unpack(point)) end
        end
      end
    end
  end
  add("Idle/before",nil,nil,nil,true)
  local function setting(id)
    add("Settings/"..id,function()touchedSettings=true;ns.OpenOptions(id)end,closeSettings,
      settingsBlocked and "window in use" or nil)
  end
  setting("overview")
  -- A bounded root-page traversal; no synthetic clicks, expanded groups or edits.
  for i,m in ipairs(ns.orderedModules) do if i<=16 and m.BuildOptions then setting(m.id) end end
  for _,tab in ipairs({"quick","restock","recipes"}) do
    local key=tab
    add("Auction/"..key,function()
      touchedAuction=true
      if A.panel then A.panel.tab=key;A.panel.page=1 end
      A.ShowPanel(true)
      if not A.panel or not A.panel:IsVisible() then error("auction preview not visible") end
      if not oldAuction then oldAuction={tab="quick",group=A.panel.group,page=1} end
    end,closeAuction,auctionBlocked and "preview unavailable or window in use" or nil)
  end
  local mythicAction=add("MythicPlus",function()
    touchedMythic=true;PVEFrame_ShowFrame("ChallengesFrame")
    if not ChallengesFrame:IsVisible() then error("mythic tab not visible") end
  end,closeMythic,mythicBlocked and "native UI unavailable, protected or in use" or nil)
  mythicAction.skipReason=function()
    -- Secure children can protect the native frame after its first successful open.
    -- Keep the safety check, but skip only this case rather than losing Idle/after.
    if protected(PVEFrame) or protected(ChallengesFrame) then return "native UI became protected" end
    if GetUIPanel then for _,slot in ipairs({"left","center","right","doublewide","fullscreen"}) do
      if GetUIPanel(slot) then return "native UI now in use" end
    end end
  end
  add("Idle/after",nil,nil,nil,true)

  local function complete(reason)
    if stopped then return end
    if timer then timer:Cancel();timer=nil end
    result.seconds=result.seconds or math.max(0,GetTime()-started)
    result.status=reason or result.status
    if InCombatLockdown() and reason~="PLAYER_LOGOUT" then
      if not waiting then api.say(T["自动回放已停止；脱战后恢复界面，不再继续测试。"]) end
      waiting=true;replayFrame:UnregisterAllEvents()
      replayFrame:RegisterEvent("PLAYER_REGEN_ENABLED");replayFrame:RegisterEvent("PLAYER_LOGOUT")
      return
    end
    stopped=true
    if row and row.status=="running" then row.status="interrupted" end
    for _,c in ipairs(result.cases) do if c.status=="pending" then c.status="skipped";c.reason="not run" end end
    if reason~="PLAYER_LOGOUT" then
      for _,restore in ipairs(restorers) do
        local ok,err=pcall(restore)
        if not ok then result.error=(result.error or "").." restore: "..tostring(err):sub(1,300);result.status="restore-error" end
      end
    end
    replayFrame:UnregisterAllEvents();replayFrame:SetScript("OnEvent",nil)
    actions,restorers,before=nil,nil,nil
    api.done(result)
    ns.PrintUIReplay(result,api.say)
  end
  s.cancel=function(reason)complete(reason or "cancelled")end
  local function interaction()
    -- Do not steal a newly opened window or clear someone's editor/chat focus.
    local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.IsVisible and focus:IsVisible() then
      touchedSettings=false;touchedAuction=false;touchedMythic=false;return true
    end
    local settingsOwned=row and row.name:match("^Settings/") and stage=="close"
    local auctionOwned=row and row.name:match("^Auction/") and stage=="close"
    local mythicOwned=row and row.name=="MythicPlus" and stage=="close"
    if not settingsBlocked and shown(BaimiaoToolboxWorkspace) and not settingsOwned then touchedSettings=false;return true end
    if not auctionBlocked and A and shown(A.panel) and not auctionOwned then touchedAuction=false;return true end
    if not mythicBlocked and shown(PVEFrame) and not mythicOwned then touchedMythic=false;return true end
    if mythicOwned and PVEFrame.activeTabIndex~=3 then touchedMythic=false;return true end
    if A and (A.IsBusy() or A.IsPurchasing()) and not settingsBlocked then return true end
    if settingsOwned and not shown(BaimiaoToolboxWorkspace) then return true end
    if auctionOwned and not shown(A.panel) then return true end
    if mythicOwned and not shown(PVEFrame) then return true end
  end
  local function measure(fn)
    local t=debugprofilestop();local ok,err=pcall(fn);local elapsed=debugprofilestop()-t
    if not ok then error(err) end
    if number(elapsed) then return elapsed end
  end
  local function openCurrent()
    local action=actions[index]
    local reason=action.skipReason and action.skipReason()
    if reason then
      row.status=row.opens>0 and "partial" or "skipped";row.reason=reason
      delta(row,before,snapshot())
      index=index+1;stage="begin"
      return
    end
    local elapsed=measure(action.open)
    row.opens=row.opens+1
    if row.opens==1 then row.firstOpen=elapsed
    else
      row.repeats=row.repeats+1
      if elapsed then row.repeatMax=math.max(row.repeatMax or 0,elapsed);row.repeatTotal=(row.repeatTotal or 0)+elapsed end
    end
    stage="close";deadline=GetTime()+.25
  end
  local function tick()
    if stopped or waiting then return end
    if InCombatLockdown() then complete("combat");return end
    if GetTime()-started>60 then complete("timeout");return end
    if interaction() then complete("interaction");return end
    if GetTime()<deadline then return end
    if stage=="begin" then
      row=result.cases[index]
      while row and row.status=="skipped" do index=index+1;row=result.cases[index] end
      if not row then complete("complete");return end
      before=snapshot();row.status="running"
      if row.idle then stage="idle";deadline=GetTime()+3 else openCurrent() end
    elseif stage=="idle" then
      local after=snapshot();delta(row,before,after);row.status="ok"
      result[row.name=="Idle/before" and "before" or "after"]=after
      index=index+1;stage="begin"
    elseif stage=="close" then
      local elapsed=measure(actions[index].close)
      if elapsed then row.closeTotal=(row.closeTotal or 0)+elapsed end
      stage="closed";deadline=GetTime()+.25
    elseif stage=="closed" then
      if row.opens<3 then openCurrent()
      else delta(row,before,snapshot());row.status="ok";index=index+1;stage="begin" end
    end
  end
  replayFrame=replayFrame or CreateFrame("Frame")
  replayFrame:UnregisterAllEvents()
  for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_LOGOUT","PLAYER_STARTED_MOVING","ZONE_CHANGED_NEW_AREA","AUCTION_HOUSE_SHOW"}) do replayFrame:RegisterEvent(event) end
  replayFrame:SetScript("OnEvent",function(_,event)
    if waiting and event=="PLAYER_REGEN_ENABLED" then complete(result.status)
    else complete(event) end
  end)
  timer=C_Timer.NewTicker(.25,function()
    local ok,err=pcall(tick)
    if not ok then result.error=tostring(err):sub(1,500);complete("error") end
  end)
  api.say(T["开始自动界面回放，约40秒：自动开关展示页，无需点击。跳过在用窗口；不购买、不搜索、不传送、不改开关。/bmperf cancel 可停止。"])
  return s
end

if ns.StartupCheckpoint then ns.StartupCheckpoint("DiagnosticsUIReplay.lua") end
