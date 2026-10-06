local ADDON, ns = ...
local T = ns.L

--------------------------------------------------------------------------------
-- 模块：坐标喊话
-- 屏上显示坐标/移速/距离，点击按模板把坐标通报到频道。
-- 由 WeakAuras 版改写而来，显示项与喊话文本、颜色均可配置。
--------------------------------------------------------------------------------

local MODULE_ID = "coordshout"

local BASE_SPEED = 7  -- 100% 地面速度 = 7 码/秒

local CHANNELS = { "AUTO", "SAY", "PARTY", "RAID", "INSTANCE", "GUILD", "YELL" }
local CHANNEL_LABEL = {
    AUTO = T["自动（团/队/说）"], SAY = T["说话"], PARTY = T["小队"], RAID = T["团队"],
    INSTANCE = T["副本/战场"], GUILD = T["公会"], YELL = T["大喊"],
}
local CHANNEL_TO_API = {
    SAY = "SAY", PARTY = "PARTY", RAID = "RAID",
    INSTANCE = "INSTANCE_CHAT", GUILD = "GUILD", YELL = "YELL",
}

local DEFAULT_TPL_NOTARGET = T["当前{pvp} {waypoint} {area} {coord}"]
local DEFAULT_TPL_TARGET   = T["当前{pvp} {waypoint} 目标：{target}{hpbracket} {range} {area} {coord}"]

local defaults = {
    display = {
        enabled = true,
        coord = true,
        speed = true,
        distance = true,
        scale = 1,
        fontSize = 16,
        coordColor = { r = 0.0, g = 0.9, b = 0.4 },
        speedColor = { r = 1.0, g = 0.5, b = 0.0 },
        distColor  = { r = 0.0, g = 0.9, b = 0.4 },
    },
    announce = {
        channel = "AUTO",
        setWaypoint = true,
        hpMultiplier = 100,
        templateNoTarget = DEFAULT_TPL_NOTARGET,
        templateTarget = DEFAULT_TPL_TARGET,
    },
}
-- 布局字段（point/relPoint/x/y/locked）从 1.2.0 起存角色档，见 L()。

local function DB() return ns.GetDB(MODULE_ID, defaults) end
-- 布局（位置/锁定）按角色保存；首次访问自动从旧账号档 DB().display 迁移。
local function L() return ns.GetLayoutDB(MODULE_ID, DB().display) end

-- 把 {r,g,b} 转成 |cffRRGGBB，用于给整行文字上色。
local function hex(c)
    if not c then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x",
        math.floor((c.r or 1) * 255 + 0.5),
        math.floor((c.g or 1) * 255 + 0.5),
        math.floor((c.b or 1) * 255 + 0.5))
end
local function colorize(text, c) return hex(c) .. text .. "|r" end

--------------------------------------------------------------------------------
-- 距离：范围区间（码）。优先用别的插件带的 LibRangeCheck-3.0；
-- 没有就退回内置的物品射程表兜底。零售版没有精确单位间距离接口。
--------------------------------------------------------------------------------

local rangeLib
local function GetRangeLib()
    if rangeLib ~= nil then return rangeLib or nil end
    if LibStub then
        rangeLib = LibStub("LibRangeCheck-3.0", true) or false
    else
        rangeLib = false
    end
    return rangeLib or nil
end

-- Check eligibility before calling a potentially protected item-range API.
-- An unexpected block quarantines only this context for this login, not the
-- whole client build forever. Never turn a secret attackability value into a boolean.
local blockedRangeContexts = {}
local rangeProbeAt, rangeProbeContext = -1, nil
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end
local function ReadRangeContext(unit)
    local restricted = InCombatLockdown()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local challenge = C_ChallengeMode.IsChallengeModeActive()
        if IsSecret(challenge) then return nil end
        restricted = restricted or challenge
    end
    local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
    if IsSecret(canAttack) then return nil end
    if restricted and canAttack ~= true then return nil end
    return restricted and "restricted-hostile" or (canAttack == true and "open-hostile" or "open-other")
