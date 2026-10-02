-- Current party only. Public, self-reported keys; no inspection, persistent
-- history or chat spam. Interoperates with LibKeystone and Keystone Group List.
local ADDON,ns=...
local K={};ns.PartyKeystones=K
local frame=CreateFrame("Frame")
local running,notify,allowed=false,nil,nil
local cache,roster,lastSend={}, {}, {}
local signature,lastRequest="",-100
local lastOwn,ownQueued,epoch={},false,0
local prefixes={"LibKS","WA-KeyStGrList"}
local function public(v)return not (issecretvalue and issecretvalue(v))end
local function str(v)return public(v) and type(v)=="string" and v~="" and v or nil end
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b,c=pcall(fn,...)
    if ok and public(a) and public(b) and public(c) then return a,b,c end
end
local function active()return running and (not allowed or allowed())end
local function channel()
    if call(IsInRaid)==true or call(IsInRaid,LE_PARTY_CATEGORY_INSTANCE or 2)==true then return end
    if call(IsInGroup,LE_PARTY_CATEGORY_INSTANCE or 2)==true then return "INSTANCE_CHAT" end
    if call(IsInGroup,LE_PARTY_CATEGORY_HOME or 1)==true then return "PARTY" end
end
local function full(name,realm)
    name=str(name);realm=str(realm)
    if not name or name:find("[|%s]") then return end
    if name:find("-",1,true) then return name end
    realm=realm or str(call(GetNormalizedRealmName))
    return realm and name.."-"..realm:gsub("%s","") or nil
