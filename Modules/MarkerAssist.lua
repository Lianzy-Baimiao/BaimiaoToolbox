-- Compact, manual raid tools. No ping system, assignments or third-party timers.
-- Secure marker actions are built once outside combat; their parent is never
-- moved, resized or hidden by insecure code during combat lockdown.
local ADDON,ns=...
local T = ns.L
local M={};ns.MarkerAssist=M
local UI=ns.UI
local WHITE="Interface\\Buttons\\WHITE8x8"
local defaults={enabled=true,groupOnly=true,leaderOnly=false,locked=true,scalePercent=100,
    showTargets=true,showWorlds=true,showManagement=true}
local bar,running,pending=nil,false,false
local laidOutTargets,laidOutWorlds,laidOutManagement
local events=CreateFrame("Frame")
local function DB()
    local d=ns.GetDB("smalltools")
    if type(d.marker)~="table" then d.marker={}end
    ns.applyDefaults(d.marker,defaults);return d.marker
end
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,v=pcall(fn,...)
    if ok and not (issecretvalue and issecretvalue(v)) then return v end
end
local function grouped()
    return call(IsInGroup)==true or call(IsInGroup,LE_PARTY_CATEGORY_INSTANCE or 2)==true
end
local function enabled()return running and ns.IsModuleEnabled("smalltools") and DB().enabled end
local function manager()
    return grouped() and (call(UnitIsGroupLeader,"player")==true
        or (call(IsInRaid)==true and call(UnitIsGroupAssistant,"player")==true))
end
local function permitted()
    if not enabled() or not DB().showManagement then return false end
    if InCombatLockdown() then ns.Print(T["请脱战后操作就位确认或倒数。"]);return false end
    if not manager() then ns.Print(T["需要小队队长、团长或团队助理权限。"]);return false end
    return true
end
local function countdown(seconds)
    if not permitted() then return end
    if not C_PartyInfo or type(C_PartyInfo.DoCountdown)~="function" then
        ns.Print(T["原生团队倒数接口暂不可用。"]);return
    end
    local ok,result=pcall(C_PartyInfo.DoCountdown,seconds)
    if not ok or (issecretvalue and issecretvalue(result)) or result~=true then
        ns.Print(T["游戏未接受倒数操作，请检查当前队伍或副本状态。"])
    end
end
local function ready()
    if not permitted() then return end
    local fn=C_PartyInfo and C_PartyInfo.DoReadyCheck or DoReadyCheck
    if type(fn)~="function" then ns.Print(T["就位确认接口暂不可用。"]);return end
    local ok=pcall(fn);if not ok then ns.Print(T["游戏未接受就位确认，请稍后再试。"])end
end
local function text(parent,value,size,role)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    UI.SetRuntimeFont(f,GameFontNormal:GetFont(),size or 11);f:SetText(value)
    UI.StyleText(f,role or "text");return f
end
local function skin(f)
    f:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=1})
    UI.OnTheme(function()
        f:SetBackdropColor(unpack(UI.palette.card));f:SetBackdropBorderColor(unpack(UI.palette.border))
    end)
end
local function tooltip(b,title,line)
    b:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_CURSOR");GameTooltip:SetText(title)
        if line then GameTooltip:AddLine(line,.7,.8,.8,true)end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function()GameTooltip:Hide()end)
