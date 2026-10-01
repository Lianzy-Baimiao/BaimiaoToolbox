
unpack=unpack or table.unpack
SlashCmdList={};UISpecialFrames={};ns={};messages={};frames={};combat=false
function print(msg) messages[#messages+1]=msg end
function InCombatLockdown() return combat end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsShiftKeyDown() return false end
function GetCurrentKeyBoardFocus() return focus end
function GetTime() return 0 end
function GetBuildInfo() return "12.0.1", "", "", 120001 end
function UnitClass() return "战士", "WARRIOR",1 end
function UnitName() return "Tester" end
function GetLocale() return "zhCN" end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 71 end
function issecretvalue() return false end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
C_AddOns={GetAddOnMetadata=function() return "1.5.0" end}
C_MountJournal={GetMountIDs=function() return {} end}
C_Spell={GetSpellName=function(id) return "Spell"..id end,GetSpellInfo=function() return {} end}
C_Timer={After=function() end,NewTicker=function() return {Cancel=function() end} end}
C_Map={};Enum={};Settings={RegisterCanvasLayoutCategory=function() return {GetID=function() return 1 end} end,RegisterAddOnCategory=function() end}
function HideUIPanel(f) f:Hide() end
local methods={}
local noop=function() end
for word in string.gmatch([[SetClampedToScreen EnableMouse EnableMouseWheel EnableKeyboard SetMovable RegisterForDrag RegisterForClicks SetFrameStrata SetOrientation SetValueStep SetObeyStepOnDrag SetThumbTexture SetAutoFocus SetMultiLine SetMaxLetters SetFontObject SetJustifyH SetJustifyV SetWordWrap SetSpacing SetShadowOffset SetTextInsets HighlightText SetTexCoord SetAllPoints SetAlpha SetTexture SetNormalTexture SetHighlightTexture SetPushedTexture SetDisabledTexture SetCheckedTexture SetBlendMode SetVertexColor SetColorTexture SetBackdrop SetBackdropColor SetBackdropBorderColor SetScrollChild SetVerticalScroll RegisterEvent UnregisterEvent UnregisterAllEvents StartMoving StopMovingOrSizing Raise SetEnabled SetNumeric SetHitRectInsets]],"%S+") do methods[word]=noop end
function methods:GetObjectType() return self.kind end
function methods:IsObjectType(t) return self.kind==t end
function methods:SetSize(w,h) self.w=w;self.h=h end
function methods:SetWidth(w) self.w=w end
function methods:SetHeight(h) self.h=h end
function methods:GetWidth() return self.w or (self.parent and self.parent:GetWidth()) or 768 end
function methods:GetHeight() return self.h or 600 end
function methods:SetPoint(...) self.point={...};self.points=self.points or {};self.points[self.point[1]]=self.point end
function methods:GetPoint() return "CENTER",UIParent,"CENTER",0,0 end
function methods:ClearAllPoints() self.point=nil;self.points={} end
function methods:GetCenter() return 520,370 end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:SetScale(n) self.scale=n end
function methods:GetScale() return self.scale or 1 end
function methods:SetFrameLevel(n) self.level=n end
function methods:GetFrameLevel() return self.level or 1 end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() return unpack(self.regions) end
function methods:SetScript(e,f) self.scripts[e]=f end
function methods:GetScript(e) return self.scripts[e] end
function methods:HookScript(e,f) local old=self.scripts[e];self.scripts[e]=function(...) if old then old(...) end; f(...) end end
function methods:Show() assert(not (combat and self.template and self.template:find("SecureActionButtonTemplate")), "protected show in combat");local old=self.hidden;self.hidden=false;if old and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() assert(not (combat and self.template and self.template:find("SecureActionButtonTemplate")), "protected hide in combat");local old=self.hidden;self.hidden=true;if not old and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetShown(b) if b then self:Show() else self:Hide() end end
function methods:IsShown() return not self.hidden end
function methods:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function methods:IsDescendantOf(p) return self.parent==p or (self.parent and self.parent:IsDescendantOf(p)) end
function methods:SetText(t) self.value=tostring(t or "");if self.fontString then self.fontString.value=self.value end end
function methods:GetText() return self.value or "" end
function methods:SetFont(path,size) self.font=path;self.fontSize=size end
function methods:GetFont() return self.font or "Fonts\\FRIZQT__.TTF",self.fontSize or 12,"" end
function methods:GetStringHeight() return math.max(16,math.ceil(#self:GetText()/100)*16) end
function methods:GetStringWidth() return #self:GetText()*5 end
function methods:SetTextColor(...) self.color={...} end
function methods:GetTextColor() return unpack(self.color or {1,1,1,1}) end
function methods:GetFontString() return self.fontString end
function methods:SetChecked(v) self.checked=v end
function methods:GetChecked() return self.checked end
function methods:SetMinMaxValues(a,b) self.min=a;self.max=b end
function methods:GetMinMaxValues() return self.min,self.max end
function methods:SetValue(v) self.val=v;if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,v) end end
function methods:GetValue() return self.val or 0 end
function methods:SetFocus() focus=self end
function methods:ClearFocus() focus=nil;if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
function methods:SetVerticalScroll(v) self.offset=v;if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self,v) end end
function methods:GetVerticalScroll() return self.offset or 0 end
function methods:GetVerticalScrollRange() return 100 end
local function object(kind,name,parent,region)
 local o=setmetatable({kind=kind,name=name,parent=parent,children={},regions={},scripts={}}, {__index=methods})
 if name then assert(not _G[name],"Duplicate global frame: "..name);_G[name]=o end
 if parent then table.insert(region and parent.regions or parent.children,o) end
 frames[#frames+1]=o;return o
end
function methods:CreateFontString(name) return object("FontString",name,self,true) end
function methods:CreateTexture(name) return object("Texture",name,self,true) end
function CreateFrame(kind,name,parent,template)
 local o=object(kind,name,parent)
 o.template=template
 if template and template:find("UIPanelButtonTemplate") then o.fontString=o:CreateFontString() end
 return o
end
UIParent=CreateFrame("Frame");UIParent:SetSize(1920,1080)
GameFontNormal=UIParent:CreateFontString();GameFontHighlight=GameFontNormal;ChatFontNormal=GameFontNormal
Minimap=CreateFrame("Frame",nil,UIParent)
GameTooltip=CreateFrame("Frame",nil,UIParent)

function methods:Clear() self.cooldownValue=nil;self.durationObject=nil end
function methods:SetCooldown(s,d,r) self.cooldownValue={s,d,r} end
function methods:SetCooldownFromDurationObject(d) self.durationObject=d end
function methods:SetDrawEdge() end
function methods:SetHideCountdownNumbers() end
function methods:SetSwipeColor() end

function methods:GetParent() return self.parent end
function methods:IsOwned(owner) return self.owner==owner end
function methods:SetOwner(owner) self.owner=owner end
function methods:AddLine(text) self.lastLine=text end
function methods:SetSpellByID(id) self.spellID=id end
function methods:EnableMouse(enabled) self.mouseEnabled=enabled end
function methods:SetEnabled(enabled) self.enabled=enabled end

function GetNumClasses() return 2 end
function GetClassInfo(i) if i==1 then return "战士","WARRIOR",1 else return "圣骑士","PALADIN",2 end end
function GetNumSpecializationsForClassID() return 3 end
function GetSpecializationInfoForClassID(id,i)
 local ids=id==1 and {71,72,73} or {65,66,70}
 local names=id==1 and {"武器","狂怒","防护"} or {"神圣","防护","惩戒"}
 return ids[i],names[i]
end

function methods:SetAttribute(key,value)
 assert(not (combat and self.template and self.template:find("SecureActionButtonTemplate")), "protected attribute in combat")
 self.attributes=self.attributes or {};self.attributes[key]=value
end
function methods:SetDrawBling() end
function methods:RegisterForClicks(...) self.clicks={...} end
