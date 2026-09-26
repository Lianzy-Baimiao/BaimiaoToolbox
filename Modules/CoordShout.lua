local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 模块：坐标喊话
-- 屏上显示坐标/移速/距离，点击按模板把坐标通报到频道。
-- 由 WeakAuras 版改写而来，显示项与喊话文本、颜色均可配置。
--------------------------------------------------------------------------------

local MODULE_ID = "coordshout"

local BASE_SPEED = 7  -- 100% 地面速度 = 7 码/秒

local CHANNELS = { "AUTO", "SAY", "PARTY", "RAID", "INSTANCE", "GUILD", "YELL" }
local CHANNEL_LABEL = {
    AUTO = "自动（团/队/说）", SAY = "说话", PARTY = "小队", RAID = "团队",
    INSTANCE = "副本/战场", GUILD = "公会", YELL = "大喊",
}
local CHANNEL_TO_API = {
    SAY = "SAY", PARTY = "PARTY", RAID = "RAID",
    INSTANCE = "INSTANCE_CHAT", GUILD = "GUILD", YELL = "YELL",
}

local DEFAULT_TPL_NOTARGET = "当前{pvp} {waypoint} {area} {coord}"
local DEFAULT_TPL_TARGET   = "当前{pvp} {waypoint} 目标：{target}{hpbracket} {range} {area} {coord}"

