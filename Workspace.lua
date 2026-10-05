-- Presentation-only workspace. Module options and secure action logic stay in Core/Modules.
local ADDON, ns = ...
local T = ns.L
local UI = ns.UI
local WHITE = "Interface\\Buttons\\WHITE8x8"
local WINDOW_WIDTH, WINDOW_HEIGHT = 1000, 660
local palettes = {
    dark = {
        bg={0.045,0.065,0.080,1}, rail={0.060,0.085,0.100,1},
        card={0.080,0.110,0.125,1}, hover={0.115,0.175,0.185,1},
        border={0.19,0.26,0.28,1}, text={0.89,0.93,0.92,1},
        muted={0.57,0.67,0.69,1}, accent={0.40,0.82,0.69,1},
        warning={1,0.82,0,1}, success={0.13,1,0.25,1}, danger={1,0.45,0.35,1},
    },
    light = {
        isLight=true,
        bg={0.945,0.949,0.953,1}, rail={0.905,0.914,0.922,1},
        card={0.990,0.992,0.995,1}, hover={0.915,0.925,0.935,1},
        border={0.78,0.80,0.82,1}, text={0.12,0.15,0.19,1},
        muted={0.34,0.38,0.43,1}, accent={0.09,0.38,0.30,1},
        warning={0.49,0.30,0.04,1}, success={0.10,0.38,0.23,1}, danger={0.70,0.17,0.15,1},
    },
}
local painters, workspace, current, nav, pages = {}, nil, "overview", {}, {}
local createModulePage, createAppearancePage
local settingsInitialized=false
UI.palette = palettes.dark
local function prefs()
    local db = ns.GetPCDB()
    db.workspace = db.workspace or {}
    return db.workspace
end
function UI.OnTheme(fn)
    painters[#painters+1] = fn
    fn()
end
local function paintText(fs)
    local p = fs._bmTextOnWorld and palettes.dark or UI.palette
    fs:SetTextColor(unpack(p[fs._bmTextRole]))
    UI.RefreshTextFont(fs)
end
-- Explicit world context is for cards whose background can be hidden; it keeps
-- readable overlay text without touching the font style of icons or native UI.
function UI.StyleText(fs, role, overWorld)
    fs._bmTextRole = role or "text"
    fs._bmTextOnWorld = not not overWorld
    if fs._bmTextStyled then paintText(fs); return end
    fs._bmTextStyled = true
    UI.OnTheme(function() paintText(fs) end)
end
local function text(parent, value, size, role)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local font = GameFontNormal:GetFont()
    fs:SetFont(font, size or 13, "")
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(value)
    UI.StyleText(fs, role or "text")
    return fs
end
local function surface(parent, role)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({bgFile=WHITE, edgeFile=WHITE, edgeSize=1})
    UI.OnTheme(function()
        f:SetBackdropColor(unpack(UI.palette[role or "card"]))
        f:SetBackdropBorderColor(unpack(UI.palette.border))
    end)
    return f
end
local function button(parent, value, w, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, 32); b:SetText(value)
    UI.SkinTextButton(b)
    UI.StyleText(b:GetFontString(), "text")
    b:SetScript("OnClick", callback)
    return b
end
-- Native options use GameFont* and sometimes explicit semantic colors. Register
-- neutral fonts once; leave red validation, color samples and game icons intact.
local function styleOptions(frame)
    for _, r in ipairs({frame:GetRegions()}) do
        if r:GetObjectType() == "FontString" and not r._bmTextRole then
            local red, green, blue = r:GetTextColor()
            local role = "text"
            if math.abs(red-green)<0.16 and math.abs(green-blue)<0.16 and red<0.7 then role="muted" end
            if green>red+0.25 and green>blue then role="accent" end
            if not (red>0.8 and green<0.35 and blue<0.35) then UI.StyleText(r, role) end
            local font, size = r:GetFont()
            if font then r:SetFont(font, math.max(size or 12, 12), "") end
            r:SetShadowOffset(0, 0)
        end
    end
    if frame:GetObjectType()=="EditBox" and not frame._bmTextRole then UI.StyleText(frame,"text") end
    for _, child in ipairs({frame:GetChildren()}) do styleOptions(child) end
end
-- 动态新增的设置行复用与初次构建相同的主题 / 字体处理。
UI.StyleOptions = styleOptions
local function applyTheme()
    UI.palette = palettes[prefs().theme] or palettes.dark
    for _, paint in ipairs(painters) do paint() end
    if workspace then workspace.theme:SetText(prefs().theme=="light" and T["切换深色"] or T["切换浅色"]) end
end
local function version()
    return (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON,"Version")) or "1.5.0"
