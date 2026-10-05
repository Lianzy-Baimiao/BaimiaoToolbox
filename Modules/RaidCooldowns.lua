local ADDON, ns = ...
local T = ns.L

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
--   12.x 战斗中嗜血增益可能返回空值；只用公开的“新获得疲惫”作约 40 秒备用判定。
--   不读取秘密字段，不把带入副本的旧疲惫当成一次新嗜血。
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
    showLust = true,
    showBrez = true,
    showSolo = true,    -- 单人时显示
    showParty = true,   -- 小队时显示
    showRaid = true,    -- 团队时显示
    music = {
        enabled = false,
        sound = "__custom__",   -- LSM 声音名；特殊值 "__custom__" = 用下面的自定义路径
        file = "",               -- 自定义路径或 fileDataID（sound 选“自定义”时用）
        channel = "Master",       -- Master/Music/SFX/Ambience/Dialog
        loop = true,             -- 嗜血持续期间循环播放
        loopInterval = 3,        -- 循环间隔（秒）；设成你音频的长度最顺
    },
}
-- 布局字段（point/relPoint/x/y/locked）从 1.2.0 起存角色档，见 LayoutDB()。

local function DB()
    local d = ns.GetDB(MODULE_ID, defaults)
    -- The removed bundled selection is no longer a valid sound. Keep user paths
    -- and all playback preferences; an empty custom path requires a new choice.
    if d.music.sound == "白描：嗜血球" then d.music.sound = "__custom__" end
    return d
end
-- 布局（位置/锁定）按角色保存；首次访问自动从旧账号档 DB() 迁移。
local function LayoutDB() return ns.GetLayoutDB(MODULE_ID, DB()) end

--------------------------------------------------------------------------------
-- 数据
--------------------------------------------------------------------------------

-- present: 1=公开可见，0=查询成功且未找到，-1=未知（失败/秘密值）。
-- 嗜血增益的 0 在受限战斗中并不保证真的不存在；疲惫仅用于观察新获得的边沿。
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- Cache only successful negative queries out of combat; never retain aura objects
-- or secret/unknown results. Player/world events invalidate immediately; a one
-- second fallback bounds recovery if an event is missed.
local absentLustUntil, absentSatedUntil
local function InvalidateAuraAbsence()
    absentLustUntil, absentSatedUntil = nil, nil
end

local function ReadAuras(ids, now, cacheAbsence)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return -1 end
    local deadline
    if ids == LUST_SPELLS then deadline = absentLustUntil else deadline = absentSatedUntil end
    if cacheAbsence and deadline and now < deadline then return 0 end
    if ids == LUST_SPELLS then absentLustUntil = nil else absentSatedUntil = nil end
    local missing = 0
    for _, sid in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if not ok or IsSecret(aura) then
            missing = -1
        elseif aura then
            local exp = aura.expirationTime
            -- 已知 ID 对应的公开 aura 即足以确认存在；不比较/格式化秘密时间。
            if IsSecret(exp) or type(exp) ~= "number" or exp == 0 then return 1 end
            if exp > now then
                local duration = aura.duration
                local start
                if not IsSecret(duration) and type(duration) == "number" and duration > 0 then
                    start = exp - duration
                end
                return 1, exp, start
            end
        end
    end
    if missing == 0 and cacheAbsence then
        if ids == LUST_SPELLS then absentLustUntil = now + 1 else absentSatedUntil = now + 1 end
    end
    return missing
end

local GUESS_DURATION = 40
local satedPrevious, guessUntil, guessContext
local worldLeaving = false
local lustState = { active = false }
local lastTriggerSource, lastTriggerAt

-- This private sample has no external owners; reuse it rather than allocate on
-- every poll. Clear all optional fields so an expired aura cannot leave a timer.
local function ClearLustState()
    wipe(lustState)
    lustState.active = false
end

local function ResetLustTracking()
    InvalidateAuraAbsence()
    satedPrevious, guessUntil, guessContext = nil, nil, nil
    ClearLustState()
end

-- 备用窗口只在副本内有效；野外只认真实可读的增益，不能由疲惫推断正在嗜血。
local function GuessContext()
    if worldLeaving or not IsInInstance then return end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or IsSecret(inside) or IsSecret(kind) then return end
    if inside == true and (kind == "party" or kind == "raid") then return kind end
