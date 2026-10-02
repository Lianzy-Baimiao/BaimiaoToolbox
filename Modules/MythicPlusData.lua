-- Retail Mythic+ data adapter. No SavedVariables, UI, networking or addon dependency.
local ADDON, ns = ...
local D = {}
ns.MythicPlusData = D

-- Challenge-mode IDs, not instance/zone IDs. Unknown future maps remain visible;
-- they deliberately have no cast action until their portal is verified.
local portals = {
    [239]=1254551, [556]=1254555, [402]=393273, [557]=1254400,
    [558]=1254572, [560]=1254559, [559]=1254563, [525]=1216786,
    [499]=445444, [505]=445414, [503]=445417, [542]=1237215,
    [378]=354465, [391]=367416, [392]=367416,
    [587]=1286809, [584]=1286801, [585]=1286804, [586]=1286807,
    [399]=393256, [249]=1286831, [250]=1286828, [588]=1286812,
}
local function public(v) return not (issecretvalue and issecretvalue(v)) end
function D.Number(v)
    if public(v) and type(v)=="number" and v==v and v~=math.huge and v~=-math.huge then return v end
end
local function call(api, name, ...)
    local fn=api and api[name]
    if type(fn)~="function" then return end
    local ok,a,b,c,d,e,f=pcall(fn,...)
    if ok and public(a) then return a,b,c,d,e,f end
end
D.Call=call
-- Keep level, individual-dungeon score and overall rating on their own scales.
-- A missing/restricted color is not a reason to hide the numerical data.
local colorAPIs={level="GetKeystoneLevelRarityColor",mapScore="GetSpecificDungeonOverallScoreRarityColor",
    rating="GetDungeonScoreRarityColor"}
local function colorRGB(color)
    if not public(color) or type(color)~="table" then return end
    local r,g,b=D.Number(color.r),D.Number(color.g),D.Number(color.b)
    if r and g and b then
        return math.max(0,math.min(1,r)),math.max(0,math.min(1,g)),math.max(0,math.min(1,b))
    end
end
function D.RarityColor(kind,value)
    value=D.Number(value)
    if not value or value<=0 or not colorAPIs[kind] then return end
    return colorRGB(call(C_ChallengeMode,colorAPIs[kind],value))
end
function D.ClassColor(classFile)
    if not public(classFile) or type(classFile)~="string" then return end
    local r,g,b=colorRGB(call(C_ClassColor,"GetClassColor",classFile))
    if r then return r,g,b end
    if public(RAID_CLASS_COLORS) and type(RAID_CLASS_COLORS)=="table" then
        return colorRGB(RAID_CLASS_COLORS[classFile])
    end
end
function D.Known(id)
    if not id then return false end
    -- Retail 12.x uses C_SpellBook; legacy globals can be absent or incomplete.
    local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if call(C_SpellBook,"IsSpellKnown",id,bank)==true then return true end
    for _,fn in ipairs({IsPlayerSpell or false, IsSpellKnown or false, C_Spell and C_Spell.IsSpellKnown or false}) do
        if type(fn)=="function" then
            local ok,known=pcall(fn,id)
            if ok and public(known) and known==true then return true end
        end
    end
    return false
end
function D.PortalID(mapID)
    if mapID==161 then
        local horde=UnitFactionGroup and UnitFactionGroup("player")=="Horde"
        local first,second=horde and 159898 or 1254557,horde and 1254557 or 159898
        return D.Known(first) and first or (D.Known(second) and second or first)
    end
    return portals[mapID]
