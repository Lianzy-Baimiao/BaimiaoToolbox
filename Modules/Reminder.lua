local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 模块：光环/宠物提示器
-- 屏幕中间大字提醒：
--   · 术士 / 猎人 没有宠物（射击专精不带宠物是正常玩法，不提醒）
--   · 骑士 没有开任何光环
-- 触发文本、字号、颜色、位置均可编辑；光环 / “独来独往”的法术 id 可自定义。
--------------------------------------------------------------------------------

local MODULE_ID = "reminder"

-- 骑士光环默认法术 id（不同版本可能变，设置里可改）。
-- 465 专注/虔诚, 32223 十字军, 183435 报应, 317920 专注……按需增减。
local DEFAULT_PALADIN_AURAS = "465,32223,183435,317920"

-- “独来独往”（Lone Wolf）的法术 id（逗号分隔，设置里可改）：
-- 155228 = 2016–11.1 那版（11.1.0 已被移除）；164273 / 295390 = 当前 DB2 SpellName(zhCN)
-- 里名为“独来独往”的条目。暴雪改 id 是常态，所以做成设置项而不是写死的常量。
local DEFAULT_LONE_WOLF = "155228,164273,295390"

local defaults = {
    fontSize = 40,
    outline = true,
    color = { r = 1.0, g = 0.2, b = 0.2 },
    pulse = true,               -- 闪烁提醒
    onlyOutOfCombat = false,    -- 只在脱战时提醒
    hideWhenDead = true,        -- 死亡/成为鬼魂时不提醒
    rules = {
        pet = {
            enabled = true,
            text = "|cffff2020没有宠物！|r",
            skipMarksmanship = true,          -- 射击专精：宠物是可选项，不带不提醒
            loneWolfSpells = DEFAULT_LONE_WOLF,
        },
        paladinAura = {
            enabled = true,
            text = "|cffff2020没有开光环！|r",
            spells = DEFAULT_PALADIN_AURAS,
        },
    },
}
-- 布局字段（point/relPoint/x/y/locked）从 1.2.0 起存角色档，见 LayoutDB()。

local function DB() return ns.GetDB(MODULE_ID, defaults) end
-- 布局（位置/锁定）按角色保存；首次访问自动从旧账号档 DB() 迁移。
local function LayoutDB() return ns.GetLayoutDB(MODULE_ID, DB()) end

local playerClass  -- 登录时缓存，本会话不变

--------------------------------------------------------------------------------
-- 判定
--------------------------------------------------------------------------------

