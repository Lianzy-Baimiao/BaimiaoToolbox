local ADDON, ns = ...
local T = ns.L

--------------------------------------------------------------------------------
-- 模块：快捷按钮（原名“快捷坐骑”，后来加了扩展按钮，名字就不再只是坐骑了）
-- 一个按钮 + 斜杠命令：
--   · 按修饰键召唤不同用途的坐骑：飞行 / 修理 / 拍卖行 / 载人 / 水下
--   · 旁边按选定方向长出一排自定义按钮：技能 / 玩具 / 物品 / 小退·退组·重载等快捷动作
-- 注意：模块 id 仍是 "quickmount"（存档键名），改名只动显示名，不动 id —— 换 id 会丢设置。
--
-- 默认按钮点击（可在设置里修改坐骑组合键）：
--   左键        飞行（未设则随机收藏坐骑）
--   Shift+左键  修理
--   Ctrl+左键   拍卖行
--   Alt+左键    载人
--   右键        水下
--   Alt+右键    打开设置
-- 扩展按钮：设置中逐条选择类型、填写技能/玩具/物品的 ID 或名称，可新增、删除、调序；
--   快捷动作直接选择（小退 / 退组 / 重载界面 / 退出游戏，受保护动作走安全按钮执行），
--   会在主按钮旁按选定方向（上/下/左/右，默认向右）长出一排同尺寸按钮，点击直接使用。
-- 施法/用玩具/用物品都是受保护动作，插件不能直接调用（CastSpellByID / UseToy /
--   UseItemByName 都会被拒），所以按钮继承 SecureActionButtonTemplate，用
--   type=spell/toy/item + 对应属性交给安全系统执行；安全属性只能在非战斗锁定下写，
--   战斗中改动会挂起、脱战后自动补上。
-- 踩过的坑（点击没反应）：安全按钮「注册的点击阶段」必须和 useOnKeyDown 配对 ——
--   只 RegisterForClicks("LeftButtonUp")（抬起）而不设 useOnKeyDown，安全系统会按
--   ActionButtonUseKeyDown 的默认值（按下）判定，阶段不匹配就直接 return，点了毫无反应，
--   而且不报错。本机两个现役实现都是显式写死的：TeleportMenu = AnyDown/AnyUp + true，
--   EllesmereUIDataBars = AnyUp + false（它的注释：注册两个阶段会被 CVar 触发两次，
--   第二次按下会打断第一次的施法）。这里取「抬起 + false」这一组，左右只认左键。
-- 斜杠：/qm fly | repair | ah | passenger | set <用途> | clear <用途>
--------------------------------------------------------------------------------

local MODULE_ID = "quickmount"

-- 用途 -> 中文名
local CATS = { "fly", "repair", "ah", "passenger", "water" }
local CAT_LABEL = {
    fly = T["飞行"], repair = T["修理"], ah = T["拍卖行"], passenger = T["载人"], water = T["水下"],
}

-- Legacy name fallback only. Prefer stable spell IDs below so automatic mounts
-- work in every client language. Explicit user bindings always take priority.
local AUTO_BY_NAME = {
    repair    = { T["顶级探险家的牦牛"], T["旅行者的苔原猛犸象"] },
    ah        = { T["鎏金雷龙"] },
    passenger = { T["沙石幼龙"] },
    water     = { T["驯服的海马"] },
    -- fly 不给默认：留空 = “随机收藏坐骑”，交给游戏按环境选。
}

-- Stable default candidates. Names and icons still come from the mount journal.
local AUTO_BY_SPELL = {
    repair = { 122708, 61425, 61447 },
    ah = { 465235 },
    passenger = { 93326, 122708, 61425, 61447, 75973 },
    water = { 98718 },
}

-- 短名字数上限的默认值。故意不写进 defaults：默认值改一次就会被存档里的旧默认顶住，
-- 所以放在代码里兜底，只有用户显式调过滑块才会存进 DB。
local DEFAULT_LABEL_CHARS = ns.locale == "enUS" and 5 or 2