end
local function RangeContext(unit)
    local ok, context = pcall(ReadRangeContext, unit)
    return ok and context or nil
end
local blockWatcher = CreateFrame("Frame")
blockWatcher:SetScript("OnEvent", function(_, _, addon, functionName)
    if IsSecret(addon) or IsSecret(functionName) then return end
    if addon == ADDON and type(functionName) == "string"
        and functionName:find("IsItemInRange", 1, true)
        and rangeProbeContext and (GetTime() - rangeProbeAt) < 0.5 then
        blockedRangeContexts[rangeProbeContext] = true
    end
end)

-- 内置兜底：几个已知射程的物品，用 C_Item.IsItemInRange 由近到远试，
-- 命中最近的那个就得到“<=该射程”的上界；再配合上一档得到下界。
-- 物品 id 可能随版本失效，失效时该档自动跳过。
local HARM_ITEMS = {
    [5]  = 37727,  -- 深度较近
    [8]  = 34368,
    [10] = 32321,
    [15] = nil,
    [20] = 21519,
    [25] = 31463,
    [30] = 1180,
    [35] = 18904,
    [40] = 28767,
}
local HARM_ORDER = { 5, 8, 10, 20, 25, 30, 35, 40 }

-- 返回 minRange, maxRange（数字，码）。测不出返回 nil。
local function GetTargetRange(unit)
    local context = RangeContext(unit)
    if not context or blockedRangeContexts[context] then return nil end
    rangeProbeAt, rangeProbeContext = GetTime(), context

    local lib = GetRangeLib()
    if lib then
        -- 库的检查器在 12.x 可能撞上秘密值而报错：出错就退回下面的内置兜底，
        -- 不让 0.1s 一次的刷新跟着炸。
        local ok, minR, maxR = pcall(lib.GetRange, lib, unit, true)
        if blockedRangeContexts[context] then return nil end
        if ok then
            if IsSecret(minR) or type(minR) ~= "number" then minR = nil end
            if IsSecret(maxR) or type(maxR) ~= "number" then maxR = nil end
            if minR or maxR then return minR, maxR end
        end
    end

    -- 兜底：找到“在射程内”的最小档，即为上界；紧邻的更小档为下界。
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    local prev = 0
    for _, yards in ipairs(HARM_ORDER) do
        local item = HARM_ITEMS[yards]
        if item then
            local ok, inRange = pcall(C_Item.IsItemInRange, item, unit)
            if blockedRangeContexts[context] then return nil end
            if not ok or IsSecret(inRange) then inRange = nil end
            if inRange == true then
                -- prev 还是 0 说明更近的档都没测出来（物品失效）：只给上界，
                -- 让 RangeString 显示成 "<40码"，比 "0-40码" 诚实也好读。
                return (prev > 0) and prev or nil, yards
            elseif inRange == false then
                prev = yards
            end
            -- inRange == nil：物品无效或不可用，跳过这一档
        end
    end
    return (prev > 0) and prev or nil, nil  -- 比最远档还远
end

-- 组织成显示/喊话用的字符串，如 "15-20码" / ">40码" / "0-100码"。
local function RangeString(unit)
    if not UnitExists(unit) then return nil end
    local minR, maxR = GetTargetRange(unit)
    if minR and maxR then
        return string.format(T["%d-%d码"], minR, maxR)
    elseif maxR then
        return string.format(T["<%d码"], maxR)
    elseif minR and minR > 0 then
        return string.format(T[">%d码"], minR)
    end
    return nil
end

--------------------------------------------------------------------------------
-- 数据采集
--------------------------------------------------------------------------------

local function GetPlayerPos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos.x, pos.y
    if not x and pos.GetXY then x, y = pos:GetXY() end
    return map, x, y
