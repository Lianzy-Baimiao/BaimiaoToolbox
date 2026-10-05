-- Event-driven, local-only conveniences owned by SmallTools. No invitations,
-- queue acceptance, protected actions, chat-channel sends or persistent history.
local ADDON,ns=...
local T = ns.L
local M={};ns.SmallToolsExtras=M
local defaults={instanceInfo=true,queueReady=true,queueSound=true,tradeReceipt=true,
    instanceHoldSeconds=5,instanceFadeSeconds=1,queueHoldSeconds=5,queueFadeSeconds=1}
local running=false
local events=CreateFrame("Frame")
local bars={}
local instanceKey,pendingInstance
local instanceRevision=0
local lfgReady=false
local pvpReady={}
local activeTrade,pendingTrade
local function DB()
    local d=ns.GetDB("smalltools")
    if type(d.extras)~="table" then d.extras={}end
    ns.applyDefaults(d.extras,defaults)
    return d.extras
end
local function enabled(key)
    return running and ns.IsModuleEnabled("smalltools") and DB()[key]
end
local function public(v)return not (issecretvalue and issecretvalue(v))end
local function text(v)
    if public(v) and type(v)=="string" and v~="" then return v end
end
local function number(v)
    if public(v) and type(v)=="number" and v>=0 and v<math.huge and v==math.floor(v) then return v end
end
-- A nil table means the read failed/is restricted; an empty table can mean a
-- legitimately empty trade slot. Never turn unavailable data into zero items.
local function result(ok,...)
    if not ok then return end
    local t={n=select("#",...),...}
    for i=1,t.n do if not public(t[i]) then return end end
    return t
end
local function values(fn,...)
    if type(fn)=="function" then return result(pcall(fn,...))end
end
local function read(fn,...)
    local t=values(fn,...)
    if t then return unpack(t,1,t.n)end
end
local function later(delay,fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay,fn)else fn()end
end

local timingLimits={
    instanceHoldSeconds={1,30,5},instanceFadeSeconds={0,10,1},
    queueHoldSeconds={1,30,5},queueFadeSeconds={0,10,1},
}
local function seconds(key)
    local limit=timingLimits[key]
    local value=DB()[key]
    if not public(value) or type(value)~="number" or value~=value or value==math.huge or value==-math.huge then
        return limit[3]
    end
    return math.max(limit[1],math.min(limit[2],value))
end

-- Two separate lanes: entering an instance cannot overwrite a queue prompt.
-- The animation script only exists while a notification is visible.
local function hideBar(key)
    local f=bars[key]
    if f then f:SetScript("OnUpdate",nil);f:Hide()end
end
local function toast(key,message)
    local f=bars[key]
    if not f then
        local name=key=="instanceInfo" and "BaimiaoInstanceInfoToast" or "BaimiaoQueueReadyToast"
        f=CreateFrame("Frame",name,UIParent)
        f:SetPoint("TOP",UIParent,"TOP",0,key=="instanceInfo" and -140 or -235)
        f:SetFrameStrata("HIGH");f:EnableMouse(false);f:SetClampedToScreen(true)
        f.label=f:CreateFontString(nil,"ARTWORK","GameFontHighlight")
        ns.UI.RegisterRuntimeFont(f.label)
        f.label:SetShadowOffset(1,-1)
        f.label:SetPoint("TOPLEFT",14,-12);f.label:SetJustifyH("CENTER");f.label:SetWordWrap(true)
        bars[key]=f
    end
    local width=math.max(220,math.min(640,UIParent:GetWidth()-40))
    f:SetWidth(width);f.label:SetWidth(width-28);f.label:SetText(message)
    f:SetHeight(math.max(46,f.label:GetStringHeight()+24))
    local prefix=key=="instanceInfo" and "instance" or "queue"
    -- Capture timing per notification. Changing options affects the next real
    -- prompt/preview, without jumping the alpha of text already on screen.
    local hold,fade=seconds(prefix.."HoldSeconds"),seconds(prefix.."FadeSeconds")
    f.elapsed=0;f:SetAlpha(1);f:Show()
    f:SetScript("OnUpdate",function(self,elapsed)
        self.elapsed=self.elapsed+elapsed
        if self.elapsed>=hold+fade then hideBar(key)
        elseif self.elapsed>hold and fade>0 then self:SetAlpha(1-(self.elapsed-hold)/fade)end
    end)
