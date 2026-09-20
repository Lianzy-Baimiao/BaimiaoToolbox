local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 模块：快捷坐骑
-- 一个按钮 + 斜杠命令，用不同方式召唤不同用途的坐骑：
--   飞行 / 修理 / 拍卖行 / 载人
-- 每个用途都能设默认坐骑（从当前正骑的那只“抓取”过来），可随时更改。
--
-- 按钮点击：
--   左键        飞行（未设则随机收藏坐骑）
--   Shift+左键  修理
--   Ctrl+左键   拍卖行
--   Alt+左键    载人
--   右键        水下
--   Alt+右键    打开设置
-- 斜杠：/qm fly | repair | ah | passenger | set <用途> | clear <用途>
--------------------------------------------------------------------------------

local MODULE_ID = "quickmount"

-- 用途 -> 中文名
local CATS = { "fly", "repair", "ah", "passenger", "water" }
local CAT_LABEL = {
    fly = "飞行", repair = "修理", ah = "拍卖行", passenger = "载人", water = "水下",
}

-- 各用途的“自动默认”候选，按【中文名】匹配你已收藏的坐骑（找到第一个就用）。
-- 中文客户端下按名字匹配最直观、也不依赖记对 id。手动设的优先于这里。
-- 名字必须和游戏内坐骑名完全一致；没匹配到时到设置里“设为当前”手动抓取即可。
local AUTO_BY_NAME = {
    repair    = { "顶级探险家的牦牛", "旅行者的苔原猛犸象" },
    ah        = { "鎏金雷龙" },
    passenger = { "沙石幼龙" },
    water     = { "驯服的海马" },
    -- fly 不给默认：留空 = “随机收藏坐骑”，交给游戏按环境选。
}

-- spellID 兜底候选（名字没匹配到时再按 spellID 试一遍）。
local AUTO_BY_SPELL = {
    repair = { 122708, 61425, 61447 },
    passenger = { 122708, 61425, 61447, 75973 },
}

local defaults = {
    button = {
        enabled = true,
        scale = 1,
    },
    -- 各用途绑定的 mountID；nil = 未设（fly 用随机，其它用自动默认/提示）
    mounts = {},
}
-- 布局字段（point/relPoint/x/y/locked）从 1.2.0 起存角色档，见 LayoutDB()。

local function DB() return ns.GetDB(MODULE_ID, defaults) end
-- 布局（位置/锁定）按角色保存；首次访问自动从旧账号档 DB().button 迁移。
local function LayoutDB() return ns.GetLayoutDB(MODULE_ID, DB().button) end

--------------------------------------------------------------------------------
-- 坐骑查询/召唤
--------------------------------------------------------------------------------

-- 当前正在骑的 mountID（没骑返回 nil）。用缓存避免每次全表扫描。
local ownedCache     -- { byName = {}, bySpell = {} }，NEW_MOUNT_ADDED / 登录后重建
local activeCache    -- 当前 isActive 的 mountID，MODIFIER 无关，随坐骑事件刷新

local function RebuildMountCache()
    local byName, bySpell = {}, {}
    activeCache = nil
    if C_MountJournal and C_MountJournal.GetMountIDs then
        for _, id in ipairs(C_MountJournal.GetMountIDs()) do
            local name, spellID, _, isActive, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
            if isCollected then
                if name then byName[name] = id end
                if spellID then bySpell[spellID] = id end
            end
            if isActive then activeCache = id end
        end
    end
    ownedCache = { byName = byName, bySpell = bySpell }
end

-- 当前正在骑的 mountID（没骑返回 nil）。优先读缓存，缓存还没建就现扫一次。
local function GetActiveMountID()
    if ownedCache then return activeCache end
    RebuildMountCache()
    return activeCache
end

-- mountID -> 名称（拿不到返回 nil）。
local function MountName(id)
    if not id or not C_MountJournal then return nil end
    local name = C_MountJournal.GetMountInfoByID(id)
    return name
end

-- 扫一遍已收藏坐骑，返回 name->mountID 和 spellID->mountID 两个映射。
-- 带缓存：坐骑日志在会话内基本不变，只有 NEW_MOUNT_ADDED 才重建。
local function BuildOwned()
    if not ownedCache then RebuildMountCache() end
    return ownedCache.byName, ownedCache.bySpell
end

-- 解析某用途实际要召唤的 mountID：手动设的优先，其次按名字匹配，最后按 spellID 兜底。
local function ResolveMount(cat)
    local set = DB().mounts[cat]
    if set then return set end

    local byName, bySpell = BuildOwned()
    local names = AUTO_BY_NAME[cat]
    if names then
        for _, nm in ipairs(names) do
            if byName[nm] then return byName[nm] end
        end
    end
    local spells = AUTO_BY_SPELL[cat]
    if spells then
        for _, sid in ipairs(spells) do
            if bySpell[sid] then return bySpell[sid] end
        end
    end
    return nil