end

-- A public, unrelated incremental update need not invalidate the whole sample.
-- Do not retain aura objects/instance IDs or guess what a removed aura was.
local watchedAuras = {}
for _, id in ipairs(LUST_SPELLS) do watchedAuras[id] = true end
for _, id in ipairs(SATED_DEBUFFS) do watchedAuras[id] = true end

local function IsUnrelatedAura(aura)
    if IsSecret(aura) or type(aura) ~= "table" then return false end
    local id = aura.spellId
    return not IsSecret(id) and type(id) == "number" and not watchedAuras[id]
end

local function IsUnrelatedAuraUpdate(info)
    -- Preserve combat and instance edge inference without filtering.
    if InCombatLockdown() or GuessContext() then return false end
    if IsSecret(info) or type(info) ~= "table" then return false end
    local full = info.isFullUpdate
    if IsSecret(full) or full ~= false then return false end
    local removed, added, updated = info.removedAuraInstanceIDs, info.addedAuras, info.updatedAuraInstanceIDs
    if IsSecret(removed) or IsSecret(added) or IsSecret(updated) then return false end
    if removed ~= nil and (type(removed) ~= "table" or next(removed) ~= nil) then return false end
    if added ~= nil then
        if type(added) ~= "table" then return false end
        for _, aura in ipairs(added) do
            if not IsUnrelatedAura(aura) then return false end
        end
    end
    if updated ~= nil then
        if type(updated) ~= "table" then return false end
        -- Large batches are cheaper/safer to handle through the existing scan.
        if #updated > 4 then return false end
        local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
        for _, id in ipairs(updated) do
            if IsSecret(id) or type(id) ~= "number" or not lookup then return false end
            if not IsUnrelatedAura(lookup("player", id)) then return false end
        end
    end
    return true
end

local function SampleLust()
    if worldLeaving then
        ClearLustState()
        return lustState
    end
    local now = GetTime()
    local context = GuessContext()
    if guessContext ~= context then
        InvalidateAuraAbsence()
        -- 不依赖世界事件一定早于下一次轮询：出本立即清除推定，进本重新建基线。
        satedPrevious, guessUntil = nil, nil
        guessContext = context
    end
    -- Keep dungeon/raid edge inference and combat polling uncached.
    local cacheAbsence = not context and not InCombatLockdown()
    local sated, satedExp, satedStart = ReadAuras(SATED_DEBUFFS, now, cacheAbsence)
    local freshSated = satedPrevious == 0 and sated == 1
    -- 首次采样只建立基线；未知采样也会打断“确认没有 -> 新出现”的证据链。
    satedPrevious = sated
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    if dead or not context or sated == 0 then guessUntil = nil end
    -- 公开时间能证明是旧疲惫时，不把过图/同步后晚到的数据认作新施放。
    local recent = not satedStart or math.abs(now - satedStart) <= 2
    if freshSated and not dead and context and recent then
        guessUntil = math.min(now, satedStart or now) + GUESS_DURATION
    end
    if guessUntil and guessUntil <= now then guessUntil = nil end

    local wasActive = lustState.active
    ClearLustState()
    local state = lustState
    state.sated, state.satedExp = sated, satedExp
    if not dead then
        local buff, buffExp = ReadAuras(LUST_SPELLS, now, cacheAbsence)
        if buff == 1 then
            state.active, state.endsAt, state.source = true, buffExp, T["嗜血增益"]
            -- 读得到实际结束时间时缩短备用窗口，不把推定计时延长到真实增益之后。
            if guessUntil and buffExp then guessUntil = math.min(guessUntil, buffExp) end
        elseif guessUntil then
            state.active, state.endsAt, state.source = true, guessUntil, T["新疲惫推定"]
            state.estimated = true
        end
    end
    if state.active and not wasActive then
        lastTriggerSource, lastTriggerAt = state.source, now
    end
    return state
end

local ACTIVE_COLOR, WAIT_COLOR = { 1, 0.85, 0.1 }, { 0.75, 0.75, 0.75 }
local READY_COLOR, EMPTY_COLOR = { 0.2, 1, 0.4 }, { 1, 0.3, 0.3 }