local defaults = {
    button = {
        enabled = true,
        scale = 1,
    },
    -- 各用途绑定的 mountID；nil = 未设（fly 用随机，其它用自动默认/提示）
    mounts = {},
    bindings = {}, -- 用途 -> 修饰键+鼠标；缺省沿用旧按键，NONE 表示不绑定
    -- 扩展按钮：技能/玩具/物品按钮，长在主坐骑按钮旁
    extra = {
        enabled = false,   -- 是否显示扩展按钮
        grow = "RIGHT",    -- 生长方向：RIGHT/LEFT/UP/DOWN（默认向右）
        text = "",         -- 每行一条的技能/玩具/物品配置（ID 或名称）
        showLabels = true, -- 按钮下方显示短名（动作名 / 名字前几个字）
        collapsed = false, -- 收起：暂时藏起那排扩展按钮，悬停主按钮显示文字控制钮
    },
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
-- 设置里允许直接填「坐骑名」或「mountID」：数字直接用；文字按名字在已收藏坐骑里查
-- （与扩展按钮那套名称匹配同一思路，省掉"必须先骑上目标坐骑才能绑定"的限制）。
local function ResolveStoredMount(v)
    if not v then return nil end
    if type(v) == "number" then return v end
    local id = tonumber(v)
    if id then return id end
    local byName = BuildOwned()
    return byName[v]
end

local function ResolveMount(cat)
    local id = ResolveStoredMount(DB().mounts[cat])
    if id then return id end

    local byName, bySpell = BuildOwned()
    local spells = AUTO_BY_SPELL[cat]
    if spells then
        for _, sid in ipairs(spells) do
            if bySpell[sid] then return bySpell[sid] end
        end
    end
    local names = AUTO_BY_NAME[cat]
    if names then
        for _, nm in ipairs(names) do
            if byName[nm] then return byName[nm] end
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

-- 坐骑组合键只作用于主按钮，不占用游戏的全局键盘绑定。
-- 所有含 Alt 的右键保留给设置；中键保留给扩展条。其余组合精确匹配。
local DEFAULT_BINDINGS = {
    fly="LEFT", repair="SHIFT-LEFT", ah="CTRL-LEFT", passenger="ALT-LEFT", water="RIGHT",
}
local BINDING_CHOICES = {{value="NONE", text=T["不绑定"]}}
local BINDING_LABEL = {NONE=T["不绑定"]}
for _, modifier in ipairs({"", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-"}) do
    for _, mouse in ipairs({"LEFT", "RIGHT"}) do
        if mouse ~= "RIGHT" or not modifier:find("ALT", 1, true) then
            local key = modifier .. mouse
            local label = modifier:gsub("ALT", "Alt"):gsub("CTRL", "Ctrl"):gsub("SHIFT", "Shift"):gsub("-", "+")
                .. (mouse == "LEFT" and T["左键"] or T["右键"])
            BINDING_CHOICES[#BINDING_CHOICES+1] = {value=key, text=label}
            BINDING_LABEL[key] = label
        end
    end
end

local function GetBindings()
    local saved = DB().bindings
    if type(saved) ~= "table" then saved = {} end
    local result, used = {}, {}
    for _, cat in ipairs(CATS) do
        local key = saved[cat]
        if not BINDING_LABEL[key] then key = DEFAULT_BINDINGS[cat] end
        if key ~= "NONE" and used[key] then key = "NONE" end
        result[cat] = key
        if key ~= "NONE" then used[key] = true end
    end
    return result
end

local function SetBinding(cat, key)
    if not CAT_LABEL[cat] or not BINDING_LABEL[key] then return end
    local bindings = GetBindings()
    local previous = bindings[cat]
    -- 选择已占用的按键就交换；不绑定允许多行同时选择。
    if key ~= "NONE" then
        for _, other in ipairs(CATS) do
            if other ~= cat and bindings[other] == key then bindings[other] = previous end
        end
    end
    bindings[cat] = key
    DB().bindings = bindings
end

local function ClickKey(mouseButton)
    local mouse = mouseButton == "LeftButton" and "LEFT" or mouseButton == "RightButton" and "RIGHT"
    if not mouse or (mouse == "RIGHT" and IsAltKeyDown()) then return nil end
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. mouse
end

local function ClickCategory(mouseButton)
    local key = ClickKey(mouseButton)
    if not key then return nil end
    local bindings = GetBindings()
    for _, cat in ipairs(CATS) do
        if bindings[cat] == key then return cat end
    end
end

local function Summon(cat)
    if InCombatLockdown() then
        ns.Print(T["快捷按钮：战斗中不能召唤坐骑。"])
        return
    end
    if not (C_MountJournal and C_MountJournal.SummonByID) then
        ns.Print(T["快捷按钮：坐骑接口不可用。"])
        return
    end

    local id = ResolveMount(cat)
    if id then
        -- 校验拥有且可用
        local name, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
        if not isCollected then
            ns.Print(T["快捷按钮："] .. (CAT_LABEL[cat] or cat) .. T["坐骑你还没收藏，请在设置中重新绑定。"])
            if cat == "fly" then C_MountJournal.SummonByID(0) end
            return
        end
        C_MountJournal.SummonByID(id)
    else
        -- 只有飞行用途可回退到随机；随机收藏并不保证满足水下等专门用途。
        if cat ~= "fly" then
            ns.Print(T["快捷按钮：未设置"] .. (CAT_LABEL[cat] or cat) .. T["坐骑（也没找到合适的默认），请在设置里指定；不会改用随机坐骑。"])
            return
        end
        C_MountJournal.SummonByID(0)
    end
end

-- 把当前正骑的坐骑设为某用途的默认。
local function CaptureCurrent(cat)
    local id = GetActiveMountID()
    if not id then
        ns.Print(T["快捷按钮：请先骑上你想设为「"] .. (CAT_LABEL[cat] or cat) .. T["」的坐骑，再来抓取。"])
        return false
    end
    DB().mounts[cat] = id
    ns.Print((T["快捷按钮：已把「%s」设为 %s 坐骑。"]):format(MountName(id) or ("#" .. id), CAT_LABEL[cat] or cat))
    return true
end

--------------------------------------------------------------------------------
-- 按钮（Core 的可拖动框工厂创建；位置/锁定存角色档）。
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 扩展按钮：技能 / 玩具 / 物品
-- 设置里每行输入一条，会在主坐骑按钮旁按选定方向长出一排同样大小的按钮
--（尺寸与主按钮一致 44x44，缩放跟随主按钮）。每行格式：
--   技能:460905              技能，按法术 ID
--   玩具:奥术秘社的私人钥匙    玩具，按名称（也可用物品 ID）
--   物品:123456              物品，按物品 ID
-- 省略前缀时：纯数字按 技能→玩具→物品 依次识别；纯名称先查玩具再查法术书（最后查背包）。
-- 生长方向：向右（默认）/ 向左 / 向上 / 向下；点击直接使用对应技能/玩具/物品。
--------------------------------------------------------------------------------

local extraEditor           -- 设置中的逐条编辑器；不参与安全按钮执行
local button                -- 主按钮（CreateButton 里创建；先声明供下方闭包使用）
local appliedCollapsed      -- last successfully applied visibility, distinct from combat requests
local pendingRebuild        -- 战斗中无法重建安全按钮时挂起的标记

local EXTRA_SIZE = 44                -- 与主按钮同尺寸
local EXTRA_GAP  = 6                 -- 与主按钮/前一个按钮之间的小间距
local GROW_ANCHORS = {
    RIGHT = { point = "LEFT",   rel = "RIGHT",   dx =  1, dy =  0 },
    LEFT  = { point = "RIGHT",  rel = "LEFT",    dx = -1, dy =  0 },
    UP    = { point = "BOTTOM", rel = "TOP",     dx =  0, dy =  1 },
    DOWN  = { point = "TOP",    rel = "BOTTOM",  dx =  0, dy = -1 },
}

-- Keep the control outside both the mount icon and the extension growth axis.
local COLLAPSE_TAB_POS = {
    RIGHT = {point="BOTTOM",rel="TOP",dx=0,dy=8},
    LEFT  = {point="BOTTOM",rel="TOP",dx=0,dy=8},
    UP    = {point="LEFT",rel="RIGHT",dx=8,dy=0},
    DOWN  = {point="LEFT",rel="RIGHT",dx=8,dy=0},
}
local KIND_LABEL = { macro = T["动作"], spell = T["技能"], toy = T["玩具"], item = T["物品"] }

-- 特殊动作：登出/退组这类是受保护动作，插件不能直接调用，统一走安全按钮的 macro 属性
-- （与本机 EllesmereUI 处理 /logout 的做法一致：它的注释写着 /logout 和 /reload 都需要
-- 经安全按钮走硬件事件）。命令取自官方宏命令表；退组没有对应宏命令，用 /run 调
-- C_PartyInfo.LeaveParty()（该 API 未被标记为 protected）。
--
-- 图标：这几个贴图名逐一验证过「存在 + 画面对得上」（用 wowhead 图标 CDN 下载后目视确认）：
--   inv_misc_rune_01        炉石（回角色选择）
--   inv_misc_groupneedmore  一队人（队伍 → 退组）
--   trade_engineering       齿轮（维护/刷新 → 重载界面）
--   spell_arcane_portalstormwind  传送门（离开 → 退出游戏）
-- 想换口味可以在动作名后加 @图标ID（法术或物品 id），例如：退组 @135824
local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
local function ActionIcon(icon, spellID)
    -- 优先用验证过的贴图；万一取不到（或用户指定了 @id）就现取，最后问号兜底，
    -- 三层都不会再有“看不见但点得着”的隐形按钮。
    if icon then return icon end
    local tex = spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    return tex or FALLBACK_ICON
end

-- @图标ID：法术 id 优先，其次物品 id（两个都取不到就用默认图标）。
local function IconOverride(id)
    if not id then return nil end
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if not tex and C_Item and C_Item.GetItemIconByID then tex = C_Item.GetItemIconByID(id) end
    return tex
end

local ACTIONS = {}
local function DefAction(names, label, macrotext, icon, short)
    local act = { label = label, macrotext = macrotext, icon = icon, short = short }
    for _, n in ipairs(names) do ACTIONS[n] = act end
end
DefAction({ "小退", "登出", "下线", "回到角色选择", "下線", "回到角色選擇", "logout" }, T["小退（回到角色选择）"], "/logout",
    [[Interface\Icons\inv_misc_rune_01]], T["小退"])
DefAction({ "退组", "离队", "离开队伍", "退組", "離隊", "離開隊伍", "leave" }, T["退组"], "/run C_PartyInfo.LeaveParty()",
    [[Interface\Icons\inv_misc_groupneedmore]], T["退组"])
DefAction({ "重载", "重载界面", "刷新界面", "重載", "重載介面", "重新載入", "重新載入介面", "reload" }, T["重载界面"], "/reload",
    [[Interface\Icons\trade_engineering]], T["重载"])
DefAction({ "退出游戏", "关闭游戏", "退出遊戲", "關閉遊戲", "quit" }, T["退出游戏"], "/quit",
    [[Interface\Icons\spell_arcane_portalstormwind]], T["退出"])

-- 特殊动作条目（kind = "macro"：安全按钮按 macrotext 执行）。
-- 图标在每次重建时现取，首次没取到、之后数据就绪了也能自己补上。
local function ResolveAction(act, iconID)
    return {
        kind = "macro",
        name = act.label,
        short = act.short,
        macrotext = act.macrotext,
        icon = IconOverride(iconID) or ActionIcon(act.icon, act.spellID),
    }
end
local PREFIX_KIND = {
    spell = "spell", ["技能"] = "spell", ["法术"] = "spell", ["法術"] = "spell",
    toy = "toy", ["玩具"] = "toy",
    item = "item", ["物品"] = "item",
}

-- GetToyFromIndex only enumerates the current filtered Toy Box view. Never
-- clear the user's search/filters just to resolve a shortcut. Keep successful
-- names for this session and use item-cache lookup before the filtered scan.
local toyNameIDs, toyDataRequests = {}, {}
-- Verified item ID; also resolves our built-in example on a cold name cache.
local knownToyNames = { ["奥术秘社的私人钥匙"] = 253629, [T["奥术秘社的私人钥匙"]] = 253629 }
local function ToyInfo(id)
    if not (id and C_ToyBox and C_ToyBox.GetToyInfo) then return nil end
    local _, name, icon = C_ToyBox.GetToyInfo(id)
    if name then toyNameIDs[name] = id end
    return name, icon
end
local function RequestToyData(id)
    if toyDataRequests[id] == nil and C_Item and C_Item.RequestLoadItemDataByID then
        toyDataRequests[id] = true -- set before requesting; completion may be immediate
        C_Item.RequestLoadItemDataByID(id)
    end
end
local function FindToyByName(name)
    if not (C_ToyBox and C_ToyBox.GetToyInfo) then return nil end
    local id = knownToyNames[name] or toyNameIDs[name]
    if id then return id end
    if C_Item and C_Item.GetItemInfoInstant then
        id = C_Item.GetItemInfoInstant(name)
        -- Item cache hits can be ordinary items: only accept confirmed toys.
        if id and ToyInfo(id) == name then return id end
    end
    local count = C_ToyBox.GetNumFilteredToys or C_ToyBox.GetNumToys
    if not (count and C_ToyBox.GetToyFromIndex) then return nil end
    for i = 1, count() do
        id = C_ToyBox.GetToyFromIndex(i)
        if id and ToyInfo(id) == name then return id end
    end
end

-- 名称 -> 玩家已学法术ID（扫法术书）。
-- 12.x 正确遍历方式：每行技能用 itemIndexOffset 起索引，GetSpellBookItemType 拿 spellID。
local function FindSpellByName(name)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return nil end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide and info.itemIndexOffset and info.numSpellBookItems then
            for si = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local _, _, sid = C_SpellBook.GetSpellBookItemType(si, bank)
                if sid and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) == name then
                    return sid
                end
            end
        end
    end
end

-- 名称 -> 背包物品ID。
-- 12.x 里容器相关函数在 C_Container 命名空间（C_Item 上没有），老的全局函数也已移除，
-- 所以按 C_Container → 全局 依次探测，拿不到就返回 nil（设置里会显示“未识别”）。
local function FindBagItemByName(name)
    local getInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not (getInfo and getSlots) then return nil end
    for bag = 0, 4 do
        local slots = getSlots(bag) or 0
        for slot = 1, slots do
            local info = getInfo(bag, slot)
            if info and info.itemID then
                local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)
                if n == name then return info.itemID end
            end
        end
    end
end

-- 玩具的“使用法术 ID” -> 玩具物品 ID。
-- 网上流传的玩具 ID 常常是 wowhead 法术页上的“使用法术 ID”（例如
-- 战团银行距离抑制器 = 法术 460905，玩具物品 ID 是 216665），按法术施放是用不了的；
-- 这里用法术名去玩具箱里找同名玩具，找到就改按玩具处理，保证点击真的能用。
local function ToyBySpellID(id)
    if not id then return nil end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name then return nil end
    return FindToyByName(name)
end

-- 按类型 + ID 解析出一条可用条目（拿不到名字/图标视为无效）。
local function ResolveById(kind, id)
    if not id then return nil end
    if kind == "spell" then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if name or icon then return { kind = "spell", id = id, name = name, icon = icon } end
    elseif kind == "toy" then
        if C_ToyBox and C_ToyBox.GetToyInfo then
            local name, icon = ToyInfo(id)
            if not name then
                RequestToyData(id)
                name, icon = ToyInfo(id) -- a cached request can complete synchronously
            end
            if name or icon then return { kind = "toy", id = id, name = name, icon = icon } end
        end
    else
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        if name or icon then return { kind = "item", id = id, name = name, icon = icon } end
    end
    return nil
end

-- 数字 ID 的解析顺序：同名玩具 → 技能 → 玩具 → 物品。
local function ResolveNumberId(id)
    local tid = ToyBySpellID(id)
    if tid then
        local toy = ResolveById("toy", tid)
        if toy then return toy end
    end
    return ResolveById("spell", id)
        or ResolveById("toy", id)
        or ResolveById("item", id)
end

-- 按钮下方的短标签：按 UTF-8 字符截断（中文一个字 3 字节，不能直接 string.sub）。
-- 截断后不加省略号 —— 保持标签干净，长度也完全可预期（2 个字就是 2 个字）。
local function TruncateChars(s, maxChars)
    if not s or s == "" then return "" end
    local out, n, i = {}, 0, 1
    while i <= #s do
        local b = s:byte(i)
        local len = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
        if n >= maxChars then return table.concat(out) end
        out[#out + 1] = s:sub(i, i + len - 1)
        n = n + 1
        i = i + len
    end
    return table.concat(out)
end

-- 条目 -> 按钮下的短名。
-- 字数上限可在设置里调（默认 2 个字：中文字宽 ≈ 字号，2 个字在「按钮 44 + 间距 6 = 50px」
-- 的槽里余量充足，不会和邻居挤在一起）。截断后不加省略号。
-- 想写别的也简单：行尾加 #短名，例如「玩具:216665 #银行」。
local function ShortLabel(e)
    if e.short then return e.short end
    local name = (e.name or ""):gsub("（.-）", ""):gsub("%(.*%)", "")
    local maxChars = tonumber(DB().extra.labelChars) or DEFAULT_LABEL_CHARS
    return TruncateChars(name, maxChars)
end

-- 解析「动作名 [@图标ID]」：返回 action, iconID（@ 后面的 id 用来换图标）。
local function ParseActionToken(text)
    if not text then return nil end
    local name, id = text:match("^(.-)%s*@%s*(%d+)%s*$")
    if name then
        return ACTIONS[(name:gsub("^%s+", ""):gsub("%s+$", ""))], tonumber(id)
    end
    return ACTIONS[text]
end

-- 解析单行配置本体（不含 #短名 的处理）。
local function ParseExtraLineCore(line)
    line = (line:gsub("^%s+", ""):gsub("%s+$", ""))
    if line == "" or line:sub(1, 2) == "--" then return nil end

    -- 带“前缀:值”的行
    -- Lua patterns are byte-based: a character class containing ： splits its
    -- UTF-8 bytes and can corrupt both the separator and Chinese prefixes.
    local prefix, value = line:match("^([^:]+):%s*(.+)$")
    if not prefix then prefix, value = line:match("^(.-)：%s*(.+)$") end
    if prefix and value then
        local pkey = (prefix:gsub("^%s+", ""):gsub("%s+$", "")):lower()
        -- 动作前缀：动作:小退 / action:小退 / 命令:退组
        if pkey == "动作" or pkey == "動作" or pkey == "action" or pkey == "命令" or pkey == "cmd" then
            local act, iconID = ParseActionToken(value)
            return act and ResolveAction(act, iconID)
        end
        local kind = PREFIX_KIND[pkey] or PREFIX_KIND[prefix]
        if kind then
            local id = tonumber(value)
            if id then
                -- 玩具/技能写数字时都允许“使用法术 ID”，交给 ResolveNumberId 兜底
                if kind == "item" then return ResolveById("item", id) end
                if kind == "toy" then
                    -- 玩具：先当玩具物品 ID，再兜底“使用法术 ID”
                    return ResolveById("toy", id) or ResolveNumberId(id)
                end
                -- 技能：法术 ID 优先，但同名玩具（玩具的使用法术 ID）会被识别成玩具
                return ResolveNumberId(id) or ResolveById("spell", id)
            elseif kind == "toy" then
                local tid = FindToyByName(value)
                return tid and ResolveById("toy", tid)
            elseif kind == "spell" then
                local sid = FindSpellByName(value)
                return sid and ResolveById("spell", sid)
            else
                local iid = FindBagItemByName(value)
                return iid and ResolveById("item", iid)
            end
        end
    end

    -- 无前缀：先看是不是特殊动作名（小退 / 退组 / 重载界面 …，可带 @图标ID）
    local act, iconID = ParseActionToken(line)
    if act then return ResolveAction(act, iconID) end

    -- 纯数字按 技能→玩具→物品 依次识别（同名玩具优先）
    local num = tonumber(line)
    if num then return ResolveNumberId(num) end
    -- 纯名称：先玩具再法术书，最后背包物品
    local tid = FindToyByName(line)
    if tid then return ResolveById("toy", tid) end
    local sid = FindSpellByName(line)
    if sid then return ResolveById("spell", sid) end
    local iid = FindBagItemByName(line)
    if iid then return ResolveById("item", iid) end
    return nil
end

-- 解析单行配置 -> entry {kind, id, name, icon, short} 或 nil。
-- 行尾的 #短名 只改按钮下方显示的短标签，不参与技能/玩具/物品的解析：
--   玩具:216665 #银行    → 按钮下面显示「银行」
--   退组 #退队
-- （不带 #短名 时按设置里的「短名字数上限」自动截断，默认 3 个字。）
local function ParseExtraLine(line)
    local short
    local body, tail = line:match("^(.-)%s*#(%S+)%s*$")
    if body and body ~= "" then line, short = body, tail end
    local entry = ParseExtraLineCore(line)
    if entry and short then entry.short = short end
    return entry
end

-- 逐条遍历配置行：跳过空行、纯空格行与 -- 注释行（注释只是给人看的，不该算“未识别”）。
local function EachExtraLine(text)
    local lines = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        if not line:match("^%s*%-%-") then
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then lines[#lines + 1] = trimmed end
        end
    end
    return lines
end

-- 统计一段配置能解析出几条、各类型几条（设置页显示状态用）。
local function CountExtra(text)
    local ok, fail, byKind = 0, 0, {}
    for _, line in ipairs(EachExtraLine(text)) do
        local good, entry = pcall(ParseExtraLine, line)
        if good and entry then
            ok = ok + 1
            byKind[entry.kind] = (byKind[entry.kind] or 0) + 1
        else
            fail = fail + 1
        end
    end
    return ok, fail, byKind
end

-- 把条目写成安全按钮属性，真正施法/使用由安全系统执行。
-- 直接调 CastSpellByID / UseToy / UseItemByName / CastSpellByName 都是受保护动作，
-- 插件调用必被拒绝（这正是主按钮召唤坐骑要 C_MountJournal.SummonByID 而非施法的原因）。
-- 属性格式依据 SecureActionButtonTemplate：
--   type="spell" + spell=<数字 spellID>  -> CastSpellByID
--   type="toy"   + toy=<玩具物品ID>      -> UseToy
--   type="item"  + item="item:<物品ID>"  -> SecureCmdItemParse（与宏 /use item:ID 同源）
local function ApplySecureAttrs(b, entry)
    b:SetAttribute("unit", "player")
    if entry.kind == "spell" then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", entry.id)
        b:SetAttribute("toy", nil)
        b:SetAttribute("item", nil)
    elseif entry.kind == "toy" then
        b:SetAttribute("type", "toy")
        b:SetAttribute("toy", entry.id)
        b:SetAttribute("spell", nil)
        b:SetAttribute("item", nil)
    elseif entry.kind == "macro" then
        -- 特殊动作（小退/退组/重载…）：受保护动作交给安全系统按下时执行
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", entry.macrotext)
        b:SetAttribute("spell", nil)
        b:SetAttribute("toy", nil)
        b:SetAttribute("item", nil)
    else
        b:SetAttribute("type", "item")
        b:SetAttribute("item", "item:" .. tostring(entry.id))
        b:SetAttribute("spell", nil)
        b:SetAttribute("toy", nil)
    end
end

-- 12.x 起部分 API 会返回 secret value（读取/算术会抛错），跨版本用存在性探测兜底。
local issecretvalue = issecretvalue or function() return false end

-- 复制一个条目的冷却。12.x 在副本/大秘境等受限场合会把冷却值变成“秘密值”：
-- plugin 读数会被拒，直接 SetCooldown(start, dur) 也会抛
-- “Secret values are only allowed during untainted execution”。
--
-- 所以这里的原则是【绝不把秘密值交给 SetCooldown】：
--   法术 —— 优先走 DurationObject 通道（GetSpellCooldownDuration 返回的对象
--           由引擎自己解析，插件全程不碰数值），Decursive / EllesmereUI 同款；
--           对象 API 不可用时退回数值通道，但先判秘密再比较。
--   物品/玩具 —— 没有稳定的对象 API；若引擎将来提供就优先用，否则只有非秘密
--           环境才画，秘密环境下宁可不显示，也不报错。
local GetItemCooldownFn = (C_Container and C_Container.GetItemCooldown)
    or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown

local function ReadCooldownActive(info) return info.isActive end

-- Cache only our successful public UI writes, never cooldown API results.
-- The engine animates numeric cooldowns; unchanged inputs need no setter call.
local function ClearExtraCooldown(cd)
    if cd._bmCooldownClear then return end
    cd:Clear()
    cd._bmCooldownClear = true
    cd._bmCooldownStart, cd._bmCooldownDuration = nil, nil
end

local function SetExtraNumericCooldown(cd, start, duration)
    if cd._bmCooldownStart == start and cd._bmCooldownDuration == duration then return end
    cd._bmCooldownClear = nil
    cd._bmCooldownStart, cd._bmCooldownDuration = nil, nil
    if pcall(cd.SetCooldown, cd, start, duration) then
        cd._bmCooldownStart, cd._bmCooldownDuration = start, duration
    end
end

local function SetExtraDurationObject(cd, object)
    -- Opaque objects may change internally: never compare or retain them.
    cd._bmCooldownClear = nil
    cd._bmCooldownStart, cd._bmCooldownDuration = nil, nil
    return pcall(cd.SetCooldownFromDurationObject, cd, object)
end

local function PaintCooldown(cd, e)
    if not cd then return end

    if e.kind == "spell" then
        local info
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, v = pcall(C_Spell.GetSpellCooldown, e.id)
            if ok and type(v) == "table" then info = v end
        end
        -- isActive 是 NeverSecret：能读到、且明确是 false，就说明确实不在冷却，直接清掉。
        -- 注意判断顺序：先 issecretvalue 再比 nil / 比 false，秘密值一旦参与比较就抛错。
        if info then
            local ok, ia = pcall(ReadCooldownActive, info)
            if ok and not issecretvalue(ia) and ia ~= nil and ia == false then
                ClearExtraCooldown(cd)
                return
            end
        end

        -- 首选：DurationObject（秘密环境下唯一可行的通道）
        if C_Spell and C_Spell.GetSpellCooldownDuration then
            local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, e.id)
            if ok and durObj then
                if SetExtraDurationObject(cd, durObj) then return end
            end
        end
        -- 退回：数值通道，先判秘密再比较（对秘密值做 > 会直接抛错）
        if info then
            local s, d = info.startTime, info.duration
            if not issecretvalue(s) and not issecretvalue(d) and d and d > 1.5 then
                SetExtraNumericCooldown(cd, s or 0, d)
                return
            end
        end

    elseif e.kind == "toy" or e.kind == "item" then
        -- 引擎若提供物品冷却的 DurationObject，优先走它（跨版本防御性探测）
        local durFn = (C_Container and C_Container.GetItemCooldownDuration)
            or (C_Item and C_Item.GetItemCooldownDuration)
        if durFn then
            local ok, durObj = pcall(durFn, e.id)
            if ok and durObj then
                if SetExtraDurationObject(cd, durObj) then return end
            end
        end
        if GetItemCooldownFn then
            local ok, s, d = pcall(GetItemCooldownFn, e.id)
            if ok and not issecretvalue(s) and not issecretvalue(d) and s and d and d > 1.5 then
                SetExtraNumericCooldown(cd, s, d)
                return
            end
        end
    end

    ClearExtraCooldown(cd)
end

-- 安全按钮池：按钮只建一次（安全属性战斗中不能写、重建代价高），多余的隐藏备用。
local extraButtons = {}

-- Diagnostic dispatch only: no extra timer and no changes to secure handlers.
ns.IdleTasks = ns.IdleTasks or {}
local cooldownTask = {run=PaintCooldown, profileRefresh=true}
ns.IdleTasks.QuickCooldown = cooldownTask

-- One non-secure timer owns refresh cadence. Secure action buttons have no
-- per-frame cooldown handlers; keep the existing reads/secret-value policy.
local function StopExtraCooldowns()
    if cooldownTask.timer then
        cooldownTask.timer:Cancel()
        cooldownTask.timer = nil
    end
end

local function NeedsExtraCooldown(b)
    return b._entry and b._entry.kind ~= "macro" and b:IsVisible()
end

local function RefreshExtraCooldowns()
    if not ns.IsModuleEnabled(MODULE_ID) then StopExtraCooldowns(); return end
    local any = false
    for _, b in ipairs(extraButtons) do
        if NeedsExtraCooldown(b) then
            any = true
            cooldownTask.run(b.cd, b._entry)
        end
    end
    if not any then StopExtraCooldowns() end
end

local function SyncExtraCooldowns()
    if ns.IsModuleEnabled(MODULE_ID) then
        for _, b in ipairs(extraButtons) do
            if NeedsExtraCooldown(b) then
                if not cooldownTask.timer then
                    cooldownTask.timer = C_Timer.NewTicker(0.25, RefreshExtraCooldowns)
                end
                return
            end
        end
    end
    StopExtraCooldowns()
end

local function EnsureExtraButton(index)
    local b = extraButtons[index]
    if b then return b end

    -- 挂在 UIParent 而不是主按钮下：安全模板会把「自己 + 所有父框」变成受保护框，
    -- 挂在主按钮下会让主按钮也变受保护（战斗中拖动/缩放会被拒），所以改同级 + 锚点跟随。
    b = CreateFrame("Button", "BaimiaoQuickMountExtra" .. index, UIParent, "SecureActionButtonTemplate")
    b:SetSize(EXTRA_SIZE, EXTRA_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:EnableMouse(true)
    -- 点击阶段与 useOnKeyDown 必须配对，否则点了没反应（见文件头注释）
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown", false)

    -- 图标铺满整格 + 同样的边缘裁切：视觉尺寸与主按钮一致（之前内缩 3px 看着更小）
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    -- 悬停高亮：与 EllesmereUIDataBars 的行按钮同款（白色 10% 叠加），不加边框所以不会显得更小
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.10)

    -- 按钮下方短名（设置里可关）：按钮多了以后不用悬停也能分辨
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.RegisterRuntimeFont(label)
    label:SetPoint("TOP", b, "BOTTOM", 0, -2)
    label:SetJustifyH("CENTER")
    label:SetTextColor(0.95, 0.95, 0.95)
    b.label = label

    -- 冷却圈
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawBling(false)
    ns.UI.RegisterRuntimeCooldown(cd)
    b.cd = cd

    -- 悬停提示（读 b._entry：池里的按钮会复用给不同条目）
    b:SetScript("OnEnter", function(self)
        local e = self._entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        if e.kind == "macro" then
            GameTooltip:SetText(e.name, 1, 1, 1)
            GameTooltip:AddLine(e.macrotext, 0.6, 0.9, 1, true)
        elseif e.kind == "spell" then
            GameTooltip:SetSpellByID(e.id)
        elseif e.kind == "toy" then
            GameTooltip:SetToyByItemID(e.id)
        else
            GameTooltip:SetItemByID(e.id)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 注意：这里绝不能 SetScript("OnClick", ...)。安全模板正是靠它自己的 OnClick
    -- 执行受保护动作，覆盖掉按钮就点不动了。
    --
    -- 但可以 HookScript —— 钩子跑在安全执行之后，不会顶掉它。用来把"环境不允许"
    -- 讲清楚，免得用户以为按钮坏了（例如单人时点退组：游戏什么都不会做）。
    b:HookScript("OnClick", function(self)
        local e = self._entry
        if not e or e.kind ~= "macro" then return end
        if e.macrotext:find("LeaveParty", 1, true) and not IsInGroup() then
            ns.Print(T["退组：当前没有队伍。"])
        end
    end)


    extraButtons[index] = b
    -- Observe visibility only; never replace secure OnClick or action attributes.
    b:HookScript("OnShow", SyncExtraCooldowns)
    b:HookScript("OnHide", SyncExtraCooldowns)
    return b
end

-- 把多行说明 / 诊断显示成提示框 —— 设置里点点看就行，不往聊天频道刷字
-- （只有用户自己敲 /qm check、/qm help 时才打印到聊天框）。
local function ShowLinesTooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 1, 1, 1, true)   -- wrap = true，长行自动折
    end
    GameTooltip:Show()
end

-- 悬停即显示（点击也显示，避免"点一下没反应"的错觉）
local function AttachLinesTooltip(frame, title, linesFn)
    local function show(self) ShowLinesTooltip(self, title, linesFn()) end
    frame:SetScript("OnEnter", show)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnClick", show)
end

-- 只加悬停（按钮的点击行为另有用途时用这个，不会顶掉 OnClick）
local function AttachHoverTooltip(frame, title, linesFn)
    frame:SetScript("OnEnter", function(self) ShowLinesTooltip(self, title, linesFn()) end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- 扩展按钮的完整说明：页面只留一行提示，细节放在输入框/按钮的悬停提示里（避免撑开设置页）。
local EXTRA_HELP = {
    T["扩展按钮 —— 完整说明（每行一条，-- 开头是注释、空行忽略；设置改动立刻生效）："],
    T["  技能:460905  或  技能:炉石        施法（空格/全角冒号都认）"],
    T["  玩具:253629  或  玩具:奥术秘社的私人钥匙    用玩具（这把钥匙不受玩具箱筛选影响）"],
    T["  其他玩具优先用物品 ID；未缓存的名称若被玩具箱筛选隐藏，可先清除筛选让它识别一次"],
    T["  物品:123456                      用背包里的物品"],
    T["  小退 / 退组 / 重载界面 / 退出游戏     受保护动作，走安全按钮执行（也可写“动作:小退”）"],
    T["  退组 @135824                     @ 后面跟法术或物品 id，换这个按钮的图标"],
    T["  玩具:216665 #银行                 行尾 #短名 = 按钮下面显示这几个字（不给就自动截断）"],
    T["  省略前缀：纯数字按 技能→玩具→物品 依次识别；纯名称先查玩具再查法术书（最后查背包）"],
    T["  找不到名字就改用 ID。网上的玩具 ID 常是它的“使用法术 ID”（战团银行距离抑制器＝法术 460905、"],
    T["  玩具物品 216665），这种会按同名玩具自动识别，包在身上也不会点不动。"],
    T["  逐行确认认成了什么：设置里点「检查配置」，或输入 /qm check。"],
}
local function PrintExtraHelp()
    for _, line in ipairs(EXTRA_HELP) do ns.Print(line) end
end

-- 逐行体检扩展按钮配置：返回每行的解析结果（供悬停提示 / `/qm check` 共用）。
local function ExtraCheckLines()
    local cfg = DB().extra
    local lines = EachExtraLine(cfg.text)
    local out = {}
    if #lines == 0 then
        out[#out + 1] = T["配置是空的（设置里每行填一条技能/玩具/物品/动作）。"]
        return out
    end
    out[#out + 1] = (T["共 %d 行 ——"]):format(#lines)
    for i, line in ipairs(lines) do
        local ok, entry = pcall(ParseExtraLine, line)
        if ok and entry then
            local what = KIND_LABEL[entry.kind] or entry.kind
            local id = entry.id and (" #" .. entry.id) or ""
            out[#out + 1] = ("%d) %s → %s%s %s"):format(i, line, what, id, entry.name or "")
        else
            out[#out + 1] = (T["|cffff6060%d) %s → 未识别|r：名称要与已收集的玩具 / 已学法术 / 背包物品"] ..
                T["完全一致，或改用 ID；动作可填 小退/退组/重载界面/退出游戏"]):format(i, line)
        end
    end
    if not ns.IsModuleEnabled(MODULE_ID) then
        out[#out + 1] = T["提示：本模块被总开关关掉了，按钮不会显示。"]
    elseif not cfg.enabled then
        out[#out + 1] = T["提示：扩展开关当前是关闭的，按钮不会显示。"]
    end
    return out
end

-- 命令 /qm check：把体检结果打到聊天框（用户主动敲的，才输出）。
local function CheckExtraConfig()
    ns.Print(T["扩展按钮 · 检查配置"])
    for _, line in ipairs(ExtraCheckLines()) do ns.Print("  " .. line) end
end

-- The external text control shows the next action or an explicit pending request.
-- Visibility changes to secure extension buttons are deferred until combat ends.
local function UpdateCollapseTab()
    local tab = button and button.collapseTab
    if not tab then return end
    local cfg = DB().extra
    local ok = select(1, CountExtra(cfg.text))   -- 已识别条目数
    local canShow = ns.IsModuleEnabled(MODULE_ID) and DB().button.enabled
        and cfg.enabled and ok > 0
    if not canShow then tab:Hide() return end

    local grow = cfg.grow or "RIGHT"
    local collapsed = cfg.collapsed and true or false
    local pos = COLLAPSE_TAB_POS[grow] or COLLAPSE_TAB_POS.RIGHT
    tab:ClearAllPoints()
    tab:SetPoint(pos.point, button, pos.rel, pos.dx, pos.dy)
    local pending=InCombatLockdown() and appliedCollapsed~=nil and collapsed~=appliedCollapsed
    tab:SetText(pending and (collapsed and T["待收起"] or T["待展开"]) or ((collapsed and T["展开 "] or T["收起 "])..ok))
    tab.pending=pending
    tab:SetShown(tab.hoverActive == true)
    if GameTooltip:IsOwned(tab) and GameTooltip:IsShown() then tab:GetScript("OnEnter")(tab) end
end

-- 按当前配置重建扩展按钮，返回（成功数, 未识别数）。
-- 安全属性只能在非战斗锁定状态下写：战斗中先挂起，脱战（PLAYER_REGEN_ENABLED）自动补上。
local function RebuildExtraButtons()
    if not button then return 0, 0 end
    if InCombatLockdown() then
        pendingRebuild = true
        return 0, 0
    end
    pendingRebuild = nil
    appliedCollapsed=DB().extra.collapsed and true or false

    local cfg = DB().extra
    -- 主按钮关掉 / 模块关掉 / 扩展开关关掉 / 手动收起，四种情况都不显示那排按钮
    local shown = ns.IsModuleEnabled(MODULE_ID) and DB().button.enabled
        and cfg.enabled and not cfg.collapsed
    local entries, fail = {}, 0
    for _, line in ipairs(EachExtraLine(cfg.text)) do
        local good, entry = pcall(ParseExtraLine, line)
        if good and entry then
            entries[#entries + 1] = entry
        else
            fail = fail + 1
        end
    end

    local scale = DB().button.scale or 1
    local anchor = GROW_ANCHORS[cfg.grow or "RIGHT"] or GROW_ANCHORS.RIGHT
    -- 逐格串起来锚定（第 1 个锚主按钮、第 2 个锚第 1 个…）：
    -- 锚点已经是「前一个的边」，所以偏移只能是那点间距本身；早先写成 i*(44+6) 让
    -- 第 1 个按钮离主按钮整整远了 50px（看着没挨着）。串起来还有个好处：主按钮被
    -- 拖动时后续按钮自动跟随，且与缩放无关（不需要在偏移里做尺寸换算）。
    local gap = EXTRA_GAP * scale
    local prev = button
    for i, entry in ipairs(entries) do
        local b = EnsureExtraButton(i)
        ApplySecureAttrs(b, entry)
        b._entry = entry
        -- An entry may have changed kind while reusing a secure button.
        ClearExtraCooldown(b.cd)
        b.icon:SetTexture(entry.icon)
        b.label:SetText(ShortLabel(entry))
        b:ClearAllPoints()
        b:SetPoint(anchor.point, prev, anchor.rel, anchor.dx * gap, anchor.dy * gap)
        b:SetScale(scale)      -- 挂在 UIParent 上不会继承主按钮缩放，这里手动同步
        b:SetFrameLevel(button:GetFrameLevel() + i)
        b:SetShown(shown)
        b.label:SetShown(shown and cfg.showLabels ~= false)
        prev = b
    end
    -- 多余的池按钮收起备用（不清属性，下次重建会重新写）
    for i = #entries + 1, #extraButtons do
        local b = extraButtons[i]
        b:Hide()
        b.label:Hide()
        b._entry = nil
    end
    SyncExtraCooldowns()
    UpdateCollapseTab()   -- 条目数 / 生长方向 / 收起状态可能都变了，同步一下开关
    return #entries, fail
end

-- 收起所有扩展按钮（模块被总开关关掉时用）。战斗中不动安全框，等脱战重建时处理。
local function HideExtraButtons()
    StopExtraCooldowns()
    if button and button.collapseTab then button.collapseTab:Hide() end
    if InCombatLockdown() then
        pendingRebuild = true
        return
    end
    for _, b in ipairs(extraButtons) do
        b:Hide()
        b._entry = nil
    end
end

-- Save the requested state and rebuild when safe; keep the settings checkbox in sync.
local function SetCollapsed(v)
    DB().extra.collapsed = v and true or false
    RebuildExtraButtons()   -- 非战斗：立即显隐；战斗：挂起，脱战自动补
    UpdateCollapseTab()
    local m=ns.modules[MODULE_ID]
    if m and m._syncLayout then m._syncLayout:SyncAll() end
end

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

-- 事件注册/注销成对：模块被总开关关掉后就不再收事件（否则每次按修饰键、上下马都要白跑一遍）。
local function SetupButtonEvents()
    if not button then return end
    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    button:RegisterEvent("NEW_MOUNT_ADDED")       -- 新坐骑入收藏：重建缓存
    button:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")  -- 上/下马：刷新激活缓存
    button:RegisterEvent("TOYS_UPDATED")          -- 玩具变动：扩展按钮重新解析
    button:RegisterEvent("ITEM_DATA_LOAD_RESULT") -- 仅重试本模块请求过的玩具数据
    button:RegisterEvent("SPELLS_CHANGED")        -- 技能变动：扩展按钮重新解析
    button:RegisterEvent("PLAYER_ENTERING_WORLD") -- 登录切换：数据就绪后重试解析
    button:RegisterEvent("PLAYER_REGEN_ENABLED")  -- 脱战：补上战斗中挂起的扩展按钮重建
    button:SetScript("OnEvent", function(self, event, itemID)
        if event == "ITEM_DATA_LOAD_RESULT" then
            if toyDataRequests[itemID] == true then
                toyDataRequests[itemID] = false -- no repeated requests on failure
                RebuildExtraButtons() -- retains the existing combat deferral
            else
                return
            end
        elseif event == "MODIFIER_STATE_CHANGED" then
            self:RefreshIcon()
        elseif event == "NEW_MOUNT_ADDED" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            ownedCache = nil                      -- 失效缓存，下次用的时候重建
            self:RefreshIcon()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingRebuild then RebuildExtraButtons() end
        else
            RebuildExtraButtons()                 -- 玩具/技能数据就绪或变动：重建扩展按钮
        end
        if event ~= "MODIFIER_STATE_CHANGED" and extraEditor and extraEditor:IsVisible() then
            extraEditor:Sync()
        end
    end)
end

local function TeardownButtonEvents()
    StopExtraCooldowns()
    if button then button:UnregisterAllEvents() end
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
        onRightClick = function()
            if IsAltKeyDown() then
                ns.OpenOptions(MODULE_ID)
            else
                local cat = ClickCategory("RightButton")
                if cat then Summon(cat) end
            end
        end,
    })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    function button:RefreshTooltip()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T["快捷按钮"], 1, 1, 1)
        local bindings = GetBindings()
        for _, cat in ipairs(CATS) do
            local key = bindings[cat]
            GameTooltip:AddLine(CAT_LABEL[cat] .. "：" .. BINDING_LABEL[key], 0.85, 0.85, 0.85, true)
        end
        GameTooltip:AddLine(T["Alt+右键：打开设置（/qm）"], 1, 0.82, 0, true)
        GameTooltip:AddLine(T["中键：展开/收起扩展按钮；悬停也可显示控制钮"], 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(T["解锁可拖动；锁定时 Alt/Ctrl+左键拖动"], 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end
    button:SetScript("OnEnter", function(self) self:RefreshTooltip() end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 优先预览当前修饰键的左键用途，其次右键；未绑定时显示通用图标。
    function button:RefreshIcon()
        local cat = ClickCategory("LeftButton") or ClickCategory("RightButton")
        self.icon:SetTexture(cat and CategoryIcon(cat) or "Interface\\ICONS\\Ability_Mount_RidingHorse")
        if GameTooltip:IsOwned(self) then self:RefreshTooltip() end
    end

    button:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton=="MiddleButton" then
            if DB().extra.enabled then SetCollapsed(not DB().extra.collapsed) end
            return
        end
        if mouseButton ~= "LeftButton" then return end  -- 右键统一交给工厂处理
        local cat = ClickCategory(mouseButton)
        if cat then Summon(cat) end
    end)

    -- Non-secure request control. Protected extensions still wait for combat end.
    local tab = CreateFrame("Button", "BaimiaoQuickMountCollapse", button,"UIPanelButtonTemplate")
    tab:SetSize(80,26)
    tab:SetFrameLevel(button:GetFrameLevel()+20)
    tab:EnableMouse(true);tab:RegisterForClicks("LeftButtonUp")
    ns.UI.SkinTextButton(tab)
    ns.UI.RegisterRuntimeFont(tab:GetFontString())
    tab:SetScript("OnClick", function(self) SetCollapsed(not DB().extra.collapsed); if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end end)
    tab:SetScript("OnEnter", function(self)
        self.hoverActive=true; self.hideRemaining=nil
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.pending then
            GameTooltip:SetText(DB().extra.collapsed and T["等待脱战后收起"] or T["等待脱战后展开"])
            GameTooltip:AddLine(T["战斗中不能改变安全按钮的显示。再次点击可取消本次等待。"],1,0.8,0.3,true)
        else
            GameTooltip:SetText(DB().extra.collapsed and T["展开扩展按钮"] or T["收起扩展按钮"],1,1,1)
            GameTooltip:AddLine(T["中键点击主坐骑图标也可切换；不会召唤坐骑。"],1,1,1,true)
        end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function(self)
        self.hideRemaining=0.45
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    tab:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    tab:Hide()
    button.collapseTab = tab
    -- Keep the control reachable across the gap; never hide secure extensions here.
    tab:SetScript("OnUpdate", function(self, elapsed)
        if not self.hideRemaining then return end
        self.hideRemaining=self.hideRemaining-elapsed
        if self.hideRemaining<=0 then
            self.hideRemaining=nil; self.hoverActive=false; self:Hide()
        end
    end)
    button:HookScript("OnEnter", function()
        tab.hoverActive=true; tab.hideRemaining=nil
        UpdateCollapseTab()
    end)
    button:HookScript("OnLeave", function() tab.hideRemaining=0.45 end)
    button:HookScript("OnHide", function()
        tab.hoverActive=false; tab.hideRemaining=nil; tab:Hide()
    end)

    -- 修饰键按下/松开时刷新图标，让按钮实时反映将要召唤的坐骑。
    -- 事件在 SetupButtonEvents() 里注册（OnEnable 调用；OnDisable 会全部摘掉）。
    return button
end

local function Refresh()
    if not button then return end
    button:ApplyPosition()
    button:ApplyLockVisual()
    UpdateButton()
    RebuildExtraButtons()
    if extraEditor then extraEditor:Sync() end
end

--------------------------------------------------------------------------------
-- 设置面板
--------------------------------------------------------------------------------

-- 自检：把设置页里几个关键控件的字体/阴影/行距/文本打出来 —— 用来查
-- "到底哪两行字叠在一起"（比如某个控件上挂了两个 FontString）。
-- 用法：/qm diag（打开过设置页之后再跑，才拿得到控件）
local diagWidgets = {}
local function DiagWidgets()
    ns.Print(T["快捷按钮 · 控件自检"])
    local function dumpWidget(f, label)
        if not f then
            ns.Print((T["  %s：没拿到（先打开一次本模块的设置页再跑）"]):format(label))
            return
        end
        local n = 0
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                n = n + 1
                local path, size, flags = r:GetFont()
                local sx, sy
                if r.GetShadowOffset then sx, sy = r:GetShadowOffset() end
                local sp = r.GetSpacing and r:GetSpacing() or "?"
                ns.Print((T["  %s #%d 文本=[%s]"]):format(label, n, tostring(r:GetText())))
                ns.Print((T["      字体=%s 字号=%s 标记=[%s] 阴影=%s,%s 行距=%s"]):format(
                    tostring(path), tostring(size), tostring(flags),
                    tostring(sx), tostring(sy), tostring(sp)))
            end
        end
        ns.Print((T["  %s：FontString 共 %d 个（>1 且文本相同 = 字被画了两遍）"]):format(label, n))
    end
    dumpWidget(diagWidgets.checkBtn, T["按钮·检查配置"])
    dumpWidget(diagWidgets.helpBtn, T["按钮·详细说明"])
    dumpWidget(diagWidgets.cfgBox, T["扩展配置首行输入框"])
    local p, s, fl = GameFontNormal:GetFont()
    ns.Print((T["  参照：GameFontNormal = %s / %s / [%s]"]):format(tostring(p), tostring(s), tostring(fl)))
end

-- 设置只负责拆分/编辑，运行时仍读取 extra.text：不更换存档结构、不改安全执行链。
-- 未修改的行保留原文（含未知前缀、注释、#短名、@图标及换行风格）。
local function TrimExtra(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end
local EDIT_KINDS = {
    {value="auto",text=T["自动识别"]}, {value="toy",text=T["玩具"]}, {value="spell",text=T["技能"]},
    {value="item",text=T["物品"]}, {value="action",text=T["快捷动作"]}, {value="comment",text=T["注释"]},
}
local EDIT_PREFIX = {toy=T["玩具:"], spell=T["技能:"], item=T["物品:"], action=T["动作:"]}
local ROW_HELP = {
    T["点「新增一行」，先选类型，再填名称或 ID；快捷动作直接从下拉列表选择。"],
    T["短名可留空（自动截取）；填写后直接用于按钮标签，不用加 #。"],
    T["文本回车 / 失焦保存，Esc 取消；每条下方显示识别结果。"],
    T["↑ / ↓ 调整按钮顺序；删除只移除这一条，空行与注释不会生成按钮。"],
    T["玩具推荐填写物品 ID，例如奥术秘社的私人钥匙：253629。"],
    T["已识别不代表当前可用，仍受收藏、背包、冷却与游戏场景限制。"],
    T["旧配置按原顺序载入，不会因未识别而丢弃；原来的 @图标设置也会保留。"],
}
local function DecodeExtraRow(raw)
    local model = {raw=raw, kind="auto", value=TrimExtra(raw), short=""}
    if model.value:sub(1,2) == "--" then
        model.kind="comment";model.value=TrimExtra(model.value:sub(3))
        return model
    end
    local body, short = model.value:match("^(.-)%s*#(%S+)%s*$")
    if body and body ~= "" then model.value=TrimExtra(body);model.short=short end
    local prefix, value = model.value:match("^([^:]+):%s*(.*)$")
    if not prefix then prefix, value = model.value:match("^(.-)：%s*(.*)$") end
    if prefix then
        local key=TrimExtra(prefix):lower()
        local kind=PREFIX_KIND[key]
        if key=="动作" or key=="動作" or key=="action" or key=="命令" or key=="cmd" then kind="action" end
        if kind then model.kind=kind;model.value=TrimExtra(value) end
    elseif ParseActionToken(model.value) then
        model.kind="action"
    end
    return model
end
local function ReadExtraRows(text)
    local models, pos = {}, 1
    while true do
        local a,b = text:find("[\r\n]",pos)
        if not a then models[#models+1]=DecodeExtraRow(text:sub(pos));break end
        if text:sub(a,a+1)=="\r\n" then b=a+1 end
        local model=DecodeExtraRow(text:sub(pos,a-1));model.eol=text:sub(a,b)
        models[#models+1]=model;pos=b+1
    end
    return models
end
local function EncodeExtraRow(model)
    local value=TrimExtra(model.value)
    if model.kind=="comment" then return "-- " .. value end
    if value=="" then return "" end -- 空白占位行不生成错误的「玩具:」按钮
    local raw=(EDIT_PREFIX[model.kind] or "") .. value
    if model.short~="" then raw=raw .. " #" .. model.short end
    return raw
end

local function BuildExtraEditor(panel,L,onResize)
    local editor=CreateFrame("Frame",nil,panel)
    editor:SetPoint("TOPLEFT",L.indent,L.y)
    editor:SetWidth(panel:GetWidth()-L.indent-24)
    editor.rows={};editor.models={};editor.lastText=nil
    extraEditor=editor
    local top, card, cardTop=L.y,L._card,L._cardTopY
    -- 本块拥有动态高度，避免 L:Finalize() 后丢失卡片锚点。
    L._card=nil
    local R=ns.UI.NewLayout(editor);R.indent=0;R.y=0
    R:Text(T["选择类型，填写名称 / ID；短名可留空。回车或失焦保存，Esc 取消。"],true)
    local function allowed() return not InCombatLockdown() end
    local function finishEdits(discardRow)
        for _,row in ipairs(editor.rows) do
            if row:IsShown() then
                for _,box in ipairs({row.value,row.short}) do
                    if box._editing then
                        local script=box.edit:GetScript((discardRow==true or row==discardRow) and "OnEscapePressed" or "OnEnterPressed")
                        script(box.edit)
                        box.edit:ClearFocus()
                    end
                end
            end
        end
    end
    local function persist()
        local out={}
        for i,model in ipairs(editor.models) do
            out[#out+1]=model.raw
            if i<#editor.models then out[#out+1]=model.eol or "\n" end
        end
        editor.lastText=table.concat(out)
        DB().extra.text=editor.lastText
        Refresh()
        if not button then editor:Sync() end -- 尚未创建主按钮时也刷新设置
    end
    local function addRow()
        if not allowed() then return end
        finishEdits()
        editor.models[#editor.models+1]=DecodeExtraRow("")
        persist()
    end
    editor.add=R:Button(120,T["＋ 新增一行"],addRow)
    editor.check=R:Button(110,T["检查配置"],function(self)
        ShowLinesTooltip(self,T["扩展按钮 · 检查配置"],ExtraCheckLines())
    end,true,editor.add)
    editor.help=R:Button(100,T["使用说明"],function(self)
        ShowLinesTooltip(self,T["逐条编辑扩展按钮"],ROW_HELP)
    end,true,editor.check)
    AttachHoverTooltip(editor.help,T["逐条编辑扩展按钮"],function() return ROW_HELP end)
    diagWidgets.checkBtn,diagWidgets.helpBtn=editor.check,editor.help
    R:step(8)
    local width=editor:GetWidth()
    local deleteX=width-48
    local downX,upX=deleteX-32,deleteX-62
    local shortX=upX-90
    local kindX,kindWidth=24,120 -- 为四字类型及下拉箭头预留足够空间
    local valueX=kindX+kindWidth+8
    local valueWidth=shortX-8-valueX
    local function label(parent,text,x,y,w,role)
        local fs=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT",x,y);fs:SetSize(w,18);fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false);fs:SetText(text)
        if ns.UI.StyleText then ns.UI.StyleText(fs,role or "muted") end
        return fs
    end
    label(editor,T["类型"],kindX,R.y,kindWidth)
    label(editor,T["名称 / ID（动作可直接选）"],valueX,R.y,valueWidth)
    label(editor,T["短名（可选）"],shortX,R.y,90)
    R:step(24)
    local rowsTop=R.y
    editor.summary=label(editor,"",0,0,width,"text")
    editor.summary:SetHeight(36);editor.summary:SetWordWrap(true)
    editor.addBottom=R:Button(120,T["＋ 新增一行"],addRow)

    local function createRow(index)
        local row=CreateFrame("Frame",nil,editor)
        row:SetSize(width,58)
        row.model=editor.models[index];row.index=index
        row.layout=ns.UI.NewLayout(row)
        local C=row.layout;C.indent=kindX;C.y=-2
        row.number=label(row,tostring(index),0,-6,22)
        local function change(field,value)
            if not allowed() or not row.model then return end
            row.model[field]=value
            row.model.raw=EncodeExtraRow(row.model)
            persist()
        end
        row.kind=C:Dropdown(kindWidth,"",EDIT_KINDS,function() return row.model.kind end,
            function(value)
                if not allowed() then return end
                finishEdits()
                change("kind",value)
            end)
        local kindText=row.kind:GetFontString()
        if kindText then kindText:SetWordWrap(false) end
        C.indent=valueX;C.y=0
        row.value=C:Box(valueWidth,28,false,function() return row.model.value end,
            function(value) change("value",TrimExtra(value:gsub("[\r\n]"," "))) end,nil,true)
        C.indent=shortX;C.y=0
        row.short=C:Box(82,28,false,function() return row.model.short end,
            function(value) change("short",value:gsub("[%s#]","")) end,nil,true)
        AttachHoverTooltip(row.value,T["名称 / ID"],function()
            return {row.model.value, T["只填名称或 ID，不用写类型前缀；回车 / 失焦保存，Esc 取消。"],
                T["玩具推荐用物品 ID；未识别的旧行会原样保留，修正后即可重试。"]}
        end)
        AttachHoverTooltip(row.short,T["按钮短名"],function()
            return {T["留空自动截取；自定义时不用加 #，空格会自动去除。"]}
        end)
        C.indent=valueX;C.y=-2
        row.action=C:Dropdown(valueWidth,"",function()
            local list={{value="",text=T["请选择快捷动作"]}}
            local current=row.model.value
            local standard=ns.locale=="zhCN" and {"小退","退组","重载界面","退出游戏"} or {"logout","leave","reload","quit"}
            local known=false
            for _,value in ipairs(standard) do
                list[#list+1]={value=value,text=ACTIONS[value].label}
                if value==current then known=true end
            end
            -- 非标准别名 / @图标不改写；用户换动作时才替换此值。
            if current~="" and not known then
                table.insert(list,2,{value=current,text=current})
            end
            return list
        end,function() return row.model.value end,function(value)
            if not allowed() then return end
            finishEdits();change("value",value)
        end)
        local function move(delta)
            if not allowed() then return end
            finishEdits()
            local i=row.index;local j=i+delta
            if j<1 or j>#editor.models then return end
            editor.models[i],editor.models[j]=editor.models[j],editor.models[i]
            persist()
        end
        C.indent=upX;C.y=-2
        row.up=C:Button(24,"↑",function() move(-1) end)
        C.indent=downX;C.y=-2
        row.down=C:Button(24,"↓",function() move(1) end)
        C.indent=deleteX;C.y=-2
        row.delete=C:Button(48,T["删除"],function()
            if not allowed() then return end
            finishEdits(row)
            table.remove(editor.models,row.index)
            if #editor.models==0 then editor.models[1]=DecodeExtraRow("") end
            persist()
        end)
        row.status=label(row,"",24,-34,width-24,"text")
        row:EnableMouse(true)
        AttachHoverTooltip(row,T["条目详情"],function() return {row.status:GetText(),row.model.raw} end)
        if ns.UI.StyleOptions then ns.UI.StyleOptions(row) end
        function row:PaintStatus()
            local p=ns.UI.palette
            if not p then return end
            local color=p.muted
            if self.statusMode=="ready" then color=p.accent
            elseif self.statusMode=="error" then
                color=p.bg[1]>0.5 and {0.64,0.28,0.02,1} or {1,0.66,0.25,1}
            end
            self.status:SetTextColor(unpack(color))
        end
        if ns.UI.OnTheme then ns.UI.OnTheme(function() row:PaintStatus() end) end
        return row
    end

    function editor:Sync()
        if self.syncing then return end
        self.syncing=true
        local text=DB().extra.text or ""
        if text~=self.lastText then
            -- 外部配置变化才重新拆行；普通同步/切页/换主题不丢编辑中的草稿。
            finishEdits(true)
            self.models=ReadExtraRows(text);self.lastText=text
        end
        local ok,fail=0,0
        for i,model in ipairs(self.models) do
            local row=self.rows[i]
            if not row then
                -- Box 初建就读取 getter，所以先提供模型再创建控件。
                row=createRow(i);self.rows[i]=row
            end
            row.model=model;row.index=i
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,rowsTop-(i-1)*58)
            row.number:SetText(tostring(i));row:Show()
            row.layout:SyncAll()
            row.value:SetShown(model.kind~="action")
            row.action:SetShown(model.kind=="action")
            row.short:SetShown(model.kind~="comment")
            row.up:SetEnabled(i>1);row.down:SetEnabled(i<#self.models)
            local status
            row.statusMode="empty"
            if model.kind=="comment" then status=T["注释 · 不生成按钮"]
            elseif TrimExtra(model.value)=="" then
                status=model.kind=="action" and T["请选择快捷动作"] or T["待填写名称 / ID"]
            else
                local good,entry=pcall(ParseExtraLine,model.raw)
                if good and entry then
                    ok=ok+1;row.statusMode="ready"
                    status=T["已识别 · "] .. (KIND_LABEL[entry.kind] or "") .. " · " .. (entry.name or tostring(entry.id))
                else
                    fail=fail+1;row.statusMode="error"
                    status=T["未识别 · 请核对名称 / ID；数据就绪后自动重试"]
                end
            end
            row.status:SetText(status);row:PaintStatus()
        end
        for i=#self.models+1,#self.rows do self.rows[i]:Hide() end
        diagWidgets.cfgBox=self.rows[1] and self.rows[1].value
        local cfg=DB().extra
        local state=not ns.IsModuleEnabled(MODULE_ID) and T["模块未启用"]
            or not DB().button.enabled and T["主按钮未显示"]
            or not cfg.enabled and T["扩展按钮未启用"]
            or cfg.collapsed and T["扩展条已收起"] or T["扩展条已启用"]
        if InCombatLockdown() and pendingRebuild then state=T["安全按钮等待脱战更新"] end
        self.summary:SetText((T["已识别 %d 条，未识别 %d 条 · %s"]):format(ok,fail,state))
        local bottom=rowsTop-#self.models*58
        self.addBottom:ClearAllPoints();self.addBottom:SetPoint("TOPLEFT",0,bottom)
        self.summary:ClearAllPoints();self.summary:SetPoint("TOPLEFT",0,bottom-34)
        local height=-bottom+70
        local changed=self:GetHeight()~=height
        self:SetHeight(height)
        if card then card:SetHeight(cardTop-top+height+12) end
        L.y=top-height-12;L:Finalize()
        self.syncing=nil
        if changed and onResize then onResize() end
    end
    editor:Sync()
    panel:HookScript("OnShow",function() editor:Sync() end)
    L.syncers[#L.syncers+1]=function() editor:Sync() end
    return editor
end

local function MountStatus(cat)
    local stored = DB().mounts[cat]
    if stored then
        local id = ResolveStoredMount(stored)
        local name = id and MountName(id)
        if name then return name, "success" end
        return T["未匹配到已收藏的坐骑："] .. tostring(stored), "danger"
    end
    local auto = ResolveMount(cat)
    if auto then return T["自动："] .. (MountName(auto) or ("#" .. auto)), "muted" end
    return cat == "fly" and T["随机收藏坐骑"] or T["未设置（没有合适的自动坐骑）"], "muted"
end

local function BuildOptions(panel,m,L)
    L:Title(T["快捷按钮"])
    L:Text(T["坐骑和按键集中设置；扩展条的内容与布局放在一起。"],true)
    m.mountRows = {}
    m.optionTabs=ns.UI.OptionTabs(panel,L,{
        {name=T["坐骑与按键"],width=150,build=function(panel,L)
            L:Section(T["坐骑与点击组合键"])
            L:Text(T["按键重复时自动交换；Alt+右键打开设置，中键收起扩展条。"], true)
            L:step(4)
            -- 同一平面五行；复用通用控件的皮肤、输入提交与同步，避免嵌套页签。
            local left, top = L.indent, L.y
            local available = panel:GetWidth()-left-24
            local keyX, nameX = left+56, left+242
            local clearX = left+available-48
            local captureX = clearX-78
            local nameWidth = captureX-nameX-8
            local function heading(text,x,w)
                local fs=panel:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
                fs:SetPoint("TOPLEFT",panel,"TOPLEFT",x,top)
                fs:SetSize(w,18);fs:SetJustifyH("LEFT");fs:SetText(text)
                if ns.UI.StyleText then ns.UI.StyleText(fs,"muted") end
            end
            heading(T["用途"],left,48);heading(T["点击组合键"],keyX,178)
            heading(T["坐骑名称 / mountID（留空自动）"],nameX,available-242)
            L.y=top-24
            for _, category in ipairs(CATS) do
                local cat=category
                local y=L.y
                local row={};m.mountRows[cat]=row
                local label=panel:CreateFontString(nil,"ARTWORK","GameFontNormal")
                label:SetPoint("TOPLEFT",panel,"TOPLEFT",left,y-6)
                label:SetSize(48,18);label:SetJustifyH("LEFT");label:SetText(CAT_LABEL[cat])
                if ns.UI.StyleText then ns.UI.StyleText(label,"accent") end
                row.label=label
                L.indent=keyX;L.y=y-2
                row.binding=L:Dropdown(178,"",BINDING_CHOICES,
                    function() return GetBindings()[cat] end,
                    function(v) SetBinding(cat,v) end,
                    function() L:SyncAll();Refresh() end)
                L.indent=nameX;L.y=y
                row.mount=L:Box(nameWidth,28,false,
                    function() local v=DB().mounts[cat];return v and tostring(v) or "" end,
                    function(v)
                        local t=(v or ""):gsub("^%s+",""):gsub("%s+$","")
                        DB().mounts[cat]=(t~="") and (tonumber(t) or t) or nil
                    end, function() L:SyncAll();Refresh() end, true)
                AttachHoverTooltip(row.mount,CAT_LABEL[cat] .. T["坐骑"],function()
                    return {MountStatus(cat), T["填写收藏中的完整名称或 mountID；回车/失焦保存，Esc 取消。骑上目标后点「抓取」。"],
                        T["清除只清坐骑，不改按键；飞行留空用随机收藏，其余用途自动匹配，没有匹配则不召唤。"]}
                end)
                L.indent=captureX;L.y=y-2
                row.capture=L:Button(70,T["抓取"],function()
                    if CaptureCurrent(cat) then L:SyncAll();Refresh() end
                end)
                L.indent=clearX;L.y=y-2
                row.clear=L:Button(48,T["清除"],function()
                    DB().mounts[cat]=nil;L:SyncAll();Refresh()
                end)
                L.indent=keyX;L.y=y-34
                row.status=L:DynLabel(function() return MountStatus(cat) end)
                row.status:ClearAllPoints()
                row.status:SetPoint("TOPLEFT",panel,"TOPLEFT",keyX,y-34)
                row.status:SetSize(available-56,18)
                row.status:SetFontObject(GameFontHighlightSmall)
                row.status:SetWordWrap(false)
                L.indent=left;L.y=y-54
            end
            L:Section(T["主按钮"])
            L:Row({
                function(c) c:Check(T["显示主按钮"], function() return DB().button.enabled end,
                    function(v) DB().button.enabled=v end, Refresh) end,
                function(c) c:Check(T["锁定位置（Alt/Ctrl+左键仍可拖动）"], function() return LayoutDB().locked end,
                    function(v) LayoutDB().locked=v end, Refresh) end,
            }, 280)
            L:Row({
                function(c) c:Slider("BaimiaoQuickMountScaleSlider", T["整体缩放（%）"], 50, 200, 5,
                    function() return (DB().button.scale or 1)*100 end,
                    function(v) DB().button.scale=v/100 end, Refresh) end,
                function(c)
                    m.resetMountBindings = c:Button(150, T["恢复默认按键"], function()
                        DB().bindings = {}
                        L:SyncAll(); Refresh()
                    end)
                end,
            }, 280)
        end},
        {name=T["扩展按钮"],width=150,build=function(panel,L,onResize)
            L:Section(T["扩展条布局"])
            L:Row({
                function(c) c:Check(T["显示扩展按钮"],function() return DB().extra.enabled end,
                    function(v) DB().extra.enabled=v end,Refresh) end,
                function(c) c:Check(T["收起扩展条（中键或悬停控制钮切换）"],function() return DB().extra.collapsed end,
                    function(v) DB().extra.collapsed=v end,Refresh) end,
            },280)
            L:Row({
                function(c) c:Dropdown(230,T["生长方向："],ns.UI.ListFrom(
                    {"RIGHT","LEFT","UP","DOWN"},{RIGHT=T["向右（默认）"],LEFT=T["向左"],UP=T["向上"],DOWN=T["向下"]}),
                    function() return DB().extra.grow or "RIGHT" end,
                    function(v) DB().extra.grow=v end,Refresh) end,
                function(c) c:Check(T["按钮下方显示短名"],function() return DB().extra.showLabels~=false end,
                    function(v) DB().extra.showLabels=v end,Refresh) end,
            },280)
            L:Slider("BaimiaoQuickMountLabelCharsSlider",T["短名字数上限"],2,6,1,
                function() return tonumber(DB().extra.labelChars) or DEFAULT_LABEL_CHARS end,
                function(v) DB().extra.labelChars=v end,Refresh)
            L:Section(T["扩展内容 · 逐条编辑"])
            m.extraEditor=BuildExtraEditor(panel,L,onResize)

        end},
    })
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
            ns.Print(T["快捷按钮：已清除"] .. CAT_LABEL[arg] .. T["坐骑。"])
        elseif cmd == "check" then
            CheckExtraConfig()   -- 逐行体检扩展按钮配置
        elseif cmd == "collapse" or cmd == "fold" or cmd == "收起" then
            SetCollapsed(true); ns.Print(InCombatLockdown() and T["快捷按钮：已请求收起，脱战后生效。"] or T["快捷按钮：已收起扩展按钮。"])
        elseif cmd == "expand" or cmd == "unfold" or cmd == "展开" or cmd == "展開" then
            SetCollapsed(false); ns.Print(InCombatLockdown() and T["快捷按钮：已请求展开，脱战后生效。"] or T["快捷按钮：已展开扩展按钮。"])
        elseif cmd == "toggle" then
            SetCollapsed(not DB().extra.collapsed)
            ns.Print(T["快捷按钮："] .. (InCombatLockdown() and T["脱战后应用："] or T["扩展按钮已"]) .. (DB().extra.collapsed and T["收起"] or T["展开"]) .. "。")
        elseif cmd == "help" then
            PrintExtraHelp()     -- 扩展按钮完整说明
        elseif cmd == "diag" then
            DiagWidgets()        -- 控件自检（字体/阴影/行距/文本）
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
    name = T["快捷按钮"],
    desc = T["一键快捷：一个按钮按自定义点击组合键召唤飞行/修理/拍卖行/载人/水下坐骑（坐骑可抓取或直接填名字）；旁边还能长出技能 / 玩具 / 物品 / 小退·退组·重载等自定义按钮。"],
    defaults = defaults,
    OnEnable = function()
        RebuildMountCache()  -- 登录时建一次坐骑缓存，之后按需重建
        CreateButton()
        SetupButtonEvents()
        UpdateButton()
        -- 上一版把短名默认值 3 回填进了存档，现在默认改成 2：把"正是那个旧默认"的值清掉，
        -- 让它跟着新默认走（真想用 3 个字，在设置里把滑块拖回去即可）。
        if DB().extra.labelChars == 3 then DB().extra.labelChars = nil end
        RebuildExtraButtons()
        SetupSlash()
    end,
    OnDisable = function()
        TeardownButtonEvents()   -- 关掉总开关后不再收事件
        if button then button:Hide() end
        HideExtraButtons()
    end,
    OnToggle = function(_, on)
        -- 重新启用时 Core 只调 OnToggle（不调 OnEnable），事件要在这里补回来；
        -- 关闭时也顺手摘一遍，保证不管调用顺序如何状态都一致。
        if on then SetupButtonEvents() else TeardownButtonEvents() end
        Refresh()
    end,
    BuildOptions = BuildOptions,
})