local defaults = {
    display = {
        enabled = true,
        coord = true,
        speed = true,
        distance = true,
        scale = 1,
        outline = true,
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

-- 12.x 起 IsItemInRange / UnitInRange 这类测距接口可能是“受保护函数”：从插件（非硬件
-- 事件）路径调用会触发 ADDON_ACTION_BLOCKED，被 BugSack 逐条抓下来刷屏——而且这不是
-- Lua 报错，pcall 拦不住。策略：监听 ADDON_ACTION_BLOCKED，一旦发现本插件“刚发起测距、
-- 随即被系统拦截”，就永久停用测距（本次登录 + 按客户端版本持久化），距离退回“未知区间”，
-- 不再撞墙。这样最多在换版本后的首个目标上留一条拦截记录，之后彻底安静。
local rangeBlocked = false     -- 被系统拦截过就置真，之后不再调用受保护测距接口
local rangeProbeAt = 0         -- 最近一次测距尝试的时间戳，用来认领“紧随其后”的拦截

local function CurBuild() return select(4, GetBuildInfo()) end

local blockWatcher = CreateFrame("Frame")
blockWatcher:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatcher:SetScript("OnEvent", function(_, _, addon)
    -- 只认领“刚发起过测距、随即到来的本插件拦截”，别把别的模块的拦截也算到测距头上。
    if addon == ADDON and (GetTime() - rangeProbeAt) < 0.5 then
        rangeBlocked = true
        DB().rangeBlockedBuild = CurBuild()   -- 记下是哪个客户端版本封的，换版本会自动重试一次
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
    -- 系统已拦截过测距：彻底停用，避免 0.1s 刷新一直撞受保护函数刷屏。
    if rangeBlocked then return nil end
    rangeProbeAt = GetTime()   -- 标记：紧随其后的本插件 ADDON_ACTION_BLOCKED 认作测距被拦

    local lib = GetRangeLib()
    if lib then
        -- 库的检查器在 12.x 可能撞上秘密值而报错：出错就退回下面的内置兜底，
        -- 不让 0.1s 一次的刷新跟着炸。
        local ok, minR, maxR = pcall(lib.GetRange, lib, unit, true)
        if ok and (type(minR) == "number" or type(maxR) == "number") then
            return minR, maxR
        end
    end

    -- 兜底：找到“在射程内”的最小档，即为上界；紧邻的更小档为下界。
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    local prev = 0
    for _, yards in ipairs(HARM_ORDER) do
        local item = HARM_ITEMS[yards]
        if item then
            local inRange = C_Item.IsItemInRange(item, unit)
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
        return string.format("%d-%d码", minR, maxR)
    elseif maxR then
        return string.format("<%d码", maxR)
    elseif minR and minR > 0 then
        return string.format(">%d码", minR)
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

local function GetSpeedPercent()
    local ok, pct, yd = pcall(function()
        local current = GetUnitSpeed("player") or 0
        return math.floor(current / BASE_SPEED * 100 + 0.5), current
    end)
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

local function DisplayDirty()
    local _, px, py = GetPlayerPos()
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
end

-- 目标变化事件：置脏标记，下次刷新就会重建（不读 guid，规避秘密值）。
-- 注册/注销跟着模块总开关走，关掉后不再白收事件。
local targetEv = CreateFrame("Frame")
targetEv:SetScript("OnEvent", function() targetDirty = true end)
local function SetupTargetEvent()
    targetEv:RegisterEvent("PLAYER_TARGET_CHANGED")
end
local function TeardownTargetEvent()
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
        ctx.range = RangeString("target") or "0-100码"
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
        ns.Print("坐标喊话：战斗中无法向聊天频道发送（系统限制），脱战后再试。")
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
        ns.Print("坐标喊话：文本为空，检查一下模板。")
        return
    end
    local okSend, err = pcall(SendChatMessage, msg, ResolveChannel())
    if not okSend then
        ns.Print("坐标喊话：发送失败（" .. tostring(err) .. "），检查一下喊话频道设置。")
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
    local fontPath = GameFontNormal:GetFont()
    button.text:SetFont(fontPath, d.fontSize or 16, d.outline and "OUTLINE" or "")
end

local function UpdateDisplay()
    if not button then return end
    local d = DB().display

    if not ns.IsModuleEnabled(MODULE_ID) or not d.enabled then
        button:Hide()
        return
    end
    button:Show()
    button:SetScale(d.scale or 1)

    -- 内容没变就跳过重排（0.1s 刷新下这能省掉绝大多数字符串/尺寸重建）。
    local pct = GetSpeedPercent()
    local speedChanged = (pct or -1) ~= lastShownPct
    if pct then lastShownPct = pct end
    if not speedChanged and not DisplayDirty() then return end

    local lines = {}
    if d.coord then
        local _, x, y = GetPlayerPos()
        local t = (x and y) and string.format("坐标 %.1f, %.1f", x * 100, y * 100) or "坐标 --"
        lines[#lines + 1] = colorize(t, d.coordColor)
    end
    if d.speed then
        local t
        if pct == nil then t = "移速 --"
        elseif pct <= 0 then t = "静止"
        else t = "移速 " .. pct .. "%" end
        lines[#lines + 1] = colorize(t, d.speedColor)
    end
    if d.distance then
        -- 没目标时显示完整未知区间 0-100码；有目标时收窄成实测区间。
        local t = "距离 " .. (UnitExists("target") and (RangeString("target") or "0-100码") or "0-100码")
        lines[#lines + 1] = colorize(t, d.distColor)
    end
    if #lines == 0 then lines[1] = "点击通报" end

    button.text:SetText(table.concat(lines, "\n"))
    button:SetSize(math.max(button.text:GetStringWidth() + 20, 90),
                    math.max(button.text:GetStringHeight() + 14, 24))
end

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
            title = "坐标喊话",
            lines = {
                "左键：把当前坐标通报到频道",
                "Alt / Ctrl+左键：拖动摆位（锁定时也可）",
                "Alt+右键：打开设置（命令 /coord 或 /bm coordshout）",
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

    local elapsed = 0
    button:SetScript("OnUpdate", function(_, dt)
        if not displayActive then return end
        elapsed = elapsed + dt
        if elapsed >= 0.1 then
            elapsed = 0
            -- 0.1s 刷一次：任何意外报错都会被放大成每秒 10 条 BugSack，所以兜一层 pcall，
            -- 只在首次出错时提示一句（不静默吞掉问题，也不刷屏）。
            local ok, err = pcall(UpdateDisplay)
            if not ok and not refreshWarned then
                refreshWarned = true
                ns.Print("坐标喊话：刷新出错（已继续运行）：" .. tostring(err))
            end
        end
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

local function BuildOptions(panel, m, layout)
    layout:Title("坐标喊话")

    layout:Section("显示")
    layout:Check("显示坐标", function() return DB().display.coord end,
        function(v) DB().display.coord = v end, Refresh)
    layout:Check("显示移速", function() return DB().display.speed end,
        function(v) DB().display.speed = v end, Refresh)
    layout:Check("显示距离（到当前目标的范围区间）", function() return DB().display.distance end,
        function(v) DB().display.distance = v end, Refresh)
    layout:Check("锁定位置（锁定后隐藏背景、不能拖动；Alt+左键仍可拖）", function() return L().locked end,
        function(v) L().locked = v end, Refresh)
    layout:Check("轮廓字体", function() return DB().display.outline end,
        function(v) DB().display.outline = v end, Refresh)

    layout:ColorSwatch("坐标颜色",
        function() local c = DB().display.coordColor return c.r, c.g, c.b end,
        function(r, g, b) DB().display.coordColor = { r = r, g = g, b = b } end, Refresh)
    layout:ColorSwatch("移速颜色",
        function() local c = DB().display.speedColor return c.r, c.g, c.b end,
        function(r, g, b) DB().display.speedColor = { r = r, g = g, b = b } end, Refresh)
    layout:ColorSwatch("距离颜色",
        function() local c = DB().display.distColor return c.r, c.g, c.b end,
        function(r, g, b) DB().display.distColor = { r = r, g = g, b = b } end, Refresh)

    layout:Slider("BaimiaoCoordShoutFontSlider", "字号", 10, 40, 1,
        function() return DB().display.fontSize or 16 end,
        function(v) DB().display.fontSize = v end, Refresh)
    layout:Slider("BaimiaoCoordShoutScaleSlider", "缩放", 0.5, 2.0, 0.05,
        function() return DB().display.scale or 1 end,
        function(v) DB().display.scale = v end, Refresh)

    layout:Section("通报")
    layout:Check("通报前在脚下落地图路点（{waypoint} 才有链接）",
        function() return DB().announce.setWaypoint end,
        function(v) DB().announce.setWaypoint = v end)
    layout:Dropdown(240, "喊话频道：", ns.UI.ListFrom(CHANNELS, CHANNEL_LABEL),
        function() return DB().announce.channel or "AUTO" end,
        function(v) DB().announce.channel = v end)

    layout:Text("血量倍数（{hppct} 用；100 = 真实百分比）:", false)
    layout:Box(80, 22, false,
        function() return tostring(DB().announce.hpMultiplier or 100) end,
        function(v) local n = tonumber(v); DB().announce.hpMultiplier = (n and n > 0) and n or 100 end)

    layout:Text("无目标喊话模板:", false)
    layout:Box(460, 56, true,
        function() return DB().announce.templateNoTarget end,
        function(v) DB().announce.templateNoTarget = v end)

    layout:Text("有目标喊话模板:", false)
    layout:Box(460, 56, true,
        function() return DB().announce.templateTarget end,
        function(v) DB().announce.templateTarget = v end)

    local help =
        "变量：{pvp} 战争模式   {waypoint} 路点链接   {map} 地图   {zone} 小地区   {area} 地图+小地区\n" ..
        "{coord} x/y   {x} {y} 单独坐标   {target} 目标名   {range} 距离区间\n" ..
        "{hp} {hpmax} 血量   {hpbracket} [血量/上限]   {hppct} 百分比（敌对目标为“秘密值”，读不到会自动省略）\n" ..
        "{speed} 移速百分比   {speedyd} 码/秒。空变量自动省略、空格自动压缩。"
    -- 给每个 {变量} 染成主题翠绿，说明文字保持浅灰，读起来有层次。
    help = help:gsub("(%b{})", "|cff0cd29f%1|r")
    layout:Text(help, true)

    local resetBtn = layout:Button(140, "恢复默认模板", function()
        DB().announce.templateNoTarget = DEFAULT_TPL_NOTARGET
        DB().announce.templateTarget = DEFAULT_TPL_TARGET
        layout:SyncAll()
        ns.Print("坐标喊话：已恢复默认模板。")
    end)
    layout:Button(140, "测试通报一次", function() Announce() end, true, resetBtn)
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
        if cmd == "say" or cmd == "send" or cmd == "go" then
            Announce()
        elseif cmd == "lock" then
            L().locked = true; Refresh(); ns.Print("坐标喊话：已锁定位置（背景已隐藏）。")
        elseif cmd == "unlock" then
            L().locked = false; Refresh(); ns.Print("坐标喊话：已解锁，可拖动。")
        elseif cmd == "reset" then
            local d = L()
            d.point, d.relPoint, d.x, d.y = "CENTER", "CENTER", 0, 0
            Refresh(); ns.Print("坐标喊话：已移回屏幕中心。")
        elseif cmd == "toggle" then
            DB().display.enabled = not DB().display.enabled
            Refresh(); ns.Print("坐标喊话显示：" .. (DB().display.enabled and "开" or "关"))
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
    name = "坐标喊话",
    desc = "屏上显示坐标/移速/到目标的距离区间，点击按模板把坐标通报到频道。",
    defaults = defaults,
    OnEnable = function()
        -- 上次已在当前客户端版本被系统封过测距：直接跳过探测，本次登录不再产生拦截记录。
        if DB().rangeBlockedBuild and DB().rangeBlockedBuild == CurBuild() then
            rangeBlocked = true
        end
        CreateButton()
        displayActive = true
        SetupTargetEvent()
        ForceDirty()            -- 重开时强制重排一次，避免沿用旧缓存
        UpdateDisplay()
        SetupSlash()
    end,
    OnDisable = function()
        displayActive = false   -- 停 0.1s 刷新，关掉总开关后不再空转
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