local function GetLustDisplay(state)
    if state.active then
        local text = T["嗜血中"]
        if state.endsAt then
            text = (state.estimated and T["嗜血中 约%.0f秒"] or T["嗜血中 %.0f秒"]):format(
                math.max(0, state.endsAt - GetTime()))
        end
        return text, ACTIVE_COLOR
    elseif state.sated == 1 then
        if state.satedExp then
            local left = math.max(0, state.satedExp - GetTime())
            return (T["冷却 %d:%02d"]):format(math.floor(left / 60), math.floor(left % 60)), WAIT_COLOR
        end
        return T["冷却中"], WAIT_COLOR
    elseif state.sated == -1 then
        return T["状态暂不可读"], WAIT_COLOR
    end
    return T["准备就绪"], READY_COLOR
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
            return T["战复：?"], WAIT_COLOR
        end
        return T["战复：无"], WAIT_COLOR
    end

    local txt = T["战复："] .. charges
    if maxc and charges < maxc and start and dur and dur > 0 then
        local left = (start + dur) - GetTime()
        if left > 0 then
            txt = txt .. (" (%d:%02d)"):format(math.floor(left / 60), math.floor(left % 60))
        end
    end
    local col = (charges <= 0) and EMPTY_COLOR or READY_COLOR
    return txt, col
end

--------------------------------------------------------------------------------
-- 嗜血音乐
--------------------------------------------------------------------------------

local musicHandle
local musicTicker    -- 循环播放的计时器
local musicWantedLast = false
local lastPlayResult, lastPlayAt = T["尚未请求"], nil

local SOUND_CHANNELS = { "Master", "Music", "SFX", "Ambience", "Dialog" }
local CHANNEL_LABEL = {
    Master = T["主声道"], Music = T["音乐"], SFX = T["音效"], Ambience = T["环境"], Dialog = T["对话"],
}

-- LibSharedMedia（可选）：读取其他插件注册的声音，不附带音乐文件。
local LSM
local function GetLSM()
    if not LSM then LSM = LibStub and LibStub("LibSharedMedia-3.0", true) end
    return LSM or nil
