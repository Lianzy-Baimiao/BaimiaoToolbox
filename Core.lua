local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 白描工具箱 · 框架
-- 每个功能都是一个模块：调用 ns.RegisterModule{...} 注册，框架负责初始化、
-- 存档隔离，并把它挂到暴雪设置界面的“白描工具箱”分类下。
--------------------------------------------------------------------------------

ns.modules = {}       -- id -> 模块定义
ns.orderedModules = {} -- 按注册顺序，保证设置界面里排序稳定

-- 递归填默认值：只补缺失键，不动用户已改过的值。
local function applyDefaults(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.applyDefaults = applyDefaults

-- 本次登录是否已为某模块补过默认值。
-- 注意：这个标记必须放会话内存，不能写进存档——写进去会持久化成"已初始化"，
-- 以后版本新增的默认键就再也补不进老用户的存档了。
local dbInited = {}

-- 取某模块的独立存档表（BaimiaoToolboxDB[moduleId]），并补上默认值。
-- 已初始化过的表跳过递归合并（DB() 在各模块里被频繁调用，避免每次全表递归）。
function ns.GetDB(moduleId, defaults)
    BaimiaoToolboxDB = BaimiaoToolboxDB or {}
    local db = BaimiaoToolboxDB[moduleId]
    if not db then
        db = {}
        BaimiaoToolboxDB[moduleId] = db
    end
    if db.__inited ~= nil then db.__inited = nil end  -- 清掉早期版本误存进存档的标记
    if defaults and not dbInited[moduleId] then
        applyDefaults(db, defaults)
        dbInited[moduleId] = true
    end
    return db
end

-- 角色级存档（位置/锁定等布局字段存这里，多角色互不干扰）。
-- toc 里对应 SavedVariablesPerCharacter: BaimiaoToolboxDBPC。
function ns.GetPCDB()
    BaimiaoToolboxDBPC = BaimiaoToolboxDBPC or {}
    return BaimiaoToolboxDBPC
end

-- 取某模块在角色档里的布局子表（含 point/relPoint/x/y/locked）。
-- 首次访问时若账号档里有旧布局值则迁移过来（老用户无感升级）。
function ns.GetLayoutDB(moduleId, legacySrc)
    local pc = ns.GetPCDB()
    pc.layout = pc.layout or {}
    local t = pc.layout[moduleId]
    if not t then
        t = {}
        pc.layout[moduleId] = t
        if type(legacySrc) == "table" then
            for _, k in ipairs({ "point", "relPoint", "x", "y", "locked" }) do
                if legacySrc[k] ~= nil then t[k] = legacySrc[k] end
            end
        end
    end
    return t
end

local function P(msg)
    print("|cff0cd29f白描工具箱|r: " .. msg)
end
ns.Print = P

-- 注册一个模块。def 字段：
--   id           唯一字符串
--   name         设置界面显示名
--   defaults     该模块的默认存档表（可选）
--   OnEnable(m)  登录后调用一次，m 是 def 本身且带 m.db（已初始化的存档）
--   OnDisable(m) （可选）模块被总开关关闭时调用，用来停 ticker / 摘事件
--   BuildOptions(panel, m)  往设置子面板里放控件（可选）
function ns.RegisterModule(def)
    assert(def and def.id, "模块必须有 id")
    ns.modules[def.id] = def
    ns.orderedModules[#ns.orderedModules + 1] = def
end

-- 模块的“总开关”状态存在 BaimiaoToolboxDB._enabled[id]，默认开。
-- 这是整块小插件的启停；模块内部的显示开关（比如坐标喊话的“显示移速”）是另一回事。
function ns.IsModuleEnabled(id)
    BaimiaoToolboxDB = BaimiaoToolboxDB or {}
    local e = BaimiaoToolboxDB._enabled
    if not e or e[id] == nil then return true end
    return e[id] and true or false
end

function ns.SetModuleEnabled(id, on)
    BaimiaoToolboxDB = BaimiaoToolboxDB or {}
    BaimiaoToolboxDB._enabled = BaimiaoToolboxDB._enabled or {}
    BaimiaoToolboxDB._enabled[id] = on and true or false
    local m = ns.modules[id]
    if not m then return end
    -- 关闭时先走 OnDisable（停 ticker / 摘事件），再走 OnToggle 刷 UI。
    if not on and m.OnDisable then
        local ok, err = pcall(m.OnDisable, m)
        if not ok then P(("模块 %s 停用时报错：%s"):format(id, tostring(err))) end
    end
    if m.OnToggle then
        local ok, err = pcall(m.OnToggle, m, on and true or false)
        if not ok then P(("模块 %s 切换时报错：%s"):format(id, tostring(err))) end
    end
end

--------------------------------------------------------------------------------
-- 共享 UI：布局器。模块用它往面板里堆控件，不用各自算坐标。
--------------------------------------------------------------------------------

ns.UI = {}

-- 给一个框统一挂上拖动逻辑：解锁时左键可拖；无论锁定与否，Alt+左键 / Ctrl+左键 都能拖。
-- isLocked() 返回当前是否锁定；onMoved() 在放手后调用（存位置）。
function ns.UI.EnableDrag(frame, isLocked, onMoved)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if (not isLocked()) or IsAltKeyDown() or IsControlKeyDown() then
            self:StartMoving()
            self._moving = true
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if self._moving then
            self:StopMovingOrSizing()
            self._moving = nil
            if onMoved then onMoved() end
        end
    end)
end

-- 可拖动屏上框工厂：四个模块原本各自重复实现同一套
-- “存位置 / 套位置 / 锁定视觉 / 拖动 / 提示”样板，这里统一下沉。
-- opts 字段：
--   name          全局框名
--   moduleId      用于角色档布局存储与 Alt+右键直达设置
--   size          {w, h} 初始尺寸
--   strata        层级（默认 MEDIUM）
--   layoutKey     布局存到 BaimiaoToolboxDBPC.layout[layoutKey]（默认 moduleId）
--   legacy        旧的账号档表（迁移老布局用）
--   defaultPos    {point, relPoint, x, y} 首次无档时的默认位置
--   unlockDragOnly  true=只在解锁时拖动（如居中警示框），锁定时完全放行鼠标
--   bgAlpha       未锁定时背景透明度（默认 0.4）
--   tooltip       {title, lines={...}} 悬停提示；不传则没有
--   onRightClick  自定义右键（默认 Alt+右键 打开本模块设置）
-- 返回 frame，且 frame:SavePosition/ApplyPosition/ApplyLockVisual 已就绪。
function ns.UI.CreateMovableFrame(opts)
    local layout = ns.GetLayoutDB(opts.layoutKey or opts.moduleId, opts.legacy)
    local f = CreateFrame(opts.clickable and "Button" or "Frame", opts.name, UIParent)
    f.layoutDB = layout
    f:SetSize((opts.size and opts.size[1]) or 120, (opts.size and opts.size[2]) or 40)
    f:SetFrameStrata(opts.strata or "MEDIUM")
    f:SetClampedToScreen(true)
    if opts.clickable then
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, opts.bgAlpha or 0.4)
    f.bg:Hide()

    function f:SavePosition()
        local point, _, relPoint, x, y = self:GetPoint(1)
        local t = self.layoutDB
        t.point, t.relPoint, t.x, t.y = point, relPoint, x, y
    end

    function f:ApplyPosition()
        local t = self.layoutDB
        local dp = opts.defaultPos or {}
        self:ClearAllPoints()
        self:SetPoint(
            t.point or dp.point or "CENTER", UIParent,
            t.relPoint or dp.relPoint or "CENTER",
            t.x or dp.x or 0, t.y or dp.y or 0)
    end

    -- 解锁时显示背景；unlockDragOnly 模式下锁定 = 不吃鼠标（放行点击穿透）。
    function f:ApplyLockVisual()
        local locked = self.layoutDB.locked and true or false
        self.bg:SetShown(not locked)
        if opts.unlockDragOnly then
            self:EnableMouse(not locked)
        else
            self:EnableMouse(true)  -- 锁定也要吃鼠标：Alt+右键开设置、Alt+左键拖动
        end
    end

    function f:IsLocked()
        return self.layoutDB.locked and true or false
    end

    ns.UI.EnableDrag(f, function() return f:IsLocked() end, function() f:SavePosition() end)

    -- 右键行为：默认 Alt+右键打开本模块设置；可用 opts.onRightClick 覆盖。
    f:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "RightButton" then return end
        if opts.onRightClick then
            opts.onRightClick(f)
        elseif IsAltKeyDown() and opts.moduleId then
            ns.OpenOptions(opts.moduleId)
        end
    end)

    if opts.tooltip then
        f:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(opts.tooltip.title or "")
            for _, line in ipairs(opts.tooltip.lines or {}) do
                GameTooltip:AddLine(line, 0.6, 0.9, 1)
            end
            if not f:IsLocked() and not opts.unlockDragOnly then
                GameTooltip:AddLine("未锁定：按住左键拖动", 0.6, 0.9, 1)
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    f:ApplyPosition()
    f:ApplyLockVisual()
    return f
