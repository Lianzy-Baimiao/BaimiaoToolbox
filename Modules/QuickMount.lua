local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 模块：快捷按钮（原名“快捷坐骑”，后来加了扩展按钮，名字就不再只是坐骑了）
-- 一个按钮 + 斜杠命令：
--   · 按修饰键召唤不同用途的坐骑：飞行 / 修理 / 拍卖行 / 载人 / 水下
--   · 旁边按选定方向长出一排自定义按钮：技能 / 玩具 / 物品 / 小退·退组·重载等快捷动作
-- 注意：模块 id 仍是 "quickmount"（存档键名），改名只动显示名，不动 id —— 换 id 会丢设置。
--
-- 按钮点击：
--   左键        飞行（未设则随机收藏坐骑）
--   Shift+左键  修理
--   Ctrl+左键   拍卖行
--   Alt+左键    载人
--   右键        水下
--   Alt+右键    打开设置
-- 扩展按钮：在设置里每行输入一条技能/玩具/物品（ID 或名称，支持“技能:”等前缀），
--   也可以写特殊动作（小退 / 退组 / 重载界面 / 退出游戏，受保护动作走安全按钮执行），
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

-- 短名字数上限的默认值。故意不写进 defaults：默认值改一次就会被存档里的旧默认顶住，
-- 所以放在代码里兜底，只有用户显式调过滑块才会存进 DB。
local DEFAULT_LABEL_CHARS = 2