-- 把 "465,32223" 解析成数字列表。
local function ParseSpells(str)
    local ids = {}
    for token in tostring(str or ""):gmatch("%d+") do
        ids[#ids + 1] = tonumber(token)
    end
    return ids
end

-- 当前专精的 specID（猎人：253 兽王 / 254 射击 / 255 生存）。取不到返回 nil。
local function CurrentSpecID()
    local idx
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        idx = C_SpecializationInfo.GetSpecialization()
    elseif GetSpecialization then
        idx = GetSpecialization()
    end
    if not idx then return nil end

    local info
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        info = C_SpecializationInfo.GetSpecializationInfo(idx)
    elseif GetSpecializationInfo then
        info = GetSpecializationInfo(idx)
    end
    if type(info) == "table" then return info.specID end
    return info  -- 传统多返回值：第一个就是 specID
end

-- 猎人专精 id：253 兽王、254 射击、255 生存。
-- 射击从 7.0.3 起就是“不带宠物作战”的设计（官方补丁说明原文：Marksmanship hunters
-- no longer fight with a pet），宠物只是可选项，不带它不算“忘带”。
-- 旧版本靠“独来独往”天赋判断，但那个天赋在 11.1.0 被移除、写死的 155228 永远匹配不到，
-- 于是射击猎一直被误报——所以这里直接按专精豁免，天赋 id 只当额外保险。
local SPEC_MARKSMANSHIP = 254

-- “独来独往”（Lone Wolf）的法术 id（逗号分隔，可在设置里改）：
-- 155228 = 2016–11.1 那版（11.1.0 已移除）；164273 / 295390 = 当前 DB2 SpellName(zhCN)
-- （DEFAULT_LONE_WOLF 定义在文件开头：defaults 表要用到它）

-- 是否拥有“独来独往”（不带宠物是正常玩法）。
local function HasLoneWolf()
    if playerClass ~= "HUNTER" then return false end
    for _, id in ipairs(ParseSpells(DB().rules.pet.loneWolfSpells or DEFAULT_LONE_WOLF)) do
        if IsPlayerSpell and IsPlayerSpell(id) then return true end
        if IsSpellKnown and IsSpellKnown(id) then return true end
    end
    return false
end

-- 需要宠物的职业当前是否没宠物。
local function MissingPet()
    if playerClass ~= "WARLOCK" and playerClass ~= "HUNTER" then return false end
    -- 载具中不提醒（此时没宠物很正常）。
    if UnitInVehicle and UnitInVehicle("player") then return false end
    local rule = DB().rules.pet
    if playerClass == "HUNTER" then
        -- 射击专精：宠物是可选项，不带不提醒（可在设置里关掉这条豁免）。
        if rule.skipMarksmanship and CurrentSpecID() == SPEC_MARKSMANSHIP then return false end
        -- 其它专精点了“独来独往”：同样算正常玩法，不是忘带。
        if HasLoneWolf() then return false end
    end
    return not UnitExists("pet")
end

-- 扫描玩家身上所有增益，返回 spellId 集合 + 是否成功。
-- 12.x 里增益枚举（GetAuraSlots/ForEachAura）在被 taint 时会抛“secret”错，
-- 所以整段 pcall，失败就返回 ok=false（只给 /remind auras 诊断用）。
local function ScanPlayerBuffs()
    local set = {}
    local ok = pcall(function()
        if AuraUtil and AuraUtil.ForEachAura then
            AuraUtil.ForEachAura("player", "HELPFUL", nil, function(...)
                local data = ...
                local spellId = type(data) == "table" and data.spellId or select(10, ...)
                if spellId then set[spellId] = true end
                return false
            end, true)
        elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            for i = 1, 40 do
                local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not data then break end
                if data.spellId then set[data.spellId] = true end
            end
        end
    end)
    return set, ok
end

-- 骑士当前是否没有开任何配置里的光环。
--
-- 关键坑（12.x）：战斗中光环会被从枚举结果里【剔除】——枚举本身不报错(ok=true)，
-- 只是那条光环“隐身”了。所以战斗中现读会把开着的光环误判成“没开”，
-- 脱战正常、一开打就误报，正是这个原因。
--
-- 解决：战斗中【不重新判断】，沿用最近一次“脱战且成功读到”的可靠结果。
-- 缓存只在【脱战 + 枚举可信】时写入，绝不从战斗中的不可信读取写入
-- （之前卡死就是因为拿不可信读取写了缓存）。初值 false，未知时不提醒。
local lastReliableMissing = false

local function MissingPaladinAura()
    if playerClass ~= "PALADIN" then return false end
    local ids = ParseSpells(DB().rules.paladinAura.spells)
    if #ids == 0 then return false end

    -- 读不可信的窗口：战斗中，或大秘境进行中（钥石一开始整局光环都对插件隐身）。
    -- 这些情况下沿用最近一次可靠判断，不重新读。
    local inChallenge = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    if InCombatLockdown() or UnitAffectingCombat("player") or inChallenge then
        return lastReliableMissing
    end

    local buffs, ok = ScanPlayerBuffs()
    if not ok then return lastReliableMissing end  -- 脱战但仍读不到：沿用上次

    for _, id in ipairs(ids) do
        if buffs[id] then lastReliableMissing = false; return false end
    end
    lastReliableMissing = true
    return true
end

-- 汇总当前需要提醒的文本行。
local function CollectMessages()
    local r = DB().rules
    local out = {}
    if r.pet.enabled and MissingPet() then
        out[#out + 1] = r.pet.text
    end
    if r.paladinAura.enabled and MissingPaladinAura() then
        out[#out + 1] = r.paladinAura.text
    end
    return out
end

--------------------------------------------------------------------------------
-- 显示
--------------------------------------------------------------------------------

local frame
local testUntil = 0  -- “测试”时强制显示到某时间点

local function ApplyLook()
    if not frame then return end
    local d = DB()
    frame.text:SetFont(GameFontNormal:GetFont(), d.fontSize or 40, d.outline and "OUTLINE" or "")
    local c = d.color or { r = 1, g = 1, b = 1 }
    frame.text:SetTextColor(c.r, c.g, c.b)
end

-- 居中大字提示器：锁定 = 不吃鼠标（不能挡住对游戏世界的点击）；解锁 = 吃鼠标可拖。
-- 工厂的 unlockDragOnly 模式正好表达这个语义。
local function StartPulse()
    if frame and frame.pulse and not frame.pulse:IsPlaying() then
        frame.pulse:Play()
    end
end
local function StopPulse()
    if frame and frame.pulse and frame.pulse:IsPlaying() then
        frame.pulse:Stop()
        frame:SetAlpha(1)
    end
end

local function Update()
    if not frame then return end
    local d = DB()

    -- 解锁状态：始终显示一个占位，方便拖动摆位。
    if not frame:IsLocked() then
        frame.text:SetText("◆ 提示器（拖动我）◆")
        frame:Show()
        StopPulse()
        frame:SetSize(math.max(frame.text:GetStringWidth() + 40, 120),
                       math.max(frame.text:GetStringHeight() + 20, 40))
        return
    end

    if not ns.IsModuleEnabled(MODULE_ID) then frame:Hide() StopPulse() return end

    -- 测试：强制显示示例文本一小段时间。
    if GetTime() < testUntil then
        frame.text:SetText("|cffff2020提示示例|r")
        frame:Show()
        if d.pulse then StartPulse() else StopPulse() end
        frame:SetSize(math.max(frame.text:GetStringWidth() + 40, 120),
                       math.max(frame.text:GetStringHeight() + 20, 40))
        return
    end

    -- 脱战限制 / 死亡限制
    if d.onlyOutOfCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then
        frame:Hide() StopPulse() return
    end
    if d.hideWhenDead and (UnitIsDeadOrGhost("player")) then
        frame:Hide() StopPulse() return
    end

    local msgs = CollectMessages()
    if #msgs == 0 then
        frame:Hide() StopPulse()
        return
    end

    frame.text:SetText(table.concat(msgs, "\n"))
    frame:SetSize(math.max(frame.text:GetStringWidth() + 40, 120),
                   math.max(frame.text:GetStringHeight() + 20, 40))
    frame:Show()
    if d.pulse then StartPulse() else StopPulse() end
end

local function CreateFrameOnce()
    if frame then return frame end

    frame = ns.UI.CreateMovableFrame({
        name = "BaimiaoReminderFrame",
        moduleId = MODULE_ID,
        clickable = false,
        size = { 300, 60 },
        strata = "HIGH",
        bgAlpha = 0.4,
        unlockDragOnly = true,              -- 锁定时放行点击，不挡屏幕中央
        legacy = DB(),                      -- 旧账号档布局自动迁移
        defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 },
        tooltip = {
            title = "光环 / 宠物提示器",
            lines = {
                "解锁状态：按住左键拖动摆位",
                "命令 /remind：lock 锁定 / unlock 解锁 / test 试显示 / auras 列出增益",
            },
        },
    })

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")
    frame.text:SetJustifyH("CENTER")

    -- 闪烁动画：透明度 1 <-> 0.35 来回。
    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.5)
    frame.pulse = ag

    ApplyLook()
    return frame
end

local function Refresh()
    if not frame then return end
    frame:ApplyPosition()
    ApplyLook()
    frame:ApplyLockVisual()
    Update()
end

--------------------------------------------------------------------------------
-- 事件
--------------------------------------------------------------------------------

local eventFrame
local pollActive = false

local function RegisterAllEvents()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterUnitEvent("UNIT_PET", "player")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    pollActive = true
end

local function SetupEvents()
    if eventFrame then
        -- 已存在：说明是被重新启用，补注册一次即可（UnregisterAllEvents 摘光了）。
        RegisterAllEvents()
        return
    end
    eventFrame = CreateFrame("Frame")
    RegisterAllEvents()
    eventFrame:SetScript("OnEvent", function() Update() end)

    -- 事件之外再挂个 0.5s 轮询兜底：有些光环/宠物变化不一定触发上面的事件，
    -- 靠轮询保证脱战、切光环后也能及时刷新。
    pollActive = true
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        if not pollActive then return end
        acc = acc + dt
        if acc >= 0.5 then acc = 0 Update() end
    end)