end

-- 打开暴雪取色器。兼容新（SetupColorPickerAndShow，10.2.5+）与旧接口。
-- onConfirm(r, g, b) 在选色/确认/取消时都会回调，保证不会卡在中间态。
function ns.UI.OpenColorPicker(r, g, b, onConfirm)
    local function applyCurrent()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onConfirm(nr, ng, nb)
    end
    local info = {
        swatchFunc = applyCurrent,
        hasOpacity = false,
        r = r, g = g, b = b,
        cancelFunc = function(prev)
            if prev then onConfirm(prev.r, prev.g, prev.b) end
        end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.func = applyCurrent
        ColorPickerFrame.cancelFunc = info.cancelFunc
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-- 给一个宿主面板套上滚动区，返回可堆控件的“滚动子面板”。
-- 内容超出可视高度时会自动出现滚动条，解决设置页出界的问题。
function ns.UI.MakeScrollable(host)
    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 3, -3)
    scroll:SetPoint("BOTTOMRIGHT", -27, 3)  -- 右侧留出滚动条宽度
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    child:SetWidth(600)
    scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w) end)
    return child, scroll
end

--------------------------------------------------------------------------------
-- 控件美化辅助：工具箱统一视觉语言（深底圆角卡片 + 翠绿 hover/聚焦描边）。
-- 暴雪默认的 UIPanelButtonTemplate 银灰按钮 / OptionsSliderTemplate 直角框
-- 与我们的分组卡片风格不搭，下面提供统一的皮肤函数。
--------------------------------------------------------------------------------

local SKIN_BORDER = { 0.35, 0.55, 0.5, 0.85 }          -- 常态边框（偏灰绿）
local SKIN_BORDER_HOVER = { 0.05, 0.83, 0.62, 1 }      -- hover：主题翠绿
local SKIN_BORDER_FOCUS = { 0.05, 0.83, 0.62, 1 }      -- 聚焦：同主题色

-- 给一个 Frame/Button 套上卡片式背景（深色半透明底 + 细边框）。
local function SkinCardFrame(f, alpha)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.06, 0.07, 0.07, alpha or 0.85)
    f:SetBackdropBorderColor(unpack(SKIN_BORDER))
end

-- 给可点控件加 hover 描边（进入亮绿，离开还原）。
local function SkinHoverBorder(f)
    f:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(SKIN_BORDER_HOVER)) end)
    f:HookScript("OnLeave", function(self)
        if not self._skinFocused then
            self:SetBackdropBorderColor(unpack(SKIN_BORDER))
        end
    end)
end