end

-- 12.x 里 GetUnitSpeed 在某些情况下也会返回“秘密值”，运算会报错。
-- pcall 包住：能算就返回百分比与码/秒，算不出返回 nil（显示成 --）。
local lastPct, lastYd = -1, -1  -- 缓存，配合 dirty 判定减少字符串重建

local function ReadSpeedPercent()
    local current = GetUnitSpeed("player") or 0
    return math.floor(current / BASE_SPEED * 100 + 0.5), current
end
local function GetSpeedPercent()
    local ok, pct, yd = pcall(ReadSpeedPercent)
    if ok then lastPct, lastYd = pct, yd return pct, yd end
    return nil, nil
end

-- 粗略判断“显示内容可能变了”，避免每 0.1s 重建字符串。
-- 坐标以 0.1 为粒度缓存；移速按整数百分比缓存。
-- 目标：12.x 里 UnitGUID("target") 是“秘密值”，比较会 taint 报错，所以不缓存 guid，
-- 改用 PLAYER_TARGET_CHANGED 事件置 targetDirty 标记来触发刷新。
local lastX, lastY = -1, -1
local lastShownPct = -1
local targetDirty = false
local cachedRange
local nextRangeAt = 0

local function DisplayDirty(px, py)
    local x10 = px and math.floor(px * 1000 + 0.5) or -1
    local y10 = py and math.floor(py * 1000 + 0.5) or -1
    local dirty = x10 ~= lastX or y10 ~= lastY or targetDirty
    lastX, lastY = x10, y10
    targetDirty = false
    return dirty
end

local function ForceDirty()
    lastX, lastY, lastShownPct = -1, -1, -1
    targetDirty = true
    nextRangeAt = 0
end

-- 目标变化事件：置脏标记，下次刷新就会重建（不读 guid，规避秘密值）。
-- 注册/注销跟着模块总开关走，关掉后不再白收事件。
local targetEv = CreateFrame("Frame")
local function SetupTargetEvent()
    blockWatcher:RegisterEvent("ADDON_ACTION_BLOCKED")
    targetEv:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetEv:RegisterEvent("PLAYER_STARTED_MOVING")
    targetEv:RegisterEvent("PLAYER_STOPPED_MOVING")
    targetEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    targetEv:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    targetEv:RegisterEvent("ZONE_CHANGED")
end
local function TeardownTargetEvent()
    blockWatcher:UnregisterAllEvents()
    targetEv:UnregisterAllEvents()
end

-- 目标血量：12.x 里敌对目标的 UnitHealth 是“秘密值”，比较/运算/发送都会报错。
-- 用 pcall 包住，能算就算（友方/自己等非秘密值），算不出就整段留空。
local function SafeTargetHP(mult)
    local ok, hp, hpmax, pct = pcall(function()
        local h, hm = UnitHealth("target"), UnitHealthMax("target")
        if hm > 0 then
            return h, hm, string.format("%.1f", h / hm * mult) .. "%"
        end
        return h, hm, ""
    end)
    if ok then
        return tostring(hp or ""), tostring(hpmax or ""), pct or ""
    end
    return "", "", ""  -- 秘密值：无法读取，全部留空
end

