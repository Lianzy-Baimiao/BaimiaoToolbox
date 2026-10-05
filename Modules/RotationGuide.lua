-- Editable skill-order cards with passive cooldown display; never cast or recommend.
local ADDON, ns = ...
local T = ns.L
local ID = "rotation"
local MAX_SLOTS = 6
local presets = {
    { name=T["惩戒骑 · 单体"], sequence="20271 > 184575 > 31884 + 255937 > 343527 > 383328 > 375576 > 383328" },
    { name=T["惩戒骑 · AOE 第一套"], sequence="20271 > 184575 > 31884 + 255937 > 383328 + 53385*1-2 > 343527 > 375576" },
    { name=T["惩戒骑 · AOE 第二套"], sequence="20271 > 184575 > 31884 + 255937 > 343527 > 383328 > 375576 > 53385" },
}
local defaults = {
    show=true, showCooldowns=true, size=38, showNames=false,
    showTitles=true, opacity=0.9, hideBackgroundLocked=false, scalePercent=100, profiles={},
}
local function CurrentSpec()
    local index=GetSpecialization and GetSpecialization()
    return index and GetSpecializationInfo and GetSpecializationInfo(index) or nil
end
local function freshRows(spec)
    local rows={}
    for i=1,MAX_SLOTS do
        local preset=spec==70 and presets[i]
        rows[i]={enabled=false,name=preset and preset.name or (T["方案 "]..i),sequence=preset and preset.sequence or "",note="",showNote=false}
    end
    return rows
end
local function copyRow(row)
    return {enabled=row.enabled,name=row.name,sequence=row.sequence,note=row.note or "",showNote=row.showNote==true}
end
local function copyRows(rows)
    local result={}
    for i,row in ipairs(rows) do
        result[i]=copyRow(row)
    end
    return result
end
local function DB()
    local d=ns.GetDB(ID,defaults)
    if not d.profileVersion then
        -- Old global rows had no specialization identity. Keep an untouched backup.
        if d.rows then
            d.legacyRows=copyRows(d.rows)
            d.profiles["70"]=d.profiles["70"] or {rows=copyRows(d.rows)}
            local current=CurrentSpec()
            if current and current~=70 then
                local custom=freshRows(current)
                for i,row in ipairs(d.rows) do
                    if row.sequence~="" and (not presets[i] or row.sequence~=presets[i].sequence) then
                        custom[i]=copyRow(row)
                    end
                end
                d.profiles[tostring(current)]=d.profiles[tostring(current)] or {rows=custom}
            end
        end
        d.profileVersion=1
    end
    return d
end
local function Profile(spec)
    if not spec then return nil end
    local profiles=DB().profiles
    local key=tostring(spec)
    profiles[key]=profiles[key] or {rows=freshRows(spec)}
    return profiles[key]
end
local function ActiveRows()
    local profile=Profile(CurrentSpec())
    return profile and profile.rows or {}