end
local function changed()if notify then notify()end end
local function rebuild()
    local list,ids,seen={}, {}, {}
    local ch=channel()
    if ch then for i=1,4 do
        local unit="party"..i
        if call(UnitExists,unit)==true then
            local name,realm=call(UnitFullName,unit)
            local owner=full(name,realm);local guid=str(call(UnitGUID,unit))
            if owner and guid and not seen[guid] then
                seen[guid]=true
                local _,class=call(UnitClass,unit)
                local online=call(UnitIsConnected,unit)~=false
                list[#list+1]={name=owner,shortName=name,unit=unit,guid=guid,class=str(class),online=online}
                ids[#ids+1]=owner..":"..guid..":"..tostring(online)
                if not online then cache[guid]=nil end
            end
        end
    end end
    for guid in pairs(cache)do if not seen[guid] then cache[guid]=nil end end
    roster=list
    local key=(ch or "solo").."/"..table.concat(ids,"/")
    local different=signature~=key;signature=key
    return different
end
local function member(sender)
    sender=str(sender);if not sender then return end
    local owner=full(sender)
    for _,row in ipairs(roster)do if row.name==owner then return row end end
end
local function pair(map,level)
    map,level=tonumber(map),tonumber(level)
    if not map or not level or map~=math.floor(map) or level~=math.floor(level) then return end
    if map==0 and level==0 then return 0,0 end
    if map>0 and map<1000000 and level>=2 and level<=200 then return map,level end
end
local function own()
    local map=call(C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID)
    local level=call(C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel)
    -- Missing/restricted APIs are not evidence that the player has no key.
    if type(map)~="number" or type(level)~="number" then return end
    return pair(map,level)
end
local function locked()
    return InCombatLockdown() or call(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)==true
end
local function send(prefix,message)
    local ch=channel()
    if not active() or not ch or locked() then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage,prefix,message,ch)end
end
local function announce(prefix)
    local now=GetTime();if now-(lastSend[prefix] or -100)<3 then return end
    local map,level=own();if not map then return end
    if locked() then return end
    lastSend[prefix]=now
    if prefix=="LibKS" then
        local info=call(C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary,"player")
        local rating=public(info) and type(info)=="table" and info.currentSeasonScore or nil
        rating=public(rating) and type(rating)=="number" and rating>=0 and rating<100000 and math.floor(rating) or 0
        send(prefix,string.format("%d,%d,%d",level,map,rating))
    else send(prefix,string.format("KSGL:Send:%d:%d:0:0:0",map,level))end
end
local function updateOwn()
    local map,level=own();if not map then return end
    local key=map..":"..level
    if locked() then return end
    for _,prefix in ipairs(prefixes)do
        if lastOwn[prefix]~=key then
            if GetTime()-(lastSend[prefix] or -100)>=3 then
                announce(prefix);lastOwn[prefix]=key
            elseif not ownQueued then
                ownQueued=true;local generation=epoch
                C_Timer.After(3.1,function()
                    if generation~=epoch then return end
                    ownQueued=false;if active() then updateOwn()end
                end)
            end
        end
    end
end
function K.Request()
    if not active() then return end
    rebuild();changed()
    if not channel() or locked() or GetTime()-lastRequest<5 then return end
    lastRequest=GetTime()
    send("LibKS","R");send("WA-KeyStGrList","KSGL:Request:0")
    for _,prefix in ipairs(prefixes)do announce(prefix)end
end
local function store(row,map,level,source)
    map,level=pair(map,level)
    if not map or not row.online then return end
    cache[row.guid]={mapID=map,level=level,time=GetTime(),source=source}
    changed()
end
local function receive(prefix,message,ch,sender)
    if not active() or not str(prefix) or not str(message) or not str(ch) or #message>100 then return end
    if ch~=channel() then return end
    rebuild();local row=member(sender);if not row or not row.online then return end
    if prefix=="LibKS" then
        if message=="R" then announce(prefix);return end
        local level,map=message:match("^(%d+),(%d+),%d+$")
        if map then store(row,map,level,"队友同步")end
    elseif prefix=="WA-KeyStGrList" then
        if message=="KSGL:Request:0" then announce(prefix);return end
        local map,level=message:match("^KSGL:Send:(%d+):(%d+):%d+:%d+:%d+$")
        if map then store(row,map,level,"队友同步")end
    end
end
function K.Snapshot()
    if not active() then return {} end
    rebuild();local result={}
    for _,row in ipairs(roster)do
        local item={name=row.name,shortName=row.shortName,class=row.class,unit=row.unit,online=row.online}
        local data=cache[row.guid]
        if data and GetTime()-data.time<=600 then
            item.mapID=data.mapID;item.level=data.level;item.source=data.source
            item.status=data.mapID==0 and "无钥石" or nil
        else item.status=row.online and "待同步" or "离线" end
        result[#result+1]=item
    end
    return result
end
function K.Stop()
    running=false;frame:UnregisterAllEvents();cache={};roster={};signature="";lastRequest=-100;lastSend={}
    epoch=epoch+1;ownQueued=false;lastOwn={}
    changed()
end
function K.Start(callback,predicate)
    notify=callback;allowed=predicate
    if running then K.Request();return end
    running=true;epoch=epoch+1
    for _,prefix in ipairs(prefixes)do call(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,prefix)end
    for _,event in ipairs({"CHAT_MSG_ADDON","CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER","CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD",
        "BAG_UPDATE_DELAYED","CHALLENGE_MODE_START","CHALLENGE_MODE_COMPLETED","PLAYER_REGEN_ENABLED"})do frame:RegisterEvent(event)end
    K.Request()
end
frame:SetScript("OnEvent",function(_,event,...)
    if not active() then return end
    if event=="CHAT_MSG_ADDON" then receive(...)
    elseif event:find("^CHAT_MSG_") then
        local message,sender=...
        if not str(message) or #message>2048 then return end
        local ch=event:find("INSTANCE") and "INSTANCE_CHAT" or "PARTY"
        if ch~=channel() then return end
        rebuild();local row=member(sender);if not row then return end
        local map,level=message:match("|Hkeystone:%d+:(%d+):(%d+):")
        if map then store(row,map,level,"队友分享的钥石链接")end
    elseif event=="PLAYER_LEAVING_WORLD" then cache={};changed()
    elseif event=="CHALLENGE_MODE_START" then cache={};changed()
    elseif event=="GROUP_ROSTER_UPDATE" then
        if rebuild() then lastRequest=-100;K.Request()end
    elseif event=="BAG_UPDATE_DELAYED" then
        updateOwn()
    else
        if event=="PLAYER_ENTERING_WORLD" or event=="CHALLENGE_MODE_COMPLETED" then cache={};lastRequest=-100 end
        K.Request()
        if event=="CHALLENGE_MODE_COMPLETED" then
            local generation=epoch
            C_Timer.After(5,function()if generation==epoch and active() then K.Request()end end)
        end
    end
end)
