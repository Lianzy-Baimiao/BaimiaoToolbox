-- Auction helper presentation; uses the toolbox theme, not AceConfig or Yishier UI.
local _, ns = ...
local T = ns.L
local A, UI = ns.AuctionHouse, ns.UI
local views, editors = {}, {}
local CATEGORY_COLUMNS = ns.locale == "zhCN" and 6 or 4
local CATEGORY_HEIGHT = math.ceil(#A.categoryOrder / CATEGORY_COLUMNS) * 32 - 2
local QUICK_PAGE_SIZE = ns.locale == "zhCN" and 10 or 8
local function label(parent,value,size,role,runtime)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    local font=GameFontNormal:GetFont()
    if runtime then UI.SetRuntimeFont(f,font,size or 12) else f:SetFont(font,size or 12,"") end
    f:SetText(value);f:SetJustifyH("LEFT");f:SetWordWrap(false)
    UI.StyleText(f,role or "text")
    return f
end
-- Stable stat hues, with darker variants for the light theme. Presentation only:
-- never store color escapes in favorites, queries, or the shared catalog.
local statColors={
    ["爆"]={"ffaf65","994100"},["急"]={"65d8ff","006481"},
    ["精"]={"c3a0ff","7340a1"},["全"]={"86dea0","25683c"},
    ["爆效"]={"ffaf65","994100"},["主属性"]={"f5d879","785500"},["主属"]={"f5d879","785500"},
}
local function statText(token)
    local colors=statColors[token]
    token=T[token]
    return colors and ("|cff"..colors[UI.palette.bg[1]>.5 and 2 or 1]..token.."|r") or token
end
function A.AttributeText(entry)
    local value=A.Attributes(entry);if not value then return nil end
    local parts={}
    -- Split whole UTF-8 tokens, not a byte character class containing '·'.
    for part in (value.."·"):gmatch("(.-)·")do
        parts[#parts+1]=(part:gsub("[^/]+",statText))
    end
    return table.concat(parts,"·")
end
local function card(parent,w,h)
    local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetSize(w,h);UI.SkinCardFrame(f);return f
end
local function button(parent,value,w,h,callback)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w,h or 28);b:SetText(value);UI.SkinTextButton(b);UI.StyleText(b:GetFontString(),"text")
    b:SetScript("OnClick",callback);return b
end
local function box(parent,w,value,save)
    local f=CreateFrame("EditBox",nil,parent,"BackdropTemplate")
    f:SetSize(w,28);f:SetAutoFocus(false);f:SetFontObject(GameFontHighlightSmall or GameFontNormal)
    f:SetTextInsets(7,7,0,0);f:SetMaxLetters(240);UI.SkinCardFrame(f)
    UI.StyleText(f,"text")
    f:SetText(value or "");f.commit=function()save(f:GetText())end
    f:SetScript("OnEnterPressed",function(self)self:ClearFocus()end)
    f:SetScript("OnEscapePressed",function(self)self:SetText(self.saved or "");self:ClearFocus()end)
    f:SetScript("OnEditFocusLost",function(self)self.commit()end)
    f.saved=value or "";f._bmAuctionInput=true;return f
end
local function setBox(f,value)
    if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()==f then return end
    f.saved=tostring(value or "");f:SetText(f.saved)
end
local function tooltip(owner,id,text)
    owner:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        if id then GameTooltip:SetHyperlink("item:"..id) else GameTooltip:AddLine(text or "", nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave",function()GameTooltip:Hide()end)
end
local function notify(message)
    if message then ns.Print(message) end
end
local function changed()
    A.Stop(T["配置已修改，请重新开始"])
    if A.RefreshUI then A.RefreshUI()end
end
local function itemName(entry)
    return A.ItemName and A.ItemName(entry.itemID) or (entry.itemID and T["物品 #"]..entry.itemID or entry.query or T["未知物品"])
end
local committing=false
local function editingAllowed()
    if A.IsPurchasing and A.IsPurchasing() then notify(T["正在等待购买结果，暂时不能编辑清单。"]);return false end
    if InCombatLockdown()then return false end
    local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus._bmAuctionInput and not committing then committing=true;focus:ClearFocus();committing=false end
    return true
end
local function addFavorite(value,group)
    group=A.CategoryID(group)
    local d=A.DB();if #d.favorites>=A.MAX_ROWS then return notify(T["最多保存 100 个快捷搜索。"])end
    local id=A.ItemID(value);local query=not id and A.Clean(value,120) or nil
    if not id and (not query or query=="")then return notify(T["请输入物品链接、ID 或搜索词。"])end
    for _,v in ipairs(d.favorites)do
        if (id and v.itemID==id) or (query and v.query==query)then return notify(T["这个快捷搜索已经存在。"])end
    end
    d.favorites[#d.favorites+1]={itemID=id,query=query,group=A.Clean(group,36)~="" and A.Clean(group,36) or "常用"}
    changed()
end
local function addItem(value)
    local items=A.Plan().items;local id=A.ItemID(value)
    if not id then return notify(T["补货请使用准确的物品链接或物品 ID。"])end
    if #items>=A.MAX_ROWS then return notify(T["每套方案最多 100 项。"])end
    for _,v in ipairs(items)do if v.itemID==id then return notify(T["该物品已经在当前方案中。"])end end
    items[#items+1]={itemID=id,target=20,maxPrice=0,enabled=true};changed()
end
local function rowEditor(parent,kind,onResize)
    local e=CreateFrame("Frame",nil,parent);e:SetSize(694,200);e.editorKind=kind;e.rows={}
    local isPlan=kind=="plan"
    local titleY=0
    if not isPlan then
        e.presets=card(e,680,66);e.presets:SetPoint("TOPLEFT",0,0)
        e.presets.title=label(e.presets,"",13,"accent");e.presets.title:SetPoint("TOPLEFT",12,-10)
        local hint=label(e.presets,T["在助手中按分类查看与搜索，不需要先加入收藏。"],11,"muted")
        hint:SetPoint("TOPLEFT",12,-36);hint:SetWidth(470)
        e.presets.open=button(e.presets,T["打开快捷搜索"],140,30,function()A.OpenQuickSearch()end)
        e.presets.open:SetPoint("TOPRIGHT",-12,-17)
        titleY=-86
    end
    e.title=label(e,isPlan and T["补齐至目标数量，不是再买这么多"] or "",13,"accent")
    e.title:SetPoint("TOPLEFT",0,titleY)
    local y=titleY-32
    if isPlan then
        e.previous=button(e,"‹",28,28,function()
            if not editingAllowed()then return end
            local d=A.DB();d.selectedPlan=(d.selectedPlan-2)%#d.plans+1;changed()
        end);e.previous:SetPoint("TOPLEFT",0,y)
        e.planName=box(e,200,"",function(value)
            if editingAllowed()then A.Plan().name=A.Clean(value,60);changed()end
        end);e.planName:SetPoint("TOPLEFT",36,y)
        e.next=button(e,"›",28,28,function()
            if not editingAllowed()then return end
            local d=A.DB();d.selectedPlan=d.selectedPlan%#d.plans+1;changed()
        end);e.next:SetPoint("TOPLEFT",244,y)
        e.newPlan=button(e,T["新建方案"],88,28,function()
            if not editingAllowed()then return end
            local d=A.DB();if #d.plans>=A.MAX_PLANS then return notify(T["最多 12 套方案。"])end
            d.plans[#d.plans+1]={name=T["补货方案 "]..(#d.plans+1),items={}};d.selectedPlan=#d.plans;changed()
        end);e.newPlan:SetPoint("TOPLEFT",286,y)
        e.deletePlan=button(e,T["删除空方案"],104,28,function()
            if not editingAllowed()then return end
            local d=A.DB();if #A.Plan().items>0 then return notify(T["请先移除方案中的物品，避免误删。"])end
            if #d.plans>1 then table.remove(d.plans,d.selectedPlan);d.selectedPlan=1;changed()end
        end);e.deletePlan:SetPoint("TOPLEFT",382,y)
        y=y-40
    end
    e.input=box(e,342,"",function()end);e.input:SetPoint("TOPLEFT",0,y)
    e.input:SetMaxLetters(240)
    e.inputHint=label(e,isPlan and T["粘贴物品链接 / ID"] or T["物品链接 / ID / 搜索词"],11,"muted")
    e.inputHint:SetPoint("TOPLEFT",0,y-32)
    if not isPlan then
        e.group=box(e,100,T["常用"],function()end);e.group:SetPoint("TOPLEFT",350,y)
        local h=label(e,T["分组"],11,"muted");h:SetPoint("TOPLEFT",350,y-32)
    end
    e.add=button(e,isPlan and T["添加物品"] or T["添加收藏"],100,28,function()
        if not editingAllowed()then return end
        if isPlan then addItem(e.input:GetText()) else addFavorite(e.input:GetText(),e.group:GetText())end
        e.input:SetText("");e.input:ClearFocus()
    end);e.add:SetPoint("TOPLEFT",isPlan and 350 or 458,y)
    y=y-62
    local columns=isPlan and {{T["启用"],0},{T["物品"],50},{T["补齐至"],314},{T["限价（金，留空不限）"],388}} or {{T["物品 / 搜索词"],0},{T["分组"],314}}
    for _,c in ipairs(columns)do local h=label(e,c[1],11,"muted");h:SetPoint("TOPLEFT",c[2],y)end
    e.rowsY=y-24
    e.empty=label(e,isPlan and T["还没有补货物品。添加后设置数量和单价上限。"] or T["暂无收藏；内置预设仍可使用，可从上方打开快捷搜索。"],12,"muted")
    e.empty:SetPoint("TOPLEFT",0,e.rowsY-12)
    function e:Refresh()
        local items=isPlan and A.Plan().items or A.DB().favorites
        if isPlan then setBox(self.planName,A.Plan().name)
        else
            self.title:SetText(T["我的收藏 · "]..#items..T[" 项"])
            self.presets.title:SetText(T["内置预设 · "]..#A.catalog..T[" 项"])
        end
        self.empty:SetShown(#items==0)
        for i,entry in ipairs(items)do
            local row=self.rows[i]
            if not row then
                row=card(self,680,42);self.rows[i]=row
                if isPlan then
                    row.toggle=button(row,"",34,26,function()
                        if editingAllowed()then row.entry.enabled=not row.entry.enabled;changed()end
                    end);row.toggle:SetPoint("TOPLEFT",6,-8)
                end
                row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(24,24);row.icon:SetPoint("TOPLEFT",isPlan and 50 or 8,-9)
                row.name=label(row,"",12);row.name:SetPoint("TOPLEFT",isPlan and 82 or 40,-8);row.name:SetWidth(isPlan and 220 or 260)
                row.id=label(row,"",10,"muted");row.id:SetPoint("TOPLEFT",isPlan and 82 or 40,-24)
                if isPlan then
                    row.target=box(row,66,"",function(value)
                        if not editingAllowed()then return end
                        local n=A.Integer(value,1,A.MAX_QUANTITY)
                        if n then row.entry.target=n;changed()else setBox(row.target,row.entry.target);notify(T["目标数量须为 1–100000 的整数。"])end
                    end);row.target:SetPoint("TOPLEFT",314,-7)
                    row.price=box(row,110,"",function(value)
                        if not editingAllowed()then return end
                        local n=A.Gold(value=="" and "0" or value)
                        if n then row.entry.maxPrice=n;changed()else setBox(row.price,row.entry.maxPrice/10000);notify(T["单价请填写非负金币数，最多四位小数。"])end
                    end);row.price:SetPoint("TOPLEFT",388,-7)
                else
                    row.group=box(row,184,"",function(value)
                        if editingAllowed()then row.entry.group=A.Clean(value,36);changed()end
                    end);row.group:SetPoint("TOPLEFT",314,-7)
                end
                row.up=button(row,"↑",28,26,function()
                    if not editingAllowed()then return end
                    local list=isPlan and A.Plan().items or A.DB().favorites;local n=row.index
                    if n>1 then list[n],list[n-1]=list[n-1],list[n];changed()end
                end);row.up:SetPoint("TOPLEFT",518,-8)
                row.down=button(row,"↓",28,26,function()
                    if not editingAllowed()then return end
                    local list=isPlan and A.Plan().items or A.DB().favorites;local n=row.index
                    if n<#list then list[n],list[n+1]=list[n+1],list[n];changed()end
                end);row.down:SetPoint("TOPLEFT",552,-8)
                row.delete=button(row,T["移除"],58,26,function()
                    if not editingAllowed()then return end
                    table.remove(isPlan and A.Plan().items or A.DB().favorites,row.index);changed()
                end);row.delete:SetPoint("TOPLEFT",594,-8)
            end
            row.entry=entry;row.index=i;row:SetPoint("TOPLEFT",0,self.rowsY-(i-1)*48);row:Show()
            row.name:SetText(itemName(entry));row.id:SetText(entry.itemID and "#"..entry.itemID or T["关键词搜索"])
            row.icon:SetTexture(A.ItemIcon and A.ItemIcon(entry.itemID) or 134400)
            if isPlan then row.toggle:SetText(entry.enabled and T["开"] or T["关"]);setBox(row.target,entry.target);setBox(row.price,(entry.maxPrice or 0)>0 and entry.maxPrice/10000 or "")
            else setBox(row.group,entry.group)end
            tooltip(row,entry.itemID,entry.query);row:EnableMouse(true)
        end
        for i=#items+1,#self.rows do self.rows[i]:Hide()end
        self:SetHeight(-self.rowsY+math.max(1,#items)*48+8)
        if onResize then onResize(self:GetHeight())end
    end
    editors[#editors+1]=e;e:Refresh();return e
end
function A.BuildOptions(panel,m,L)
    L:Row({
        function(c)c:Check(T["打开拍卖行时显示助手"],function()return A.DB().showPanel end,function(v)A.DB().showPanel=v;A.SyncPanel()end)end,
        function(c)c:Button(150,T["打开助手 / 预览布局"],function()A.ShowPanel(true)end)end,
    },260)
    L:Row({
        function(c)c:Check(T["快捷搜索"],function()return A.DB().quickSearch end,function(v)A.DB().quickSearch=v;A.RefreshUI()end)end,
        function(c)c:Check(T["清单补货"],function()return A.DB().restock end,function(v)A.DB().restock=v;if not v then A.Stop(T["补货已关闭"])end;A.RefreshUI()end)end,
    },260)
    L:Row({
        function(c)
            c:Text(T["本次采购预算（金，0 不限制总额）"],true)
            c:Box(180,24,false,function()return tostring(A.DB().sessionBudget/10000)end,function(value)
                local n=A.Gold(value);if n then A.DB().sessionBudget=n;changed()else notify(T["预算请输入非负金币数。"])end
            end)
        end,
        function(c)c:Text(T["限价可不填。显示数量和总价后点一次购买；最终报价涨价不买。邮箱未同步时不扣除未知邮件。"],true)end,
    },280)
    local tabs=UI.OptionTabs(panel,L,{
        {name=T["快捷搜索"],width=120,build=function(child,layout,resize)
            local e=rowEditor(child,"quick",function(h)layout.y=-h-16;if child:IsShown()then layout:Finalize();resize()end end)
            e:SetPoint("TOPLEFT",16,-12);layout.y=-e:GetHeight()-16
            child:HookScript("OnShow",function()e:Refresh()end)
        end},
        {name=T["补货方案"],width=120,build=function(child,layout,resize)
            local e=rowEditor(child,"plan",function(h)layout.y=-h-16;if child:IsShown()then layout:Finalize();resize()end end)
            e:SetPoint("TOPLEFT",16,-12);layout.y=-e:GetHeight()-16
            child:HookScript("OnShow",function()e:Refresh()end)
        end},
    });m.optionTabs=tabs
    L.syncers[#L.syncers+1]=function()A.RefreshUI()end
end
local panel
local returnFromSettings=false
-- Dock as a real child, not an independent UIParent window with copied numbers.
-- The engine then propagates native Raise/Lower, strata, visibility and render
-- grouping immediately. Never poll/reset the level: that fights native stacking.
local function attachPanel(f)
    local ah=AuctionHouseFrame;local attached=ah and ah:IsShown()
    local parent=attached and ah or UIParent
    if f:GetParent()==parent then return true end
    -- Reparenting a window under native UI must not happen during lockdown.
    if InCombatLockdown()then return false end
    f:SetFixedFrameStrata(false);f:SetFixedFrameLevel(false)
    f:SetParent(parent)
    f:SetToplevel(not attached)
    f:SetFrameStrata(attached and parent:GetFrameStrata() or "DIALOG")
    f:SetFrameLevel(attached and (parent:GetFrameLevel()+1) or f.previewLevel)
    f:SetFixedFrameStrata(not attached)
    return true
end
-- Keep all coordinates in the helper's local scale, including persisted offsets.
-- WoW movement APIs detach relative anchors, so restore AH attachment after drag.
function A.LayoutPanel(force)
    if not panel then return end
    if InCombatLockdown()then return false end
    local f=panel;if not attachPanel(f)then return false end
    if f.dragging then return end
    local ah=AuctionHouseFrame;local attached=ah and ah:IsShown()
    local height,scale=584,math.min(1,(UIParent:GetWidth()-32)/424,(UIParent:GetHeight()-32)/584)
    if attached then
        height=ah:GetHeight()
        -- Native scale is now inherited through the parent (do not apply twice).
        -- Small AH frames scale the whole design down rather than clip controls.
        scale=math.min(1,height/584);height=math.max(584,height)
    end
    local d=ns.GetLayoutDB("auctionhouse")
    local x,y=attached and (d.dockX or 10) or (d.x or 260),attached and (d.dockY or 0) or (d.y or 0)
    if not force and f.layoutHeight==height and f.layoutScale==scale and f.layoutParent==f:GetParent() and f.layoutX==x and f.layoutY==y then return end
    f.layoutHeight=height;f.layoutScale=scale;f.layoutParent=f:GetParent();f.layoutX=x;f.layoutY=y
    f:SetScale(scale);f:SetHeight(height);f:SetClampedToScreen(not attached)
    f:ClearAllPoints()
    if attached then f:SetPoint("TOPLEFT",ah,"TOPRIGHT",x,y)
    elseif d.moved and d.point then f:SetPoint(d.point,UIParent,d.relPoint or d.point,x,y)
    else f:SetPoint("CENTER",UIParent,"CENTER",260,0)end
    -- Content keeps its readable size; bottom controls follow the matching height.
    f.prev:ClearAllPoints();f.prev:SetPoint("BOTTOMLEFT",18,80)
    f.next:ClearAllPoints();f.next:SetPoint("BOTTOMLEFT",92,80)
    f.pageLabel:ClearAllPoints();f.pageLabel:SetPoint("BOTTOMRIGHT",-18,84)
    f.status:ClearAllPoints();f.status:SetPoint("BOTTOMLEFT",18,44)
end
local function buildPanel()
    if panel then return panel end
    local f=card(UIParent,424,584);f:SetFrameStrata("DIALOG");f:SetFixedFrameStrata(true);f:SetToplevel(true)
    f:SetClampedToScreen(true);f:SetMovable(true);f:EnableMouse(true)
    panel=f;A.panel=f;f.previewLevel=f:GetFrameLevel();f.tab="quick";f.page=1;f.group="全部"
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent",function()
        local request=f.pendingShow;f.pendingShow=nil
        if request and ns.IsModuleEnabled("auctionhouse") and (request=="preview" or A.IsOpen())then
            A.ShowPanel(request=="preview")
        end
    end)
    f:HookScript("OnHide",function()f.pendingShow=nil end)
    local title=label(f,T["拍卖行助手"],19,"text",true);title:SetPoint("TOPLEFT",18,-17)
    local kicker=label(f,T["白描 / AUCTION COMPANION"],10,"accent",true);kicker:SetPoint("TOPLEFT",18,-42)
    f.drag=CreateFrame("Frame",nil,f);f.drag:SetPoint("TOPLEFT",0,0);f.drag:SetSize(330,58);f.drag:EnableMouse(true);f.drag:RegisterForDrag("LeftButton")
    f.drag:SetScript("OnDragStart",function()if not InCombatLockdown()then f.dragging=true;f:StartMoving()end end)
    f.drag:SetScript("OnDragStop",function()
        f:StopMovingOrSizing();f.dragging=false
        local d=ns.GetLayoutDB("auctionhouse");local ah=AuctionHouseFrame
        if ah and ah:IsShown()then
            local left,top,right,ahTop=f:GetLeft(),f:GetTop(),ah:GetRight(),ah:GetTop()
            if left and top and right and ahTop then
                local factor=ah:GetEffectiveScale()/f:GetEffectiveScale()
                d.dockX=left-right*factor;d.dockY=top-ahTop*factor
            end
        else
            local p,_,rp,x,y=f:GetPoint();d.point=p;d.relPoint=rp;d.x=x;d.y=y;d.moved=true
        end
        A.LayoutPanel(true)
    end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+dt
        if elapsed>=.15 then elapsed=0;A.LayoutPanel()end
    end)
    f.close=button(f,"×",28,28,function()A.Stop(T["助手已关闭"]);f:Hide()end);f.close:SetPoint("TOPRIGHT",-12,-12)
    f.settings=button(f,T["设置"],ns.locale=="enUS" and 72 or 52,26,function()ns.OpenOptions("auctionhouse")end);f.settings:SetPoint("TOPRIGHT",-48,-13)
    f.tabs={}
    for i,entry in ipairs({{"quick",T["快捷搜索"]},{"restock",T["清单补货"]},{"recipes",T["追踪补货"]}})do
        local key=entry[1];local b=button(f,entry[2],124,34,function()
            if not editingAllowed()then return end
            if not A.SetPurchaseSource(key=="recipes" and "recipes" or "manual")then return end
            f.tab=key;f.page=1;f.restock.planMenu:Hide();f.restock.recipeHeader.menu:Hide();A.RefreshUI()
        end)
        b:SetPoint("TOPLEFT",18+(i-1)*132,-68);f.tabs[key]=b
        b.edge=b:CreateTexture(nil,"OVERLAY");b.edge:SetPoint("BOTTOMLEFT",4,0);b.edge:SetPoint("BOTTOMRIGHT",-4,0);b.edge:SetHeight(2)
        UI.OnTheme(function()b.edge:SetColorTexture(unpack(UI.palette.accent))end)
    end
    f.quick=CreateFrame("Frame",nil,f);f.quick:SetPoint("TOPLEFT",18,-116);f.quick:SetSize(388,364);f.quick.buttons={}
    -- Direct category tabs: no hidden cycling. Extra user groups scroll here,
    -- all built-in tabs remain visible, with wider columns for longer locales.
    f.quick.categoryScroll=CreateFrame("ScrollFrame",nil,f.quick)
    f.quick.categoryScroll:SetPoint("TOPLEFT",0,0);f.quick.categoryScroll:SetSize(388,CATEGORY_HEIGHT)
    f.quick.categoryContent=CreateFrame("Frame",nil,f.quick.categoryScroll)
    f.quick.categoryContent:SetPoint("TOPLEFT",0,0);f.quick.categoryContent:SetSize(388,CATEGORY_HEIGHT)
    f.quick.categoryScroll:SetScrollChild(f.quick.categoryContent);f.quick.categories={}
    f.quick.categoryScroll:EnableMouseWheel(true)
    f.quick.categoryScroll:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(f.quick.categoryContent:GetHeight()-CATEGORY_HEIGHT,self:GetVerticalScroll()-delta*32)))
    end)
    f.quick.search=box(f.quick,296,"",function()end);f.quick.search:SetPoint("TOPLEFT",0,-CATEGORY_HEIGHT-8)
    local function searchText()
        local value=f.quick.search:GetText();local id=A.ItemID(value)
        local query=not id and A.Clean(value,120) or nil
        if id or (query and query~="")then A.QuickSearch({itemID=id,query=query})end
        f.quick.search:ClearFocus()
    end
    f.quick.search:SetScript("OnEnterPressed",searchText)
    f.quick.searchButton=button(f.quick,T["搜索"],84,28,searchText);f.quick.searchButton:SetPoint("TOPLEFT",304,-CATEGORY_HEIGHT-8)
    f.quick.searchHint=label(f.quick.search,T["输入名称 / 链接 / ID"],11,"muted",true);f.quick.searchHint:SetPoint("LEFT",8,0)
    f.quick.search:SetScript("OnTextChanged",function(self)f.quick.searchHint:SetShown(self:GetText()=="")end)
    for i=1,QUICK_PAGE_SIZE do
        local b=button(f.quick,"",190,44,function(self)if self.entry then A.QuickSearch(self.entry)end end)
        b:SetPoint("TOPLEFT",((i-1)%2)*198,-CATEGORY_HEIGHT-48-math.floor((i-1)/2)*50)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(28,28);b.icon:SetPoint("LEFT",8,0)
        b.name=label(b,"",12,"text",true);b.name:SetPoint("TOPLEFT",44,-8);b.name:SetWidth(112)
        b.sub=label(b,"",10,"muted",true);b.sub:SetPoint("TOPLEFT",44,-27);b.sub:SetWidth(112)
        b.favorite=button(b,T["藏"],24,24,function()
            if not b.entry or not editingAllowed()then return end
            local list=A.DB().favorites;local key=A.SearchKey(b.entry)
            for n,entry in ipairs(list)do
                if A.SearchKey(entry)==key then table.remove(list,n);A.RefreshUI();return end
            end
            addFavorite(b.entry.itemID or b.entry.query,b.entry.group)
        end);b.favorite:SetPoint("TOPRIGHT",-3,-10)
        f.quick.buttons[i]=b
    end
    f.quick.empty=label(f.quick,T["暂无收藏，点击物品旁的 ＋ 添加"],12,"muted",true);f.quick.empty:SetPoint("TOPLEFT",0,-126)
    f.restock=CreateFrame("Frame",nil,f);f.restock:SetPoint("TOPLEFT",18,-116);f.restock:SetSize(388,364);f.restock.rows={}
    f.restock.plan=button(f.restock,"",388,28,function()
        if not editingAllowed()then return end
        local menu=f.restock.planMenu
        if menu:IsShown()then menu:Hide();return end
        for i,plan in ipairs(A.DB().plans)do
            local b=menu.buttons[i]
            if not b then
                b=button(menu,"",376,26,function(self)
                    if not editingAllowed()then return end
                    A.DB().selectedPlan=self.index;menu:Hide();f.page=1;changed()
                end);menu.buttons[i]=b;b:SetPoint("TOPLEFT",6,-6-(i-1)*30)
            end
            b.index=i;b:SetText(plan.name);b:Show()
        end
        for i=#A.DB().plans+1,#menu.buttons do menu.buttons[i]:Hide()end
        menu:SetHeight(#A.DB().plans*30+10);menu:Show()
    end);f.restock.plan:SetPoint("TOPLEFT",0,0)
    f.restock.planMenu=card(f.restock,388,40);f.restock.planMenu:SetPoint("TOPLEFT",0,-32)
    f.restock.planMenu:SetFrameLevel(f.restock:GetFrameLevel()+20);f.restock.planMenu.buttons={};f.restock.planMenu:Hide()
    f.restock.hint=label(f.restock,T["库存按背包计算 · 邮箱未同步"],11,"muted",true);f.restock.hint:SetPoint("TOPLEFT",0,-38)
    for i=1,6 do
        local row=card(f.restock,388,44);row:SetPoint("TOPLEFT",0,-60-(i-1)*48)
        row.name=label(row,"",12,"text",true);row.name:SetPoint("TOPLEFT",9,-6);row.name:SetWidth(ns.locale=="enUS" and 184 or 196)
        row.count=label(row,"",10,"muted",true);row.count:SetPoint("TOPLEFT",9,-26);row.count:SetWidth(ns.locale=="enUS" and 202 or 214)
        row.limit=label(row,"",11,"muted",true);row.limit:SetPoint("TOPRIGHT",ns.locale=="enUS" and -78 or -66,-6);row.limit:SetWidth(104);row.limit:SetJustifyH("RIGHT")
        row.status=label(row,"",11,"accent",true);row.status:SetPoint("TOPRIGHT",ns.locale=="enUS" and -78 or -66,-26);row.status:SetJustifyH("RIGHT");row.status:SetWidth(88)
        row.retry=button(row,T["重新核算"],74,22,function()
            if row.entry then A.ResetReservation(row.entry.itemID)end
        end);row.retry:SetPoint("TOPRIGHT",-64,-19);row.retry:Hide()
        tooltip(row.retry,nil,T["仅在确认上笔订单已处理后使用。会清除这一项的在途标记；邮件延迟时重买可能重复采购。"])
        row.search=button(row,T["搜索"],ns.locale=="enUS" and 60 or 48,28,function()
            if row.entry then A.SearchRestockItem(row.entry)end
        end);row.search:SetPoint("TOPRIGHT",-8,-8)
        f.restock.rows[i]=row
    end
    f.restock.empty=label(f.restock,T["还没有补货清单，点击右上角设置添加。"],12,"muted",true);f.restock.empty:SetPoint("TOPLEFT",0,-80)
    local rh=CreateFrame("Frame",nil,f.restock);f.restock.recipeHeader=rh;rh:SetPoint("TOPLEFT",0,0);rh:SetSize(388,126)
    rh.select=button(rh,T["全部追踪配方"],388,28,function()
        if not editingAllowed()then return end
        local menu=rh.menu;if menu:IsShown()then menu:Hide();return end
        local entries={{key="all",name=T["全部追踪配方"]}}
        for _,recipe in ipairs(A.Recipes.Plan().recipes)do entries[#entries+1]=recipe end
        for i,entry in ipairs(entries)do
            local b=menu.buttons[i]
            if not b then
                b=button(menu.content,"",372,26,function(self)
                    if editingAllowed()then A.Recipes.Configure(nil,nil,self.key);menu:Hide();f.page=1;A.RefreshUI()end
                end);menu.buttons[i]=b;b:SetPoint("TOPLEFT",2,-(i-1)*30)
                b:GetFontString():SetWidth(350)
            end
            b.key=entry.key;b:SetText(entry.name);b:Show()
        end
        for i=#entries+1,#menu.buttons do menu.buttons[i]:Hide()end
        local height=math.min(240,#entries*30)
        menu:SetHeight(height+12);menu.scroll:SetHeight(height);menu.content:SetHeight(#entries*30)
        menu.scroll:SetVerticalScroll(0);menu:Show()
    end);rh.select:SetPoint("TOPLEFT",0,0);rh.select:GetFontString():SetWidth(358)
    rh.menu=card(rh,388,40);local menu=rh.menu;menu:SetPoint("TOPLEFT",0,-32);menu:SetFrameLevel(rh:GetFrameLevel()+30)
    menu.scroll=CreateFrame("ScrollFrame",nil,menu);menu.scroll:SetPoint("TOPLEFT",6,-6);menu.scroll:SetSize(376,30)
    menu.content=CreateFrame("Frame",nil,menu.scroll);menu.content:SetSize(376,30);menu.scroll:SetScrollChild(menu.content);menu.buttons={}
    menu.scroll:EnableMouseWheel(true);menu.scroll:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(menu.content:GetHeight()-self:GetHeight(),self:GetVerticalScroll()-delta*30)))
    end);menu:Hide()
    local qualityLabel=label(rh,T["品质"],11,"muted",true);qualityLabel:SetPoint("TOPLEFT",0,-47)
    rh.quality={}
    for rank=1,5 do
        local b=button(rh,rank==5 and T["最高"] or (rank..T["阶"]),43,26,function()
            if editingAllowed()then A.Recipes.Configure(rank);f.page=1;A.RefreshUI()end
        end);b:SetPoint("TOPLEFT",34+(rank-1)*47,-38);rh.quality[rank]=b
        b.active=b:CreateTexture(nil,"OVERLAY");b.active:SetPoint("BOTTOMLEFT",3,0);b.active:SetPoint("BOTTOMRIGHT",-3,0);b.active:SetHeight(2)
        UI.OnTheme(function()b.active:SetColorTexture(unpack(UI.palette.accent))end)
        tooltip(b,nil,T["默认最高，超出档位取最高。\n金色图标≠五星。\n按所选品质扣库存，不保证成品品质。"])
    end
    local craftsLabel=label(rh,T["份数"],11,"muted",true);craftsLabel:SetPoint("TOPLEFT",278,-47)
    rh.crafts=box(rh,70,"1",function(value)
        if not editingAllowed()then return end
        if not A.Recipes.Configure(nil,value)then notify(T["制作份数须为 1–1000 的整数。"])end
        setBox(rh.crafts,A.Recipes.Crafts());f.page=1;A.RefreshUI()
    end);rh.crafts:SetPoint("TOPLEFT",318,-37)
    tooltip(rh.crafts,nil,T["每个选中配方的制作次数，不是成品数量。默认每个制作 1 次。"])
    rh.summary=label(rh,"",11,"muted",true);rh.summary:SetPoint("TOPLEFT",0,-76);rh.summary:SetSize(388,42);rh.summary:SetWordWrap(true)
    rh:EnableMouse(true);rh:Hide()

    f.prev=button(f,T["上一页"],66,24,function()f.page=math.max(1,f.page-1);A.RefreshUI()end);f.prev:SetPoint("TOPLEFT",18,-480)
    f.next=button(f,T["下一页"],66,24,function()f.page=f.page+1;A.RefreshUI()end);f.next:SetPoint("TOPLEFT",92,-480)
    f.pageLabel=label(f,"",11,"muted",true);f.pageLabel:SetPoint("TOPRIGHT",-18,-486)
    f.status=label(f,"",11,"muted",true);f.status:SetPoint("TOPLEFT",18,-512);f.status:SetSize(388,28);f.status:SetWordWrap(true)
    f.action=button(f,T["开始补货"],232,30,function()
        if f.tab=="quick"then ns.OpenOptions("auctionhouse");ns.modules.auctionhouse.optionTabs.Select(1)
        else A.Action()end
    end);f.action:SetPoint("BOTTOMLEFT",18,10)
    f.stop=button(f,T["停止"],62,30,function()A.Stop(T["已停止"]);A.RefreshUI()end);f.stop:SetPoint("BOTTOMLEFT",258,10)
    f.spent=label(f,"",10,"muted",true);f.spent:SetPoint("BOTTOMRIGHT",-16,18);f.spent:SetWidth(80);f.spent:SetJustifyH("RIGHT")
    f:Hide();views[#views+1]=f;return f
end
function A.ShowPanel(preview)
    if not ns.IsModuleEnabled("auctionhouse")then return notify(T["请先启用拍卖行助手。"])end
    local f=buildPanel()
    local settings=BaimiaoToolboxWorkspace
    if settings and settings:IsShown()then
        if not preview then returnFromSettings=true;f:Hide();return end
        returnFromSettings=false;settings:Hide()
    end
    if A.LayoutPanel(true)==false then f.pendingShow=preview and "preview" or "auto";return end
    f.pendingShow=nil;f:Show();A.RefreshUI()
end
function A.OpenQuickSearch()
    if not editingAllowed() or not ns.IsModuleEnabled("auctionhouse")then return end
    if not A.SetPurchaseSource("manual")then return end
    A.Stop(T["选择分类或物品开始搜索"])
    local f=buildPanel();f.tab="quick";f.group="全部";f.page=1
    f.restock.planMenu:Hide();f.restock.recipeHeader.menu:Hide()
    A.ShowPanel(true)
end
function A.OnWorkspaceShow()
    if panel then panel.pendingShow=nil end
    if panel and panel:IsShown()then
        returnFromSettings=true;panel:Hide()
        if A.IsBusy() and not A.IsPurchasing()then A.Stop(T["配置完成后可重新开始补货"])end
    end
end
function A.OnWorkspaceHide()
    if returnFromSettings then
        returnFromSettings=false
        if A.IsOpen()then A.ShowPanel()end
    end
end
function A.SyncPanel()
    if A.IsOpen and A.IsOpen() and A.DB().showPanel and ns.IsModuleEnabled("auctionhouse")then A.ShowPanel()
    elseif panel then panel.pendingShow=nil;panel:Hide()end
end
local refreshing=false
function A.RefreshUI()
    if refreshing then return end
    refreshing=true
    for _,e in ipairs(editors)do if e:IsVisible()then e:Refresh()end end
    local f=panel
    if f then
        local d=A.DB();local quick=f.tab=="quick";local recipes=f.tab=="recipes"
        f.quick:SetShown(quick);f.restock:SetShown(not quick)
        for key,b in pairs(f.tabs)do b.edge:SetShown(key==f.tab)end
        local list={};local size=quick and QUICK_PAGE_SIZE or (recipes and 4 or 6)
        if quick then
            local groups=A.Categories();local valid=false
            for _,group in ipairs(groups)do if f.group==group then valid=true end end
            if not valid then f.group="全部"end
            list=A.SearchEntries(f.group)
            f.quick.categoryContent:SetHeight(math.ceil(#groups/CATEGORY_COLUMNS)*32)
            for i,group in ipairs(groups)do
                local b=f.quick.categories[i]
                if not b then
                    b=button(f.quick.categoryContent,"",(388+2)/CATEGORY_COLUMNS-5,26,function(self)
                        f.group=self.group;f.page=1;A.RefreshUI()
                    end);f.quick.categories[i]=b
                    b.active=b:CreateTexture(nil,"OVERLAY");b.active:SetPoint("BOTTOMLEFT",3,0);b.active:SetPoint("BOTTOMRIGHT",-3,0);b.active:SetHeight(2)
                    UI.OnTheme(function()b.active:SetColorTexture(unpack(UI.palette.accent))end)
                end
                b.group=group;b:SetText(A.CategoryName(group));b:SetPoint("TOPLEFT",((i-1)%CATEGORY_COLUMNS)*(390/CATEGORY_COLUMNS),-math.floor((i-1)/CATEGORY_COLUMNS)*32)
                b:Show();b.active:SetShown(group==f.group)
            end
            for i=#groups+1,#f.quick.categories do f.quick.categories[i]:Hide()end
        else
            local plan=recipes and A.Recipes.Plan() or A.Plan()
            for _,entry in ipairs(plan.items)do if entry.enabled then list[#list+1]=entry end end
            f.restock.plan:SetShown(not recipes);f.restock.hint:SetShown(not recipes);f.restock.recipeHeader:SetShown(recipes)
            f.restock.plan:SetText((A.Plan().name or T["补货方案"]).."  ›")
            if recipes then
                local rh=f.restock.recipeHeader
                rh.select:SetText(plan.selectionName or T["追踪配方"]);setBox(rh.crafts,A.Recipes.Crafts())
                for rank,b in ipairs(rh.quality)do b.active:SetShown(rank==A.Recipes.Quality())end
                rh.summary:SetText(T["基础材料 · "]..plan.recipeCount..T[" 个配方 · 每个 "]..A.Recipes.Crafts()..T[" 次\n"]..
                    (#plan.warnings>0 and (T["另有 "]..#plan.warnings..T[" 项需自行准备（悬停查看）"]) or T["扣除背包 / 银行可见库存与已知邮件"]))
                tooltip(rh,nil,#plan.warnings>0 and table.concat(plan.warnings,"\n") or T["只补必需基础材料；可选材料与成品品质不在配方追踪数据中。未同步的邮件不计入库存。"])
            end
        end
        local pages=math.max(1,math.ceil(#list/size));f.page=math.min(f.page,pages)
        f.prev:SetEnabled(f.page>1);f.next:SetEnabled(f.page<pages);f.pageLabel:SetText(f.page.." / "..pages.." · "..#list..T[" 项"])
        if quick then
            f.quick.empty:SetShown(#list==0)
            for i,b in ipairs(f.quick.buttons)do
                local entry=list[(f.page-1)*size+i];b:SetShown(entry~=nil);b.entry=entry
                if entry then
                    local attributes=A.AttributeText(entry)
                    b.name:SetText(itemName(entry));b.icon:SetTexture(A.ItemIcon(entry.itemID))
                    local groupName=A.CategoryName(entry.group or "常用")
                    b.sub:SetText(ns.locale~="zhCN" and attributes or (attributes and (groupName.." · "..attributes) or groupName))
                    local saved=false
                    for _,v in ipairs(d.favorites)do if A.SearchKey(v)==A.SearchKey(entry)then saved=true;break end end
                    b.favorite:SetText(saved and "★" or "＋")
                    b:SetEnabled(A.IsOpen() and d.quickSearch and not A.IsPurchasing());tooltip(b,entry.itemID,entry.query)
                end
            end
        else
            f.restock.hint:SetText(A.MailKnown() and T["库存已包含扫描的邮件与本次已购"] or T["邮箱未同步 · 按背包与本次已购补货"])
            f.restock.empty:SetShown(#list==0)
            f.restock.empty:SetText(recipes and T["在专业面板追踪配方后，材料自动出现在这里。"] or T["没有启用的补货项目，在设置中添加或启用。"])
            f.restock.empty:ClearAllPoints();f.restock.empty:SetPoint("TOPLEFT",0,recipes and -138 or -80)
            for i,row in ipairs(f.restock.rows)do
                local index=(f.page-1)*size+i;local entry=i<=size and list[index] or nil;row.entry=entry;row:SetShown(entry~=nil)
                row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-(recipes and 132 or 60)-(i-1)*48)
                if entry then
                    local owned,mail,need,known=A.Inventory(entry.itemID,entry.target,entry.includeBank)
                    row.name:SetText(itemName(entry)..A.Recipes.QualityLabel(entry));tooltip(row,entry.itemID);row:EnableMouse(true);row.count:SetText(T["持有 "]..(owned or "?")..T[" · 在邮 "]..(known and mail or (mail>0 and (mail.."+") or "?"))..T[" · 待补 "]..(need or "?"))
                    row.search:SetEnabled(A.IsOpen() and not A.IsPurchasing() and not InCombatLockdown())
                    row.limit:SetText((entry.maxPrice or 0)>0 and ("≤ "..A.Money(entry.maxPrice)) or T["不限价"])
                    local reserved=A.HasReservation(entry.itemID)
                    row.retry:SetShown(reserved);row.status:SetShown(not reserved)
                    row.status:SetText(A.StatusFor(entry.itemID) or (need==0 and T["已备齐"] or T["待查询"]))
                end
            end
        end
        local action,enabled,message=A.ActionState()
        f.action:SetText(quick and T["编辑我的收藏"] or action);f.action:SetEnabled(quick or (enabled and d.restock))
        f.status:SetText(quick and (statText(T["爆"])..T["=暴击 · "]..statText(T["急"])..T["=急速 · "]..statText(T["精"])..T["=精通 · "]..statText(T["全"])..T["=全能；悬停看详情"]) or message)
        f.spent:SetText(A.Money(A.Spent()));f.spent:SetShown(not quick)
        f.stop:SetShown(not quick);f.stop:SetEnabled(A.IsBusy())
    end
    refreshing=false
end
-- Inline color escapes need a text refresh as well as the normal font repaint.
UI.OnTheme(function()A.RefreshUI()end)