end
local descriptions = {
    coord=T["坐标、移速、距离与快捷通报。"],
    coordshout=T["坐标、移速、距离与快捷通报。"],
    quickmount=T["常用坐骑与扩展动作。"],
    reminder=T["光环与宠物准备提醒。"],
    raidcd=T["嗜血、战复与触发音乐。"],
    rotation=T["技能循环与冷却提示。"],
    mythicplus=T["副本成绩、记录与手动传送。"],
    smalltools=T["右键操作、进本与排队提醒、交易回执。"],
    auctionhouse=T["快捷搜索、清单与追踪配方补货。"],
}
local icons={135802,132261,135940,136012,135959,525134,133742,133784}
local function combatMessage()
    if InCombatLockdown() then
        ns.Print(T["战斗中暂不修改工具箱配置；请脱战后再试。"])
        return true
    end
    return false
end
local function refresh()
    local count=0
    for _, m in ipairs(ns.orderedModules) do
        if ns.IsModuleEnabled(m.id) then count=count+1 end
        if m._workspaceStatus then
            m._workspaceStatus:SetText(ns.IsModuleEnabled(m.id) and T["已启用"] or T["已停用"])
            m._workspaceToggle:SetText(ns.IsModuleEnabled(m.id) and T["停用"] or T["启用"])
        end
    end
    workspace.summary:SetText(count.." / "..#ns.orderedModules..T["  功能已启用"])
    workspace.minimap:SetText(ns.IsMinimapButtonShown() and T["小地图入口：显示"] or T["小地图入口：隐藏"])
    if workspace.currentModule then
        workspace.toggle:SetText(ns.IsModuleEnabled(workspace.currentModule.id) and T["模块已启用 · 点击停用"] or T["模块已停用 · 点击启用"])
    end
end
local function selectPage(key)
    if InCombatLockdown() then return end
    local module=ns.modules[key]
    key=(pages[key] or (module and module.BuildOptions) or key=="appearance") and key or "overview"
    -- WoW frames live for the whole session. Build only visited pages, once.
    if not pages[key] then
        if key=="appearance" then createAppearancePage()
        else createModulePage(ns.modules[key]) end
    end
    -- Commit/clear an actively edited native option before hiding its page.
    if GetCurrentKeyBoardFocus then
        local focus=GetCurrentKeyBoardFocus()
        if focus then focus:ClearFocus() end
    end
    current=key
    for id, page in pairs(pages) do page:SetShown(id==key) end
    for id, item in pairs(nav) do
        item.selection:SetShown(id==key)
        item.edge:SetShown(id==key)
    end
    local m=ns.modules[key]
    workspace.currentModule=m
    workspace.heading:SetText(m and m.name or (key=="appearance" and T["外观设置"] or T["旅程，从容开始。"]))
    workspace.eyebrow:SetText(m and T["修改即时生效 · 输入框回车或失焦保存"] or (key=="appearance" and T["APPEARANCE / 全局外观"] or "YOUR ADVENTURE, ORGANIZED"))
    workspace.toggle:SetShown(m~=nil)
    if m and m._syncLayout and not InCombatLockdown() then m._syncLayout:SyncAll() end
    refresh()
end
local function fitWindow()
    if not workspace then return end
    local w,h=UIParent:GetWidth(),UIParent:GetHeight()
    local scale=math.min(1, (w-32)/WINDOW_WIDTH, (h-32)/WINDOW_HEIGHT)
    workspace:SetScale(math.max(0.35,scale))
end
local function navItem(key, label, index)
    local b=CreateFrame("Button",nil,workspace.rail)
    b:SetSize(168,38); b:SetPoint("TOPLEFT",12,-52-index*44)
    local selection=b:CreateTexture(nil,"BACKGROUND")
    selection:SetAllPoints(); b.selection=selection
    local edge=b:CreateTexture(nil,"ARTWORK")
    edge:SetSize(3,24); edge:SetPoint("LEFT"); b.edge=edge
    local number=text(b,string.format("%02d",index+1),10,"muted");number:SetPoint("LEFT",10,0)
    local title=text(b,label,13);title:SetPoint("LEFT",38,0)
    title:SetWidth(120)
    local hover=b:CreateTexture(nil,"HIGHLIGHT");hover:SetAllPoints()
    UI.OnTheme(function()
        selection:SetColorTexture(unpack(UI.palette.hover))
        edge:SetColorTexture(unpack(UI.palette.accent))
        hover:SetColorTexture(UI.palette.accent[1],UI.palette.accent[2],UI.palette.accent[3],0.08)
    end)
    b:SetScript("OnClick",function() selectPage(key) end)
    nav[key]=b
end
local function createOverview()
    local host=CreateFrame("Frame",nil,workspace.content)
    host:SetAllPoints(); pages.overview=host
    local home=UI.MakeScrollable(host)
    -- Keep the original identity/header; density comes from individual cards.
    local columns,gap=3,12
    local cardWidth=(738-(columns-1)*gap)/columns
    local footerY=150+math.ceil(#ns.orderedModules/columns)*112
    home:SetHeight(footerY+40)
    local hero=surface(home,"rail");workspace.hero=hero
    hero:SetPoint("TOPLEFT",0,0);hero:SetPoint("TOPRIGHT",0,0);hero:SetHeight(104)
    local kicker=text(hero,"BAIMIAO / FIELD NOTES",10,"accent");kicker:SetPoint("TOPLEFT",22,-14)
    workspace.heroTitle=text(hero,T["少一点繁琐，多一点冒险。"],23);workspace.heroTitle:SetPoint("TOPLEFT",22,-34)
    workspace.heroSubtitle=text(hero,T["轻量工具，自由组合。一个属于你的游戏工作台。"],12,"muted")
    workspace.heroSubtitle:SetPoint("TOPLEFT",22,-72)
    local cat=hero:CreateTexture(nil,"ARTWORK")
    cat:SetTexture("Interface\\AddOns\\BaimiaoToolbox\\media\\cat_icon.tga")
    cat:SetSize(70,70);cat:SetPoint("RIGHT",-25,0);cat:SetAlpha(.7)
    workspace.toolsTitle=text(home,T["我的工具"],13);workspace.toolsTitle:SetPoint("TOPLEFT",0,-122)
    workspace.summary=text(home,"",12,"muted");workspace.summary:SetPoint("TOPRIGHT",-2,-123)
    for i,m in ipairs(ns.orderedModules) do
        local col=(i-1)%columns;local row=math.floor((i-1)/columns)
        local card=surface(home)
        card:SetSize(cardWidth,104);card:SetPoint("TOPLEFT",col*(cardWidth+gap),-150-row*112)
        local icon=card:CreateTexture(nil,"ARTWORK")
        icon:SetSize(30,30);icon:SetPoint("TOPLEFT",14,-10)
        icon:SetTexture(icons[i] or 134400);icon:SetTexCoord(0.08,0.92,0.08,0.92)
        local name=text(card,m.name or m.id,15);name:SetPoint("TOPLEFT",54,-10);name:SetWidth(cardWidth-68)
        local status=text(card,"",11,"accent");status:SetPoint("TOPLEFT",54,-30)
        m._workspaceStatus=status
        local desc=text(card,descriptions[m.id] or m.desc or T["独立配置，按需启用。"],11,"muted")
        desc:SetPoint("TOPLEFT",14,-48);desc:SetSize(cardWidth-28,16)
        local configure=button(card,T["打开设置"],92,function() selectPage(m.id) end)
        configure:SetPoint("BOTTOMRIGHT",-14,8);configure:SetHeight(26)
        local toggle=button(card,"",60,function()
            if combatMessage() then return end
            ns.SetModuleEnabled(m.id,not ns.IsModuleEnabled(m.id));refresh()
        end)
        toggle:SetPoint("BOTTOMLEFT",14,8);toggle:SetHeight(26);m._workspaceToggle=toggle
    end
    workspace.minimap=button(home,"",164,function()
        if combatMessage() then return end
        ns.SetMinimapButtonShown(not ns.IsMinimapButtonShown());refresh()
    end)
    workspace.minimap:SetPoint("TOPLEFT",0,-footerY);workspace.minimap:SetHeight(28)
    local hint=text(home,T["Alt + 右键屏上工具可直达设置"],11,"muted")
    hint:SetPoint("TOPRIGHT",-2,-footerY-8)
end
-- Slim scrollbars keep the options free of the default gold arrow ornaments.
-- The scroll child's width never changes when the bar hides, so text stays aligned.
function UI.MakeScrollable(host)
    local scroll=CreateFrame("ScrollFrame",nil,host)
    scroll:SetPoint("TOPLEFT",2,-2);scroll:SetPoint("BOTTOMRIGHT",-28,2)
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(738,1)
    scroll:SetScrollChild(child)
    local bar=CreateFrame("Slider",nil,host)
    bar:SetPoint("TOPRIGHT",-5,-4);bar:SetPoint("BOTTOMRIGHT",-5,4);bar:SetWidth(12)
    bar:SetOrientation("VERTICAL");bar:SetMinMaxValues(0,0);bar:SetValueStep(1)
    local track=bar:CreateTexture(nil,"BACKGROUND");track:SetWidth(2)
    track:SetPoint("TOP",0,0);track:SetPoint("BOTTOM",0,0)
    local thumb=bar:CreateTexture(nil,"ARTWORK");thumb:SetSize(6,36);bar:SetThumbTexture(thumb)
    UI.OnTheme(function()
        track:SetColorTexture(unpack(UI.palette.border))
        thumb:SetColorTexture(unpack(UI.palette.accent))
    end)
    local updating=false
    local function update()
        if updating then return end
        updating=true
        local range=math.max(0,scroll:GetVerticalScrollRange())
        local offset=math.min(math.max(0,scroll:GetVerticalScroll()),range)
        bar:SetMinMaxValues(0,range);bar:SetValue(offset);bar:SetShown(range>1)
        if offset~=scroll:GetVerticalScroll() then scroll:SetVerticalScroll(offset) end
        updating=false
    end
    bar:SetScript("OnValueChanged",function(_,value)
        if not updating then scroll:SetVerticalScroll(value) end
    end)
    scroll:SetScript("OnVerticalScroll",update)
    scroll:SetScript("OnScrollRangeChanged",update)
    scroll:SetScript("OnSizeChanged",function(_,w) if w>0 then child:SetWidth(w) end;update() end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(_,delta)
        local range=math.max(0,scroll:GetVerticalScrollRange())
        scroll:SetVerticalScroll(math.max(0,math.min(range,scroll:GetVerticalScroll()-delta*42)))
        update()
    end)
    scroll:SetScript("OnShow",update)
    return child,scroll
end
createModulePage=function(m)
    local host=CreateFrame("Frame",nil,workspace.content)
    host:SetAllPoints();host:Hide();pages[m.id]=host
    local child,scroll=UI.MakeScrollable(host)
    -- Explicit width while hidden prevents first-open wrapping/height errors.
    child:SetWidth(738)
    local layout=UI.NewLayout(child)
    layout.hasPageHeading=true
    local ok,err=pcall(m.BuildOptions,child,m,layout)
    if not ok then
        ns.Print(T["设置页构建失败："]..m.id.." / "..tostring(err))
        layout:Text(T["此模块设置加载失败，请记录 Lua 错误；其他模块仍可使用。"],false)
    end
    layout:Finalize();layout:SyncAll();m._syncLayout=layout
    styleOptions(child)
    host:SetScript("OnShow",function() if not InCombatLockdown() then layout:SyncAll() end end)
end
createAppearancePage=function()
    local host=CreateFrame("Frame",nil,workspace.content)
    host:SetAllPoints();host:Hide();pages.appearance=host
    local child=UI.MakeScrollable(host)
    child:SetWidth(738)
    local layout=UI.NewLayout(child)
    layout:Title(T["统一屏幕文字"])
    layout:Text(T["账号通用，修改后立即生效；各模块的字号、颜色与位置保持不变。"],true)
    layout:Section(T["字体样式"])
    layout:Check(T["轮廓字体"],function() return UI.GetAppearanceDB().outline end,UI.SetRuntimeOutline)
    layout:Text(T["作用于坐标、提醒、图标数字等屏幕文字；浅色面板文字自动去除描边和阴影，保持清晰。"],true)
    layout:Text(T["不改变工具箱设置界面的字体，也不修改游戏原生聊天、菜单、鼠标提示或其他插件的字体。"],true)
    layout:Finalize();layout:SyncAll();styleOptions(child)
    host:SetScript("OnShow",function() if not InCombatLockdown() then layout:SyncAll() end end)
end
function UI.BuildWorkspace()
    if workspace or InCombatLockdown() then return end
    UI.InitializeSettings()
    UI.palette=palettes[prefs().theme] or palettes.dark
    workspace=surface(UIParent,"bg")
    -- The named escape target is non-secure and never parents gameplay buttons.
    _G.BaimiaoToolboxWorkspace=workspace
    UISpecialFrames[#UISpecialFrames+1]="BaimiaoToolboxWorkspace"
    workspace:SetSize(WINDOW_WIDTH,WINDOW_HEIGHT);workspace:SetPoint("CENTER");workspace:SetFrameStrata("DIALOG")
    workspace:SetClampedToScreen(true);workspace:EnableMouse(true);workspace:SetMovable(true)
    workspace:Hide()
    local saved=prefs()
    if type(saved.x)=="number" and type(saved.y)=="number" then workspace:SetPoint("CENTER",UIParent,"CENTER",saved.x,saved.y) end
    local drag=CreateFrame("Frame",nil,workspace)
    drag:SetPoint("TOPLEFT");drag:SetPoint("TOPRIGHT");drag:SetHeight(52)
    drag:EnableMouse(true);drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() workspace:StartMoving() end)
    drag:SetScript("OnDragStop",function()
        workspace:StopMovingOrSizing()
        local x,y=workspace:GetCenter();local ux,uy=UIParent:GetCenter()
        local ratio=UIParent:GetEffectiveScale()/workspace:GetEffectiveScale()
        prefs().x=x-ux*ratio;prefs().y=y-uy*ratio
    end)
    local brand=text(drag,T["白描工具箱"],20);brand:SetPoint("LEFT",20,0)
    local wordmark=text(drag,"BAIMIAO TOOLBOX  /  "..version(),10,"muted");wordmark:SetPoint("LEFT",brand,"RIGHT",14,-2)
    local close=button(drag,T["关闭"],60,function() workspace:Hide() end);close:SetPoint("RIGHT",-16,0);close:SetHeight(28)
    workspace.theme=button(drag,"",90,function()
        prefs().theme=prefs().theme=="light" and "dark" or "light";applyTheme()
    end);workspace.theme:SetPoint("RIGHT",close,"LEFT",-8,0);workspace.theme:SetHeight(28)
    workspace.rail=surface(workspace,"rail")
    workspace.rail:SetPoint("TOPLEFT",0,-52);workspace.rail:SetPoint("BOTTOMLEFT");workspace.rail:SetWidth(192)
    local railTitle=text(workspace.rail,T["功能导航"],13,"muted");railTitle:SetPoint("TOPLEFT",16,-20)
    local railFoot=text(workspace.rail,T["拖动顶栏移动窗口\n/bm 打开 · Esc 关闭"],11,"muted")
    railFoot:SetPoint("BOTTOMLEFT",16,20);railFoot:SetSpacing(6)
    workspace.eyebrow=text(workspace,"",10,"accent");workspace.eyebrow:SetPoint("TOPLEFT",208,-60)
    workspace.heading=text(workspace,"",25);workspace.heading:SetPoint("TOPLEFT",208,-76)
    workspace.toggle=button(workspace,"",188,function()
        local m=workspace.currentModule
        if not m or combatMessage() then return end
        ns.SetModuleEnabled(m.id,not ns.IsModuleEnabled(m.id));refresh()
    end);workspace.toggle:SetPoint("TOPRIGHT",-24,-74);workspace.toggle:SetHeight(28)
    workspace.content=CreateFrame("Frame",nil,workspace)
    workspace.content:SetPoint("TOPLEFT",208,-112);workspace.content:SetPoint("BOTTOMRIGHT",-24,16)
    createOverview();navItem("overview",T["工作台总览"],0)
    for i,m in ipairs(ns.orderedModules) do
        if m.BuildOptions then navItem(m.id,m.name or m.id,i) end
    end
    navItem("appearance",T["外观设置"],#ns.orderedModules+1)
    -- An opaque, higher-level guard prevents unsafe edits when combat begins
    -- while settings are open. Theme/close controls remain usable.
    local guard=surface(workspace)
    guard:SetPoint("TOPLEFT",workspace, "TOPLEFT",193,-53)
    guard:SetPoint("BOTTOMRIGHT",workspace,"BOTTOMRIGHT",-1,1)
    guard:SetFrameLevel(workspace:GetFrameLevel()+100);guard:EnableMouse(true);guard:EnableMouseWheel(true)
    guard:SetScript("OnMouseWheel",function() end)
    local warning=text(guard,T["战斗进行中"],26,"accent");warning:SetPoint("CENTER",0,28)
    local detail=text(guard,T["设置暂时锁定，脱战后自动恢复。屏上的工具照常运行。"],13,"muted")
    detail:SetPoint("TOP",warning,"BOTTOM",0,-18)
    workspace.guard=guard
    local function syncCombat()
        if InCombatLockdown() and GetCurrentKeyBoardFocus then
            -- Do not ClearFocus here: existing options commit on focus loss.
            local focus=GetCurrentKeyBoardFocus()
            if focus and focus.IsDescendantOf and focus:IsDescendantOf(workspace) then workspace:Hide() end
        end
        guard:SetShown(InCombatLockdown())
    end
    workspace:RegisterEvent("PLAYER_REGEN_DISABLED");workspace:RegisterEvent("PLAYER_REGEN_ENABLED")
    workspace:RegisterEvent("DISPLAY_SIZE_CHANGED");workspace:RegisterEvent("UI_SCALE_CHANGED")
    workspace:SetScript("OnEvent",function(_,event)
        if event=="DISPLAY_SIZE_CHANGED" or event=="UI_SCALE_CHANGED" then fitWindow() else syncCombat() end
    end)
    workspace:SetScript("OnShow",function()
        fitWindow();syncCombat();selectPage(current)
        if ns.AuctionHouse and ns.AuctionHouse.OnWorkspaceShow then ns.AuctionHouse.OnWorkspaceShow()end
    end)
    workspace:SetScript("OnHide",function()
        if ns.AuctionHouse and ns.AuctionHouse.OnWorkspaceHide then ns.AuctionHouse.OnWorkspaceHide()end
    end)
    applyTheme();selectPage("overview");syncCombat();fitWindow()
end

-- Login needs only the native Settings launcher and saved theme. The workspace
-- and each module editor are created by explicit navigation, not by login.
function UI.InitializeSettings()
    if settingsInitialized then return end
    settingsInitialized=true
    applyTheme()
    -- Keep the standard Blizzard Settings entry without constructing options twice.
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local launcher=CreateFrame("Frame")
        local title=text(launcher,T["白描工具箱"],26,"accent");title:SetPoint("TOPLEFT",24,-28)
        local detail=text(launcher,T["新版独立工作台：功能总览、分组设置与明暗主题。\n也可使用 /bm 或小地图按钮随时打开。"],14)
        detail:SetPoint("TOPLEFT",24,-80);detail:SetSpacing(8)
        local open=button(launcher,T["打开工具箱"],160,function()
            if SettingsPanel then HideUIPanel(SettingsPanel) end
            UI.OpenWorkspace()
        end);open:SetPoint("TOPLEFT",24,-150)
        local category=Settings.RegisterCanvasLayoutCategory(launcher,T["白描工具箱"])
        Settings.RegisterAddOnCategory(category)
        UI.settingsCategory=category
    end
end
function UI.OpenWorkspace(moduleId)
    -- Check before constructing even the workspace shell.
    if combatMessage() then return end
    if not workspace then UI.BuildWorkspace() end
    selectPage(moduleId or "overview");workspace:Show();workspace:Raise()
end

-- Commit only the region being hidden, not another editor in the workspace.
function UI.CommitOptionsFocus(panel)
    if InCombatLockdown() then return end
    local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.IsDescendantOf and focus:IsDescendantOf(panel) then focus:ClearFocus() end
end

-- A terminal stack of settings groups, built once. Collapsing or disabling a
-- group only changes visibility/geometry; values and editor frames are retained.
-- enabled/setEnabled add a persistent header switch; visible hides the whole
-- group for dependent settings. collapsed is session-only presentation state.
function UI.OptionGroups(panel,L,entries,onResize)
    local hadCard=L._card~=nil
    L:_closeCard()
    if hadCard then L:step(12) end
    local top=L.y
    local groups={}
    local ready,updating=false,false
    local function reflow()
        if not ready or updating then return end
        updating=true
        local y,any=top,false
        for _,g in ipairs(groups) do
            local entry=g.entry
            local visible=not entry.visible or entry.visible()
            local enabled=not entry.enabled or entry.enabled()
            local expanded=visible and enabled and not g.collapsed
            if not expanded then UI.CommitOptionsFocus(g.body) end
            g.frame:SetShown(visible)
            g.body:SetShown(expanded)
            if g.fold then
                g.fold:SetEnabled(enabled)
                g.fold:SetText(expanded and T["收起设置"] or T["展开设置"])
            end
            local height=g.headerHeight+(expanded and g.layout.panel:GetHeight() or 0)
            g.frame:SetHeight(height)
            if visible then
                g.frame:ClearAllPoints();g.frame:SetPoint("TOPLEFT",8,y)
                g.frame:SetPoint("TOPRIGHT",-8,y)
                y=y-height-12;any=true
            end
        end
        L.y=any and y+12 or top;L:Finalize()
        updating=false
        if onResize then onResize() end
    end
    for _,entry in ipairs(entries) do
        local f=surface(panel)
        f:SetWidth(panel:GetWidth()-16)
        local g={frame=f,entry=entry,collapsed=entry.collapsed==true}
        groups[#groups+1]=g
        local header=UI.NewLayout(f)
        header.y=-14;header.indent=14
        header._cellWidth=f:GetWidth()-(entry.collapsed~=nil and 150 or 28)
        local title
        if entry.enabled then
            g.toggle=header:Check(entry.title,entry.enabled,function(v)
                entry.setEnabled(v);reflow()
            end)
            title=g.toggle.label
        else
            title=text(f,entry.title,13,"accent")
            title:SetPoint("TOPLEFT",14,-14);title:SetWidth(header._cellWidth)
            title:SetWordWrap(true)
        end
        g.headerHeight=math.max(44,title:GetStringHeight()+28)
        if entry.collapsed~=nil then
            g.fold=button(f,"",112,function()
                if InCombatLockdown() then return end
                g.collapsed=not g.collapsed;reflow()
            end)
            g.fold:SetHeight(26);g.fold:SetPoint("TOPRIGHT",-12,-9)
        end
        local body=CreateFrame("Frame",nil,f)
        body:SetPoint("TOPLEFT",0,-g.headerHeight);body:SetPoint("TOPRIGHT",0,-g.headerHeight)
        body:SetWidth(f:GetWidth());g.body=body
        local layout=UI.NewLayout(body);layout.y=-4;layout.indent=14;g.layout=layout
        if entry.build then entry.build(body,layout,reflow) end
        layout:Finalize()
        if not entry.build then body:SetHeight(0) end
        g.header=header
    end
    L.syncers[#L.syncers+1]=function()
        for _,g in ipairs(groups) do g.header:SyncAll();g.layout:SyncAll() end
        reflow()
    end
    ready=true;reflow()
    return {groups=groups,Refresh=reflow}
end

-- Build each tab once: switching never destroys edit boxes or their drafts.
function UI.OptionTabs(panel,L,entries,onResize)
    local pages,buttons={},{}
    local selected=1
    local top=L.y-38
    local function resize()
        L.y=top-pages[selected].panel:GetHeight()
        L:Finalize()
        if onResize then onResize() end
    end
    local function selectPage(index)
        selected=index
        for i,page in ipairs(pages) do
            page.panel:SetShown(i==index)
            buttons[i]:SetEnabled(i~=index)
            buttons[i].tabIndicator:SetShown(i==index)
        end
        resize()
        local scroll=panel:GetParent()
        if scroll and scroll.GetVerticalScroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    end
    local previous
    for i,entry in ipairs(entries) do
        local index=i
        local b=L:Button(entry.width or 108,entry.name,function() selectPage(index) end,i>1,previous)
        previous=b;buttons[i]=b
        b.tabIndicator=b:CreateTexture(nil,"OVERLAY")
        b.tabIndicator:SetPoint("BOTTOMLEFT",4,0);b.tabIndicator:SetPoint("BOTTOMRIGHT",-4,0)
        b.tabIndicator:SetHeight(2)
        UI.OnTheme(function() b.tabIndicator:SetColorTexture(unpack(UI.palette.accent)) end)
        local child=CreateFrame("Frame",nil,panel)
        child:SetPoint("TOPLEFT",0,top);child:SetPoint("TOPRIGHT",0,top)
        child:SetWidth(panel:GetWidth())
        local layout=ns.UI.NewLayout(child)
        pages[i]=layout
        entry.build(child,layout,function() if pages[selected] then resize() end end)
        layout:Finalize()
    end
    L.syncers[#L.syncers+1]=function() for _,page in ipairs(pages) do page:SyncAll() end end
    selectPage(1)
    return {Select=selectPage,pages=pages,buttons=buttons}
end