-- 皮肤化一个文本按钮：去掉模板贴图，改卡片底 + hover 高亮 + 字色。
local function SkinTextButton(b)
    -- UIPanelButtonTemplate 的左右中三段贴图清掉，换成卡片底。
    for _, region in ipairs({ b:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
            region:Hide()
        end
    end
    SkinCardFrame(b, 0.55)
    SkinHoverBorder(b)
    local fs = b.GetFontString and b:GetFontString()
    if fs then
        -- 去掉字体阴影与字体标记（OUTLINE / THICK 之类）：我们的底是深色卡片，
        -- 暴雪默认的阴影/描边在上面只会让字看着发虚、像"重影"。
        local path, size = fs:GetFont()
        if path then fs:SetFont(path, size, "") end
        fs:SetShadowOffset(0, 0)
        if fs.SetSpacing then fs:SetSpacing(0) end
        fs:SetTextColor(0.9, 0.95, 0.93)
    end
    b:SetScript("OnMouseDown", function(self) self:SetBackdropColor(0.10, 0.16, 0.13, 0.9) end)
    b:SetScript("OnMouseUp", function(self) self:SetBackdropColor(0.06, 0.07, 0.07, 0.55) end)
    b:HookScript("OnEnter", function(self) self:SetBackdropColor(0.08, 0.12, 0.10, 0.85) end)
    b:HookScript("OnLeave", function(self) self:SetBackdropColor(0.06, 0.07, 0.07, 0.55) end)
end
ns.UI.SkinTextButton = SkinTextButton
ns.UI.SkinCardFrame = SkinCardFrame

-- 把「值数组 + 显示名映射」组合成下拉用的列表：
--   ns.UI.ListFrom({"A","B"}, {A="甲", B="乙"}) -> {{value="A",text="甲"}, {value="B",text="乙"}}
-- 没有映射时直接用值本身当显示名。
function ns.UI.ListFrom(values, labels)
    local out = {}
    for _, v in ipairs(values) do
        out[#out + 1] = { value = v, text = (labels and labels[v]) or v }
    end
    return out
end

function ns.UI.NewLayout(panel)
    -- indent：当前控件左缩进（进入分组卡片后加大）。
    local L = { panel = panel, y = -16, syncers = {}, indent = 16 }

    function L:step(dy) self.y = self.y - (dy or 26) end

    -- 刷新所有控件的显示值。
    -- 关键：逐个 pcall 隔离——以前一个控件报错会让后面的控件全部拿不到值
    --（表现就是滑块右边的数值框一片空白）。现在出错只跳过它自己并提示一次。
    function L:SyncAll()
        for _, f in ipairs(self.syncers) do
            local ok, err = pcall(f)
            if not ok and not self._syncWarned then
                self._syncWarned = true
                ns.Print("|cffff4040某个设置控件刷新失败（其余控件已正常显示）：|r" .. tostring(err))
            end
        end
    end

    -- 关闭当前分组卡片：按内容高度撑开卡片背景，恢复缩进。
    function L:_closeCard()
        if self._card then
            self:step(12)  -- 卡片底部内边距
            self._card:SetHeight(math.max(self._cardTopY - self.y, 20))
            self._card = nil
        end
        self.indent = 16
    end

    -- 堆完所有控件后调用：收尾最后一个卡片并按内容高度撑开面板。
    function L:Finalize()
        self:_closeCard()
        self.panel:SetHeight(-self.y + 20)
    end

    function L:Title(text)
        local fs = self.panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
        fs:SetPoint("TOPLEFT", 16, self.y)
        fs:SetText("|cff0cd29f" .. text .. "|r")  -- 主题翠绿色
        self:step(38)
        return fs
    end

    -- 开一个分组卡片：翠绿标题在上，下面是带边框的半透明背景板，控件缩进其中。
    function L:Section(text)
        self:_closeCard()
        self:step(12)  -- 与上一块拉开间距
        local fs = self.panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 14, self.y)
        fs:SetText("|cff0cd29f" .. text .. "|r")
        self:step(20)  -- 标题高度

        local card = CreateFrame("Frame", nil, self.panel, "BackdropTemplate")
        card:SetPoint("TOPLEFT", 8, self.y)
        card:SetPoint("TOPRIGHT", -8, self.y)
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        card:SetBackdropColor(0, 0, 0, 0.25)
        card:SetBackdropBorderColor(0.35, 0.55, 0.5, 0.9)
        card:SetFrameLevel(self.panel:GetFrameLevel())
        self._card = card
        self._cardTopY = self.y
        self:step(12)      -- 卡片顶部内边距
        self.indent = 22   -- 卡片内控件缩进
        return fs
    end

    function L:Text(text, small)
        local fs = self.panel:CreateFontString(nil, "ARTWORK",
            small and "GameFontHighlightSmall" or "GameFontHighlight")
        local pad = self.indent + 6
        fs:SetPoint("TOPLEFT", self.indent, self.y)
        fs:SetPoint("RIGHT", self.panel, "RIGHT", -pad, 0)
        fs:SetJustifyH("LEFT")
        -- 固定换行宽度，让文字按面板宽度折行；这样 GetStringHeight 才是真实高度。
        fs:SetWidth((self.panel:GetWidth() or 600) - self.indent - pad)
        fs:SetWordWrap(true)
        fs:SetText(text)
        -- 高度估算：取实际渲染高度（含折行），并给个按换行符估算的下限兜底。
        -- 但构建设置页时面板还没布局好，GetStringHeight() 会给偏小的值（折行被当成一行），
        -- 于是长说明会压住下面第一个控件。所以再按「行宽 / 字号」粗算一次折行数（按最宽的
        -- 中文字估：1 字 = 3 字节），取较大值 —— 宁可多留点白，也不压住下一个控件。
        local wrapW = math.max((self.panel:GetWidth() or 600) - self.indent - pad, 80)
        local fontH = small and 10 or 12
        local bytesPerLine = math.max(math.floor(wrapW / fontH) * 3, 30)
        local wrapLines = math.max(math.ceil(#text / bytesPerLine), 1)
        local nl = select(2, text:gsub("\n", "\n")) + 1
        -- 行距：中文默认行距很紧，相邻两行会"贴着"，看着像叠字 —— 每行加 2px 呼吸空间。
        if fs.SetSpacing then fs:SetSpacing(2) end
        local h = math.max(fs:GetStringHeight() + 6, (16 + 2) * math.max(nl, wrapLines) + 8)
        self:step(h)
        return fs
    end

    function L:Check(label, getter, setter, onChange)
        local cb = CreateFrame("CheckButton", nil, self.panel, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", self.indent, self.y)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(label)
        cb:SetScript("OnClick", function(self2)
            setter(self2:GetChecked() and true or false)
            if onChange then onChange() end
        end)
        self.syncers[#self.syncers + 1] = function() cb:SetChecked(getter() and true or false) end
        self:step(26)
        return cb
    end

    function L:Box(w, h, multi, getter, setter, onChange)
        local box = CreateFrame("Frame", nil, self.panel, "BackdropTemplate")
        box:SetSize(w, h)
        box:SetPoint("TOPLEFT", self.indent, self.y)
        SkinCardFrame(box, 0.85)
        box:EnableMouse(true)

        -- 显示层：FontString。单行 EditBox 的文字在部分环境下渲染不出来
        -- （自检可证：框内有值、可见、alpha=1，就是画不出来），所以单行框
        -- 平时用 FontString 展示内容，点击才进入编辑态。
        -- 多行走 ScrollFrame + 多行 EditBox 的渲染路径，实测正常，保持原样。
        local valueFs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valueFs:SetPoint("TOPLEFT", 8, -4)
        valueFs:SetPoint("RIGHT", box, "RIGHT", -8, 0)
        valueFs:SetJustifyH("LEFT")
        valueFs:SetJustifyV("TOP")
        valueFs:SetHeight(h - 10)
        valueFs:SetWordWrap(true)
        if multi then valueFs:Hide() end   -- 多行框的 EditBox 常显，不需要 FontString 展示

        -- 编辑层。
        local eb
        if multi then
            local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 6, -5)
            scroll:SetPoint("BOTTOMRIGHT", -24, 5)
            eb = CreateFrame("EditBox", nil, scroll)
            eb:SetWidth(w - 34)
            eb:SetFontObject(ChatFontNormal)
            eb:SetAutoFocus(false)
            eb:SetMultiLine(true)
            eb:SetMaxLetters(2048)
            scroll:SetScrollChild(eb)

            -- 滚动条：暴雪模板自带一条带金色圆钮的滚动条，和这套扁平卡片不搭。
            -- 之前只藏了圆箭头、结果还留着（模板结构一变就失效），现在改成
            -- 「滚动框里除了 EditBox 以外一律藏掉」，不管它是 Slider、Button 还是别的。
            for _, child in ipairs({ scroll:GetChildren() }) do
                if child ~= eb then child:Hide() end
            end
            -- 框里也可能挂了别的滚动控件/小按钮，一并藏掉（只藏滚动/按钮类，不动 EditBox）
            for _, child in ipairs({ box:GetChildren() }) do
                if child ~= eb and (child:IsObjectType("Slider") or child:IsObjectType("Button")) then
                    child:Hide()
                end
            end
            -- 没了滚动条就用滚轮滚（EditBox 默认不吃滚轮）
            local function wheelScroll(_, delta)
                local cur = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
                local maxv = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
                local target = cur - (delta or 0) * 26
                if target < 0 then target = 0 elseif target > maxv then target = maxv end
                if scroll.SetVerticalScroll then scroll:SetVerticalScroll(target) end
            end
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", wheelScroll)
            eb:EnableMouseWheel(true)
            eb:SetScript("OnMouseWheel", wheelScroll)
            -- 多行 EditBox 的中文行距也太紧，加一点呼吸空间
            if eb.SetSpacing then eb:SetSpacing(2) end
            -- 内容刷新后把滚动位置拉回顶部：EditBox 会把光标放末尾、连带滚到底，
            -- 于是第一行经常被截成半行，压在下一行上看着像"两行字叠在一起"。
            box._snapTop = function()
                if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
            end
        else
            eb = CreateFrame("EditBox", nil, box)
            eb:SetPoint("TOPLEFT", 8, -4)
            eb:SetPoint("BOTTOMRIGHT", -8, 4)
            eb:SetFontObject(ChatFontNormal)
            eb:SetAutoFocus(false)
            eb:SetMaxLetters(1024)
            eb:Hide()   -- 单行：平时显示 FontString，点击才进入编辑
        end

        -- 聚焦时边框亮成主题翠绿，失焦还原，明确“正在编辑哪个框”。
        eb:SetScript("OnEditFocusGained", function()
            box._skinFocused = true
            box:SetBackdropBorderColor(unpack(SKIN_BORDER_FOCUS))
        end)

        -- 右侧“保存”按钮 + “已保存”提示。让用户明确知道有没有生效。
        local saveBtn = CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
        saveBtn:SetSize(56, 22)
        saveBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
        saveBtn:SetText("保存")
        SkinTextButton(saveBtn)
        local flash = self.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        flash:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
        flash:SetText("")

        local dirty = false
        local function markDirty()
            dirty = true
            flash:SetText("|cffffd100未保存*|r")
        end
        local function commit()
            setter(eb:GetText())
            dirty = false
            flash:SetText("|cff20ff40已保存|r")
            C_Timer.After(1.5, function() if not dirty then flash:SetText("") end end)
            if onChange then onChange() end
        end

        -- 单行框的编辑态切换：点击卡片进入，回车/失焦确认，Esc 取消。
        local function exitEdit(apply)
            if not box._editing then return end
            box._editing = false
            if apply then
                commit()
            else
                eb:SetText(getter() or "")
                dirty = false
                flash:SetText("")
            end
            eb:Hide()
            valueFs:SetText(getter() or "")
            valueFs:Show()
            box:SetBackdropBorderColor(unpack(SKIN_BORDER))
        end
        local function enterEdit()
            if box._editing then return end
            box._editing = true
            valueFs:Hide()
            eb:SetText(getter() or "")
            eb:Show()
            eb:HighlightText()
            eb:SetFocus()
            box:SetBackdropBorderColor(unpack(SKIN_BORDER_FOCUS))
        end

        eb:SetScript("OnTextChanged", function(_, userInput)
            if userInput then markDirty() end
        end)
        eb:SetScript("OnEscapePressed", function(self2)
            self2:SetText(getter() or "")
            dirty = false
            flash:SetText("")
            if multi then self2:ClearFocus() else exitEdit(false) end
        end)
        eb:SetScript("OnEditFocusLost", function()
            box._skinFocused = nil
            if multi then
                box:SetBackdropBorderColor(unpack(SKIN_BORDER))
                commit()
            else
                exitEdit(true)
            end
        end)
        if not multi then
            eb:SetScript("OnEnterPressed", function() exitEdit(true) end)
        else
            -- 多行框回车是换行，Ctrl+回车 当作保存。
            eb:SetScript("OnEnterPressed", function(self2)
                if IsControlKeyDown() then commit(); self2:ClearFocus() end
            end)
        end
        if not multi then
            box:SetScript("OnMouseDown", function() enterEdit() end)
        end
        saveBtn:SetScript("OnClick", function()
            if multi then commit(); eb:ClearFocus() else exitEdit(true) end
        end)

        box.edit = eb
        self.syncers[#self.syncers + 1] = function()
            local v = getter() or ""
            local changed = (v ~= box._lastValue)
            box._lastValue = v
            if not box._editing then eb:SetText(v) end
            valueFs:SetText(v)
            dirty = false
            flash:SetText("")
            if changed and box._snapTop then box._snapTop() end   -- 换过内容就滚回顶部
        end
        valueFs:SetText(getter() or "")
        self:step(h + 8)
        return box
    end

    -- 滑块：完全自绘的扁平样式，替换掉暴雪模板的粗糙外观。
    -- 一行结构：[ − ] 细轨道（主题色填充 + 药丸拖块）[ + ]  [ 数值框 ]
    -- 四种改法：拖拖块、滚轮、点 −/+、直接输入数值。
    -- 标题行右侧同时显示当前值，不必眯眼看刻度。
    function L:Slider(globalName, label, minV, maxV, stepV, getter, setter, onChange)
        local function fmt(v)
            v = tonumber(v) or minV
            if stepV >= 1 then return tostring(math.floor(v + 0.5)) end
            return string.format("%.2f", v)
        end
        local function clampSnap(v)
            v = tonumber(v) or minV
            v = math.max(minV, math.min(maxV, v))
            local n = math.floor(v / stepV + 0.5) * stepV
            if stepV < 1 then n = math.floor(n * 1000 + 0.5) / 1000 end  -- 去掉浮点毛刺
            return n
        end

        local TRACK_W = 210
        local KNOB_COLOR = { 0.05, 0.83, 0.62 }
        local KNOB_HOVER = { 0.20, 1.00, 0.78 }

        -- 标题行：标签 + 主题色当前值。
        local title = self.panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOPLEFT", self.indent, self.y)
        title:SetText(label)
        local valueText = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        valueText:SetPoint("LEFT", title, "RIGHT", 8, 0)
        valueText:SetTextColor(0.05, 0.83, 0.62)
        self:step(18)

        -- 控件行容器（宽度需容纳：步进钮 + 轨道 + 步进钮 + 数值框）。
        local holder = CreateFrame("Frame", nil, self.panel)
        holder:SetSize(TRACK_W + 130, 22)
        holder:SetPoint("TOPLEFT", self.indent, self.y)
        holder:EnableMouse(true)
        holder:EnableMouseWheel(true)

        -- 左步进按钮。
        local minus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
        minus:SetSize(22, 22)
        minus:SetPoint("LEFT", holder, "LEFT", 0, 0)
        minus:SetText("-")
        SkinTextButton(minus)

        -- 轨道 + 填充。
        local trackX = 30
        local track = holder:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT", holder, "LEFT", trackX, 0)
        track:SetSize(TRACK_W, 8)
        track:SetColorTexture(0, 0, 0, 0.55)

        local fill = holder:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("LEFT", track, "LEFT", 0, 0)
        fill:SetHeight(8)
        fill:SetColorTexture(0.05, 0.83, 0.62, 0.5)

        -- 真正的 Slider：只负责拖动逻辑与命中判定。
        local slider = CreateFrame("Slider", globalName, holder)
        slider:SetPoint("LEFT", track, "LEFT", 0, 0)
        slider:SetSize(TRACK_W, 22)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(stepV)
        slider:SetObeyStepOnDrag(true)
        slider:EnableMouseWheel(true)

        -- thumb 做成 2px 宽的透明条：拖动行程几乎铺满整条轨道，
        -- 视觉上的“药丸”由下面自绘的 knob 承担。
        local hit = slider:CreateTexture(nil, "OVERLAY")
        hit:SetSize(2, 22)
        hit:SetColorTexture(0, 0, 0, 0)
        slider:SetThumbTexture(hit)

        -- 自绘拖块：主题色药丸 + 顶部高光。
        local knob = CreateFrame("Frame", nil, holder)
        knob:SetSize(10, 20)
        knob:SetFrameLevel(slider:GetFrameLevel() + 2)
        local knobBg = knob:CreateTexture(nil, "ARTWORK")
        knobBg:SetAllPoints(knob)
        knobBg:SetColorTexture(unpack(KNOB_COLOR))
        local knobShine = knob:CreateTexture(nil, "OVERLAY")
        knobShine:SetPoint("TOPLEFT", knob, "TOPLEFT", 2, -2)
        knobShine:SetPoint("TOPRIGHT", knob, "TOPRIGHT", -2, -2)
        knobShine:SetHeight(2)
        knobShine:SetColorTexture(1, 1, 1, 0.35)

        -- 右步进按钮。
        local plus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
        plus:SetSize(22, 22)
        plus:SetPoint("LEFT", holder, "LEFT", trackX + TRACK_W + 8, 0)
        plus:SetText("+")
        SkinTextButton(plus)

        -- 数值框：平时用 FontString 显示数值。
        -- 原因：FontString 在任何 UI 环境下都稳定渲染（本设置页的标题/说明都是它，
        -- 自检证实 EditBox 里"框内有值"却画不出来）。点击数值进入编辑态，
        -- EditBox 只在编辑时显示，回车/失焦确认，Esc 取消。
        local ebHolder = CreateFrame("Frame", nil, holder, "BackdropTemplate")
        ebHolder:SetSize(56, 22)
        ebHolder:SetPoint("LEFT", plus, "RIGHT", 12, 0)
        ebHolder:EnableMouse(true)
        SkinCardFrame(ebHolder, 0.85)

        local valueFs = ebHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valueFs:SetPoint("CENTER")
        valueFs:SetTextColor(0.05, 0.83, 0.62)

        -- 编辑用 EditBox：默认隐藏，点击数值才显示。
        local eb = CreateFrame("EditBox", nil, ebHolder)
        eb:SetPoint("TOPLEFT", 7, -2)
        eb:SetPoint("BOTTOMRIGHT", -5, 2)
        eb:SetFontObject(ChatFontNormal)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(7)
        eb:Hide()

        -- 拖块 / 填充 / 数值文字跟随取值。
        local function updateVisual(v)
            local frac = (maxV > minV) and ((v - minV) / (maxV - minV)) or 0
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            knob:ClearAllPoints()
            knob:SetPoint("CENTER", track, "LEFT", frac * TRACK_W, 0)
            fill:SetWidth(math.max(frac * TRACK_W, 0.001))
            valueText:SetText(fmt(v))
            valueFs:SetText(fmt(v))
        end

        -- applying=true 表示"同步控件值"而非用户操作：别回写输入框、别触发 onChange。
        local applying = false

        slider:SetScript("OnValueChanged", function(_, value)
            local snapped = clampSnap(value)
            setter(snapped)
            updateVisual(snapped)
            if not applying then
                eb:SetText(fmt(snapped))
                if onChange then onChange() end
            end
        end)

        local function stepBy(delta)
            slider:SetValue(clampSnap(slider:GetValue() + delta))  -- 触发 OnValueChanged
        end
        minus:SetScript("OnClick", function() stepBy(-stepV) end)
        plus:SetScript("OnClick", function() stepBy(stepV) end)
        slider:SetScript("OnMouseWheel", function(_, delta) stepBy(delta * stepV) end)
        holder:SetScript("OnMouseWheel", function(_, delta) stepBy(delta * stepV) end)

        -- 悬停轨道时拖块提亮，提示"这里可以拖"。
        slider:SetScript("OnEnter", function() knobBg:SetColorTexture(unpack(KNOB_HOVER)) end)
        slider:SetScript("OnLeave", function() knobBg:SetColorTexture(unpack(KNOB_COLOR)) end)

        -- 点击数值 → 编辑态；回车/失焦确认，Esc 取消。
        local editing = false
        local function enterEdit()
            if editing then return end
            editing = true
            valueFs:Hide()
            eb:SetText(fmt(slider:GetValue()))
            eb:Show()
            eb:HighlightText()
            eb:SetFocus()
            ebHolder:SetBackdropBorderColor(unpack(SKIN_BORDER_FOCUS))
        end
        local function exitEdit(apply)
            if not editing then return end
            editing = false
            if apply then
                local n = tonumber(eb:GetText())
                if n then slider:SetValue(clampSnap(n)) end   -- 触发 setter + 视觉 + onChange
            end
            updateVisual(slider:GetValue())
            eb:Hide()
            valueFs:Show()
            ebHolder:SetBackdropBorderColor(unpack(SKIN_BORDER))
        end

        ebHolder:SetScript("OnMouseDown", function() enterEdit() end)
        eb:SetScript("OnEnterPressed", function() exitEdit(true) end)
        eb:SetScript("OnEscapePressed", function() exitEdit(false) end)
        eb:SetScript("OnEditFocusLost", function() exitEdit(true) end)

        local function sync()
            local v = clampSnap(getter())
            applying = true
            slider:SetValue(v)
            applying = false
            updateVisual(v)
            if editing then eb:SetText(fmt(v)) end
        end
        -- 包一层保护：这个函数会被 OnShow / 定时器多次调用，
        -- 万一某次取值异常，只提示一次而不是让后面所有控件跟着空白。
        local syncWarned = false
        local function safeSync()
            local ok, err = pcall(sync)
            if not ok and not syncWarned then
                syncWarned = true
                ns.Print("|cffff4040「" .. (label or "?") .. "」滑块取值失败：|r" .. tostring(err))
            end
        end
        self.syncers[#self.syncers + 1] = safeSync
        safeSync()                            -- 建完立即填一次
        C_Timer.After(0, safeSync)            -- 面板尺寸/显示态就绪后再补一次
        holder:SetScript("OnShow", safeSync)  -- 每次本页显示时刷新，保证一进来就有数值

        -- 登记到自检列表，供 /bm diag 排查"数值框空白"这类显示问题。
        ns._diag = ns._diag or {}
        ns._diag[#ns._diag + 1] = function()
            local g = getter()
            return ("%-18s 取值=%s 计算=%s 显示=[%s] 可见=%s"):format(
                tostring(label), tostring(g), fmt(clampSnap(g)),
                valueFs:GetText() or "", tostring(valueFs:IsShown()))
        end
        self:step(30)
        return holder
    end

    -- 循环切换按钮：点一下在 values 里前进一位。labels 是可选的显示名映射。
    function L:Cycle(w, prefix, values, labels, getter, setter, onChange)
        local b = CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", self.indent, self.y)
        SkinTextButton(b)
        local function refresh()
            local cur = getter()
            b:SetText(prefix .. ((labels and labels[cur]) or cur))
        end
        b:SetScript("OnClick", function()
            local cur = getter()
            local idx = 1
            for i, v in ipairs(values) do if v == cur then idx = i break end end
            setter(values[(idx % #values) + 1])
            refresh()
            if onChange then onChange() end
        end)
        self.syncers[#self.syncers + 1] = refresh
        self:step(30)
        return b
    end

    -- 下拉菜单。listFn 可以是 { {value=,text=}, ... } 表格，也可以是返回它的函数；
    -- getter 返回当前 value，setter(value) 写回。
    -- 用 12.x 的 MenuUtil（比老 UIDropDownMenu 稳），没有则退回一个循环按钮。
    -- previewFn(value)（可选）：鼠标悬停某项时调用，用于试听。
    function L:Dropdown(w, prefix, listFn, getter, setter, onChange, previewFn)
        -- 统一取列表：支持直接给表，也支持给函数（内容会变化时需要传函数）。
        local function items_()
            if type(listFn) == "function" then return listFn() end
            return listFn
        end
        local b = CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", self.indent, self.y)
        SkinTextButton(b)
        -- 右端加一个下拉箭头指示，和普通按钮区分开。
        local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        arrow:SetText("|cff0cd29f▼|r")
        local bfs = b:GetFontString()
        if bfs then bfs:SetPoint("RIGHT", arrow, "LEFT", -2, 0) bfs:SetJustifyH("LEFT") bfs:SetPoint("LEFT", b, "LEFT", 8, 0) end
        local function curText()
            local cur = getter()
            for _, it in ipairs(items_()) do
                if it.value == cur then return it.text end
            end
            return cur or "（未选）"
        end
        local function refresh() b:SetText(prefix .. curText()) end
        b:SetScript("OnClick", function()
            local items = items_()
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(b, function(_, root)
                    -- 列表很长时（比如 LSM 声音）限高并出滚动条，避免撑满屏幕。
                    if root.SetScrollMode and #items > 15 then
                        root:SetScrollMode(math.min(20 * 25, (GetScreenHeight() or 768) - 100))
                    end
                    for _, it in ipairs(items) do
                        local entry = root:CreateButton(it.text, function()
                            setter(it.value); refresh()
                            if onChange then onChange() end
                        end)
                        -- 悬停试听
                        if previewFn and entry and entry.SetOnEnter then
                            entry:SetOnEnter(function() previewFn(it.value) end)
                        end
                    end
                end)
            else
                -- 退回：循环到下一个
                local cur, idx = getter(), 1
                for i, it in ipairs(items) do if it.value == cur then idx = i break end end
                local nxt = items[(idx % #items) + 1]
                if nxt then setter(nxt.value); refresh(); if onChange then onChange() end end
            end
        end)
        self.syncers[#self.syncers + 1] = refresh
        self:step(30)
        return b
    end

    -- 颜色方块：点开取色器。getter 返回 r,g,b；setter(r,g,b) 写回。
    function L:ColorSwatch(label, getter, setter, onChange)
        local btn = CreateFrame("Button", nil, self.panel)
        btn:SetSize(24, 24)
        btn:SetPoint("TOPLEFT", self.indent, self.y)
        local border = btn:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", 2, -2)
        border:SetColorTexture(unpack(SKIN_BORDER))
        btn.borderTex = border
        btn:HookScript("OnEnter", function(self) self.borderTex:SetColorTexture(unpack(SKIN_BORDER_HOVER)) end)
        btn:HookScript("OnLeave", function(self) self.borderTex:SetColorTexture(unpack(SKIN_BORDER)) end)
        local sw = btn:CreateTexture(nil, "ARTWORK")
        sw:SetAllPoints(btn)
        btn.sw = sw
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", btn, "RIGHT", 6, 0)
        fs:SetText(label)
        btn:SetScript("OnClick", function()
            local r, g, b = getter()
            ns.UI.OpenColorPicker(r, g, b, function(nr, ng, nb)
                setter(nr, ng, nb)
                sw:SetColorTexture(nr, ng, nb)
                if onChange then onChange() end
            end)
        end)
        self.syncers[#self.syncers + 1] = function()
            local r, g, b = getter()
            sw:SetColorTexture(r, g, b)
        end
        self:step(28)
        return btn
    end

    function L:Button(w, label, onClick, sameLine, anchorTo)
        local b = CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        SkinTextButton(b)
        if sameLine and anchorTo then
            b:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
        else
            b:SetPoint("TOPLEFT", self.indent, self.y)
            self:step(28)
        end
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- 动态文字行：内容由 getter() 提供，SyncAll 时刷新（用于显示会变化的状态）。
    function L:DynLabel(getter)
        local fs = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", self.indent, self.y)
        fs:SetPoint("RIGHT", self.panel, "RIGHT", -(self.indent + 6), 0)
        fs:SetJustifyH("LEFT")
        self.syncers[#self.syncers + 1] = function() fs:SetText(getter() or "") end
        self:step(22)
        return fs
    end

    return L
end

--------------------------------------------------------------------------------
-- 设置界面：父分类“白描工具箱” + 每个模块一个子分类
--------------------------------------------------------------------------------

local parentCategory

local function GetVersion()
    return (C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"
end

-- 建一个带滚动条的设置页宿主，layout 挂在滚动子面板上；返回 host, layout。
local function MakePage(name)
    local host = CreateFrame("Frame", "BaimiaoToolbox_" .. name .. "_Host")
    local child = ns.UI.MakeScrollable(host)
    local layout = ns.UI.NewLayout(child)
    -- Settings 显示的是 host，OnShow 时同步控件值。
    host:SetScript("OnShow", function() layout:SyncAll() end)
    return host, layout
end

local function BuildAbout(L)
    L:Title("白描工具箱")
    L:Text("|cff888888BaimiaoToolbox  v" .. GetVersion() .. "  ·  作者 白描|r", true)
    L:step(4)
    L:Text("白描的游戏内小工具合集。下面可勾选启用/停用各功能；左侧展开进入对应功能的详细设置。", false)
    L:step(6)
    L:Section("功能开关")
    for _, m in ipairs(ns.orderedModules) do
        local id = m.id
        L:Check(m.name or id,
            function() return ns.IsModuleEnabled(id) end,
            function(v) ns.SetModuleEnabled(id, v) end)
        if m.desc then
            L:Text("|cff999999" .. m.desc .. "|r", true)
        end
    end
    L:step(6)
    L:Section("小地图按钮")
    L:Check("在小地图边缘显示“白描工具箱”按钮（左键设置 / 右键列模块）",
        function() return ns.IsMinimapButtonShown() end,
        function(v) ns.SetMinimapButtonShown(v) end)
    L:Finalize()
end

local function BuildSettings()
    local aboutHost, aboutLayout = MakePage("about")
    BuildAbout(aboutLayout)
    aboutLayout:SyncAll()  -- 建完立即同步一次，避免首次打开勾选状态不对

    if Settings and Settings.RegisterCanvasLayoutCategory then
        parentCategory = Settings.RegisterCanvasLayoutCategory(aboutHost, "|cff0cd29f白描工具箱|r")
        parentCategory.ID = "BaimiaoToolbox"
        Settings.RegisterAddOnCategory(parentCategory)

        for _, m in ipairs(ns.orderedModules) do
            if m.BuildOptions then
                local host, layout = MakePage(m.id)
                local ok, err = pcall(m.BuildOptions, layout.panel, m, layout)
                if not ok then
                    P(("|cffff4040模块 %s 的设置页构建失败：|r%s"):format(tostring(m.id), tostring(err)))
                end
                layout:Finalize()
                layout:SyncAll()  -- 同上，先同步一次
                local sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, host, m.name or m.id)
                m._category = sub
                m._syncLayout = layout
            end
        end
    elseif InterfaceOptions_AddCategory then
        -- 旧接口回退：每个模块单独一页。
        aboutHost.name = "白描工具箱"
        InterfaceOptions_AddCategory(aboutHost)
        for _, m in ipairs(ns.orderedModules) do
            if m.BuildOptions then
                local host, layout = MakePage(m.id)
                host.name = m.name or m.id
                host.parent = "白描工具箱"
                local ok, err = pcall(m.BuildOptions, layout.panel, m, layout)
                if not ok then
                    P(("|cffff4040模块 %s 的设置页构建失败：|r%s"):format(tostring(m.id), tostring(err)))
                end
                layout:Finalize()
                layout:SyncAll()
                InterfaceOptions_AddCategory(host)
                m._legacyPanel = host
            end
        end
    end
end

-- 打开设置。传模块 id 直达其子页；不传则打开父页。
function ns.OpenOptions(moduleId)
    local m = moduleId and ns.modules[moduleId]
    if Settings and Settings.OpenToCategory then
        if m and m._category then
            if m._syncLayout then m._syncLayout:SyncAll() end
            Settings.OpenToCategory(m._category:GetID())
        elseif parentCategory then
            Settings.OpenToCategory(parentCategory:GetID())
        end
    elseif InterfaceOptionsFrame_OpenToCategory then
        local panel = (m and m._legacyPanel)
        if panel then
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    end
end

-- 自检：列出所有滑块的"取值 / 计算值 / 框内文字 / 可见性"。
-- 用于排查"数值框空白"：计算有值而框内为空 → 显示问题；计算报错 → 取值问题。
function ns.Diag()
    local list = ns._diag or {}
    P(("—— 滑块自检（共 %d 个）——"):format(#list))
    for _, f in ipairs(list) do
        local ok, line = pcall(f)
        P("  " .. (ok and line or ("|cffff4040自检出错：|r" .. tostring(line))))
    end
    if #list == 0 then P("  （没有发现滑块，可能设置页没建起来）") end
end

--------------------------------------------------------------------------------
-- 小地图按钮：左键开设置，右键列出模块直达。无 LibDBIcon 依赖，自己画一个。
--------------------------------------------------------------------------------

local minimapBtn

local function CreateMinimapButton()
    if minimapBtn then return minimapBtn end
    local pc = ns.GetPCDB()
    pc.minimap = pc.minimap or {}
    if pc.minimap.angle == nil then pc.minimap.angle = -35 end

    local b = CreateFrame("Button", "BaimiaoToolboxMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\BaimiaoToolbox\\media\\cat_icon.tga")
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    b.icon = icon

    local function UpdatePos()
        local a = math.rad(pc.minimap.angle)
        local r = (Minimap:GetWidth() / 2) + 5
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end
    b.UpdatePos = UpdatePos

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            pc.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePos()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            P("已加载模块（/bm <id> 直达设置）：")
            for _, m in ipairs(ns.orderedModules) do
                local on = ns.IsModuleEnabled(m.id)
                P(("  %s|r %s —— %s"):format(
                    on and "|cff20ff40●" or "|cffff4040●", m.id, m.name or ""))
            end
        else
            ns.OpenOptions()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff0cd29f白描工具箱|r")
        GameTooltip:AddLine("左键：打开设置", 0.6, 0.9, 1)
        GameTooltip:AddLine("右键：查看模块", 0.6, 0.9, 1)
        GameTooltip:AddLine("拖动：沿小地图边缘移动", 0.6, 0.9, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if pc.minimap.hide then b:Hide() else UpdatePos() end
    minimapBtn = b
    return b
end

-- 设置面板开关用：显隐小地图按钮（不用重载）。
function ns.SetMinimapButtonShown(show)
    local pc = ns.GetPCDB()
    pc.minimap = pc.minimap or {}
    pc.minimap.hide = not show
    if show then
        local b = CreateMinimapButton()
        b.UpdatePos()
        b:Show()
    elseif minimapBtn then
        minimapBtn:Hide()
    end
end

function ns.IsMinimapButtonShown()
    local pc = ns.GetPCDB()
    return not (pc.minimap and pc.minimap.hide)
end

--------------------------------------------------------------------------------
-- 启动
--------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    -- 单模块报错不连坐：每个 OnEnable 独立 pcall，失败的打印出来继续。
    for _, m in ipairs(ns.orderedModules) do
        local ok, err = pcall(function()
            m.db = ns.GetDB(m.id, m.defaults)
            if m.OnEnable then m.OnEnable(m) end
        end)
        if not ok then
            P(("|cffff4040模块 %s 初始化失败：|r%s"):format(tostring(m.id), tostring(err)))
        end
    end
    local ok, err = pcall(BuildSettings)
    if not ok then P("|cffff4040设置界面构建失败：|r" .. tostring(err)) end
    pcall(CreateMinimapButton)
end)

--------------------------------------------------------------------------------
-- 总斜杠命令
--------------------------------------------------------------------------------

SLASH_BAIMIAO1 = "/bm"
SLASH_BAIMIAO2 = "/baimiao"
SlashCmdList["BAIMIAO"] = function(msg)
    local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if cmd == "" then
        ns.OpenOptions()
        return
    end
    -- /bm <模块id> 直达对应设置子页
    if ns.modules[cmd] then
        ns.OpenOptions(cmd)
        return
    end
    if cmd == "minimap" then
        local shown = not ns.IsMinimapButtonShown()
        ns.SetMinimapButtonShown(shown)
        P("小地图按钮：" .. (shown and "显示" or "隐藏"))
        return
    end
    if cmd == "diag" then
        ns.Diag()
        return
    end
    P("已加载模块：")
    for _, m in ipairs(ns.orderedModules) do
        P("  " .. m.id .. " —— " .. (m.name or ""))
    end
    P("用法：/bm 打开设置，/bm <模块id> 直达该模块设置，/bm minimap 切换小地图按钮。")
end