end
-- The editor selection never changes the active gameplay profile.
local editorSpec,editorClass
local function EditorRows() return Profile(editorSpec or CurrentSpec() or 70).rows end
local function Classes()
    local list={}
    for i=1,(GetNumClasses and GetNumClasses() or 0) do
        local name,_,id=GetClassInfo(i)
        if name then list[#list+1]={value=id,text=name} end
    end
    return list
end
local function Specs(classID)
    local list={}
    for i=1,(GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(classID) or 0) do
        local id,name=GetSpecializationInfoForClassID(classID,i)
        if id then list[#list+1]={value=id,text=name} end
    end
    return list
end
local function Layout() return ns.GetLayoutDB(ID) end
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function literal(s)
    -- User-provided labels are plain text, not WoW texture/hyperlink markup.
    return tostring(s or ""):gsub("|","||"):gsub("[\r\n]"," ")
end
-- Whitespace bounds a skill token. Standalone punctuation/symbol tokens are
-- separators, not unknown spells; never use live spell-cache readiness to decide
-- whether a token is retained. UTF-8 is decoded here because Lua 5.1 %p is ASCII.
local function SymbolToken(token)
    for ch in token:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local a,b,c,d=ch:byte(1,4)
        local cp=a
        if a>=240 and d then cp=(a-240)*262144+(b-128)*4096+(c-128)*64+d-128
        elseif a>=224 and c then cp=(a-224)*4096+(b-128)*64+c-128
        elseif a>=192 and b then cp=(a-192)*64+b-128 end
        local symbol=(cp<128 and ch:match("%p"))
            or (cp>=0x2000 and cp<=0x206F) or (cp>=0x20A0 and cp<=0x2BFF)
            or (cp>=0x3000 and cp<=0x303F) or (cp>=0xFE00 and cp<=0xFE6F)
            or (cp>=0xFF01 and cp<=0xFF0F) or (cp>=0xFF1A and cp<=0xFF20)
            or (cp>=0xFF3B and cp<=0xFF40) or (cp>=0xFF5B and cp<=0xFF65)
            or (cp>=0x1F000 and cp<=0x1FAFF)
            or (cp>=0xA1 and cp<=0xBF and cp~=0xAA and cp~=0xB5 and cp~=0xBA)
            or cp==0xD7 or cp==0xF7
        if not symbol then return false end
    end
    return true
end
-- Explicit branch captions apply to the next skill only, never a live target
-- condition. Both alternatives stay visible. Unknown words remain skill tokens.
local BRANCH_LABELS={ ["单体"]=T["单体"], ["單體"]=T["单体"], ["st"]=T["单体"], ["aoe"]="AOE", ["群体"]="AOE", ["群體"]="AOE" }
local function Parse(value)
    if type(value)~="string" then return nil,T["请输入技能 ID 或名称。"] end
    if #value>2048 then return nil,T["顺序过长（最多 2048 字节）。"] end
    -- Keep legacy compact sequences working; other separators must stand alone.
    value=value:gsub("→",">"):gsub("＞",">"):gsub("＋","+"):gsub("，",">")
        :gsub("　"," "):gsub("\194\160"," "):gsub("／","/"):gsub("([>+/])"," %1 ")
    local out,step,join,branch={},0,">",nil
    for raw in value:gmatch("%S+") do
        local caption=BRANCH_LABELS[raw:gsub("：$",""):gsub(":$",""):lower()]
        if caption then
            if branch then return nil,T["分支标注后请填写技能 ID 或名称。"] end
            branch=caption
        elseif SymbolToken(raw) then
            -- Preserve alternative '/' and legacy grouped '+' presentation.
            join=(raw=="+" or raw=="/") and raw or ">"
        else
            local skill,count=raw,nil
            local star=raw:find("*",1,true)
            if star then
                skill=raw:sub(1,star-1);count=raw:sub(star+1)
                local lo,hi=count:match("^(%d+)%-(%d+)$")
                if not lo then lo=count:match("^(%d+)$");hi=lo end
                if not lo or tonumber(lo)<1 or tonumber(hi)>9 or tonumber(lo)>tonumber(hi) then
                    return nil,T["次数写法应为技能后紧跟 *1 至 *9，或 *1-2 这样的范围。"]
                end
            end
            if skill=="" or skill:find("|",1,true) then return nil,T["技能名称不能包含 |，请使用技能 ID 或纯文本名称。"] end
            local number=tonumber(skill)
            if number and (number<1 or number~=math.floor(number) or number>2147483647) then
                return nil,T["技能 ID 必须是有效的正整数。"]
            end
            if #out==0 or join~="+" then step=step+1 end
            out[#out+1]={spell=number or skill,count=count,step=step,join=join,branch=branch}
            join=">";branch=nil
        end
    end
    if branch then return nil,T["分支标注后请填写技能 ID 或名称。"] end
    return out,nil
end
local fallbackNames={
    [20271]=T["审判"],[184575]=T["公正之剑"],[31884]=T["复仇之怒"],
    [255937]=T["灰烬觉醒"],[343527]=T["处决宣判"],[383328]=T["最终审判"],
    [375576]=T["圣洁鸣钟"],[53385]=T["神圣风暴"],
}
local function Resolve(spell)
    local ok,info=false,nil
    if C_Spell and C_Spell.GetSpellInfo then ok,info=pcall(C_Spell.GetSpellInfo,spell) end
    if ok and type(info)=="table" and info.iconID then
        return info.iconID,info.name or tostring(spell),true
    end
    return 134400,fallbackNames[spell] or tostring(spell),false
end
local frames={}
local Refresh
local function hideTip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
local function label(parent,size)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    ns.UI.SetRuntimeFont(f,GameFontNormal:GetFont(),size)
    f:SetShadowOffset(1,-1);f:SetJustifyH("CENTER")
    return f
end
local function paint()
    local p=ns.UI.palette
    for _,f in pairs(frames) do
        f.card:SetShown(not (DB().hideBackgroundLocked and f:IsLocked()))
        f.card:SetBackdropColor(p.card[1],p.card[2],p.card[3],DB().opacity)
        f.card:SetBackdropBorderColor(unpack(p.border))
        -- Text on a light card must not inherit the outline used over the world.
        -- Hidden/mostly transparent cards keep light overlay text and the user's
        -- outline preference. Icon badges, charges and cooldowns stay untouched.
        local overWorld = not f.card:IsShown() or DB().opacity < 0.5
        ns.UI.StyleText(f.title,"accent",overWorld)
        ns.UI.StyleText(f.note,"text",overWorld)
        for _,cell in ipairs(f.cells) do
            ns.UI.StyleText(cell.name,"text",overWorld)
            ns.UI.StyleText(cell.connector,"accent",overWorld)
            ns.UI.StyleText(cell.branch,"accent",overWorld)
        end
    end
end
local function createRow(index)
    local f=ns.UI.CreateMovableFrame({
        name="BaimiaoRotationGuide"..index,moduleId=ID,layoutKey=ID..index,
        size={500,72},defaultPos={point="CENTER",relPoint="CENTER",x=0,y=140-(index-1)*100},
        unlockDragOnly=true,
    })
    local layout=f.layoutDB
    if layout.locked==nil then layout.locked=Layout().locked~=false end
    f.card=CreateFrame("Frame",nil,f,"BackdropTemplate")
    f.card:SetAllPoints()
    f.card:SetFrameLevel(f:GetFrameLevel())
    f.card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
    f.card:EnableMouse(false)
    f.title=label(f,12);f.title:SetPoint("TOPLEFT",12,-10);f.title:SetJustifyH("LEFT")
    f.note=label(f,12);f.note:SetJustifyH("LEFT");f.note:SetJustifyV("TOP");f.note:SetWordWrap(true)
    f.close=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    f.close:SetSize(24,22);f.close:SetPoint("TOPRIGHT",-5,-5);f.close:SetText("x")
    ns.UI.SkinTextButton(f.close)
    ns.UI.RegisterRuntimeFont(f.close:GetFontString())
    f.close:SetFrameLevel(f:GetFrameLevel()+5)
    f.close:SetScript("OnClick",function()
        if f:IsLocked() then return end
        Profile(f.specID).rows[index].enabled=false
        Refresh()
        local m=ns.modules[ID]
        if m and m._syncLayout then m._syncLayout:SyncAll() end
    end)
    f.close:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText(T["隐藏此方案"])
        GameTooltip:AddLine(T["仅关闭这一条，不删除配置。可在方案编辑页重新勾选。"],1,1,1,true)
        GameTooltip:Show()
    end)
    f.close:SetScript("OnLeave",hideTip);f.close:SetScript("OnHide",hideTip)
    f:SetScript("OnHide",function(self)
        if self._moving then self:StopMovingOrSizing();self._moving=nil;self:SavePosition() end
    end)
    f.cells={}
    frames[index]=f
    return f
end
-- Never compare, calculate with, or stringify restricted cooldown values.
local secret=issecretvalue or function() return false end
local function query(fn,spell)
    if not fn then return nil end
    local ok,value=pcall(fn,spell)
    if ok then return value end
end
local function paintCooldown(cell)
    local cd=cell.cooldown
    cd:Clear();cell.charges:SetText("")
    if not DB().showCooldowns or not cell.spell or not C_Spell then return end
    local charges=query(C_Spell.GetSpellCharges,cell.spell)
    local charging=false
    if type(charges)=="table" then
        local current,maximum=charges.currentCharges,charges.maxCharges
        if not secret(current) and not secret(maximum) and type(current)=="number" and type(maximum)=="number" and maximum>1 then
            cell.charges:SetText(current)
            charging=current<maximum
        end
    end
    -- Duration objects are passed straight to the native widget, including in combat.
    local duration=query(C_Spell.GetSpellChargeDuration,cell.spell)
    if not duration then duration=query(C_Spell.GetSpellCooldownDuration,cell.spell) end
    if duration and cd.SetCooldownFromDurationObject then
        if pcall(cd.SetCooldownFromDurationObject,cd,duration) then return end
    end
    local info=query(C_Spell.GetSpellCooldown,cell.spell)
    local start,length,rate
    if charging then
        start,length,rate=charges.cooldownStartTime,charges.cooldownDuration,charges.chargeModRate
    elseif type(info)=="table" then
        -- Exclude a pure global cooldown when the API exposes this flag.
        if not secret(info.isOnGCD) and info.isOnGCD==true then return end
        start,length,rate=info.startTime,info.duration,info.modRate
    end
    if secret(start) or secret(length) or secret(rate) then return end
    if type(start)=="number" and type(length)=="number" and length>0 then
        pcall(cd.SetCooldown,cd,start,length,type(rate)=="number" and rate or 1)
    end
end
local function updateCooldowns()
    for _,f in pairs(frames) do
        if f:IsShown() then
            for _,cell in ipairs(f.cells) do if cell:IsShown() then paintCooldown(cell) end end
        end
    end
end
local function createCell(f)
    local cell=CreateFrame("Frame",nil,f)
    cell:EnableMouse(false)
    cell.hit=CreateFrame("Frame",nil,cell)

    cell.icon=cell:CreateTexture(nil,"ARTWORK")
    cell.icon:SetPoint("TOPLEFT");cell.icon:SetTexCoord(0.06,0.94,0.06,0.94)
    cell.hit:SetAllPoints(cell.icon)
    cell.hit:SetScript("OnEnter",function(self)
        if f:IsLocked() then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        local info=cell.spell and query(C_Spell and C_Spell.GetSpellInfo,cell.spell)
        local id=type(info)=="table" and info.spellID or type(cell.spell)=="number" and cell.spell
        local ok=false
        if id then ok=pcall(GameTooltip.SetSpellByID,GameTooltip,id) end
        if not ok then
            GameTooltip:SetText(literal(cell.displayName))
            GameTooltip:AddLine(T["未能读取技能详情，请检查技能 ID 或名称。"],1,0.75,0.4,true)
        end
        GameTooltip:Show()
    end)
    cell.hit:SetScript("OnLeave",hideTip);cell.hit:SetScript("OnHide",hideTip)
    cell.hit:RegisterForDrag("LeftButton")
    cell.hit:SetScript("OnDragStart",function() if not f:IsLocked() then f:StartMoving();f._moving=true;hideTip(cell.hit) end end)
    cell.hit:SetScript("OnDragStop",function() if f._moving then f:StopMovingOrSizing();f._moving=nil;f:SavePosition() end end)
    cell.cooldown=CreateFrame("Cooldown",nil,cell,"CooldownFrameTemplate")
    cell.cooldown:SetAllPoints(cell.icon);cell.cooldown:EnableMouse(false)
    cell.cooldown:SetDrawEdge(false);cell.cooldown:SetHideCountdownNumbers(false)
    cell.cooldown:SetSwipeColor(0,0,0,0.65)
    ns.UI.RegisterRuntimeCooldown(cell.cooldown)
    cell.hit:SetFrameLevel(cell.cooldown:GetFrameLevel()+3)
    local overlay=CreateFrame("Frame",nil,cell)
    overlay:SetAllPoints(cell);overlay:SetFrameLevel(cell.cooldown:GetFrameLevel()+2)
    overlay:EnableMouse(false)
    cell.charges=label(overlay,12);cell.charges:SetPoint("TOPRIGHT",cell.icon,"TOPRIGHT",-2,-2)
    cell.connector=label(cell,16)
    cell.name=label(cell,11)
    cell.branch=label(cell,12);cell.branch:SetWordWrap(false)
    cell.badge=label(overlay,11);cell.badge:SetTextColor(1,1,1,1)
    cell.badgeBg=overlay:CreateTexture(nil,"BACKGROUND")
    cell.badgeBg:SetColorTexture(0.04,0.05,0.06,0.94)
    return cell
end
local function eligible()
    return ns.IsModuleEnabled(ID) and DB().show and CurrentSpec()~=nil
end
local function Render(index,nodes)
    local d=DB();local row=ActiveRows()[index]
    local f=frames[index] or createRow(index)
    f.specID=CurrentSpec()
    local scale=math.max(50,math.min(200,tonumber(d.scalePercent) or 100))/100
    local size=math.max(24,math.min(64,tonumber(d.size) or 38))
    local hasBranches=false
    for _,node in ipairs(nodes) do if node.branch then hasBranches=true;break end end
    local cellWidth=math.max(size,d.showNames and 76 or 0,hasBranches and 40 or 0)
    local gap=22
    local unlocked=not f:IsLocked()
    local top=((d.showTitles or unlocked) and 34 or 12)+(hasBranches and 18 or 0)
    if not unlocked and f._moving then f:StopMovingOrSizing();f._moving=nil;f:SavePosition() end
    f.close:SetShown(unlocked)
    if not unlocked then hideTip(f.close) end
    local lineHeight=size+(d.showNames and 30 or 0)+22
    -- One baseline for every skill, independent of old perLine saved values.
    local width=24+#nodes*cellWidth+(#nodes-1)*gap
    local height=top+lineHeight-10
    local note=type(row.note)=="string" and trim(row.note) or ""
    local showNote=row.showNote==true and note~=""
    -- Keep all icons on screen by reducing presentation scale, not by wrapping
    -- or mutating the user's configured scale. A short plan still fits its note.
    if showNote then width=math.max(width,220) end
    local available=math.max(1,UIParent:GetWidth()-24)
    f:SetScale(math.min(scale,available/width))
    f.note:ClearAllPoints();f.note:SetPoint("TOPLEFT",12,-height)
    f.note:SetWidth(width-24);f.note:SetHeight(0)
    -- Preserve user line breaks but render WoW markup as literal text.
    f.note:SetText(showNote and note:gsub("|","||"):gsub("\r\n","\n"):gsub("\r","\n") or "")
    f.note:SetShown(showNote)
    if showNote then height=height+math.max(14,f.note:GetStringHeight())+12 end
    f:SetSize(width,height)
    f.title:SetWidth(f:GetWidth()-(unlocked and 52 or 24));f.title:SetText(literal(row.name));f.title:SetShown(d.showTitles)
    for i,node in ipairs(nodes) do
        local cell=f.cells[i] or createCell(f);f.cells[i]=cell
        cell:SetSize(cellWidth,lineHeight);cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT",12+(i-1)*(cellWidth+gap),-top)
        cell.icon:SetSize(size,size);cell.icon:ClearAllPoints();cell.icon:SetPoint("TOP",0,0)
        cell.branch:ClearAllPoints();cell.branch:SetPoint("BOTTOM",cell.icon,"TOP",0,3)
        cell.branch:SetSize(cellWidth,15);cell.branch:SetText(node.branch or "");cell.branch:SetShown(node.branch~=nil)
        local texture,name,valid=Resolve(node.spell)
        cell.icon:SetTexture(texture)
        cell.spell=valid and node.spell or nil
        cell.displayName=name
        cell.hit:EnableMouse(unlocked)
        if not unlocked then hideTip(cell.hit) end
        cell.name:ClearAllPoints();cell.name:SetPoint("TOP",cell.icon,"BOTTOM",0,-5)
        cell.name:SetSize(cellWidth,26);cell.name:SetText(literal(name));cell.name:SetShown(d.showNames)
        cell.connector:ClearAllPoints();cell.connector:SetPoint("RIGHT",cell,"LEFT",-4,-size/2+lineHeight/2)
        -- ASCII separators use the game's font; no external glyph/icon font.
        cell.connector:SetText(node.join);cell.connector:SetShown(i>1)
        cell.badge:SetPoint("BOTTOMRIGHT",cell.icon,"BOTTOMRIGHT",-2,2)
        cell.badge:SetText(node.count and ("x"..node.count) or (valid and "" or "?"))
        cell.badgeBg:ClearAllPoints();cell.badgeBg:SetPoint("BOTTOMRIGHT",cell.icon,"BOTTOMRIGHT",0,0)
        cell.badgeBg:SetSize(node.count and (#node.count*7+13) or 16,15)
        cell.badgeBg:SetShown(node.count~=nil or not valid)
        cell:Show()
    end
    for i=#nodes+1,#f.cells do f.cells[i]:Hide() end
    f:ApplyPosition();f:ApplyLockVisual();f:Show()
end
Refresh=function()
    for i=1,MAX_SLOTS do
        local row=ActiveRows()[i]
        local nodes=row and Parse(row.sequence)
        if eligible() and row and row.enabled and nodes and #nodes>0 then Render(i,nodes)
        elseif frames[i] then frames[i]:Hide() end
    end
    paint();updateCooldowns()
end
local function Status(i)
    local nodes,err=Parse(EditorRows()[i].sequence)
    if err then return err, "danger" end
    if #nodes==0 then return T["尚未配置技能；空方案不会显示。"] end
    local missing={}
    for _,node in ipairs(nodes) do
        local _,name,valid=Resolve(node.spell)
        if not valid then missing[#missing+1]=literal(name) end
    end
    if #missing>0 then return T["未识别："]..table.concat(missing,"、",1,math.min(2,#missing))..(#missing>2 and T[" 等"] or "")..T["（显示问号，请检查 ID / 名称）"], "warning" end
    return #nodes..T[" 个技能图标 · 顺序有效"]
end
local function SetSequence(i,value)
    -- Preserve invalid user text for correction rather than pretending it saved
    -- successfully as a different sequence. Invalid rows never render stale data.
    EditorRows()[i].sequence=value
end
local Tabs=ns.UI.OptionTabs
local function BuildOptions(panel,m,L)
    local _,_,classID=UnitClass("player")
    editorClass=classID
    editorSpec=CurrentSpec() or (Specs(classID)[1] or {}).value or 70
    L:Title(T["循环提示助手"])
    L:Text(T["选择方案、调整外观，或查看配置写法。技能顺序由你决定，冷却实时显示。"],true)
    local entries={
        {name=T["显示与布局"],width=150,build=function(_,L)
    L:Section(T["显示与摆放"])
    L:Check(T["显示循环提示助手"],function() return DB().show end,function(v) DB().show=v end,Refresh)
    L:Text(T["自动显示当前职业专精的已勾选方案；切换专精自动换条。编辑其他专精不会改变屏幕上的方案。"],true)
    L:Check(T["锁定所有顺序卡片（锁定后鼠标穿透，不挡战斗操作）"],
        function() return Layout().locked~=false end,
        function(v)
            Layout().locked=v
            for i=1,MAX_SLOTS do ns.GetLayoutDB(ID..i).locked=v end
        end,Refresh)
    L:Text(T["在「方案编辑」勾选方案。解锁后可拖动卡片、悬停查看技能、点击右上角 x 隐藏单条；锁定后完全鼠标穿透。"],true)
    L:Check(T["锁定后隐藏背景与边框"],function() return DB().hideBackgroundLocked end,
        function(v) DB().hideBackgroundLocked=v end,Refresh)
    L:Text(T["隐藏背景不影响图标、冷却和文字；解锁后恢复背景，方便定位与拖动。"],true)
    L:Slider("BaimiaoRotationScale",T["整体缩放（%）"],50,200,5,function() return DB().scalePercent end,
        function(v) DB().scalePercent=v end,Refresh)
    L:Check(T["显示技能冷却与充能"],function() return DB().showCooldowns end,function(v) DB().showCooldowns=v end,Refresh)
    L:Text(T["冷却圈和倒计时由游戏绘制；充能数可读取时显示在右上角。冷却不代表距离、资源或其他施放条件。"],true)
    L:Check(T["显示方案名称"],function() return DB().showTitles end,function(v) DB().showTitles=v end,Refresh)
    L:Check(T["在图标下显示技能名称"],function() return DB().showNames end,function(v) DB().showNames=v end,Refresh)
    L:Slider("BaimiaoRotationSize",T["图标大小"],24,64,1,function() return DB().size end,function(v) DB().size=v end,Refresh)
    L:Text(T["技能始终单行排列，不按数量换行；超出屏幕宽度时自动整体缩小，未超出时使用设定缩放。"],true)
    L:Slider("BaimiaoRotationOpacity",T["卡片背景不透明度"],0,1,0.05,function() return DB().opacity end,function(v) DB().opacity=v end,Refresh)
    L:Button(140,T["重置卡片位置"],function()
        for i=1,MAX_SLOTS do
            local pos=ns.GetLayoutDB(ID..i)
            pos.point,pos.relPoint,pos.x,pos.y="CENTER","CENTER",0,140-(i-1)*100
        end
        Refresh()
    end)

        end},
        {name=T["方案编辑"],width=150,build=function(panel,L,onResize)
            local function syncEditor() L:SyncAll() end
            -- Explicitly commit focus before changing profile so edits cannot land in another spec.
            local function commitFocus()
                local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
                if focus and focus.ClearFocus then focus:ClearFocus() end
            end
            m.rotationClassSelect=L:Dropdown(280,T["职业："],Classes,function() return editorClass end,function(v)
                commitFocus();editorClass=v;editorSpec=(Specs(v)[1] or {}).value or editorSpec
            end,syncEditor)
            m.rotationSpecSelect=L:Dropdown(280,T["专精："],function() return Specs(editorClass) end,function() return editorSpec end,function(v)
                commitFocus();editorSpec=v
            end,syncEditor)
            m.rotationSpecSelect:ClearAllPoints()
            m.rotationSpecSelect:SetPoint("LEFT",m.rotationClassSelect,"RIGHT",12,0)
            L:step(-30)
            local currentButton=L:Button(180,T["编辑当前角色专精"],function()
                commitFocus()
                local _,_,id=UnitClass("player")
                editorClass=id;editorSpec=CurrentSpec() or (Specs(id)[1] or {}).value or editorSpec
                syncEditor()
            end)
            L:Button(240,T["从旧版恢复到空方案槽"],function()
                commitFocus()
                local old=DB().legacyRows
                if not old then return end
                for i,row in ipairs(old) do
                    if EditorRows()[i].sequence=="" then
                        EditorRows()[i]=copyRow(row)
                    end
                end
                Refresh();syncEditor()
            end,true,currentButton)
            L:Text(T["各专精独立保存 6 套方案；编辑选择不影响屏上匹配。旧版恢复仅填入对应的空槽，不覆盖已编辑内容。"],true)
            local rows={}
            m.rotationEditors={}
            for i=1,MAX_SLOTS do
                local index=i
                rows[i]={name=T["方案 "]..i,width=100,build=function(_,L)
        local controls={};m.rotationEditors[index]=controls
        L:Section(T["方案 "]..index)
        L:Check(T["在屏幕上显示本方案"],function() return EditorRows()[index].enabled end,
            function(v) EditorRows()[index].enabled=v end,Refresh)
        L:Text(T["方案名称"],true)
        L:Box(480,28,false,function() return EditorRows()[index].name end,
            function(v) EditorRows()[index].name=v end,Refresh)
        L:Text(T["技能顺序（名称 / ID 用空格分隔，可用单体 / AOE 标注分支）"],true)
        controls.sequence=L:Box(560,70,true,function() return EditorRows()[index].sequence end,
            function(v) SetSequence(index,v) end,function() Refresh();L:SyncAll() end)
        local status=L:DynLabel(function() return Status(index) end)
        status:SetHeight(48);L:step(30)
        L:Text(T["方案备注（可换行，修改后点击保存）"],true)
        controls.note=L:Box(560,60,true,function() return EditorRows()[index].note or "" end,
            function(v) EditorRows()[index].note=v end,Refresh)
        controls.showNote=L:Check(T["在技能循环下方显示备注"],function() return EditorRows()[index].showNote==true end,
            function(v) EditorRows()[index].showNote=v end,Refresh)
        if presets[index] then
            local restore=L:Button(180,T["还原惩戒预设"],function()
                if editorSpec~=70 then return end
                EditorRows()[index].sequence=presets[index].sequence
                EditorRows()[index].name=presets[index].name
                Refresh();L:SyncAll()
            end)
            L.syncers[#L.syncers+1]=function() restore:SetEnabled(editorSpec==70) end
        end

                end}
            end
            m.rotationRowTabs=Tabs(panel,L,rows,onResize)
        end},
        {name=T["写法帮助"],width=150,build=function(_,L)
            L:Section(T["技能顺序怎么写"])
            L:Text(T["技能 ID 或名称用空格分隔，也支持换行。中间可用任意独立符号或不写符号；符号前后请留空格，不会作为技能。含空格的技能名称请用 ID。"],false)
            L:Text(T["名称示例：审判 → 公正之剑 / 复仇之怒 + 灰烬觉醒"],true)
            L:Text(T["ID 示例：20271 184575 31884 255937（仅空格也可）"],true)
            L:Text(T["分支示例：375576 > 单体 383328 /AOE 53385；单体、AOE（或群体）标在紧随的技能上方，两个技能同时显示，不会自动选择。"],true)
            L:Text(T["次数示例：383328 + 53385*1-2；次数紧跟技能。紧凑 > / + 写法仍支持，+ 保留分组，/ 表示并列备选，其他符号显示为 >。"],true)
            L:Section(T["保存与使用"])
            L:Text(T["每个方案可单独填写备注，并选择是否显示在循环下方。关闭显示仍保留内容，空备注不占位置；备注不会参与技能解析。"],true)
            L:Text(T["每套最多 2048 字节，不再限制 24 个图标；全部技能始终一行。编辑后点击保存；技能未识别时显示问号，语法错误时暂时隐藏该条，输入仍会保留。"],true)
            L:Text(T["惩戒专精前三套内置素材预设；其他专精默认为空，由你配置。所有方案均可编辑和分别显示。关闭卡片只取消该方案的显示勾选，不删除内容。"],true)
            L:Text(T["未锁定时悬停图标查看技能详情，也可从图标直接拖动整条。锁定后关闭按钮和悬停提示停用，鼠标完全穿透。"],true)
        end},
    }
    m.rotationTabs=Tabs(panel,L,entries)
end

local events=CreateFrame("Frame")
events:SetScript("OnEvent",function(_,event)
    if event=="SPELL_UPDATE_COOLDOWN" or event=="SPELL_UPDATE_CHARGES" then updateCooldowns() else Refresh() end
end)
local function setupEvents()
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    events:RegisterEvent("SPELL_UPDATE_CHARGES")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    events:RegisterEvent("PLAYER_TALENT_UPDATE")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
end
ns.RotationGuide={Parse=Parse,Resolve=Resolve,Refresh=Refresh,GetDB=DB,Status=Status,UpdateCooldowns=updateCooldowns,Profile=Profile,CurrentSpec=CurrentSpec,EditorRows=EditorRows}
ns.RegisterModule({id=ID,name=T["循环提示助手"],desc=T["按职业专精自动匹配的技能顺序与冷却提示；每个专精独立配置。"],
    defaults=defaults,BuildOptions=BuildOptions,
    OnEnable=function()
        setupEvents()
        SLASH_BAIMIAOROTATION1="/bmrotation"
        SlashCmdList.BAIMIAOROTATION=function() ns.OpenOptions(ID) end
        ns.UI.OnTheme(paint)
        Refresh()
    end,
    OnDisable=function() events:UnregisterAllEvents();for _,f in pairs(frames) do f:Hide() end end,
    OnToggle=function(_,on) if on then setupEvents() end;Refresh() end,
})
