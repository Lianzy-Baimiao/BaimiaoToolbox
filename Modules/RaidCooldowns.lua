local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 模块：嗜血 / 战复 监控
-- 两行，小图标（和文字一样大）+ 文字，各占一行：
--   第一行  嗜血图标  准备就绪 / 剩余时间 / 冷却倒计时
--   第二行  战复图标  战复：次数（充能中附上恢复倒计时）
-- 可选：嗜血触发时播放一段自选音乐。
--
-- API 参考自 EllesmereUIQoL（12.x 实测可用）：
--   战复共享池 = Rebirth(20484) 的充能：C_Spell.GetSpellCharges
--   注意：共享池只认「充能」。用「不在冷却 = 1 次」那种兜底会让自己不会战复的职业
--   （武僧等）也读出 1 次 —— 因为 GetSpellCooldown(20484) 对不会这法术的人同样有数据。
--   嗜血/沙 的法术、疲惫 debuff id 均为“非秘密”，GetPlayerAuraBySpellID 战斗中也能读。
--------------------------------------------------------------------------------

local MODULE_ID = "raidcd"

local BREZ_SPELL = 20484  -- 复生：战复共享池的代表法术

-- 各种嗜血类增益
local LUST_SPELLS = {
    2825,    -- 嗜血（萨满，部落）
    32182,   -- 英勇（萨满，联盟）
    80353,   -- 时间扭曲（法师）
    390386,  -- 亲龙之赐（唤唤）
    272678,  -- 原始狂暴（猎人宠物）
    264667,  -- 原始狂暴（宠物变体）
}
-- 嗜血后的“疲惫/沙”锁定 debuff（判冷却用）
local SATED_DEBUFFS = {
    57723,   -- 疲惫（英勇）
    57724,   -- 精疲力竭（嗜血）
    80354,   -- 时间错位（时间扭曲）
    95809,   -- 失心（远古歇斯底里）
    160455,  -- 疲倦（灵风）
    264689,  -- 疲倦（原始狂暴）
    390435,  -- 疲惫（亲龙之赐）
}

local defaults = {
    enabled = true,
    fontSize = 16,
    showBrez = true,
    showSolo = true,    -- 单人时显示
    showParty = true,   -- 小队时显示
    showRaid = true,    -- 团队时显示
    music = {
        enabled = false,
        sound = "白描：嗜血球",   -- LSM 声音名；特殊值 "__custom__" = 用下面的自定义路径
        file = "",               -- 自定义路径或 fileDataID（sound 选“自定义”时用）
        channel = "Master",       -- Master/Music/SFX/Ambience/Dialog
        loop = true,             -- 嗜血持续期间循环播放
        loopInterval = 3,        -- 循环间隔（秒）；设成你音频的长度最顺
    },
}
-- 布局字段（point/relPoint/x/y/locked）从 1.2.0 起存角色档，见 LayoutDB()。

local function DB() return ns.GetDB(MODULE_ID, defaults) end
-- 布局（位置/锁定）按角色保存；首次访问自动从旧账号档 DB() 迁移。
local function LayoutDB() return ns.GetLayoutDB(MODULE_ID, DB()) end

--------------------------------------------------------------------------------
-- 数据
--------------------------------------------------------------------------------