-- 组装模板可用的所有 token；空项留空字符串，替换后统一压空格。
local function BuildContext()
    local ctx = {}
    ctx.pvp = (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) and "PVP" or "PVE"
    local name = GetInstanceInfo()
    local zone = GetZoneText()
    ctx.map = name or ""
    ctx.zone = zone or ""
    if zone and name and zone ~= "" and zone ~= name then
        ctx.area = name .. " " .. zone
    else
        ctx.area = name or zone or ""
    end

    local map, px, py = GetPlayerPos()
    if px and py then
        ctx.x = string.format("%.1f", px * 100)
        ctx.y = string.format("%.1f", py * 100)
        ctx.coord = ctx.x .. "/" .. ctx.y
    else
        ctx.x, ctx.y, ctx.coord = "", "", ""
    end

    local speedPct, speedYd = GetSpeedPercent()
    ctx.speed = speedPct and (speedPct .. "%") or ""
    ctx.speedyd = speedYd and string.format("%.1f", speedYd) or ""

    if UnitExists("target") then
        local mult = DB().announce.hpMultiplier or 100
        local hp, hpmax, hppct = SafeTargetHP(mult)
        -- 12.x 里敌对目标的 UnitName 也可能是“秘密值”，直接拼进字符串会报错：读不到就留空。
        local okName, tname = pcall(UnitName, "target")
        ctx.target = (okName and tname) or ""
        ctx.hp, ctx.hpmax, ctx.hppct = hp, hpmax, hppct
        -- {hpbracket}：血量能读到才拼成 [x/y]，读不到（秘密值）自动省略。
        ctx.hpbracket = (hp ~= "" and hpmax ~= "") and ("[" .. hp .. "/" .. hpmax .. "]") or ""
        ctx.range = RangeString("target") or T["0-100码"]
    else
        ctx.target, ctx.hp, ctx.hpmax, ctx.hppct, ctx.hpbracket, ctx.range =
            "", "", "", "", "", ""
    end

    return ctx, map, px, py
end

local function FormatTemplate(tpl, ctx)
    local s = (tpl or ""):gsub("{(%w+)}", function(key)
        local v = ctx[key:lower()]
        if v == nil or v == "" then return "" end
        return tostring(v)
    end)
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function ResolveChannel()
    local ch = DB().announce.channel or "AUTO"
    if ch == "AUTO" then
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return "SAY"
    end
    return CHANNEL_TO_API[ch] or "SAY"
end

local function Announce()
    -- 战斗中 SendChatMessage 常被系统以“秘密值/受限”为由拒发，提前给出准确提示。
    if InCombatLockdown() then
        ns.Print(T["坐标喊话：战斗中无法向聊天频道发送（系统限制），脱战后再试。"])
        return
    end
    local a = DB().announce
    local ctx, map, px, py = BuildContext()

    if a.setWaypoint and map and px and py then
        -- 路点在部分地图/副本里会失败（也可能被别的插件影响）。失败不能连累喊话，
        -- 所以两条都 pcall：落点不成功只是 {waypoint} 变空，消息照发。
        pcall(C_Map.ClearUserWaypoint)
        pcall(C_Map.SetUserWaypoint, { uiMapID = map, position = { x = px, y = py } })
    end
    local okLink, link = pcall(C_Map.GetUserWaypointHyperlink)
    ctx.waypoint = (okLink and link) or ""

    local hasTarget = UnitExists("target")
    local msg = FormatTemplate(hasTarget and a.templateTarget or a.templateNoTarget, ctx)
    if msg == "" then
        ns.Print(T["坐标喊话：文本为空，检查一下模板。"])
        return
    end
    local okSend, err = pcall(SendChatMessage, msg, ResolveChannel())
    if not okSend then
        ns.Print(T["坐标喊话：发送失败（"] .. tostring(err) .. T["），检查一下喊话频道设置。"])
    end
end

--------------------------------------------------------------------------------
-- 屏上显示（同时是可点击、可拖动的按钮）。用 Core 的可拖动框工厂创建，
-- 位置/锁定存角色档；这里只保留坐标文字刷新与点击通报逻辑。
--------------------------------------------------------------------------------

local button
local displayActive = false   -- 0.1s 刷新开关；模块总开关关闭时停掉避免空转
local refreshWarned = false   -- 刷新里意外出错只提示一次，别把 BugSack 刷爆

-- 字体：按设置套用大小与轮廓。
local function ApplyLook()
    if not button then return end
    local d = DB().display
    button:SetScale(d.scale or 1)
    local fontPath = GameFontNormal:GetFont()
    ns.UI.SetRuntimeFont(button.text, fontPath, d.fontSize or 16)