end
-- 下拉可选项：所有 LSM 声音 + “自定义路径”。没装 LSM 时仅提供自定义。
local function SoundList()
    local out = {}
    local lsm = GetLSM()
    if lsm then
        for _, name in ipairs(lsm:List("sound")) do
            out[#out + 1] = { value = name, text = name }
        end
    end
    out[#out + 1] = { value = "__custom__", text = T["自定义路径…"] }
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
    return nil
end

-- 播放一次并返回 handle、请求结果；客户端接受请求不等于玩家一定能听见。
-- sound 不传则用当前设置；report 仅供主动点“试听”反馈，悬停/自动播放不刷屏。
local function PlaySoundOnce(sound, report)
    local m = DB().music
    local file
    if sound then
        if sound == "__custom__" then
            file = (m.file and m.file ~= "") and (tonumber(m.file) or m.file) or nil
        else
            local lsm = GetLSM()
            file = (lsm and lsm:Fetch("sound", sound, true)) or nil
        end
    else
        file = ResolveSoundFile()
    end
    if not file then
        if report then ns.Print(T["嗜血音乐：没选到有效的声音（自定义模式请填路径/fileDataID）。"]) end
        return nil, T["声音资源未找到"]
    end
    local ok, willPlay, handle = pcall(PlaySoundFile, file, m.channel or "Master")
    if ok and willPlay then
        -- report=true 的调用点（点“试听”按钮）给一次确认；
        -- 悬停下拉试听传 false，避免滑一遍列表就刷屏。
        if report then
            ns.Print(T["嗜血音乐：已请求播放（"] .. (CHANNEL_LABEL[m.channel] or m.channel or "?") .. "）。")
        end
        return handle, T["客户端已接受请求（不代表一定可听见）"]
    end
    if report then
        ns.Print(T["嗜血音乐：播放失败。自定义音频请放进插件目录用 "] ..
            T["Interface\\AddOns\\...\\xxx.ogg 路径（游戏启动后临时丢进 Interface\\Music 的常读不到），或改用 fileDataID。"])
    end
    return nil, ok and T["客户端拒绝播放"] or T["播放接口调用失败"]
end

-- 停止：取消循环计时器 + 停当前音。
local function StopLustMusic()
    if musicTicker then musicTicker:Cancel(); musicTicker = nil end
    if musicHandle then pcall(StopSound, musicHandle); musicHandle = nil end
end

-- 试听：只放一次，不循环。report=true（点“试听”按钮）会回报一次；
-- 悬停下拉试听走 false，静默播放——听得见就是反馈，不再刷屏。
local function PreviewMusic(sound, report)
    StopLustMusic()
    musicHandle = PlaySoundOnce(sound, report)
end

local function WantsMusic()
    return ns.IsModuleEnabled(MODULE_ID) and DB().enabled and DB().music.enabled and lustState.active
        and (not lustState.estimated or GuessContext() ~= nil)
end

local function PlayAutomaticOnce()
    musicHandle, lastPlayResult = PlaySoundOnce(nil, false)
    lastPlayAt = GetTime()
end

local function PlayLustMusic()
    local m = DB().music
    StopLustMusic()
    PlayAutomaticOnce()
    if m.loop then
        local interval = math.max(1, tonumber(m.loopInterval) or 3)
        musicTicker = C_Timer.NewTicker(interval, function()
            if not WantsMusic() or not DB().music.loop
                or (lustState.endsAt and GetTime() >= lustState.endsAt)
                or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
                StopLustMusic()
                return
            end
            if musicHandle then pcall(StopSound, musicHandle) end
            PlayAutomaticOnce()
        end)
    end
end

-- 音乐由状态驱动，与文字/场景可见性无关。主动“停止”或试听不会在下一帧被抢回。
local function SyncLustMusic()
    local wanted = WantsMusic() and true or false
    if wanted and not musicWantedLast then
        PlayLustMusic()
    elseif not wanted and musicWantedLast then
        StopLustMusic()
    end
    musicWantedLast = wanted
end

local function ResetLustSession()
    StopLustMusic()
    musicWantedLast = false
    ResetLustTracking()
end

-- 只在用户请求时输出，自动检测失败不刷屏；保留本次登录最近一次自动触发/请求。
local function ReportMusic()
    local m = DB().music
    local text = GetLustDisplay(lustState)
    ns.Print(T["嗜血音乐：模块"] .. ((ns.IsModuleEnabled(MODULE_ID) and DB().enabled) and T["开"] or T["关"]) ..
        T[" / 自动"] .. (m.enabled and T["开"] or T["关"]) .. " / " .. (CHANNEL_LABEL[m.channel] or T["主声道"]) ..
        T["；当前："] .. text .. "。")
    local trigger = lastTriggerSource and (lastTriggerSource .. (T["（%.0f秒前）"]):format(GetTime() - lastTriggerAt)) or T["未检测到"]
    local result = lastPlayResult .. (lastPlayAt and (T["（%.0f秒前）"]):format(GetTime() - lastPlayAt) or "")
    ns.Print(T["上次触发："] .. trigger .. T["；自动播放："] .. result .. "。")
    ns.Print(T["声音："] .. (m.sound or T["未选择"]) .. T["；资源"] .. (ResolveSoundFile() and T["已解析"] or T["未找到"]) .. "。")
    if GetCVar then
        local channel = m.channel or "Master"
        local function Setting(name)
            local ok, value = pcall(GetCVar, name)
            if not ok or IsSecret(value) or value == nil or value == "" then return "?" end
            return tostring(value)
        end
        local enabled = channel == "Master" and "Sound_EnableAllSound" or "Sound_Enable" .. channel
        ns.Print(T["声音设置：总开关="] .. Setting("Sound_EnableAllSound") .. T[" / 总音量="] .. Setting("Sound_MasterVolume") ..
            T[" / 声道开关="] .. Setting(enabled) .. T[" / 声道音量="] .. Setting("Sound_" .. channel .. "Volume") .. "。")
    end
end

--------------------------------------------------------------------------------
-- 显示
--------------------------------------------------------------------------------

local frame
local pollActive = false      -- 0.25s 轮询开关；模块关闭时停掉避免空转
local pollFrame
ns.IdleTasks = ns.IdleTasks or {}
local pollTask = {}
ns.IdleTasks.RaidCD = pollTask
local function PollTick()
    if pollActive then pollTask.run() end
end
local function SetPolling(active)
    pollActive = active and true or false
    if not pollFrame then return end
    pollFrame:SetShown(pollActive)
    if pollActive then
        if not pollTask.timer then pollTask.timer = C_Timer.NewTicker(0.25, PollTick) end
        if pollFrame.RegisterUnitEvent then pollFrame:RegisterUnitEvent("UNIT_AURA", "player")
        else pollFrame:RegisterEvent("UNIT_AURA") end
    else
        if pollTask.timer then pollTask.timer:Cancel(); pollTask.timer = nil end
        pollFrame:UnregisterEvent("UNIT_AURA")
    end
end
local layoutDirty = true
local layoutLust, layoutBrez, layoutSize

local function ApplyLockVisual()
    if not frame then return end
    -- 鼠标始终开启（保证锁定时 Alt+右键 仍能打开设置）；只有背景随锁定隐藏。
    frame:EnableMouse(true)
    frame.bg:SetShown(not frame:IsLocked())
end

-- 按字号重排：图标 = 字高，图标在左、文字在右，两行左对齐。
local function ApplyLook()
    if not frame then return end
    layoutDirty = true
    local size = DB().fontSize or 16
    local fontPath = GameFontNormal:GetFont()
    for _, row in ipairs(frame.rows) do
        row.icon:SetSize(size, size)
        ns.UI.SetRuntimeFont(row.text, fontPath, size)
    end
    frame.rows[1]:SetHeight(size + 2)
    frame.rows[2]:SetHeight(size + 2)
end

local function UpdateRow(row, text, color)
    local changed = row.text:GetText() ~= text
    if changed then row.text:SetText(text) end
    if row.displayColor ~= color then
        row.text:SetTextColor(color[1], color[2], color[3])
        row.displayColor = color
    end
    -- Runtime appearance may change the font without going through ApplyLook.
    local path, size, flags = row.text:GetFont()
    if row.displayFont ~= path or row.displaySize ~= size or row.displayFlags ~= flags then
        row.displayFont, row.displaySize, row.displayFlags = path, size, flags
        changed = true
    end
    return changed
end

local function UpdateDisplay()
    if not frame then return end
    local d = DB()

    if not ns.IsModuleEnabled(MODULE_ID) or not d.enabled then
        ResetLustSession()
        frame:Hide()
        return
    end

    local state = SampleLust()
    SyncLustMusic()

    -- 按当前处于 单人/小队/团队 的可见性设置决定显示；解锁时强制可见便于摆位。
    local show
    if IsInRaid() then show = d.showRaid
    elseif IsInGroup() then show = d.showParty
    else show = d.showSolo end
    if not show and frame:IsLocked() then
        frame:Hide()
        return
    end
    local showLust = d.showLust ~= false
    frame:SetShown(showLust or d.showBrez)
    frame.rows[1]:SetShown(showLust)

    -- 第一行：嗜血
    local lustTxt, lustCol = GetLustDisplay(state)
    local changed = UpdateRow(frame.rows[1], lustTxt, lustCol)
    -- 第二行：战复
    if d.showBrez then
        frame.rows[2]:Show()
        local brezTxt, brezCol = GetBrezState()
        if UpdateRow(frame.rows[2], brezTxt, brezCol) then changed = true end
    else
        frame.rows[2]:Hide()
    end

    -- Keep polling aura/music state, but only lay out changed display content.
    local size = d.fontSize or 16
    if layoutLust ~= showLust or layoutBrez ~= d.showBrez or layoutSize ~= size then
        layoutDirty = true
    end
    if not changed and not layoutDirty then return end
    if layoutDirty then
        frame.rows[2]:ClearAllPoints()
        if showLust then
            frame.rows[2]:SetPoint("TOPLEFT", frame.rows[1], "BOTTOMLEFT", 0, -2)
        else
            frame.rows[2]:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
        end
        frame.rows[2]:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
        frame:SetHeight(((showLust and 1 or 0) + (d.showBrez and 1 or 0)) * (size + 4) + 8)
        layoutLust, layoutBrez, layoutSize = showLust, d.showBrez, size
        layoutDirty = false
    end
    local w1 = showLust and (frame.rows[1].icon:GetWidth() + 4 + frame.rows[1].text:GetStringWidth()) or 0
    local w2 = d.showBrez and (frame.rows[2].icon:GetWidth() + 4 + frame.rows[2].text:GetStringWidth()) or 0
    frame:SetWidth(math.max(w1, w2, 60) + 12)
end

pollTask.run = UpdateDisplay

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
            title = T["嗜血 / 战复监控"],
            lines = {
                T["Alt / Ctrl+左键：拖动摆位（锁定时也可）"],
                T["Alt+右键：打开设置（命令 /raidcd 或 /bm raidcd）"],
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
    -- 音乐独立轮询，不依附可见监控框。玩家光环事件用于及时捕获疲惫的移除/新获得。
    local poll = CreateFrame("Frame", "BaimiaoRaidCDPoll", UIParent)
    pollFrame = poll
    SetPolling(ns.IsModuleEnabled(MODULE_ID) and DB().enabled)
    poll:RegisterEvent("PLAYER_ENTERING_WORLD")
    poll:RegisterEvent("PLAYER_LEAVING_WORLD")
    poll:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    poll:RegisterEvent("PLAYER_DEAD")
    poll:RegisterEvent("PLAYER_REGEN_DISABLED")
    poll:RegisterEvent("PLAYER_REGEN_ENABLED")
    poll:SetScript("OnEvent", function(_, event, unit, updateInfo)
        -- 即使模块在载入期间关闭，也不能把离开世界的标记留到再次启用。
        if event == "PLAYER_ENTERING_WORLD" then worldLeaving = false end
        if not pollActive or (event == "UNIT_AURA" and unit ~= "player") then return end
        if event == "UNIT_AURA" then
            -- Any restricted field or failed lookup falls back, never suppresses.
            local ok, unrelated = pcall(IsUnrelatedAuraUpdate, updateInfo)
            if ok and unrelated then return end
        end
        InvalidateAuraAbsence()
        if event == "PLAYER_LEAVING_WORLD" then
            worldLeaving = true
            ResetLustSession()
        elseif event == "PLAYER_ENTERING_WORLD" then
            worldLeaving = false
            ResetLustSession()
        elseif event == "PLAYER_DEAD" then
            ResetLustSession()
        end
        UpdateDisplay()
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

local function BuildOptions(panel,m,L)
    L:Title(T["嗜血 / 战复监控"])
    m.optionTabs=ns.UI.OptionTabs(panel,L,{
        {name=T["监控显示"],width=150,build=function(panel,L,onResize)
            L:Section(T["监控内容与场景"])
            L:Row({
                function(c)c:Check(T["显示嗜血行"],function()return DB().showLust~=false end,
                    function(v)DB().showLust=v end,Refresh)end,
                function(c)c:Check(T["显示战复行"],function()return DB().showBrez end,
                    function(v)DB().showBrez=v end,Refresh)end,
            },260)
            L:Text(T["关闭两行只隐藏监控条，不影响嗜血音乐。"],true)
            L:Row({
                function(c)c:Check(T["单人时显示"],function()return DB().showSolo end,
                    function(v)DB().showSolo=v end,Refresh)end,
                function(c)c:Check(T["小队时显示"],function()return DB().showParty end,
                    function(v)DB().showParty=v end,Refresh)end,
                function(c)c:Check(T["团队时显示"],function()return DB().showRaid end,
                    function(v)DB().showRaid=v end,Refresh)end,
            })
            L:Section(T["外观与位置"])
            L:Row({
                function(c)c:Slider("BaimiaoRaidCDFontSlider",T["字号"],10,40,1,
                    function()return DB().fontSize or 16 end,function(v)DB().fontSize=v end,Refresh)end,
                function(c)c:Check(T["锁定位置"],function()return LayoutDB().locked end,
                    function(v)LayoutDB().locked=v end,Refresh)
                    c:Button(180,T["重置监控条位置"],function()
                        local d=LayoutDB();d.point,d.relPoint,d.x,d.y="CENTER","CENTER",0,60;Refresh()
                    end)
                end,
            },280)
            L:Text(T["锁定后隐藏背景；Alt + 左键拖动，Alt + 右键打开设置。"],true)
            m.monitorHelp=ns.UI.OptionGroups(panel,L,{{title=T["监控说明"],collapsed=true,build=function(_,c)
                c:Text(T["团队中显示共享战复次数；单人或小队中显示自身战复。没有战复技能时显示“无”。"],true)
                c:Text(T["嗜血判定已内置常见变体（嗜血/英勇/时间扭曲/亲龙之赐/原始狂暴）。"],true)
            end}},onResize)
        end},
        {name=T["嗜血音乐"],width=150,build=function(panel,L,onResize)
            L:Check(T["嗜血触发时播放音乐"],function()return DB().music.enabled end,function(v)
                DB().music.enabled=v;if not v then StopLustMusic()end
            end,function()L:SyncAll()end)
            local function musicEnabled()return DB().music.enabled end
            m.musicGroups=ns.UI.OptionGroups(panel,L,{
                {title=T["音乐与试听"],visible=musicEnabled,build=function(_,c)
                    c:Row({
                        function(cell)cell:Dropdown(320,T["音乐："],SoundList,
                            function()return DB().music.sound end,function(v)DB().music.sound=v end,
                            function()L:SyncAll()end,function(v)PreviewMusic(v)end)end,
                        function(cell)cell:Dropdown(260,T["声道："],ns.UI.ListFrom(SOUND_CHANNELS,CHANNEL_LABEL),
                            function()return DB().music.channel or "Master" end,function(v)DB().music.channel=v end)end,
                    },280)
                    local play=c:Button(120,T["试听"],function()
                        ns.UI.CommitOptionsFocus(panel);PreviewMusic(nil,true)
                    end)
                    c:Button(120,T["停止"],StopLustMusic,true,play)
                    c:Text(T["试听仅在本机播放；也可悬停音乐列表试听。"],true)
                end},
                {title=T["自定义路径 / fileDataID"],visible=function()return musicEnabled() and DB().music.sound=="__custom__"end,
                    build=function(_,c)
                        c:Box(500,28,false,function()return DB().music.file end,
                            function(v)DB().music.file=(v or ""):gsub("^%s+",""):gsub("%s+$","")end)
                    end},
                {title=T["嗜血持续期间循环播放"],visible=musicEnabled,enabled=function()return DB().music.loop end,
                    setEnabled=function(v)DB().music.loop=v end,build=function(_,c)
                        c:Slider("BaimiaoRaidCDLoopSlider",T["循环间隔(秒)"],1,30,1,
                            function()return DB().music.loopInterval or 3 end,function(v)DB().music.loopInterval=v end)
                        c:Text(T["间隔建议与音频长度一致；声道设置对循环同样生效。"],true)
                    end},
            },onResize)
        end},
    })
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
            LayoutDB().locked = true; Refresh(); ns.Print(T["嗜血/战复监控：已锁定。"])
        elseif cmd == "unlock" then
            LayoutDB().locked = false; Refresh(); ns.Print(T["嗜血/战复监控：已解锁，可拖动。"])
        elseif cmd == "music" then
            ReportMusic()
        elseif cmd == "reset" then
            local d = LayoutDB()
            d.point, d.relPoint, d.x, d.y = "CENTER", "CENTER", 0, 60
            Refresh(); ns.Print(T["嗜血/战复监控：位置已重置。"])
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
    name = T["嗜血/战复监控"],
    desc = T["两行小图标常驻：嗜血准备就绪/倒计时、战复剩余次数，可选嗜血音乐。"],
    defaults = defaults,
    OnEnable = function()
        CreateFrameOnce()
        SetupSlash()
        ResetLustSession()
        UpdateDisplay()
    end,
    OnDisable = function()
        SetPolling(false)
        if frame then frame:Hide() end
        ResetLustSession()
    end,
    OnToggle = function(_, on)
        if on then
            ResetLustSession()
            SetPolling(DB().enabled)
        end
        Refresh()
    end,
    BuildOptions = BuildOptions,
})