end

local function instance()
    local name,kind,difficultyID,difficultyName,_,_,_,id=read(GetInstanceInfo)
    if (kind~="party" and kind~="raid") or not number(id) or not number(difficultyID) then return end
    return kind..":"..id..":"..difficultyID,text(name) or T["副本"],text(difficultyName) or T["未知难度"]
end
local function lootSpec()
    local id=number(read(GetLootSpecialization))
    if not id then return T["未知"]end
    local current=id==0
    local name,ignored
    if current then
        local spec=number(read(GetSpecialization))
        if spec and spec>0 then ignored,name=read(GetSpecializationInfo,spec)end
    else
        ignored,name=read(GetSpecializationInfoByID,id)
    end
    return (text(name) or T["未知"])..(current and T["（当前）"] or "")
end
local function durability()
    local lowest
    for slot=1,19 do
        local t=values(GetInventoryItemDurability,slot)
        if not t then return T["未知"]end
        local now,max=number(t[1]),number(t[2])
        if now and max and max>0 then
            local percent=math.min(100,math.floor(now/max*100))
            lowest=lowest and math.min(lowest,percent) or percent
        end
    end
    if not lowest then return T["无耐久装备"]end
    local value=lowest.."%"
    if lowest<=30 then value="|cffff6655"..value.."|r"end
    return value
end
local function displayInstance()
    if not enabled("instanceInfo") or not pendingInstance then return end
    if read(InCombatLockdown)==true then return end
    local key,name,difficulty=instance()
    if key==pendingInstance then
        toast("instanceInfo","|cff0cd29f"..name.." · "..difficulty..T["|r\n拾取专精："]..lootSpec()..T["  |  最低耐久："]..durability())
    end
    pendingInstance=nil
end
local function enteredWorld(_,reloading)
    instanceRevision=instanceRevision+1
    local revision=instanceRevision
    pendingInstance=nil;hideBar("instanceInfo")
    if not enabled("instanceInfo") then return end
    later(.5,function()
        if revision~=instanceRevision or not enabled("instanceInfo") then return end
        local key=instance()
        if not key then instanceKey=nil;return end
        if key==instanceKey then return end
        instanceKey=key
        if reloading==true then return end
        pendingInstance=key;displayInstance()
    end)
end