end

local displayLines = {}
-- Stable dispatch slot allows opt-in diagnostics to time the actual timer work.
ns.IdleTasks = ns.IdleTasks or {}
local displayTask = {}
ns.IdleTasks.Coord = displayTask
local function DisplayTick()
    if displayActive and button and button:IsVisible() then displayTask.run() end
end
local displayInterval
local sampledX, sampledY
local movementWake = false
local function SetDisplayPolling(active, interval)
    interval = interval or 0.1
    if active then
        if displayTask.timer and displayInterval == interval then return end
        if displayTask.timer then displayTask.timer:Cancel() end
        displayInterval = interval
        displayTask.timer = C_Timer.NewTicker(interval, function() return DisplayTick() end)
    elseif displayTask.timer then
        displayTask.timer:Cancel()
        displayTask.timer = nil
        displayInterval = nil
    end
end

local function UpdateDisplay()
    if not button then return end
    local d = DB().display

    if not ns.IsModuleEnabled(MODULE_ID) or not d.enabled then
        SetDisplayPolling(false)
        button:Hide()
        return
    end
    button:Show()

    -- Sample only displayed data, once per update. Reuse the position for text.
    local pct
    if d.speed then pct = GetSpeedPercent() end
    local x, y
    if d.coord or (d.distance and UnitExists("target")) then
        local map
        map, x, y = GetPlayerPos()
    end
    -- Keep a low-frequency safety sample for transports/teleports without movement events.
    -- Raw position detects slow movement even before the displayed tenth changes.
    local moved = x ~= sampledX or y ~= sampledY
    sampledX, sampledY = x, y
    local fast = movementWake or moved or (d.speed and (pct == nil or pct > 0))
    movementWake = false
    SetDisplayPolling(displayActive and (d.coord or d.speed or d.distance), fast and 0.1 or 0.5)
    local speedChanged = (pct or -1) ~= lastShownPct
    lastShownPct = pct or -1
    -- The target can move while the player stands still. Range has its own
    -- bounded sample and dirty check, independent of position/speed formatting.
    local rangeChanged = false
    if d.distance then
        local now = GetTime()
        if now >= nextRangeAt then
            local value = RangeString("target")
            rangeChanged = value ~= cachedRange
            cachedRange = value
            nextRangeAt = now + 0.5
        end
    else
        cachedRange = nil
        nextRangeAt = 0
    end
    local positionChanged = DisplayDirty(x, y)
    if not speedChanged and not positionChanged and not rangeChanged then return end

    local lines = displayLines
    wipe(lines)
    if d.coord then
        local t = (x and y) and string.format(T["坐标 %.1f, %.1f"], x * 100, y * 100) or T["坐标 --"]
        lines[#lines + 1] = colorize(t, d.coordColor)
    end
    if d.speed then
        local t
        if pct == nil then t = T["移速 --"]
        elseif pct <= 0 then t = T["静止"]
        else t = T["移速 "] .. pct .. "%" end
        lines[#lines + 1] = colorize(t, d.speedColor)
    end
    if d.distance then
        -- 没目标时显示完整未知区间 0-100码；有目标时收窄成实测区间。
        local t = T["距离 "] .. (cachedRange or T["0-100码"])
        lines[#lines + 1] = colorize(t, d.distColor)
    end
    if #lines == 0 then lines[1] = T["点击通报"] end

    button.text:SetText(table.concat(lines, "\n"))
    button:SetSize(math.max(button.text:GetStringWidth() + 20, 90),
                    math.max(button.text:GetStringHeight() + 14, 24))
end

displayTask.run = function()
    local ok, err = pcall(UpdateDisplay)
    if not ok and not refreshWarned then
        refreshWarned = true
        ns.Print(T["坐标喊话：刷新出错（已继续运行）："] .. tostring(err))
    end
end

targetEv:SetScript("OnEvent", function(_, event)
    if not displayActive then return end
    movementWake = event == "PLAYER_STARTED_MOVING"
    ForceDirty()
    -- Wake immediately through the same guarded refresh used by the timer.
    displayTask.run()
end)

local function CreateButton()
    if button then return button end

    button = ns.UI.CreateMovableFrame({
        name = "BaimiaoCoordShoutButton",
        moduleId = MODULE_ID,
        clickable = true,
        size = { 120, 24 },
        strata = "MEDIUM",
        bgAlpha = 0.45,
        legacy = DB().display,                      -- 旧账号档布局自动迁移
        defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        tooltip = {
            title = T["坐标喊话"],
            lines = {
                T["左键：把当前坐标通报到频道"],
                T["Alt / Ctrl+左键：拖动摆位（锁定时也可）"],
                T["Alt+右键：打开设置（命令 /coord 或 /bm coordshout）"],
            },
        },
    })

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("CENTER")
    button.text:SetJustifyH("CENTER")

    button:SetScript("OnClick", function(_, mouseButton)
        -- 右键（含 Alt+右键开设置）统一交给工厂处理；Alt/Ctrl+左键是拖动，不触发通报。
        if mouseButton ~= "LeftButton" then return end
        if IsAltKeyDown() or IsControlKeyDown() then return end
        Announce()
    end)


    ApplyLook()
    return button
end

local function Refresh()
    if not button then return end
    ForceDirty()      -- 设置变了，强制下一轮重排
    button:ApplyPosition()
    ApplyLook()
    button:ApplyLockVisual()
    UpdateDisplay()
end

--------------------------------------------------------------------------------
-- 设置面板
--------------------------------------------------------------------------------

local function BuildOptions(panel,m,layout)
    layout:Title(T["坐标喊话"])
    layout:Text(T["先选显示内容，再配置喊话模板；变量说明单独查阅。"],true)
    m.optionTabs=ns.UI.OptionTabs(panel,layout,{
        {name=T["屏幕显示"],width=150,build=function(panel,layout)
    layout:Section(T["显示"])
    layout:Row({
        function(cell) cell:Check(T["显示坐标"], function() return DB().display.coord end,
            function(v) DB().display.coord = v end, Refresh) end,
        function(cell) cell:Check(T["显示移速"], function() return DB().display.speed end,
            function(v) DB().display.speed = v end, Refresh) end,
        function(cell) cell:Check(T["显示目标距离"], function() return DB().display.distance end,
            function(v) DB().display.distance = v end, Refresh) end,
    })
    layout:Check(T["锁定位置（Alt+左键可拖动）"], function() return L().locked end,
        function(v) L().locked = v end, Refresh)
    layout:Row({
        function(cell) cell:ColorSwatch(T["坐标颜色"],
            function() local c = DB().display.coordColor return c.r, c.g, c.b end,
            function(r, g, b) DB().display.coordColor = { r = r, g = g, b = b } end, Refresh) end,
        function(cell) cell:ColorSwatch(T["移速颜色"],
            function() local c = DB().display.speedColor return c.r, c.g, c.b end,
            function(r, g, b) DB().display.speedColor = { r = r, g = g, b = b } end, Refresh) end,
        function(cell) cell:ColorSwatch(T["距离颜色"],
            function() local c = DB().display.distColor return c.r, c.g, c.b end,
            function(r, g, b) DB().display.distColor = { r = r, g = g, b = b } end, Refresh) end,
    })
    layout:step(8)
    layout:Row({
        function(cell) cell:Slider("BaimiaoCoordShoutFontSlider", T["字号"], 10, 40, 1,
            function() return DB().display.fontSize or 16 end,
            function(v) DB().display.fontSize = v end, Refresh) end,
        function(cell) cell:Slider("BaimiaoCoordShoutScaleSlider", T["整体缩放（%）"], 50, 200, 5,
            function() return (DB().display.scale or 1)*100 end,
            function(v) DB().display.scale = v/100 end, Refresh) end,
    }, 260)


        end},
        {name=T["通报模板"],width=150,build=function(panel,layout)
    layout:Section(T["通报"])
    layout:Check(T["通报前在脚下落地图路点（{waypoint} 才有链接）"],
        function() return DB().announce.setWaypoint end,
        function(v) DB().announce.setWaypoint = v end)
    layout:Dropdown(240, T["喊话频道："], ns.UI.ListFrom(CHANNELS, CHANNEL_LABEL),
        function() return DB().announce.channel or "AUTO" end,
        function(v) DB().announce.channel = v end)

    layout:Text(T["血量倍数（{hppct} 用；100 = 真实百分比）:"], false)
    layout:Box(80, 22, false,
        function() return tostring(DB().announce.hpMultiplier or 100) end,
        function(v) local n = tonumber(v); DB().announce.hpMultiplier = (n and n > 0) and n or 100 end)

    layout:Text(T["无目标喊话模板:"], false)
    layout:Box(460, 56, true,
        function() return DB().announce.templateNoTarget end,
        function(v) DB().announce.templateNoTarget = v end)

    layout:Text(T["有目标喊话模板:"], false)
    layout:Box(460, 56, true,
        function() return DB().announce.templateTarget end,
        function(v) DB().announce.templateTarget = v end)

    layout:Text(T["注意：下方发送按钮会向所选频道真实发送消息，并非仅本地预览。"],true)
    local resetBtn = layout:Button(140, T["恢复默认模板"], function()
        DB().announce.templateNoTarget = DEFAULT_TPL_NOTARGET
        DB().announce.templateTarget = DEFAULT_TPL_TARGET
        layout:SyncAll()
        ns.Print(T["坐标喊话：已恢复默认模板。"])
    end)
    layout:Button(200, T["发送一次（真实喊话）"], function() Announce() end, true, resetBtn)
        end},
        {name=T["变量帮助"],width=150,build=function(panel,layout)
    local help =
        T["变量：{pvp} 战争模式   {waypoint} 路点链接   {map} 地图   {zone} 小地区   {area} 地图+小地区\n"] ..
        T["{coord} x/y   {x} {y} 单独坐标   {target} 目标名   {range} 距离区间\n"] ..
        T["{hp} {hpmax} 血量   {hpbracket} [血量/上限]   {hppct} 百分比（敌对目标为“秘密值”，读不到会自动省略）\n"] ..
        T["{speed} 移速百分比   {speedyd} 码/秒。空变量自动省略、空格自动压缩。"]
    -- 给每个 {变量} 染成主题翠绿，说明文字保持浅灰，读起来有层次。
    help = help:gsub("(%b{})", "|cff0cd29f%1|r")
    layout:Text(help, true)


        end},
    })
end

--------------------------------------------------------------------------------
-- 斜杠命令：/coord、/cs
--------------------------------------------------------------------------------

local function SetupSlash()
    SLASH_BMCOORDSHOUT1 = "/coord"
    SLASH_BMCOORDSHOUT2 = "/cs"
    SLASH_BMCOORDSHOUT3 = "/bmcoord"  -- 保底别名：短命令被别的插件抢走时用
    SlashCmdList["BMCOORDSHOUT"] = function(msg)
        local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if cmd == "range" then
            -- Report only on request; never clear a live context quarantine.
            if not UnitExists("target") then
                ns.Print(T["距离诊断：请先选择目标。"])
            elseif not RangeContext("target") then
                ns.Print(T["距离诊断：当前目标或场景不允许安全测距，暂不调用接口。"])
            elseif blockedRangeContexts[RangeContext("target")] then
                ns.Print(T["距离诊断：当前测距场景曾被拦截，本次登录已停止调用；其他安全场景不受影响。"])
            else
                local ok, value = pcall(RangeString, "target")
                if ok and value then ns.Print(T["距离诊断：当前区间 "] .. value)
                else ns.Print(T["距离诊断：接口未返回可用区间；0-100码表示未知，并非实测距离。"]) end
            end
        elseif cmd == "say" or cmd == "send" or cmd == "go" then
            Announce()
        elseif cmd == "lock" then
            L().locked = true; Refresh(); ns.Print(T["坐标喊话：已锁定位置（背景已隐藏）。"])
        elseif cmd == "unlock" then
            L().locked = false; Refresh(); ns.Print(T["坐标喊话：已解锁，可拖动。"])
        elseif cmd == "reset" then
            local d = L()
            d.point, d.relPoint, d.x, d.y = "CENTER", "CENTER", 0, 0
            Refresh(); ns.Print(T["坐标喊话：已移回屏幕中心。"])
        elseif cmd == "toggle" then
            DB().display.enabled = not DB().display.enabled
            Refresh(); ns.Print(T["坐标喊话显示："] .. (DB().display.enabled and T["开"] or T["关"]))
        else
            ns.OpenOptions(MODULE_ID)
        end
    end
end

--------------------------------------------------------------------------------
-- 注册模块
--------------------------------------------------------------------------------

ns.RegisterModule({
    id = MODULE_ID,
    name = T["坐标喊话"],
    desc = T["屏上显示坐标/移速/到目标的距离区间，点击按模板把坐标通报到频道。"],
    defaults = defaults,
    OnEnable = function()
        -- Retire the old overbroad build-wide switch; every query is now gated.
        DB().rangeBlockedBuild = nil
        CreateButton()
        displayActive = true
        SetupTargetEvent()
        ForceDirty()            -- 重开时强制重排一次，避免沿用旧缓存
        UpdateDisplay()
        SetupSlash()
    end,
    OnDisable = function()
        displayActive = false
        SetDisplayPolling(false)
        TeardownTargetEvent()   -- 同时也摘掉目标变化监听
        if button then button:Hide() end
    end,
    OnToggle = function(_, on)
        displayActive = on and true or false
        -- 重新启用时 Core 只调 OnToggle（不调 OnEnable），事件要在这里补回来。
        if on then SetupTargetEvent() else TeardownTargetEvent() end
        Refresh()  -- 总开关关掉时 UpdateDisplay 会隐藏按钮
    end,
    BuildOptions = BuildOptions,
})

if ns.PerfWatchFrame then ns.PerfWatchFrame("Coord", targetEv, "OnEvent") end

if ns.StartupWatchSlot then ns.StartupWatchSlot("Coord/Refresh", displayTask, "run") end

-- Manual current-run attribution: no wrapping or timing while diagnostics are off.
if ns.PerfWatchFunction then
    ns.PerfWatchFunction("Coord/GetPlayerPos", function() return GetPlayerPos end, function(fn) GetPlayerPos=fn end)
    ns.PerfWatchFunction("Coord/GetSpeedPercent", function() return GetSpeedPercent end, function(fn) GetSpeedPercent=fn end)
    ns.PerfWatchFunction("Coord/RangeString", function() return RangeString end, function(fn) RangeString=fn end)
    ns.PerfWatchFunction("Coord/DisplayDirty", function() return DisplayDirty end, function(fn) DisplayDirty=fn end)
    ns.PerfWatchFunction("Coord/SetDisplayPolling", function() return SetDisplayPolling end, function(fn) SetDisplayPolling=fn end)
    ns.PerfWatchFunction("Coord/DB", function() return DB end, function(fn) DB=fn end)
    ns.PerfWatchFunction("Coord/Timer", function() return DisplayTick end, function(fn) DisplayTick=fn end)
end

if ns.StartupCheckpoint then ns.StartupCheckpoint("CoordShout.lua") end