-- 返回：状态字符串, 颜色{r,g,b}。三态：正在嗜血 / 冷却中(沙) / 准备就绪。
local function GetLustState()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return "准备就绪", { 0.2, 1, 0.4 }
    end
    -- 正在嗜血中？
    for _, sid in ipairs(LUST_SPELLS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura and aura.expirationTime then
            local left = aura.expirationTime - GetTime()
            if left > 0 then
                return ("嗜血中 %.0f秒"):format(left), { 1, 0.85, 0.1 }
            end
        end
    end
    -- 处于沙（冷却）？
    for _, sid in ipairs(SATED_DEBUFFS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura and aura.expirationTime then
            local left = aura.expirationTime - GetTime()
            if left > 0 then
                local m = math.floor(left / 60)
                local s = math.floor(left % 60)
                return ("冷却 %d:%02d"):format(m, s), { 0.75, 0.75, 0.75 }
            end
        end
    end
    return "准备就绪", { 0.2, 1, 0.4 }
end

-- 各职业自带的战复法术（单人/小队时读自己这只）。
local BREZ_BY_CLASS = {
    DRUID       = 20484,   -- 复生
    DEATHKNIGHT = 61999,   -- 复活盟友
    WARLOCK     = 20707,   -- 灵魂石
    PALADIN     = 391054,  -- 代祷（惩戒骑等自带战复）
}

local function GetOwnBrez()
    local _, class = UnitClass("player")
    return BREZ_BY_CLASS[class]
end

local function IsKnown(spellID)
    if not spellID then return false end
    return (IsSpellKnown and IsSpellKnown(spellID)) or (IsPlayerSpell and IsPlayerSpell(spellID)) or false
end

-- 读某法术的可用性：优先按“充能”，没有充能体系就退回“冷却”当 1 充能算。
-- poolOnly = true 只认充能 —— 共享战复池必须这么读，因为「不在冷却就当 1 充能」只对
-- 自己会的单发战复成立；对不会的法术（武僧去读复生 20484）会读成「不在 CD = 1」，
-- 于是没有战复的职业也显示「战复：1」。非 poolOnly 时同样会跳过自己没学的法术。
-- 返回 charges, maxCharges, cdStart, cdDuration；读不到返回 nil。
local function SpellAvail(spellID, poolOnly)
    if not (C_Spell and spellID) then return nil end
    if not poolOnly and not IsKnown(spellID) then return nil end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
    if ci and ci.maxCharges and ci.maxCharges > 0 then
        return ci.currentCharges, ci.maxCharges, ci.cooldownStartTime, ci.cooldownDuration
    end
    if poolOnly then return nil end
    -- 单发战复（如惩戒骑代祷、术士灵魂石）没有充能，用冷却判断：不在 CD = 1，在 CD = 0。
    local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if cd then
        local onCD = cd.duration and cd.duration > 1.5 and cd.startTime and cd.startTime > 0
        return onCD and 0 or 1, 1, cd.startTime, cd.duration
    end
    return nil
end

-- 返回：文字, 颜色。团队 = 共享战复池；单人/小队 = 自己的战复法术（没有就读队伍共享池）。
local function GetBrezState()
    local charges, maxc, start, dur

    if IsInRaid() then
        -- 团队：共享池的代表法术（复生 20484），跨职业通用；只认充能。
        charges, maxc, start, dur = SpellAvail(BREZ_SPELL, true)
    else
        -- 单人/小队：先看自己职业的战复（惩戒骑=代祷，不在 CD 就是 1）。
        local own = GetOwnBrez()
        if own and IsKnown(own) then
            charges, maxc, start, dur = SpellAvail(own)
        end
        -- 自己不会：小队副本里队友的战复走共享池；读不到充能就是「没有」，
        -- 绝不再回退到冷却判断（那正是武僧被误报「战复 1」的原因）。
        if not charges then
            charges, maxc, start, dur = SpellAvail(BREZ_SPELL, true)
        end
    end

    if not charges then
        -- 组着队却读不到共享池（例如野外小队）：显示「?」而不是「无」，
        -- 避免把"读不到"说成"没有战复"（模块里其它读不到的值也用「--/?」这种写法）。
        if IsInGroup() and not IsInRaid() then
            return "战复：?", { 0.75, 0.75, 0.75 }
        end
        return "战复：无", { 0.75, 0.75, 0.75 }
    end

    local txt = "战复：" .. charges
    if maxc and charges < maxc and start and dur and dur > 0 then
        local left = (start + dur) - GetTime()
        if left > 0 then
            txt = txt .. (" (%d:%02d)"):format(math.floor(left / 60), math.floor(left % 60))
        end
    end
    local col = (charges <= 0) and { 1, 0.3, 0.3 } or { 0.2, 1, 0.4 }
    return txt, col
end

--------------------------------------------------------------------------------
-- 嗜血音乐
--------------------------------------------------------------------------------

local musicHandle
local musicTicker    -- 循环播放的计时器
local BUNDLED_SOUND = "白描：嗜血球"
local BUNDLED_PATH = "Interface\\AddOns\\BaimiaoToolbox\\media\\lust_ball.ogg"

local SOUND_CHANNELS = { "Master", "Music", "SFX", "Ambience", "Dialog" }
local CHANNEL_LABEL = {
    Master = "主声道", Music = "音乐", SFX = "音效", Ambience = "环境", Dialog = "对话",
}

-- LibSharedMedia（可选）。把随插件打包的嗜血球注册进去，让它出现在下拉里，
-- 也能读到别的插件注册的所有声音。
local LSM
local function GetLSM()
    if LSM == nil then LSM = (LibStub and LibStub("LibSharedMedia-3.0", true)) or false end
    return LSM or nil
end
local function RegisterBundled()
    local lsm = GetLSM()
    if lsm then lsm:Register("sound", BUNDLED_SOUND, BUNDLED_PATH) end
end

-- 下拉可选项：所有 LSM 声音 + “自定义路径”。没装 LSM 时至少给内置那首和自定义。
local function SoundList()
    local out = {}
    local lsm = GetLSM()
    if lsm then
        for _, name in ipairs(lsm:List("sound")) do
            out[#out + 1] = { value = name, text = name }
        end
    else
        out[#out + 1] = { value = BUNDLED_SOUND, text = BUNDLED_SOUND }
    end
    out[#out + 1] = { value = "__custom__", text = "自定义路径…" }
    return out
end

-- 解析出真正要播放的文件（路径或 fileDataID）。
local function ResolveSoundFile()
    local m = DB().music
    if m.sound == "__custom__" then
        if not m.file or m.file == "" then return nil end
        return tonumber(m.file) or m.file
    end
    local lsm = GetLSM()
    if lsm then
        local f = lsm:Fetch("sound", m.sound, true)  -- noDefault
        if f then return f end
    end
    -- 没装 LSM 但选的是内置那首
    if m.sound == BUNDLED_SOUND then return BUNDLED_PATH end
    return nil
end

-- 播放指定声音一次；成功返回 handle。sound 传具体值（用于试听下拉里的某项），
-- 不传则用当前设置。
-- report=true 只在【失败】时提示——成功是能听见的，不需要刷屏
--（以前悬停下拉列表会每项打印一句"已播放"，滑一遍就刷屏）。
local function PlaySoundOnce(sound, report)
    local m = DB().music
    local file
    if sound then
        if sound == "__custom__" then
            file = (m.file and m.file ~= "") and (tonumber(m.file) or m.file) or nil
        else
            local lsm = GetLSM()
            file = (lsm and lsm:Fetch("sound", sound, true)) or (sound == BUNDLED_SOUND and BUNDLED_PATH) or nil
        end
    else
        file = ResolveSoundFile()
    end
    if not file then
        if report then ns.Print("嗜血音乐：没选到有效的声音（自定义模式请填路径/fileDataID）。") end
        return nil
    end
    local ok, willPlay, handle = pcall(PlaySoundFile, file, m.channel or "Master")
    if ok and willPlay then
        -- report=true 的调用点（点“试听”按钮）给一次确认；
        -- 悬停下拉试听传 false，避免滑一遍列表就刷屏。
        if report then
            ns.Print("嗜血音乐：已播放（" .. (CHANNEL_LABEL[m.channel] or m.channel or "?") .. "）。")
        end
        return handle
    end
    if report then
        ns.Print("嗜血音乐：播放失败。自定义音频请放进插件目录用 " ..
            "Interface\\AddOns\\...\\xxx.ogg 路径（游戏启动后临时丢进 Interface\\Music 的常读不到），或改用 fileDataID。")
    end
    return nil
end

-- 停止：取消循环计时器 + 停当前音。
local function StopLustMusic()
    if musicTicker then musicTicker:Cancel(); musicTicker = nil end
    if musicHandle then pcall(StopSound, musicHandle); musicHandle = nil end
end

-- 试听：只放一次，不循环。report=true（点“试听”按钮）会回报一次；
-- 悬停下拉试听走 false，静默播放——听得见就是反馈，不再刷屏。
local function PreviewMusic(sound, report)
    if musicHandle then pcall(StopSound, musicHandle) end
    musicHandle = PlaySoundOnce(sound, report)
end

-- 嗜血触发时调用：受“启用”开关控制。可循环，直到 StopLustMusic。
local function PlayLustMusic()
    local m = DB().music
    if not m.enabled then return end
    StopLustMusic()  -- 清掉上一轮
    musicHandle = PlaySoundOnce(nil, false)
    if m.loop then
        local interval = tonumber(m.loopInterval) or 3
        if interval < 1 then interval = 1 end
        musicTicker = C_Timer.NewTicker(interval, function()
            if musicHandle then pcall(StopSound, musicHandle) end
            musicHandle = PlaySoundOnce(nil, false)
        end)
    end
end

--------------------------------------------------------------------------------
-- 显示
--------------------------------------------------------------------------------

local frame
local lustActiveLast = false  -- 上次是否处于嗜血中（用于检测“刚触发”）
local pollActive = false      -- 0.25s 轮询开关；模块关闭时停掉避免空转

local function ApplyLockVisual()
    if not frame then return end
    -- 鼠标始终开启（保证锁定时 Alt+右键 仍能打开设置）；只有背景随锁定隐藏。
    frame:EnableMouse(true)
    frame.bg:SetShown(not frame:IsLocked())
end

-- 按字号重排：图标 = 字高，图标在左、文字在右，两行左对齐。
local function ApplyLook()
    if not frame then return end
    local size = DB().fontSize or 16
    local fontPath = GameFontNormal:GetFont()
    for _, row in ipairs(frame.rows) do
        row.icon:SetSize(size, size)
        row.text:SetFont(fontPath, size, "OUTLINE")
    end
    frame.rows[1]:SetHeight(size + 2)
    frame.rows[2]:SetHeight(size + 2)
end

local function UpdateDisplay()
    if not frame then return end
    local d = DB()

    if not ns.IsModuleEnabled(MODULE_ID) or not d.enabled then
        frame:Hide()
        return
    end

    -- 按当前处于 单人/小队/团队 的可见性设置决定显示；解锁时强制可见便于摆位。
    local show
    if IsInRaid() then show = d.showRaid
    elseif IsInGroup() then show = d.showParty
    else show = d.showSolo end
    if not show and frame:IsLocked() then
        frame:Hide()
        return
    end
    frame:Show()

    -- 第一行：嗜血
    local lustTxt, lustCol = GetLustState()
    frame.rows[1].text:SetText(lustTxt)
    frame.rows[1].text:SetTextColor(lustCol[1], lustCol[2], lustCol[3])
    local lustActive = lustTxt:find("嗜血中") ~= nil
    if lustActive and not lustActiveLast then
        PlayLustMusic()      -- 刚触发嗜血
    elseif not lustActive and lustActiveLast then
        StopLustMusic()      -- 嗜血结束
    end
    lustActiveLast = lustActive

    -- 第二行：战复
    if d.showBrez then
        frame.rows[2]:Show()
        local brezTxt, brezCol = GetBrezState()
        frame.rows[2].text:SetText(brezTxt)
        frame.rows[2].text:SetTextColor(brezCol[1], brezCol[2], brezCol[3])
    else
        frame.rows[2]:Hide()
    end

    -- 按内容自适应宽度
    local w1 = frame.rows[1].icon:GetWidth() + 4 + frame.rows[1].text:GetStringWidth()
    local w2 = d.showBrez and (frame.rows[2].icon:GetWidth() + 4 + frame.rows[2].text:GetStringWidth()) or 0
    frame:SetWidth(math.max(w1, w2, 60) + 12)
    frame:SetHeight((d.showBrez and 2 or 1) * ((d.fontSize or 16) + 4) + 8)
end

local function CreateRow(parent, spellID)
    local row = CreateFrame("Frame", nil, parent)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if C_Spell and C_Spell.GetSpellTexture then
        row.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
    end
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetJustifyH("LEFT")
    return row
end

local function CreateFrameOnce()
    if frame then return frame end

    frame = ns.UI.CreateMovableFrame({
        name = "BaimiaoRaidCDFrame",
        moduleId = MODULE_ID,
        clickable = false,
        size = { 120, 40 },
        strata = "MEDIUM",
        bgAlpha = 0.4,
        legacy = DB(),                          -- 旧账号档布局自动迁移
        defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 60 },
        tooltip = {
            title = "嗜血 / 战复监控",
            lines = {
                "Alt / Ctrl+左键：拖动摆位（锁定时也可）",
                "Alt+右键：打开设置（命令 /raidcd 或 /bm raidcd）",
            },
        },
    })
    -- 工厂把 EnableMouse 交给 unlockDragOnly 控制；本模块锁定也要吃鼠标（Alt+右键开设置）。
    frame:EnableMouse(true)

    frame.rows = {}
    frame.rows[1] = CreateRow(frame, LUST_SPELLS[1])   -- 嗜血图标
    frame.rows[2] = CreateRow(frame, BREZ_SPELL)       -- 战复(复生)图标
    frame.rows[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
    frame.rows[1]:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    frame.rows[2]:SetPoint("TOPLEFT", frame.rows[1], "BOTTOMLEFT", 0, -2)
    frame.rows[2]:SetPoint("RIGHT", frame, "RIGHT", -6, 0)

    -- 0.25s 刷新，倒计时够顺滑又不费。模块关闭时由 OnDisable 停掉。
    pollActive = true
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        if not pollActive then return end
        acc = acc + dt
        if acc >= 0.25 then acc = 0 UpdateDisplay() end
    end)

    ApplyLook()
    frame:ApplyLockVisual()
    return frame
end

local function Refresh()
    if not frame then return end
    frame:ApplyPosition()
    ApplyLook()
    frame:ApplyLockVisual()
    UpdateDisplay()
end

--------------------------------------------------------------------------------
-- 设置面板
--------------------------------------------------------------------------------

local function BuildOptions(panel, m, L)
    L:Title("嗜血 / 战复 监控")
    L:Text("两行常驻显示：第一行嗜血状态（准备就绪/嗜血中/冷却倒计时），第二行战复剩余次数。", false)

    L:Section("显示")
    L:Check("显示战复行", function() return DB().showBrez end,
        function(v) DB().showBrez = v end, Refresh)
    L:Check("锁定位置（锁定后隐藏背景、不能拖动；Alt+左键仍可拖）",
        function() return LayoutDB().locked end,
        function(v) LayoutDB().locked = v end, Refresh)

    L:Section("在哪些情况下显示")
    L:Check("单人时显示", function() return DB().showSolo end,
        function(v) DB().showSolo = v end, Refresh)
    L:Check("小队时显示", function() return DB().showParty end,
        function(v) DB().showParty = v end, Refresh)
    L:Check("团队时显示", function() return DB().showRaid end,
        function(v) DB().showRaid = v end, Refresh)
    L:Slider("BaimiaoRaidCDFontSlider", "字号", 10, 40, 1,
        function() return DB().fontSize or 16 end,
        function(v) DB().fontSize = v end, Refresh)

    L:Section("嗜血音乐")
    L:Check("嗜血触发时播放音乐",
        function() return DB().music.enabled end,
        function(v) DB().music.enabled = v end)
    -- 声音下拉：悬停某项即试听（previewFn）。
    L:Dropdown(300, "音乐：", SoundList,
        function() return DB().music.sound end,
        function(v) DB().music.sound = v end,
        nil,
        function(v) PreviewMusic(v) end)
    L:Dropdown(200, "声道：", ns.UI.ListFrom(SOUND_CHANNELS, CHANNEL_LABEL),
        function() return DB().music.channel or "Master" end,
        function(v) DB().music.channel = v end)
    L:Check("嗜血持续期间循环播放",
        function() return DB().music.loop end,
        function(v) DB().music.loop = v end)
    L:Slider("BaimiaoRaidCDLoopSlider", "循环间隔(秒)", 1, 30, 1,
        function() return DB().music.loopInterval or 3 end,
        function(v) DB().music.loopInterval = v end)
    L:Text("循环间隔建议设成你音频的实际长度，衔接最顺。悬停上面的音乐下拉项可直接试听。", true)
    L:Text("声道对单次播放和循环播放都生效（循环用的是定时重播 PlaySoundFile）。", true)
    L:Text("自定义路径 / fileDataID（音乐下拉选“自定义路径…”时用）：", true)
    L:Box(460, 22, false,
        function() return DB().music.file end,
        function(v) DB().music.file = (v or ""):gsub("^%s+", ""):gsub("%s+$", "") end)
    local tryBtn = L:Button(120, "试听", function() PreviewMusic(nil, true) end)
    L:Button(120, "停止", function() StopLustMusic() end, true, tryBtn)

    L:Text("提示：团队里读共享战复池；单人/小队里读你自己职业的战复（惩戒骑=代祷，不在CD就是1）。" ..
        "自己职业没有战复时显示「战复：无」，不会误报 1 次。" ..
        "嗜血判定已内置常见变体（嗜血/英勇/时间扭曲/亲龙之赐/原始狂暴）。" ..
        "锁定后可用 Alt+右键 打开本设置。", true)
end

--------------------------------------------------------------------------------
-- 斜杠命令：/raidcd
--------------------------------------------------------------------------------

local function SetupSlash()
    SLASH_BMRAIDCD1 = "/raidcd"
    SLASH_BMRAIDCD2 = "/xuebiao"
    SLASH_BMRAIDCD3 = "/bmraidcd"  -- 保底别名
    SlashCmdList["BMRAIDCD"] = function(msg)
        local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if cmd == "lock" then
            LayoutDB().locked = true; Refresh(); ns.Print("嗜血/战复监控：已锁定。")
        elseif cmd == "unlock" then
            LayoutDB().locked = false; Refresh(); ns.Print("嗜血/战复监控：已解锁，可拖动。")
        elseif cmd == "reset" then
            local d = LayoutDB()
            d.point, d.relPoint, d.x, d.y = "CENTER", "CENTER", 0, 60
            Refresh(); ns.Print("嗜血/战复监控：位置已重置。")
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
    name = "嗜血/战复监控",
    desc = "两行小图标常驻：嗜血准备就绪/倒计时、战复剩余次数，可选嗜血音乐。",
    defaults = defaults,
    OnEnable = function()
        RegisterBundled()
        CreateFrameOnce()
        SetupSlash()
        UpdateDisplay()
    end,
    OnDisable = function()
        pollActive = false
        if frame then frame:Hide() end
        StopLustMusic()  -- 顺手停掉可能正在循环的嗜血音乐
    end,
    OnToggle = function(_, on)
        if on then
            pollActive = true
        end
        Refresh()
    end,
    BuildOptions = BuildOptions,
})