local defaults = {
    button = {
        enabled = true,
        scale = 1,
    },
    -- 各用途绑定的 mountID；nil = 未设（fly 用随机，其它用自动默认/提示）
    mounts = {},
    -- 扩展按钮：技能/玩具/物品按钮，长在主坐骑按钮旁
    extra = {
        enabled = false,   -- 是否显示扩展按钮
        grow = "RIGHT",    -- 生长方向：RIGHT/LEFT/UP/DOWN（默认向右）
        text = "",         -- 每行一条的技能/玩具/物品配置（ID 或名称）
        showLabels = true, -- 按钮下方显示短名（动作名 / 名字前几个字）
        collapsed = false, -- 收起：暂时藏起那排扩展按钮，主按钮旁留个箭头随时展开
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
        ns.Print("快捷按钮：战斗中不能召唤坐骑。")
        return
    end
    if not (C_MountJournal and C_MountJournal.SummonByID) then
        ns.Print("快捷按钮：坐骑接口不可用。")
        return
    end

    local id = ResolveMount(cat)
    if id then
        -- 校验拥有且可用
        local name, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
        if not isCollected then
            ns.Print("快捷按钮：" .. (CAT_LABEL[cat] or cat) .. "坐骑你还没收藏，改用随机。")
            C_MountJournal.SummonByID(0)
            return
        end
        C_MountJournal.SummonByID(id)
    else
        -- 未设：飞行/无候选 -> 随机收藏坐骑；游戏会按当前环境选合适的。
        if cat ~= "fly" then
            ns.Print("快捷按钮：未设置" .. (CAT_LABEL[cat] or cat) .. "坐骑（也没找到合适的默认），改用随机。可在设置里指定。")
        end
        C_MountJournal.SummonByID(0)
    end
end

-- 把当前正骑的坐骑设为某用途的默认。
local function CaptureCurrent(cat)
    local id = GetActiveMountID()
    if not id then
        ns.Print("快捷按钮：请先骑上你想设为「" .. (CAT_LABEL[cat] or cat) .. "」的坐骑，再来抓取。")
        return false
    end
    DB().mounts[cat] = id
    ns.Print(("快捷按钮：已把「%s」设为 %s 坐骑。"):format(MountName(id) or ("#" .. id), CAT_LABEL[cat] or cat))
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

local button                -- 主按钮（CreateButton 里创建；先声明供下方闭包使用）
local pendingRebuild        -- 战斗中无法重建安全按钮时挂起的标记

local EXTRA_SIZE = 44                -- 与主按钮同尺寸
local EXTRA_GAP  = 6                 -- 与主按钮/前一个按钮之间的小间距
local GROW_ANCHORS = {
    RIGHT = { point = "LEFT",   rel = "RIGHT",   dx =  1, dy =  0 },
    LEFT  = { point = "RIGHT",  rel = "LEFT",    dx = -1, dy =  0 },
    UP    = { point = "BOTTOM", rel = "TOP",     dx =  0, dy =  1 },
    DOWN  = { point = "TOP",    rel = "BOTTOM",  dx =  0, dy = -1 },
}

-- 展开/收起小开关贴在主按钮“生长方向那条边”的内侧（不外凸，免得压住第一个扩展按钮）。
local COLLAPSE_TAB_POS = {
    RIGHT = { point = "RIGHT",  rel = "RIGHT",  dx = -1, dy =  0 },
    LEFT  = { point = "LEFT",   rel = "LEFT",   dx =  1, dy =  0 },
    UP    = { point = "TOP",    rel = "TOP",    dx =  0, dy = -1 },
    DOWN  = { point = "BOTTOM", rel = "BOTTOM", dx =  0, dy =  1 },
}
-- 箭头（用 GBK 都覆盖的 ←↑→↓，各字体都画得出，不会出豆腐块）：
-- 收起时指向生长方向（点它=展开），展开时指回主按钮（点它=收起）。
local COLLAPSE_ARROW = {
    RIGHT = { collapsed = "→", expanded = "←" },
    LEFT  = { collapsed = "←", expanded = "→" },
    UP    = { collapsed = "↑", expanded = "↓" },
    DOWN  = { collapsed = "↓", expanded = "↑" },
}
local KIND_LABEL = { macro = "动作", spell = "技能", toy = "玩具", item = "物品" }

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
DefAction({ "小退", "登出", "下线", "回到角色选择" }, "小退（回到角色选择）", "/logout",
    [[Interface\Icons\inv_misc_rune_01]], "小退")
DefAction({ "退组", "离队", "离开队伍" }, "退组", "/run C_PartyInfo.LeaveParty()",
    [[Interface\Icons\inv_misc_groupneedmore]], "退组")
DefAction({ "重载", "重载界面", "刷新界面" }, "重载界面", "/reload",
    [[Interface\Icons\trade_engineering]], "重载")
DefAction({ "退出游戏", "关闭游戏" }, "退出游戏", "/quit",
    [[Interface\Icons\spell_arcane_portalstormwind]], "退出")

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
    spell = "spell", ["技能"] = "spell", ["法术"] = "spell",
    toy = "toy", ["玩具"] = "toy",
    item = "item", ["物品"] = "item",
}

-- 名称 -> 玩具物品ID（扫一遍玩具箱）
local function FindToyByName(name)
    if not (C_ToyBox and C_ToyBox.GetNumToys) then return nil end
    for i = 1, C_ToyBox.GetNumToys() do
        local itemID = C_ToyBox.GetToyFromIndex(i)
        if itemID then
            local _, toyName = C_ToyBox.GetToyInfo(itemID)
            if toyName == name then return itemID end
        end
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
            local _, name, icon = C_ToyBox.GetToyInfo(id)
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
    local prefix, value = line:match("^([^:：]+)%s*[:：]%s*(.+)$")
    if prefix and value then
        local pkey = (prefix:gsub("^%s+", ""):gsub("%s+$", "")):lower()
        -- 动作前缀：动作:小退 / action:小退 / 命令:退组
        if pkey == "动作" or pkey == "action" or pkey == "命令" or pkey == "cmd" then
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
            local ok, ia = pcall(function() return info.isActive end)
            if ok and not issecretvalue(ia) and ia ~= nil and ia == false then
                cd:Clear()
                return
            end
        end

        -- 首选：DurationObject（秘密环境下唯一可行的通道）
        if C_Spell and C_Spell.GetSpellCooldownDuration then
            local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, e.id)
            if ok and durObj then
                if pcall(cd.SetCooldownFromDurationObject, cd, durObj) then return end
            end
        end
        -- 退回：数值通道，先判秘密再比较（对秘密值做 > 会直接抛错）
        if info then
            local s, d = info.startTime, info.duration
            if not issecretvalue(s) and not issecretvalue(d) and d and d > 1.5 then
                pcall(cd.SetCooldown, cd, s or 0, d)
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
                if pcall(cd.SetCooldownFromDurationObject, cd, durObj) then return end
            end
        end
        if GetItemCooldownFn then
            local ok, s, d = pcall(GetItemCooldownFn, e.id)
            if ok and not issecretvalue(s) and not issecretvalue(d) and s and d and d > 1.5 then
                pcall(cd.SetCooldown, cd, s, d)
                return
            end
        end
    end

    cd:Clear()