end

-- 模块被总开关关闭时：摘掉事件、停轮询，避免空转。
local function TeardownEvents()
    pollActive = false
    if eventFrame then eventFrame:UnregisterAllEvents() end
end

--------------------------------------------------------------------------------
-- 设置面板
--------------------------------------------------------------------------------

local function BuildOptions(panel, m, L)
    L:Title("光环/宠物提示器")
    L:Text("屏幕中间大字提醒。术士/猎人没宠物、骑士没开光环时弹出（射击专精不带宠物属正常，已豁免）。", false)

    L:Section("外观")
    L:Slider("BaimiaoReminderFontSlider", "字号", 16, 72, 1,
        function() return DB().fontSize or 40 end,
        function(v) DB().fontSize = v end, Refresh)
    L:ColorSwatch("默认文字颜色",
        function() local c = DB().color return c.r, c.g, c.b end,
        function(r, g, b) DB().color = { r = r, g = g, b = b } end, Refresh)
    L:Check("轮廓字体", function() return DB().outline end,
        function(v) DB().outline = v end, Refresh)
    L:Check("闪烁提醒", function() return DB().pulse end,
        function(v) DB().pulse = v end, Refresh)
    L:Check("锁定位置（锁定后不挡鼠标；解锁可拖动摆位）",
        function() return LayoutDB().locked end,
        function(v) LayoutDB().locked = v end, Refresh)

    L:Section("触发条件")
    L:Check("术士/猎人 没有宠物时提醒",
        function() return DB().rules.pet.enabled end,
        function(v) DB().rules.pet.enabled = v end, Refresh)
    L:Text("宠物提醒文字（支持 |cffRRGGBB 颜色码、\\n 无效请直接换行）:", true)
    L:Box(460, 26, false,
        function() return DB().rules.pet.text end,
        function(v) DB().rules.pet.text = v end, Refresh)
    L:Check("射击猎（射击专精）不带宠物不提醒（宠物是可选项）",
        function() return DB().rules.pet.skipMarksmanship end,
        function(v) DB().rules.pet.skipMarksmanship = v end, Refresh)
    L:Text("算作“独来独往”的法术 id（逗号分隔，随版本可改）:", true)
    L:Box(460, 26, false,
        function() return DB().rules.pet.loneWolfSpells or DEFAULT_LONE_WOLF end,
        function(v) DB().rules.pet.loneWolfSpells = v end, Refresh)

    L:Check("骑士 没开光环时提醒",
        function() return DB().rules.paladinAura.enabled end,
        function(v) DB().rules.paladinAura.enabled = v end, Refresh)
    L:Text("骑士光环提醒文字:", true)
    L:Box(460, 26, false,
        function() return DB().rules.paladinAura.text end,
        function(v) DB().rules.paladinAura.text = v end, Refresh)
    L:Text("算作“已开光环”的法术 id（逗号分隔，随版本可改）:", true)
    L:Box(460, 26, false,
        function() return DB().rules.paladinAura.spells end,
        function(v) DB().rules.paladinAura.spells = v end, Refresh)

    L:Section("其它")
    L:Check("只在脱战时提醒",
        function() return DB().onlyOutOfCombat end,
        function(v) DB().onlyOutOfCombat = v end, Refresh)
    L:Check("死亡/鬼魂时不提醒",
        function() return DB().hideWhenDead end,
        function(v) DB().hideWhenDead = v end, Refresh)

    L:Button(160, "测试显示 3 秒", function()
        testUntil = GetTime() + 3
        Update()
    end)