end
function D.Portal(mapID)
    local id=D.PortalID(mapID)
    if not id then return nil,"未收录传送" end
    if not D.Known(id) then return id,"未学会传送" end
    if InCombatLockdown() then return id,"战斗中不可传送" end
    local cd=call(C_Spell,"GetSpellCooldown",id)
    if type(cd)=="table" then
        local start,duration=D.Number(cd.startTime),D.Number(cd.duration)
        if not start or not duration then return id,"冷却状态暂不可用" end
        local remaining=math.max(0,start+duration-GetTime())
        if remaining>1.5 then
            local minutes=math.ceil(remaining/60)
            return id,minutes>=60 and ("冷却 "..math.ceil(minutes/60).." 小时") or ("冷却 "..minutes.." 分钟")
        end
    else
        return id,"冷却状态暂不可用"
    end
    return id,"点击传送"
end
function D.Map(id)
    local name,_,limit,texture=call(C_ChallengeMode,"GetMapUIInfo",id)
    return {id=id, name=type(name)=="string" and name or ("地下城 #"..id),
        limit=D.Number(limit),texture=(public(texture) and texture) or 134400,
        best=0,score=0,count=0,weekly=0,timed=0}
end
-- Copy only public fields; do not retain or mutate Blizzard tables.
local function plainTable(v) return public(v) and type(v)=="table" end
local function dateCopy(value)
    if not plainTable(value) then return end
    local date={}
    for _,key in ipairs({"year","month","monthDay","hour","minute"}) do
        date[key]=D.Number(value[key]);if not date[key] then return end
    end
    if date.month<1 or date.month>12 or date.monthDay<1 or date.monthDay>31
        or date.hour<0 or date.hour>23 or date.minute<0 or date.minute>59 then return end
    return date
end
local function membersCopy(value)
    local result={}
    if not plainTable(value) then return result end
    for _,member in ipairs(value) do
        if plainTable(member) then
            result[#result+1]={name=public(member.name) and type(member.name)=="string" and member.name or nil,
                classID=D.Number(member.classID),specID=D.Number(member.specID)}
        end
    end
    return result