local function queueNotice(message)
    toast("queueReady",T["|cff0cd29f排队已就绪|r\n"]..message..T["，请在游戏原生窗口中确认。"])
    if DB().queueSound then
        -- No force-play flag and no CVar writes: respects master/background audio.
        read(PlaySound,(SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960,"Master")
    end
end
local function proposal()
    local data=values(GetLFGProposal)
    -- Silent proposals and already-answered prompts require no user action.
    if not data or data[1]~=true or data[8]==true or data[15]==true then return end
    if not lfgReady then
        lfgReady=true;queueNotice(text(data[5]) or T["地下城 / 团队查找器"])
    end
end
local function battlefield(index)
    index=number(index)
    if not index or index<1 or index>(MAX_BATTLEFIELD_QUEUES or 3) then return end
    local status,name=read(GetBattlefieldStatus,index)
    if status=="confirm" then
        if not pvpReady[index] then
            pvpReady[index]=true;queueNotice(text(name) or T["战场 / 竞技场"])
        end
    elseif status then pvpReady[index]=nil end
end

local function partnerName()
    local name,realm=read(UnitFullName,"NPC")
    name=text(name);realm=text(realm)
    if not name then return T["未知角色"]end
    if name:find("-",1,true) then return name end
    realm=realm or text(read(GetNormalizedRealmName))
    return realm and (name.."-"..realm:gsub("%s","")) or name
end
local function money(amount)
    amount=number(amount)
    if not amount then return T["金币未知"]end
    local gold=math.floor(amount/10000)
    local silver=math.floor(amount/100)%100
    local copper=amount%100
    return gold..T["金"]..silver..T["银"]..copper..T["铜"]
end
local function offer(infoFn,linkFn,moneyFn,enchantIndex)
    local parts={money(read(moneyFn))}
    for slot=1,6 do
        local info=values(infoFn,slot)
        if not info then parts[#parts+1]=T["物品信息未知"];break end
        local name=text(info[1])
        if name then
            local link=text(read(linkFn,slot)) or name
            local count=number(info[3])
            parts[#parts+1]=link.." ×"..(count and tostring(count) or "?")
        end
    end
    -- Slot 7 is NOT transferred. Only describe the enchantment service.
    local enchantInfo=values(infoFn,7)
    local enchant=enchantInfo and text(enchantInfo[enchantIndex])
    return table.concat(parts,"、"),enchant
end
local function snapshotTrade()
    if not activeTrade or not enabled("tradeReceipt") then return end
    local given,receivedEnchant=offer(GetTradePlayerItemInfo,GetTradePlayerItemLink,GetPlayerTradeMoney,5)
    local received,givenEnchant=offer(GetTradeTargetItemInfo,GetTradeTargetItemLink,GetTargetTradeMoney,6)
    activeTrade.given=given;activeTrade.received=received
    activeTrade.givenEnchant=givenEnchant;activeTrade.receivedEnchant=receivedEnchant
end
local function closeTrade()
    if not activeTrade then return end
    local closed=activeTrade
    activeTrade=nil;pendingTrade=closed
    -- TRADE_CLOSED is not success. Keep the last open-window snapshot briefly
    -- because the authoritative completion message can arrive after the close.
    later(2,function()if pendingTrade==closed then pendingTrade=nil end end)
end
local function tradeComplete(message)
    if not text(message) then return end
    if text(ERR_TRADE_CANCELLED) and message==ERR_TRADE_CANCELLED then
        activeTrade=nil;pendingTrade=nil;return
    end
    if not text(ERR_TRADE_COMPLETE) or message~=ERR_TRADE_COMPLETE then return end
    local trade=activeTrade or pendingTrade
    activeTrade=nil;pendingTrade=nil
    if not trade then return end
    local lines={T["与 "]..trade.partner..T[" 的交易已完成"], T["给出："]..(trade.given or T["信息未知"]),T["收到："]..(trade.received or T["信息未知"])}
    if trade.givenEnchant then lines[#lines+1]=T["提供附魔："]..trade.givenEnchant end
    if trade.receivedEnchant then lines[#lines+1]=T["收到附魔："]..trade.receivedEnchant end
    ns.Print(table.concat(lines,"\n"))
end

local instanceEvents={"PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED"}
local queueEvents={"LFG_PROPOSAL_SHOW","LFG_PROPOSAL_FAILED","LFG_PROPOSAL_SUCCEEDED","LFG_PROPOSAL_DONE","UPDATE_BATTLEFIELD_STATUS"}
local tradeEvents={"TRADE_SHOW","TRADE_UPDATE","TRADE_PLAYER_ITEM_CHANGED","TRADE_TARGET_ITEM_CHANGED",
    "TRADE_MONEY_CHANGED","PLAYER_TRADE_MONEY","TRADE_ACCEPT_UPDATE","TRADE_CLOSED","TRADE_REQUEST_CANCEL","UI_INFO_MESSAGE","PLAYER_LEAVING_WORLD"}
local function refresh()
    events:UnregisterAllEvents()
    for key,list in pairs({instanceInfo=instanceEvents,queueReady=queueEvents,tradeReceipt=tradeEvents})do
        if enabled(key) then
            for _,event in ipairs(list)do events:RegisterEvent(event)end
        end
    end
    if not enabled("instanceInfo") then
        instanceRevision=instanceRevision+1;instanceKey=nil;pendingInstance=nil;hideBar("instanceInfo")
    end
    if not enabled("queueReady") then lfgReady=false;pvpReady={};hideBar("queueReady")end
    if not enabled("tradeReceipt") then activeTrade=nil;pendingTrade=nil end
end
function M.Start()
    if running then return end
    running=true;refresh()
end
function M.Stop()
    running=false;refresh()
end
function M.AddOptionGroups(groups)
    local function timing(label,key)
        return function(cell)
            local limits=timingLimits[key]
            cell:Slider("BaimiaoSmallTools"..key,label,limits[1],limits[2],.5,
                function()return seconds(key)end,function(v)DB()[key]=v end)
        end
    end
    groups[#groups+1]={title=T["进本信息小条"],collapsed=true,
        enabled=function()return DB().instanceInfo end,setEnabled=function(v)DB().instanceInfo=v;refresh()end,
        build=function(_,L)
            L:Row({timing(T["进本停留时间（秒）"],"instanceHoldSeconds"),timing(T["进本渐隐时间（秒）"],"instanceFadeSeconds")},260)
            L:Text(T["停留后渐隐；渐隐为 0 时直接隐藏。修改从下次提醒或预览生效。"],true)
            L:Button(200,T["预览进本小条"],function()
                if enabled("instanceInfo")then toast("instanceInfo",T["|cff0cd29f进本信息 · 示例（非当前状态）|r\n史诗难度  |  拾取专精：惩戒  |  最低耐久：|cffff665528%|r"])end
            end)
        end}
    groups[#groups+1]={title=T["排队就绪提醒"],collapsed=true,
        enabled=function()return DB().queueReady end,setEnabled=function(v)DB().queueReady=v;refresh()end,
        build=function(_,L)
            L:Check(T["排队提示音（遵循游戏声音设置）"],function()return DB().queueSound end,function(v)DB().queueSound=v end)
            L:Row({timing(T["排队停留时间（秒）"],"queueHoldSeconds"),timing(T["排队渐隐时间（秒）"],"queueFadeSeconds")},260)
            L:Text(T["停留后渐隐；渐隐为 0 时直接隐藏。修改从下次提醒或预览生效。"],true)
            L:Button(200,T["预览排队提醒"],function()
                if enabled("queueReady")then queueNotice(T["示例队列（非实际邀请）"])end
            end)
        end}
    groups[#groups+1]={title=T["交易完成回执（仅自己可见）"],
        enabled=function()return DB().tradeReceipt end,setEnabled=function(v)DB().tradeReceipt=v;refresh()end}
end

events:SetScript("OnEvent",function(_,event,a,b)
    if not running or not ns.IsModuleEnabled("smalltools") then return end
    if event=="PLAYER_ENTERING_WORLD" then enteredWorld(a,b)
    elseif event=="PLAYER_REGEN_ENABLED" then displayInstance()
    elseif event=="LFG_PROPOSAL_SHOW" and enabled("queueReady") then
        proposal()
    elseif event=="LFG_PROPOSAL_FAILED" or event=="LFG_PROPOSAL_SUCCEEDED" or event=="LFG_PROPOSAL_DONE" then
        lfgReady=false;hideBar("queueReady")
    elseif event=="UPDATE_BATTLEFIELD_STATUS" and enabled("queueReady") then battlefield(a)
    elseif enabled("tradeReceipt") then
        if event=="TRADE_SHOW" then
            pendingTrade=nil;activeTrade={partner=partnerName()};snapshotTrade()
        elseif event=="TRADE_CLOSED" then closeTrade()
        elseif event=="TRADE_REQUEST_CANCEL" or event=="PLAYER_LEAVING_WORLD" then activeTrade=nil;pendingTrade=nil
        elseif event=="UI_INFO_MESSAGE" then tradeComplete(b)
        elseif event=="TRADE_UPDATE" or event=="TRADE_PLAYER_ITEM_CHANGED" or event=="TRADE_TARGET_ITEM_CHANGED"
            or event=="TRADE_MONEY_CHANGED" or event=="PLAYER_TRADE_MONEY" or event=="TRADE_ACCEPT_UPDATE" then
            snapshotTrade()
        end
    end
end)
