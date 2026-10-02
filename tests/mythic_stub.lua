-- Retail API/secure state test double, not a game rendering or taint test.
local methods=getmetatable(UIParent).__index
function methods:AddDoubleLine() end
function methods:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function methods:SetFrameStrata(value) self.strata=value end
function methods:GetEffectiveScale() return self:GetScale()*(self.parent and self.parent:GetEffectiveScale() or 1) end
function methods:SetTexture(value) self.texture=value end
function methods:SetAlpha(value) self.alpha=value end
function methods:GetAlpha() return self.alpha or 1 end
function methods:SetBackdrop(value) self.backdrop=value end
function methods:SetBackdropColor(...) self.bg={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetTexCoord(...) self.texcoords={...} end
function methods:RegisterEvent(name) self.events=self.events or {};self.events[name]=true end
function methods:UnregisterEvent(name) if self.events then self.events[name]=nil end end
function methods:UnregisterAllEvents() self.events={} end
function fire(name,...)
    for _,f in ipairs(frames) do if f.events and f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f,name,...) end end
end
local pending={};Now=100
function GetTime() return Now end
function C_Timer.After(delay,fn) pending[#pending+1]={time=Now+delay,fn=fn} end
function advance(delta)
    local target=Now+(delta or 0);local iterations=0
    while true do
        table.sort(pending,function(a,b)return a.time<b.time end)
        if not pending[1] or pending[1].time>target then break end
        local t=table.remove(pending,1);Now=t.time;t.fn();iterations=iterations+1;assert(iterations<1000,"timer loop")
    end
    Now=target
end
function hooksecurefunc(object,key,hook)
    if type(object)=="string" then object,key,hook=_G,object,key end
    local original=assert(object[key]);object[key]=function(...)local results={original(...)};hook(...);return unpack(results)end
end
function RegisterStateDriver(f,key,value) assert(not combat);f.driverRule=value end
function UnregisterStateDriver(f,key) assert(not combat);f.driverRule=nil end
function setCombat(value)
    combat=value
    for _,f in ipairs(frames) do if f.driverRule then f.hidden=combat end end
    fire(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED");advance()
end
function ShowUIPanel(f)f:Show()end
function IsPlayerSpell(id)return known[id]==true end
function UnitFactionGroup()return faction or "Alliance"end
known={[393256]=true,[1286831]=true}
C_Spell.GetSpellCooldown=function()return {startTime=0,duration=0}end
PVEFrame=CreateFrame("Frame",nil,UIParent);PVEFrame:SetSize(563,428);PVEFrame:SetScale(.9)
ChallengesFrame=CreateFrame("Frame",nil,PVEFrame);ChallengesFrame:Hide()
ChallengesFrame.WeeklyInfo=CreateFrame("Frame",nil,ChallengesFrame)
ChallengesFrame.DungeonIcons={}
for i=1,8 do
    local icon=CreateFrame("Frame",nil,ChallengesFrame);icon:SetFrameStrata("HIGH")
    ChallengesFrame.DungeonIcons[i]=icon
end
function ChallengesFrame:Update() self.updates=(self.updates or 0)+1 end
function PVEFrame_ShowFrame(name)
    -- Blizzard selects the destination's dimensions before hiding Challenges.
    -- HonorInset expands the PvP page beyond the shared base width.
    PVEFrame:Show();PVEFrame.activeTabIndex=name=="ChallengesFrame" and 3 or (name=="PVPUIFrame" and 2 or 1)
    PVEFrame:SetWidth(name=="PVPUIFrame" and 800 or 563)
    ChallengesFrame:SetShown(name=="ChallengesFrame")
end
function PVEFrame_ToggleFrame(name)PVEFrame_ShowFrame(name)end
mapIDs={399,249,250,584,585,586,587,588}
local names={[399]="红玉新生法池",[249]="诸王之眠",[250]="塞塔里斯神庙",[584]="夺目海岸",[585]="虚空之痕",[586]="纳洛拉克的洞穴",[587]="密谋之巢",[588]="毒牙神殿"}
C_ChallengeMode={GetMapTable=function()return mapIDs end,
    GetMapUIInfo=function(id)return names[id] or ("新副本"..id),id,1800,123 end,
    GetAffixInfo=function(id)return "词缀"..id,"词缀说明",456 end}
history={{mapChallengeModeID=399,level=16,thisWeek=true,completed=false,durationSec=1799},
    {mapChallengeModeID=399,level=15,thisWeek=true,completed=true,durationSec=1900},
    {mapChallengeModeID=249,level=12,thisWeek=true,durationSec=1700},
    {mapChallengeModeID=249,level=30,thisWeek=false,durationSec=1700}}
C_MythicPlus={GetRunHistory=function(a,b,c)assert(a==false and b==true and c==true);return history end,
    GetCurrentAffixes=function()return {{id=1},{id=2},{id=3},{id=4},{id=5}}end,
    GetOwnedKeystoneChallengeMapID=function()return 586 end,GetOwnedKeystoneLevel=function()return 15 end,
    RequestMapInfo=function()requests=(requests or 0)+1 end,RequestCurrentAffixes=function()end,RequestRewards=function()end}
C_PlayerInfo={GetPlayerMythicPlusRatingSummary=function()return {currentSeasonScore=3204,runs={{challengeModeID=399,bestRunLevel=16,mapScore=428},{challengeModeID=249,bestRunLevel=14,mapScore=396}}}end}
Enum.WeeklyRewardChestThresholdType={Activities=1}
C_WeeklyRewards={GetActivities=function(kind)assert(kind==1);return {{index=2,threshold=4,progress=3,level=12},{index=1,threshold=1,progress=3,level=16},{index=3,threshold=8,progress=3,level=0}}end}
C_AddOns.IsAddOnLoaded=function(name)return loaded and loaded[name] or false end
C_AddOns.LoadAddOn=function(name)if name=="Blizzard_WeeklyRewards" then WeeklyRewardsFrame=CreateFrame("Frame",nil,UIParent) end end