end
local function bestCopy(value,source)
    if not plainTable(value) then return end
    local level,duration=D.Number(value.level),D.Number(value.durationSec)
    if not level or level<=0 then return end
    local affixIDs={}
    if plainTable(value.affixIDs) then
        for _,id in ipairs(value.affixIDs) do if D.Number(id) then affixIDs[#affixIDs+1]=id end end
    end
    return {level=level,duration=duration,date=dateCopy(value.completionDate),score=D.Number(value.dungeonScore),
        members=membersCopy(value.members),affixIDs=affixIDs,source=source}
end
-- Called only when hovering. Weekly history has no roster; best APIs do.
function D.MapDetails(id)
    local duration,level,date,affixes,members,score=call(C_MythicPlus,"GetWeeklyBestForMap",id)
    local result={}
    local weekly=bestCopy({durationSec=duration,level=level,completionDate=date,affixIDs=affixes,members=members,dungeonScore=score},"本周最佳")
    if weekly then result[#result+1]=weekly end
    local intime,overtime=call(C_MythicPlus,"GetSeasonBestForMap",id)
    for _,pair in ipairs({{intime,"赛季限时最佳"},{overtime,"赛季超时最佳"}}) do
        local best=bestCopy(pair[1],pair[2]);if best then result[#result+1]=best end
    end
    return result
end
-- Best-roster tooltip is deliberately independent of the hovered history row.
-- Cards prefer season best; weekly rows/summary prefer weekly best.
-- Return the complete chosen record; never splice teammates from another run.
function D.MemberCounts(members)
    local named=0
    for _,member in ipairs(members or {}) do
        if member.name and member.name~="" then named=named+1 end
    end
    return #(members or {}),named
end
function D.BestDetails(id,preferWeekly)
    local best,weekly
    local candidates=D.MapDetails(id)
    for _,candidate in ipairs(candidates) do
        if candidate.source=="本周最佳" then weekly=candidate
        elseif not best or (candidate.score or 0)>(best.score or 0)
            or ((candidate.score or 0)==(best.score or 0) and candidate.level>best.level) then best=candidate end
    end
    local chosen=(preferWeekly and weekly) or best or weekly
    local alternate=chosen==weekly and best or weekly
    if chosen and alternate then
        local _,named=D.MemberCounts(chosen.members)
        local _,otherNamed=D.MemberCounts(alternate.members)
        -- A self-only/anonymous result is not useful as a team. Fall back to the
        -- other best record as a whole, including its source, level and time.
        if named<2 and otherNamed>=2 then chosen=alternate end
    end
    return chosen,candidates
end
function D.Snapshot()
    local result={maps={},byMap={},runs={},vault={},affixes={}}
    local maps=call(C_ChallengeMode,"GetMapTable")
    result.mapsReady=type(maps)=="table" and #maps>0
    for _,id in ipairs(type(maps)=="table" and maps or {}) do
        id=D.Number(id)
        if id and not result.byMap[id] then
            local map=D.Map(id);result.byMap[id]=map;result.maps[#result.maps+1]=map
        end
    end
    local summary=call(C_PlayerInfo,"GetPlayerMythicPlusRatingSummary","player")
    if type(summary)=="table" and type(summary.runs)=="table" then
        for _,map in ipairs(result.maps) do map.ratingReady=true end
        result.rating=D.Number(summary.currentSeasonScore)
        for _,run in ipairs(type(summary.runs)=="table" and summary.runs or {}) do
            local id=D.Number(run.challengeModeID)
            local map=id and result.byMap[id]
            if map then map.best=D.Number(run.bestRunLevel) or 0;map.score=D.Number(run.mapScore) or 0 end
        end
    end
    local history=call(C_MythicPlus,"GetRunHistory",false,true,true)
    result.historyReady=type(history)=="table"
    for index,run in ipairs(type(history)=="table" and history or {}) do
        local id,level=D.Number(run.mapChallengeModeID),D.Number(run.level)
        if id and level and level>0 and public(run.thisWeek) and run.thisWeek~=false then
            local map=result.byMap[id] or D.Map(id)
            local duration=D.Number(run.durationSec)
            local timed
            -- Use elapsed time vs the map's limit. Do not guess the meaning of
            -- `completed`, or label unknown/restricted timings as failed runs.
            if duration and duration>0 and map.limit and map.limit>0 then timed=duration<=map.limit end
            local entry={id=id,name=map.name,level=level,timed=timed,duration=duration,limit=map.limit,index=index,
                date=dateCopy(run.completionDate),score=D.Number(run.runScore)}
            result.runs[#result.runs+1]=entry
            map.count=map.count+1;map.weekly=math.max(map.weekly,level)
            if timed then map.timed=map.timed+1 end
        end
    end
    table.sort(result.runs,function(a,b) if a.level~=b.level then return a.level>b.level end;return a.index<b.index end)
    local activities=call(C_WeeklyRewards,"GetActivities",Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities or 1)
    for _,a in ipairs(type(activities)=="table" and activities or {}) do
        local threshold,progress=D.Number(a.threshold),D.Number(a.progress)
        if threshold and threshold>0 and progress then
            result.vault[#result.vault+1]={threshold=threshold,progress=progress,level=D.Number(a.level),index=D.Number(a.index) or 0}
        end
    end
    table.sort(result.vault,function(a,b)return a.index<b.index end)
    for _,a in ipairs(call(C_MythicPlus,"GetCurrentAffixes") or {}) do
        local id=D.Number(a.id)
        if id then
            local name,description,texture=call(C_ChallengeMode,"GetAffixInfo",id)
            result.affixes[#result.affixes+1]={id=id,name=name or ("词缀 #"..id),description=description,texture=texture or 134400}
        end
    end
    result.keyMap=D.Number(call(C_MythicPlus,"GetOwnedKeystoneChallengeMapID"))
    result.keyLevel=D.Number(call(C_MythicPlus,"GetOwnedKeystoneLevel"))
    if result.keyMap then result.keyName=(result.byMap[result.keyMap] or D.Map(result.keyMap)).name end
    return result
end