end

--------------------------------------------------------------------------------
-- 斜杠命令：/remind
--------------------------------------------------------------------------------

local function SetupSlash()
    SLASH_BMREMINDER1 = "/remind"
    SLASH_BMREMINDER2 = "/bmremind"  -- 保底别名
    SlashCmdList["BMREMINDER"] = function(msg)
        local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if cmd == "lock" then
            LayoutDB().locked = true; Refresh(); ns.Print("提示器：已锁定。")
        elseif cmd == "unlock" then
            LayoutDB().locked = false; Refresh(); ns.Print("提示器：已解锁，可拖动摆位。")
        elseif cmd == "reset" then
            local d = LayoutDB()
            d.point, d.relPoint, d.x, d.y = "CENTER", "CENTER", 0, 180
            Refresh(); ns.Print("提示器：位置已重置。")
        elseif cmd == "test" then
            testUntil = GetTime() + 3; Update()
        elseif cmd == "auras" then
            -- 列出当前身上所有增益的名字和 spellId，方便找光环真正的 id。
            local buffs, ok = ScanPlayerBuffs()
            if not ok then
                ns.Print("当前无法读取增益（游戏把它标成了“秘密值”，通常在战斗/副本中）。请脱战后再试。")
            else
                ns.Print("当前增益（把要当光环的那个 id 填进设置）：")
                local any = false
                for id in pairs(buffs) do
                    any = true
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                    local nm = (info and info.name) or (GetSpellInfo and GetSpellInfo(id)) or "?"
                    ns.Print("  " .. id .. " —— " .. nm)
                end
                if not any then ns.Print("  （没扫到增益）") end
            end
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
    name = "光环/宠物提示器",
    desc = "屏幕中间大字提醒：术士/猎人没宠物（射击专精除外）、骑士没开光环。文字/颜色/字号可编辑。",
    defaults = defaults,
    OnEnable = function()
        playerClass = select(2, UnitClass("player"))
        CreateFrameOnce()
        SetupEvents()
        SetupSlash()
        Update()
    end,
    OnDisable = function()
        TeardownEvents()
        if frame then frame:Hide() StopPulse() end
    end,
    OnToggle = function(_, on)
        if on and eventFrame then
            -- 重新注册事件（OnDisable 已摘光）。
            SetupEvents()
        end
        Refresh()
    end,
    BuildOptions = BuildOptions,
})