end

-- 某用途对应坐骑的图标；解析不到具体坐骑（如飞行用随机）就退回收藏里第一只的图标，
-- 再不行给个通用坐骑图标。
local function CategoryIcon(cat)
    local id = ResolveMount(cat)
    if id then
        local _, _, icon = C_MountJournal.GetMountInfoByID(id)
        if icon then return icon end
    end
    -- 飞行/随机：拿第一只收藏且设为偏好的坐骑图标当代表（用缓存，不全表扫）。
    local byName = BuildOwned()
    for _, mid in pairs(byName) do
        local _, _, ic, _, _, _, isFav = C_MountJournal.GetMountInfoByID(mid)
        if isFav and ic then return ic end
    end
    return "Interface\\ICONS\\Ability_Mount_RidingHorse"
end

-- 当前修饰键指向哪个用途（用于按钮图标与左键分派）。
local function CurrentCategory()
    if IsAltKeyDown() then return "passenger"
    elseif IsControlKeyDown() then return "ah"
    elseif IsShiftKeyDown() then return "repair"
    else return "fly" end
end

local function Summon(cat)
    if InCombatLockdown() then
        ns.Print("快捷坐骑：战斗中不能召唤坐骑。")
        return
    end
    if not (C_MountJournal and C_MountJournal.SummonByID) then
        ns.Print("快捷坐骑：坐骑接口不可用。")
        return
    end

    local id = ResolveMount(cat)
    if id then
        -- 校验拥有且可用
        local name, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
        if not isCollected then
            ns.Print("快捷坐骑：" .. (CAT_LABEL[cat] or cat) .. "坐骑你还没收藏，改用随机。")
            C_MountJournal.SummonByID(0)
            return
        end
        C_MountJournal.SummonByID(id)
    else
        -- 未设：飞行/无候选 -> 随机收藏坐骑；游戏会按当前环境选合适的。
        if cat ~= "fly" then
            ns.Print("快捷坐骑：未设置" .. (CAT_LABEL[cat] or cat) .. "坐骑（也没找到合适的默认），改用随机。可在设置里指定。")
        end
        C_MountJournal.SummonByID(0)
    end
end

-- 把当前正骑的坐骑设为某用途的默认。
local function CaptureCurrent(cat)
    local id = GetActiveMountID()
    if not id then
        ns.Print("快捷坐骑：请先骑上你想设为「" .. (CAT_LABEL[cat] or cat) .. "」的坐骑，再来抓取。")
        return false
    end
    DB().mounts[cat] = id
    ns.Print(("快捷坐骑：已把「%s」设为 %s 坐骑。"):format(MountName(id) or ("#" .. id), CAT_LABEL[cat] or cat))
    return true
end

--------------------------------------------------------------------------------
-- 按钮（Core 的可拖动框工厂创建；位置/锁定存角色档）。
--------------------------------------------------------------------------------

local button

local function UpdateButton()
    if not button then return end
    local b = DB().button
    if not ns.IsModuleEnabled(MODULE_ID) or not b.enabled then
        button:Hide()
        return
    end
    button:Show()
    button:SetScale(b.scale or 1)
    button:RefreshIcon()
end

local function CreateButton()
    if button then return button end

    button = ns.UI.CreateMovableFrame({
        name = "BaimiaoQuickMountButton",
        moduleId = MODULE_ID,
        clickable = true,
        size = { 44, 44 },
        strata = "MEDIUM",
        bgAlpha = 0.45,
        legacy = DB().button,                       -- 旧账号档布局自动迁移
        defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        tooltip = {
            title = "快捷坐骑",
            lines = {
                "左键：飞行　　Shift+左键：修理",
                "Ctrl+左键：拍卖行　　Alt+左键：载人",
                "右键：水下坐骑",
                "Alt+右键：打开设置（命令 /qm 或 /bm quickmount）",
            },
        },
        onRightClick = function()
            -- Alt+右键打开设置；普通右键召唤水下坐骑。
            if IsAltKeyDown() then ns.OpenOptions(MODULE_ID) else Summon("water") end
        end,
    })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- 图标随“当前修饰键指向的用途”实时变化（不按修饰键时显示飞行坐骑）。
    function button:RefreshIcon()
        self.icon:SetTexture(CategoryIcon(CurrentCategory()))
    end

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end  -- 右键统一交给工厂处理
        Summon(CurrentCategory())
    end)

    -- 修饰键按下/松开时刷新图标，让按钮实时反映将要召唤的坐骑。
    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    button:RegisterEvent("NEW_MOUNT_ADDED")       -- 新坐骑入收藏：重建缓存
    button:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")  -- 上/下马：刷新激活缓存
    button:SetScript("OnEvent", function(self, event)
        if event == "MODIFIER_STATE_CHANGED" then
            self:RefreshIcon()
        else
            ownedCache = nil                      -- 失效缓存，下次用的时候重建
            self:RefreshIcon()
        end
    end)

    return button
