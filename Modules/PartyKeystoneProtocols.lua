-- Wire formats only; no addon globals, roster, cache or UI dependencies.
local ADDON,ns=...
local P={prefixes={"LibKS","WA-KeyStGrList","AngryKeystones","LRS"}}
ns.PartyKeystoneProtocols=P
local D=ns.KeystoneDeflate
-- LRS uses raw DEFLATE + LibDeflate addon-channel encoding, then AceComm framing.
-- J/K packets fit one message. Never assemble unrelated cooldown/gear streams.
local function pack(text)
    if not D then return end
    local ok,compressed=pcall(D.CompressDeflate,D,text,{level=1})
    if not ok or type(compressed)~="string" then return end
    local encoded=D:EncodeForWoWAddonChannel(compressed)
    if encoded:find("^[\001-\009]") then encoded="\004"..encoded end
    if #encoded<=255 then return encoded end
end
local function unpackKey(message)
    if not D or #message>255 then return end
    local control=message:byte(1)
    if control==4 then message=message:sub(2)
    elseif control and control<=9 then return end
    local ok,compressed=pcall(D.DecodeForWoWAddonChannel,D,message)
    if not ok or type(compressed)~="string" then return end
    local success,text,remaining=pcall(D.DecompressDeflate,D,compressed)
    if success and type(text)=="string" and #text<=128 and remaining==0 then return text end
end
local function uint(value,maximum)
    local n=tonumber(value)
    return n and n>=0 and n<=maximum and n==math.floor(n)
end
local known={};for _,prefix in ipairs(P.prefixes)do known[prefix]=true end
function P.Supports(prefix,channel)
    return known[prefix] and (channel=="PARTY" or channel=="INSTANCE_CHAT" and prefix~="AngryKeystones")
end
function P.Request(prefix)
    if prefix=="LibKS" then return "R"
    elseif prefix=="WA-KeyStGrList" then return "KSGL:Request:0"
    elseif prefix=="AngryKeystones" then return "Schedule|request"
    elseif prefix=="LRS" then return pack("J")end
end
function P.Key(prefix,info)
    if prefix=="LibKS" then return string.format("%d,%d,%d",info.level,info.map,info.rating)
    elseif prefix=="WA-KeyStGrList" then return string.format("KSGL:Send:%d:%d:0:0:0",info.map,info.level)
    elseif prefix=="AngryKeystones" then
        return info.map==0 and "Schedule|0" or string.format("Schedule|%d:%d",info.map,info.level)
    elseif prefix=="LRS" then
        return pack(string.format("K,%d,%d,%d,%d,%d,%d,%d",info.level,info.worldMap or 0,
            info.map,info.classID or 0,info.rating,info.map,info.specID or 0))
    end
end
function P.Read(prefix,message)
    if type(message)~="string" or #message==0 or #message>255 then return end
    local map,level
    if prefix=="LibKS" then
        if message=="R" then return "request" end
        level,map=message:match("^(%d+),(%d+),%d+$")
    elseif prefix=="WA-KeyStGrList" then
        if message=="KSGL:Request:0" then return "request" end
        map,level=message:match("^KSGL:Send:(%d+):(%d+):%d+:%d+:%d+$")
    elseif prefix=="AngryKeystones" then
        if message=="Schedule|request" then return "request" end
        if message=="Schedule|0" then return "key",0,0 end
        map,level=message:match("^Schedule|(%d+):(%d+)$")
    elseif prefix=="LRS" then
        local text=unpackKey(message);if not text then return end
        if text=="J" then return "request" end
        local world,class,rating,mythic,spec
        level,world,map,class,rating,mythic,spec=text:match("^K,(%d+),(%d+),(%d+),(%d+),(%d+%.?%d*),(%d+),(%d+)$")
        if not level then
            -- Older OpenRaid builds sent six fields (no specialization).
            level,world,map,class,rating,mythic=text:match("^K,(%d+),(%d+),(%d+),(%d+),(%d+%.?%d*),(%d+)$")
        end
        if not level or not uint(world,999999) or not uint(class,100) or not uint(mythic,999999)
            or not uint(spec or "0",99999) or not tonumber(rating) or tonumber(rating)>100000 then return end
        -- Field 3 is challengeMapID; field 2 is a DIFFERENT map ID. Never swap them.
    end
    if map then return "key",tonumber(map),tonumber(level) end
end