end
local markNames={T["星星"],T["圆圈"],T["菱形"],T["三角"],T["月亮"],T["方块"],T["叉号"],T["骷髅"]}
-- World-marker IDs are not raid-target icon IDs.
local worldIDs={5,6,3,2,7,1,4,8}
local function secureButton(index,world)
    local b=CreateFrame("Button",nil,bar,"SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(26,24);b:SetPoint("TOPLEFT",46+(index-1)*29,world and -56 or -28)
    b:RegisterForClicks("AnyDown","AnyUp");skin(b)
    b:SetAttribute("type",world and "worldmarker" or "raidtarget")
    if not world then b:SetAttribute("unit","target")end
    if index<=8 then
        b:SetAttribute("marker",world and worldIDs[index] or index)
        b:SetAttribute("action1","set");b:SetAttribute("action2","clear")
        local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(18,18);icon:SetPoint("CENTER")
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_"..index)
        tooltip(b,(world and T["地面 · "] or T["目标 · "])..markNames[index],
            world and T["左键放置，右键清除此地面标记。"] or T["左键标记当前目标，右键清除当前目标标记。"])
    else
        b:SetAttribute("action","clear") -- nil world marker means clear ALL.
        local label=text(b,"×",18,"muted");label:SetPoint("CENTER")
        tooltip(b,world and T["清除全部地面标记"] or T["清除当前目标标记"])
    end
    return b
end
local function action(label,x,width,callback,tip)
    local b=CreateFrame("Button",nil,bar,"UIPanelButtonTemplate")
    b:SetSize(width,24);b:SetPoint("TOPLEFT",x,-86);b:SetText(label)
    UI.SkinTextButton(b);UI.StyleText(b:GetFontString(),"text")
    UI.RegisterRuntimeFont(b:GetFontString())
    b:SetScript("OnClick",callback);tooltip(b,tip or label);return b
end
local function position()
    local p=ns.GetLayoutDB("markerassist")
    bar:ClearAllPoints();bar:SetPoint("CENTER",UIParent,"CENTER",tonumber(p.x) or 0,tonumber(p.y) or -160)
end
local function build()
    bar=CreateFrame("Frame","BaimiaoMarkerAssist",UIParent,"BackdropTemplate")
    bar:SetSize(314,118);bar:SetFrameStrata("MEDIUM");bar:SetClampedToScreen(true);bar:SetMovable(true)
    skin(bar);bar:Hide()
    local title=text(bar,T["标记助手"],11,"accent");title:SetPoint("TOPLEFT",8,-7)
    local drag=CreateFrame("Frame",nil,bar);drag:SetPoint("TOPLEFT",0,0);drag:SetSize(244,24)
    drag:EnableMouse(true);drag:RegisterForDrag("LeftButton");bar.drag=drag
    drag:SetScript("OnDragStart",function()
        if not InCombatLockdown() and not DB().locked then bar:StartMoving();bar.moving=true end
    end)
    drag:SetScript("OnDragStop",function()
        if InCombatLockdown() or not bar.moving then return end
        bar:StopMovingOrSizing();bar.moving=nil
        local x,y=bar:GetCenter();local ux,uy=UIParent:GetCenter()
        local ratio=UIParent:GetEffectiveScale()/bar:GetEffectiveScale()
        local p=ns.GetLayoutDB("markerassist");p.x=x-ux*ratio;p.y=y-uy*ratio
    end)
    tooltip(drag,T["标记助手"],T["解锁后拖动此标题栏。"])
    local config=CreateFrame("Button",nil,bar,"UIPanelButtonTemplate")
    config:SetSize(44,18);config:SetPoint("TOPRIGHT",-8,-4);config:SetText(T["设置"])
    UI.SkinTextButton(config);UI.StyleText(config:GetFontString(),"muted")
    UI.RegisterRuntimeFont(config:GetFontString())
    config:SetScript("OnClick",function()ns.OpenOptions("smalltools")end)
    bar.targetLabel=text(bar,T["目标"],11,"muted")
    bar.worldLabel=text(bar,T["地面"],11,"muted")
    bar.targets={};bar.worlds={}
    for i=1,9 do bar.targets[i]=secureButton(i,false);bar.worlds[i]=secureButton(i,true)end
    bar.ready=action(T["就位"],8,54,ready)
    bar.pull5=action(T["倒数 5秒"],68,76,function()countdown(5)end,T["原生团队管理倒数 · 5 秒"])
    bar.pull10=action(T["10秒"],150,64,function()countdown(10)end,T["原生团队管理倒数 · 10 秒"])
    bar.cancel=action(T["取消倒数"],220,86,function()countdown(0)end,T["取消原生团队倒数"])
    position()
end
-- Called only outside lockdown, including every row's protected children.
local function layoutRows()
    local d=DB();local y,count,bottom=28,0,32
    local function visible(f,show)
        if not show and GameTooltip:IsOwned(f) then GameTooltip:Hide()end
        f:SetShown(show)
    end
    local function markers(buttons,label,show)
        label:SetShown(show)
        if show then label:ClearAllPoints();label:SetPoint("TOPLEFT",8,-y-6)end
        for i,b in ipairs(buttons)do
            visible(b,show)
            if show then b:ClearAllPoints();b:SetPoint("TOPLEFT",46+(i-1)*29,-y)end
        end
        if show then bottom=y+32;y=y+28;count=count+1 end
    end
    markers(bar.targets,bar.targetLabel,d.showTargets)
    markers(bar.worlds,bar.worldLabel,d.showWorlds)
    if d.showManagement and count>0 then y=y+2 end
    local offsets={8,68,150,220}
    for i,b in ipairs({bar.ready,bar.pull5,bar.pull10,bar.cancel})do
        visible(b,d.showManagement)
        if d.showManagement then b:ClearAllPoints();b:SetPoint("TOPLEFT",offsets[i],-y)end
    end
    if d.showManagement then bottom=y+32;count=count+1 end
    bar:SetHeight(bottom)
    return count>0
end
function M.Refresh()
    if InCombatLockdown() then pending=true;return end
    pending=false
    local d=DB()
    local hasRows=d.showTargets or d.showWorlds or d.showManagement
    local show=enabled() and hasRows and (not d.groupOnly or grouped())
        and (not d.leaderOnly or (grouped() and call(UnitIsGroupLeader,"player")==true))
    -- A hidden group/leader-only bar has no work to do at login. Build once
    -- when it can actually be shown; combat requests are rechecked on regen.
    if not bar then
        if not show then return end
        build()
    end
    -- Roster/leader events affect eligibility, not row geometry. Keep rows
    -- synchronized with settings without repositioning every secure button.
    if laidOutTargets~=d.showTargets or laidOutWorlds~=d.showWorlds
        or laidOutManagement~=d.showManagement then
        layoutRows()
        laidOutTargets,laidOutWorlds,laidOutManagement=d.showTargets,d.showWorlds,d.showManagement
    end
    if not show and bar:IsShown() then
        for _,f in ipairs({bar:GetChildren()})do if GameTooltip:IsOwned(f) then GameTooltip:Hide();break end end
    end
    local scale=math.max(70,math.min(140,tonumber(d.scalePercent) or 100))/100
    if bar:GetScale()~=scale then bar:SetScale(scale)end
    if bar:IsShown()~=show then bar:SetShown(show)end
end
function M.Start()
    running=true
    for _,event in ipairs({"GROUP_ROSTER_UPDATE","PARTY_LEADER_CHANGED","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED"})do events:RegisterEvent(event)end
    M.Refresh()
end
function M.Stop()
    running=false;M.Refresh()
    if not pending then events:UnregisterAllEvents()end
end
function M.AddOptionGroups(groups)
    groups[#groups+1]={title=T["标记助手"],collapsed=true,
        enabled=function()return DB().enabled end,setEnabled=function(v)DB().enabled=v;M.Refresh()end,
        build=function(_,L)
            L:Row({
                function(cell) cell:Check(T["目标标记"],function()return DB().showTargets end,function(v)DB().showTargets=v end,M.Refresh) end,
                function(cell) cell:Check(T["地面标记"],function()return DB().showWorlds end,function(v)DB().showWorlds=v end,M.Refresh) end,
                function(cell) cell:Check(T["团队管理（就位 / 倒数）"],function()return DB().showManagement end,function(v)DB().showManagement=v end,M.Refresh) end,
            })
            L:Row({
                function(cell) cell:Check(T["仅在小队 / 团队中显示"],function()return DB().groupOnly end,function(v)DB().groupOnly=v end,M.Refresh) end,
                function(cell) cell:Check(T["仅队长显示"],function()return DB().leaderOnly end,function(v)DB().leaderOnly=v end,M.Refresh) end,
                function(cell) cell:Check(T["锁定位置"],function()return DB().locked end,function(v)DB().locked=v end) end,
            })
            L:step(8)
            L:Row({
                function(cell) cell:Slider("BaimiaoMarkerScale",T["标记助手缩放（%）"],70,140,5,function()return DB().scalePercent end,function(v)DB().scalePercent=v end,M.Refresh) end,
                function(cell)
                    cell:step(18)
                    cell:Button(160,T["重置标记助手位置"],function()
                        if InCombatLockdown() then return end
                        local p=ns.GetLayoutDB("markerassist");p.x=nil;p.y=nil
                        if bar then position()end
                    end)
                end,
            }, 260)
        end}
end

events:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_REGEN_DISABLED" then
        -- Do not invoke protected StopMoving/geometry changes after lockdown.
        return
    end
    if event=="PLAYER_REGEN_ENABLED" and bar and bar.moving then bar:StopMovingOrSizing();bar.moving=nil end
    M.Refresh()
    if not running and not pending then events:UnregisterAllEvents()end
end)

if ns.PerfWatchFrame then ns.PerfWatchFrame("MarkerAssist", events, "OnEvent") end