end

local function Refresh()
    if not button then return end
    button:ApplyPosition()
    button:ApplyLockVisual()
    UpdateButton()
end

--------------------------------------------------------------------------------
-- 设置面板
--------------------------------------------------------------------------------

local function BuildOptions(panel, m, L)
    L:Title("快捷坐骑")
    L:Text("一个按钮用不同方式召唤不同用途坐骑：左键飞行、Shift+左键修理、Ctrl+左键拍卖行、Alt+左键载人、右键水下。按钮图标会随当前修饰键变成对应坐骑。", false)

    L:Section("按钮")
    L:Check("锁定位置（锁定后隐藏背景、不能拖动；Alt+左键仍可拖）",
        function() return LayoutDB().locked end,
        function(v) LayoutDB().locked = v end, Refresh)
    L:Slider("BaimiaoQuickMountScaleSlider", "缩放", 0.5, 2.0, 0.05,
        function() return DB().button.scale or 1 end,
        function(v) DB().button.scale = v end, Refresh)

    L:Section("各用途坐骑（先骑上想要的坐骑，再点“设为当前”）")
    for _, cat in ipairs(CATS) do
        local label = CAT_LABEL[cat]
        L:DynLabel(function()
            local id = DB().mounts[cat]
            if id then
                return label .. "：|cff00ff88" .. (MountName(id) or ("#" .. id)) .. "|r"
            end
            local auto = ResolveMount(cat)
            if auto then
                return label .. "：|cffaaaaaa自动 " .. (MountName(auto) or ("#" .. auto)) .. "|r"
            end
            return label .. "：|cffaaaaaa" .. (cat == "fly" and "随机收藏坐骑" or "未设置（随机）") .. "|r"
        end)
        local setBtn = L:Button(110, "设为当前", function()
            if CaptureCurrent(cat) then L:SyncAll() Refresh() end
        end)
        L:Button(90, "清除", function()
            DB().mounts[cat] = nil
            L:SyncAll()
            Refresh()
            ns.Print("快捷坐骑：已清除" .. label .. "坐骑。")
        end, true, setBtn)
    end

    L:Text("说明：飞行默认用“随机收藏坐骑”，游戏按能否飞行自动选。其余用途按坐骑中文名自动匹配你已收藏的：" ..
        "修理=牦牛/苔原猛犸象，拍卖行=鎏金雷龙，载人=沙石幼龙，水下=驯服的海马。" ..
        "没匹配到、或想换别的，就骑上目标坐骑点“设为当前”。", true)
end

--------------------------------------------------------------------------------
-- 斜杠命令：/qm
--------------------------------------------------------------------------------

local function SetupSlash()
    SLASH_BMQUICKMOUNT1 = "/qm"
    SLASH_BMQUICKMOUNT2 = "/bmmount"  -- 保底别名：短命令被别的插件抢走时用
    SlashCmdList["BMQUICKMOUNT"] = function(msg)
        local args = {}
        for w in (msg or ""):lower():gmatch("%S+") do args[#args + 1] = w end
        local cmd, arg = args[1], args[2]

        if cmd and CAT_LABEL[cmd] then
            Summon(cmd)
        elseif cmd == "set" and arg and CAT_LABEL[arg] then
            CaptureCurrent(arg)
        elseif cmd == "clear" and arg and CAT_LABEL[arg] then
            DB().mounts[arg] = nil
            ns.Print("快捷坐骑：已清除" .. CAT_LABEL[arg] .. "坐骑。")
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
    name = "快捷坐骑",
    desc = "一个按钮用不同修饰键召唤飞行/修理/拍卖行/载人/水下坐骑，默认坐骑可自定义。",
    defaults = defaults,
    OnEnable = function()
        RebuildMountCache()  -- 登录时建一次坐骑缓存，之后按需重建
        CreateButton()
        UpdateButton()
        SetupSlash()
    end,
    OnDisable = function()
        if button then button:Hide() end
    end,
    OnToggle = function() Refresh() end,
    BuildOptions = BuildOptions,
})