end

-- 安全按钮池：按钮只建一次（安全属性战斗中不能写、重建代价高），多余的隐藏备用。
local extraButtons = {}

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
    label:SetPoint("TOP", b, "BOTTOM", 0, -2)
    label:SetJustifyH("CENTER")
    label:SetTextColor(0.95, 0.95, 0.95)
    b.label = label

    -- 冷却圈
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawBling(false)
    b.cd = cd

    -- 悬停提示（读 b._entry：池里的按钮会复用给不同条目）
    b:SetScript("OnEnter", function(self)
        local e = self._entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        if e.kind == "macro" then
            GameTooltip:SetText(e.name, 1, 1, 1)
            GameTooltip:AddLine(e.macrotext, 0.6, 0.9, 1)
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
            ns.Print("退组：当前没有队伍。")
        end
    end)

    -- 冷却显示（节流刷新，避免每帧查询）。秘密环境下数值不可读，
    -- PaintCooldown 内部会走 DurationObject 通道或直接不画，绝不把秘密值交给 SetCooldown。
    local t = 0
    b:SetScript("OnUpdate", function(self, dt)
        local e = self._entry
        if not e then return end
        t = t + dt
        if t < 0.25 then return end
        t = 0
        PaintCooldown(self.cd, e)
    end)

    extraButtons[index] = b
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
    "扩展按钮 —— 完整说明（每行一条，-- 开头是注释、空行忽略；设置改动立刻生效）：",
    "  技能:460905  或  技能:炉石        施法（空格/全角冒号都认）",
    "  玩具:216665  或  玩具:奥术秘社的私人钥匙    用玩具（名称要与玩具箱里完全一致）",
    "  物品:123456                      用背包里的物品",
    "  小退 / 退组 / 重载界面 / 退出游戏     受保护动作，走安全按钮执行（也可写“动作:小退”）",
    "  退组 @135824                     @ 后面跟法术或物品 id，换这个按钮的图标",
    "  玩具:216665 #银行                 行尾 #短名 = 按钮下面显示这几个字（不给就自动截断）",
    "  省略前缀：纯数字按 技能→玩具→物品 依次识别；纯名称先查玩具再查法术书（最后查背包）",
    "  找不到名字就改用 ID。网上的玩具 ID 常是它的“使用法术 ID”（战团银行距离抑制器＝法术 460905、",
    "  玩具物品 216665），这种会按同名玩具自动识别，包在身上也不会点不动。",
    "  逐行确认认成了什么：设置里点「检查配置」，或输入 /qm check。",
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
        out[#out + 1] = "配置是空的（设置里每行填一条技能/玩具/物品/动作）。"
        return out
    end
    out[#out + 1] = ("共 %d 行 ——"):format(#lines)
    for i, line in ipairs(lines) do
        local ok, entry = pcall(ParseExtraLine, line)
        if ok and entry then
            local what = KIND_LABEL[entry.kind] or entry.kind
            local id = entry.id and (" #" .. entry.id) or ""
            out[#out + 1] = ("%d) %s → %s%s %s"):format(i, line, what, id, entry.name or "")
        else
            out[#out + 1] = ("|cffff6060%d) %s → 未识别|r：名称要与已收集的玩具 / 已学法术 / 背包物品" ..
                "完全一致，或改用 ID；动作可填 小退/退组/重载界面/退出游戏"):format(i, line)
        end
    end
    if not ns.IsModuleEnabled(MODULE_ID) then
        out[#out + 1] = "提示：本模块被总开关关掉了，按钮不会显示。"
    elseif not cfg.enabled then
        out[#out + 1] = "提示：扩展开关当前是关闭的，按钮不会显示。"
    end
    return out
end

-- 命令 /qm check：把体检结果打到聊天框（用户主动敲的，才输出）。
local function CheckExtraConfig()
    ns.Print("扩展按钮 · 检查配置")
    for _, line in ipairs(ExtraCheckLines()) do ns.Print("  " .. line) end
end

-- 更新“展开/收起”小开关：只有在（模块开 + 主按钮开 + 扩展开 + 至少 1 条已识别）时才显示，
-- 位置贴在生长方向那条边，箭头随收起/展开状态翻向。开关本身是普通按钮（非安全框），
-- 战斗中也能随便显隐/移动；真正藏起那排安全按钮仍走 RebuildExtraButtons 的脱战补处理。
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
    tab.arrow:SetText((COLLAPSE_ARROW[grow] or COLLAPSE_ARROW.RIGHT)[collapsed and "collapsed" or "expanded"])
    tab:Show()
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
    UpdateCollapseTab()   -- 条目数 / 生长方向 / 收起状态可能都变了，同步一下开关
    return #entries, fail
end

-- 收起所有扩展按钮（模块被总开关关掉时用）。战斗中不动安全框，等脱战重建时处理。
local function HideExtraButtons()
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

-- 展开/收起那排扩展按钮：改状态 + 重建（战斗中自动挂起、脱战补上）+ 立刻翻箭头。
local function SetCollapsed(v)
    DB().extra.collapsed = v and true or false
    RebuildExtraButtons()   -- 非战斗：立即显隐；战斗：挂起，脱战自动补
    UpdateCollapseTab()     -- 箭头方向立刻反映意图（即便安全按钮要脱战才真正显隐）
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
    button:RegisterEvent("SPELLS_CHANGED")        -- 技能变动：扩展按钮重新解析
    button:RegisterEvent("PLAYER_ENTERING_WORLD") -- 登录切换：数据就绪后重试解析
    button:RegisterEvent("PLAYER_REGEN_ENABLED")  -- 脱战：补上战斗中挂起的扩展按钮重建
    button:SetScript("OnEvent", function(self, event)
        if event == "MODIFIER_STATE_CHANGED" then
            self:RefreshIcon()
        elseif event == "NEW_MOUNT_ADDED" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            ownedCache = nil                      -- 失效缓存，下次用的时候重建
            self:RefreshIcon()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingRebuild then RebuildExtraButtons() end
        else
            RebuildExtraButtons()                 -- 玩具/技能数据就绪或变动：重建扩展按钮
        end
    end)
end

local function TeardownButtonEvents()
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
        tooltip = {
            title = "快捷按钮",
            lines = {
                "左键：飞行　　Shift+左键：修理",
                "Ctrl+左键：拍卖行　　Alt+左键：载人",
                "右键：水下坐骑",
                "扩展按钮：技能 / 玩具 / 物品 / 小退·退组·重载 等，在设置里添加",
                "有扩展按钮时，边上的小箭头可一键展开/收起那排按钮",
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

    -- 展开/收起小开关：普通按钮，做主按钮的子件（跟着位移/缩放走），压在图标之上。
    -- 它不是安全框，可随时显隐/移动；真正藏那排安全按钮由 RebuildExtraButtons 负责
    -- （战斗中挂起、脱战自动补），所以战斗中点它只翻箭头，脱战后那排按钮才真正显隐。
    local tab = CreateFrame("Button", "BaimiaoQuickMountCollapse", button)
    tab:SetSize(15, 15)
    tab:SetFrameLevel(button:GetFrameLevel() + 20)
    tab:EnableMouse(true)
    tab:RegisterForClicks("LeftButtonUp")
    local tbg = tab:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints(tab)
    tbg:SetColorTexture(0, 0, 0, 0.6)
    tab.arrow = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.arrow:SetPoint("CENTER", 0, 0)
    tab.arrow:SetTextColor(0.05, 0.83, 0.62)   -- 主题翠绿
    local thl = tab:CreateTexture(nil, "HIGHLIGHT")
    thl:SetAllPoints(tab)
    thl:SetColorTexture(1, 1, 1, 0.15)
    tab:SetScript("OnClick", function() SetCollapsed(not DB().extra.collapsed) end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(DB().extra.collapsed and "展开扩展按钮" or "收起扩展按钮", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab:Hide()
    button.collapseTab = tab

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
end

--------------------------------------------------------------------------------
-- 设置面板
--------------------------------------------------------------------------------

-- 自检：把设置页里几个关键控件的字体/阴影/行距/文本打出来 —— 用来查
-- "到底哪两行字叠在一起"（比如某个控件上挂了两个 FontString）。
-- 用法：/qm diag（打开过设置页之后再跑，才拿得到控件）
local diagWidgets = {}
local function DiagWidgets()
    ns.Print("快捷按钮 · 控件自检")
    local function dumpWidget(f, label)
        if not f then
            ns.Print(("  %s：没拿到（先打开一次本模块的设置页再跑）"):format(label))
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
                ns.Print(("  %s #%d 文本=[%s]"):format(label, n, tostring(r:GetText())))
                ns.Print(("      字体=%s 字号=%s 标记=[%s] 阴影=%s,%s 行距=%s"):format(
                    tostring(path), tostring(size), tostring(flags),
                    tostring(sx), tostring(sy), tostring(sp)))
            end
        end
        ns.Print(("  %s：FontString 共 %d 个（>1 且文本相同 = 字被画了两遍）"):format(label, n))
    end
    dumpWidget(diagWidgets.checkBtn, "按钮·检查配置")
    dumpWidget(diagWidgets.helpBtn, "按钮·详细说明")
    dumpWidget(diagWidgets.exampleBtn, "按钮·填入示例")
    dumpWidget(diagWidgets.cfgBox, "扩展配置输入框")
    local p, s, fl = GameFontNormal:GetFont()
    ns.Print(("  参照：GameFontNormal = %s / %s / [%s]"):format(tostring(p), tostring(s), tostring(fl)))
end

local function BuildOptions(panel, m, L)
    L:Title("快捷按钮")
    L:Text("一键快捷：一个按钮按修饰键召唤不同用途坐骑（左键飞行、Shift+左键修理、Ctrl+左键拍卖行、" ..
        "Alt+左键载人、右键水下），图标随修饰键实时变化；旁边还能长出一排自定义按钮" ..
        "（技能 / 玩具 / 物品 / 小退·退组·重载等快捷动作）。", false)

    L:Section("按钮")
    L:Check("锁定位置（锁定后隐藏背景、不能拖动；Alt+左键仍可拖）",
        function() return LayoutDB().locked end,
        function(v) LayoutDB().locked = v end, Refresh)
    L:Slider("BaimiaoQuickMountScaleSlider", "缩放", 0.5, 2.0, 0.05,
        function() return DB().button.scale or 1 end,
        function(v) DB().button.scale = v end, Refresh)

    L:Section("各用途坐骑（“设为当前”抓取，或直接在下面填名字 / mountID）")
    for _, cat in ipairs(CATS) do
        local label = CAT_LABEL[cat]
        L:DynLabel(function()
            local stored = DB().mounts[cat]
            if stored then
                local id = ResolveStoredMount(stored)
                local nm = id and MountName(id)
                if nm then
                    return label .. "：|cff00ff88" .. nm .. "|r"
                end
                return label .. "：|cffff6060“" .. tostring(stored) .. "”没匹配到已收藏的坐骑|r"
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
            ns.Print("快捷按钮：已清除" .. label .. "坐骑。")
        end, true, setBtn)
        -- 直接填名字或 mountID：名称要与收藏里的坐骑名完全一致
        local mBox = L:Box(240, 22, false,
            function() local v = DB().mounts[cat]; return v and tostring(v) or "" end,
            function(v)
                local t = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
                DB().mounts[cat] = (t ~= "") and (tonumber(t) or t) or nil
            end, function() L:SyncAll() Refresh() end)
        AttachHoverTooltip(mBox, label .. " 坐骑", function()
            return {
                "填坐骑名（与收藏里的名称完全一致）或 mountID，例如：鎏金雷龙 / 1234",
                "也可以骑上目标坐骑后点上面的「设为当前」抓取。",
                "清空 = 回到自动匹配 / 随机。",
            }
        end)
    end

    L:Section("扩展按钮（技能 · 玩具 · 物品 · 快捷动作）")
    L:Check("显示扩展按钮（在主坐骑按钮旁长出一排同尺寸的按钮）",
        function() return DB().extra.enabled end,
        function(v) DB().extra.enabled = v end, Refresh)
    L:Dropdown(200, "生长方向：", ns.UI.ListFrom(
        { "RIGHT", "LEFT", "UP", "DOWN" },
        { RIGHT = "向右（默认）", LEFT = "向左", UP = "向上", DOWN = "向下" }),
        function() return DB().extra.grow or "RIGHT" end,
        function(v) DB().extra.grow = v end, Refresh)
    L:Check("按钮下方显示短名（动作名 / 名字前几个字）",
        function() return DB().extra.showLabels ~= false end,
        function(v) DB().extra.showLabels = v end, Refresh)
    L:Check("收起扩展按钮（只藏那排按钮，主按钮旁留个箭头随时展开；也可点箭头切换）",
        function() return DB().extra.collapsed end,
        function(v) DB().extra.collapsed = v end, Refresh)
    L:Slider("BaimiaoQuickMountLabelCharsSlider", "短名字数上限", 2, 6, 1,
        function() return tonumber(DB().extra.labelChars) or DEFAULT_LABEL_CHARS end,
        function(v) DB().extra.labelChars = v end, Refresh)
    L:Text("每行一条，例：|cff00ff88技能:460905|r　|cff00ff88玩具:216665 #银行|r（悬停输入框看完整写法）", true)
    L:step(8)   -- 折行会让 L:Text 的高度估算偏小，补一点间距，免得压住下面的输入框
    local boxCfg = L:Box(460, 110, true,
        function() return DB().extra.text or "" end,
        function(v) DB().extra.text = v end, Refresh)
    diagWidgets.cfgBox = boxCfg
    -- 写法说明挂在输入框上：悬停看提示、点进去编辑时自动收起，不刷聊天频道。
    -- 注意用 HookScript：Core 在这个框上挂了自己的 OnMouseDown（进入编辑态）与描边钩子，
    -- 用 SetScript 会把它们顶掉。
    boxCfg:HookScript("OnEnter", function(self)
        ShowLinesTooltip(self, "扩展按钮 · 写法说明", EXTRA_HELP)
    end)
    boxCfg:HookScript("OnLeave", function() GameTooltip:Hide() end)
    boxCfg:HookScript("OnMouseDown", function() GameTooltip:Hide() end)
    L:DynLabel(function()
        local cfg = DB().extra
        if not ns.IsModuleEnabled(MODULE_ID) or not cfg.enabled then
            return "|cffaaaaaa扩展按钮未启用，勾选上面的开关生效|r"
        end
        if InCombatLockdown() and pendingRebuild then
            return "|cffffd100战斗中不能改安全按钮，脱战后自动生效|r"
        end
        local ok, fail, byKind = CountExtra(cfg.text)
        if ok == 0 and fail == 0 then return "|cffaaaaaa尚未输入任何条目|r" end
        local parts = {}
        for _, kind in ipairs({ "macro", "spell", "toy", "item" }) do
            if byKind[kind] then
                parts[#parts + 1] = ("%s %d"):format(KIND_LABEL[kind], byKind[kind])
            end
        end
        local s = ("|cff00ff88已生成 %d 个扩展按钮|r（%s）"):format(ok, table.concat(parts, "、"))
        if fail > 0 then
            s = s .. ("，|cffff6060%d 条未能识别|r（登录后数据就绪会自动重试）"):format(fail)
        end
        return s
    end)

    local checkBtn = L:Button(140, "检查配置", function(self)
        ShowLinesTooltip(self, "扩展按钮 · 检查配置", ExtraCheckLines())
    end)
    local helpBtn = L:Button(140, "详细说明", function(self)
        ShowLinesTooltip(self, "扩展按钮 · 写法说明", EXTRA_HELP)
    end, true, checkBtn)
    -- 供 /qm diag 自检用
    diagWidgets.checkBtn, diagWidgets.helpBtn = checkBtn, helpBtn
    -- 悬停也弹同一个提示框（不必非得点）
    AttachHoverTooltip(checkBtn, "扩展按钮 · 检查配置", ExtraCheckLines)
    AttachHoverTooltip(helpBtn, "扩展按钮 · 写法说明", function() return EXTRA_HELP end)
    local exampleBtn = L:Button(140, "填入示例", function()
        if (DB().extra.text or ""):gsub("%s", "") ~= "" then
            ns.Print("扩展按钮：框里已经有内容了，示例不会覆盖（清空后再点）。")
            return
        end
        DB().extra.text = [[-- 每行一条；-- 开头是注释、空行会被忽略
玩具:奥术秘社的私人钥匙 #钥匙
技能:460905

-- 快捷动作（受保护动作，走安全按钮执行）
小退
退组]]
        L:SyncAll()
        Refresh()
        ns.Print("扩展按钮：已填入示例，按需删改。")
    end, true, helpBtn)
    diagWidgets.exampleBtn = exampleBtn
    -- 同一行的按钮不占步进高度，这里补一段，否则下面的说明文字会紧贴甚至压住按钮底边
    L:step(14)

    L:step(6)
    L:Text("说明：飞行默认用“随机收藏坐骑”，游戏按能否飞行自动选。其余用途按坐骑中文名自动匹配你已收藏的：" ..
        "修理=牦牛/苔原猛犸象，拍卖行=鎏金雷龙，载人=沙石幼龙，水下=驯服的海马。" ..
        "没匹配到、或想换别的，就在下面填名字，或骑上目标坐骑点“设为当前”。", true)
    L:step(12)
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
            ns.Print("快捷按钮：已清除" .. CAT_LABEL[arg] .. "坐骑。")
        elseif cmd == "check" then
            CheckExtraConfig()   -- 逐行体检扩展按钮配置
        elseif cmd == "collapse" or cmd == "fold" or cmd == "收起" then
            SetCollapsed(true);  ns.Print("快捷按钮：已收起扩展按钮。")
        elseif cmd == "expand" or cmd == "unfold" or cmd == "展开" then
            SetCollapsed(false); ns.Print("快捷按钮：已展开扩展按钮。")
        elseif cmd == "toggle" then
            SetCollapsed(not DB().extra.collapsed)
            ns.Print("快捷按钮：扩展按钮已" .. (DB().extra.collapsed and "收起" or "展开") .. "。")
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
    name = "快捷按钮",
    desc = "一键快捷：一个按钮按修饰键召唤飞行/修理/拍卖行/载人/水下坐骑（坐骑可抓取或直接填名字）；旁边还能长出技能 / 玩具 / 物品 / 小退·退组·重载等自定义按钮。",
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
