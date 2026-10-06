-- A reversible presentation of the native Mythic Keystone tab.
-- Does not replace Blizzard methods, touch other addons' saved settings, or cast
-- from Lua. Teleports use hardware-click secure buttons, prepared out of combat.
local ADDON, ns = ...
-- Startup-only local timer view; restored to the untouched global API on stop.
local C_Timer = C_Timer
if ns.StartupTimerScope then ns.StartupTimerScope("MythicPlus", C_Timer, function(api) C_Timer = api end) end
local T = ns.L
local ID, D, UI = "mythicplus", ns.MythicPlusData, ns.UI
local WHITE="Interface\\Buttons\\WHITE8x8"
local defaults={show=true,showWeekly=true,showBest=true,showScore=true,teleport=true,
    replaceKogo=true,scalePercent=100,sortBy="score"}
local function DB() return ns.GetDB(ID,defaults) end
local function Enabled() return ns.IsModuleEnabled(ID) and DB().show end
local host, canvas, original, applied, snapshot
local active, pending, queued, hooked, kogoHooked=false,false,false,false,nil
local queuedFull,queuedParty,queuedKey=false,false,false
local kogoWasShown=false
local tiles, affixes, rows, vaults, painters = {},{},{},{},{}
local page, rowOffset, mode=1,0,"runs"
local partyRows={}
local PARTY_NAME_WIDTH=100
local PARTY_ROW_WIDTH=PARTY_NAME_WIDTH+92
local lastTeamMapID,lastTeamWeekly
local W,H=820,422
local CONTENT_BOTTOM=H-8
local TILE_HEIGHT,TILE_PITCH=64,70
local TILE_TOP=CONTENT_BOTTOM-3*TILE_PITCH-TILE_HEIGHT
local Refresh, Queue, Render, HidePortals, RequestData, SyncEvents
local events=CreateFrame("Frame")
-- Presentation belongs to these pooled widgets. Remember only the last applied
-- value, not historical snapshots; live game data is still read on every refresh.
local function setText(f,value)
    if f._bmPresentedText==value then return false end
    f._bmPresentedText=value;f:SetText(value);return true
end
local function setWidth(f,width)
    if f._bmPresentedWidth==width then return end
    f._bmPresentedWidth=width;f:SetWidth(width)
end
local function setTexture(f,texture)
    if f._bmPresentedTexture==texture then return end
    f._bmPresentedTexture=texture;f:SetTexture(texture)
end
local function styleText(f,role)
    role=role or "text"
    -- StyleText's existing theme subscription handles palette/outline changes.
    if not f._bmTextStyled or f._bmTextRole~=role or f._bmTextOnWorld then UI.StyleText(f,role) end
end
local function Paint()
    for _,fn in ipairs(painters) do fn() end
end
local function paint(fn) painters[#painters+1]=fn;fn() end
local function text(parent,value,size,role)
    local fs=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    UI.SetRuntimeFont(fs,STANDARD_TEXT_FONT or GameFontNormal:GetFont(),size or 13)
    fs:SetJustifyH("LEFT");fs:SetWordWrap(false);setText(fs,value)
    styleText(fs,role or "text")
    return fs
end
local function surface(parent,role,borderless)
    local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetBackdrop(borderless and {bgFile=WHITE} or {bgFile=WHITE,edgeFile=WHITE,edgeSize=1})
    paint(function()
        f:SetBackdropColor(unpack(UI.palette[role or "card"]))
        f:SetBackdropBorderColor(unpack(UI.palette.border))
    end)
    return f
end
local function place(f,x,y,w,h)
    if f._bmLayoutX~=x or f._bmLayoutY~=y then
        f._bmLayoutX=x;f._bmLayoutY=y
        f:ClearAllPoints();f:SetPoint("TOPLEFT",canvas,"TOPLEFT",x,-y)
    end
    if f._bmLayoutW~=w or f._bmLayoutH~=h then
        f._bmLayoutW=w;f._bmLayoutH=h;f:SetSize(w,h)
    end
end
local function label(parent,value,size,x,y,w,role)
    local fs=text(parent,value,size,role);fs:SetPoint("TOPLEFT",x,-y);fs:SetWidth(w);return fs
end
local function tip(owner,title,lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner,"ANCHOR_CURSOR");GameTooltip:SetText(title)
    for _,line in ipairs(lines or {}) do
        if type(line)=="table" then
            GameTooltip:AddDoubleLine(line[1],line[2],0.8,0.85,0.85,0.65,0.7,0.7)
        else GameTooltip:AddLine(line,0.8,0.85,0.85,true) end
    end
    GameTooltip:Show()
end
local function leave() if GameTooltip then GameTooltip:Hide() end end
local function button(parent,value,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,26);setText(b,value);UI.SkinTextButton(b)
    styleText(b:GetFontString(),"text")
    UI.RegisterRuntimeFont(b:GetFontString())
    b:SetScript("OnClick",fn);return b
end
local function openVault()
    if InCombatLockdown() then ns.Print(T["请脱离战斗后查看宏伟宝库。"]);return end
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WeeklyRewards") end
    if WeeklyRewardsFrame then ShowUIPanel(WeeklyRewardsFrame) else ns.Print(T["宏伟宝库界面暂不可用。"]) end
end
local function openTab()
    if InCombatLockdown() then ns.Print(T["请脱离战斗后打开大秘境页签。"]);return end
    if PVEFrame_ShowFrame then
        PVEFrame_ShowFrame("ChallengesFrame")
        if PVEFrame then ShowUIPanel(PVEFrame) end
    elseif PVEFrame_ToggleFrame then PVEFrame_ToggleFrame("ChallengesFrame") end
end
local function Duration(seconds)
    if not seconds or seconds<=0 then return T["用时未知"] end
    return string.format("%d:%02d",math.floor(seconds/60),math.floor(seconds%60))
end
local function tint(display,r,g,b)
    if not r then return display end
    return string.format("|cff%02x%02x%02x%s|r",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),display)
end
local function colored(kind,value,display) return tint(display,D.RarityColor(kind,value)) end
local function Level(value,timed)
    if timed==false then return tint("+"..(value or 0),unpack(UI.palette.muted)) end
    return colored("level",value,"+"..(value or 0))
end
local function Score(value,kind)
    return value and colored(kind or "mapScore",value,tostring(math.floor(value+.5))) or "—"
end
local function Points(value) return value and (Score(value)..T["分"]) or "—" end
local function Timed(run)
    if run.timed==nil then return T["时间未知"] end
    return run.timed and T["限时"] or T["超时"]
end
local function TimePair(run)
    local elapsed=run.duration and run.duration>0 and Duration(run.duration) or "—"
    local limit=run.limit and run.limit>0 and (run.limit%60==0 and tostring(math.floor(run.limit/60)) or Duration(run.limit)) or "—"
    return "("..elapsed.."/"..limit..")"
end
local function AddMembers(lines,members)
    if not members or #members==0 then lines[#lines+1]=T["暂无队伍名单"];return end
    for _,member in ipairs(members) do
        local class,classFile
        if member.classID then class,classFile=D.Call(_G,"GetClassInfo",member.classID) end
        local _,spec=D.Call(_G,"GetSpecializationInfoByID",member.specID)
        local name=member.name and member.name~="" and member.name or T["姓名未提供"]
        -- Name and specialization have fixed columns, rather than free-form prose.
        lines[#lines+1]={tint(name,D.ClassColor(classFile)),
            (spec or "")..(class and ((spec and " " or "")..class) or "")}
    end
end
local function AddBest(lines,best,limit)
    local timed=best.timed
    if timed==nil then timed=D.Timed(best.duration,limit) end
    local count,named=D.MemberCounts(best.members)
    local suffix=count==1 and T["（仅1人资料）"] or (named<count and T["（姓名不全）"] or "")
    lines[#lines+1]={tint(T[best.source]..T["队伍"]..suffix,unpack(UI.palette.accent)),Level(best.level,timed).." · "..Points(best.score)}
    lines[#lines+1]=T["用时 / 限时  "]..TimePair({duration=best.duration,limit=limit})
    AddMembers(lines,best.members)
end
local function MapLines(map,weekly)
    local lines={}
    lastTeamMapID,lastTeamWeekly=map.id,weekly
    local best=D.BestDetails(map.id,weekly)
    if best then AddBest(lines,best,map.limit)
    else
        lines[#lines+1]=not map.ratingReady and T["赛季成绩待同步"]
            or (map.best>0 and (T["赛季 "]..Level(map.best,map.bestTimed).." · "..Points(map.score)) or T["赛季未完成"])
        lines[#lines+1]=T["暂无最佳队伍信息"]
    end
    return lines
end
local function RunTooltip(owner,run)
    local lines={{T["本次 "]..Level(run.level,run.timed).." "..TimePair(run).." "..Timed(run),Points(run.score)}}
    lastTeamMapID,lastTeamWeekly=run.id,true
    local best=D.BestDetails(run.id,true)
    if best then lines[#lines+1]=" ";AddBest(lines,best,run.limit)
    else lines[#lines+1]=T["暂无最佳队伍信息"] end
    tip(owner,run.name,lines)
end
local function sortedMaps()
    local list={}
    for i,map in ipairs(snapshot.maps) do list[i]=map end
    local sort=DB().sortBy
    table.sort(list,function(a,b)
        if sort=="weekly" and a.weekly~=b.weekly then return a.weekly>b.weekly end
        if sort=="score" and a.score~=b.score then return a.score>b.score end
        if a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    return list
end
local function PortalTooltip(tile,owner)
    if not tile.map then return end
    local _,state=D.Portal(tile.map.id)
    if state==T["点击传送"] and owner~=tile.portal then state=T["传送已就绪"] end
    tip(owner,tile.map.name,{DB().teleport and state or T["传送已关闭"]})
end
local function makeTile(index)
    local f=surface(canvas);f:EnableMouse(true)
    f.icon=f:CreateTexture(nil,"ARTWORK");f.icon:SetSize(30,30);f.icon:SetPoint("TOPLEFT",8,-8)
    f.icon:SetTexCoord(.08,.92,.08,.92)
    f.name=label(f,"",13,46,7,168)
    f.name:SetWordWrap(false);f.name:SetHeight(16)
    f.stats=label(f,"",11,46,26,168,"muted")
    f.week=label(f,"",11,8,47,122,"muted")
    -- Unavailable states use an ordinary (non-secure) status surface in the
    -- exact same slot. Only the independent secure overlay is clickable.
    f.portalStatus=surface(f,"bg");f.portalStatus:SetSize(84,20)
    f.portalStatus:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-8,4);f.portalStatus:EnableMouse(true)
    f.state=text(f.portalStatus,"",10,"muted");f.state:SetPoint("CENTER");f.state:SetWidth(80);f.state:SetJustifyH("CENTER")
    f.portalStatus:SetScript("OnEnter",function(self) PortalTooltip(f,self) end)
    f.portalStatus:SetScript("OnLeave",leave)
    f:SetScript("OnEnter",function(self)
        if self.map then tip(self,self.map.name,MapLines(self.map)) end
    end);f:SetScript("OnLeave",leave)
    -- UIParent ownership is intentional: secure descendants would protect the
    -- native PVE frame/our layout, making combat tab changes unsafe. StateDriver
    -- hides ONLY our independent click targets during combat.
    local b=CreateFrame("Button","BaimiaoMythicPortal"..index,UIParent,"SecureActionButtonTemplate,BackdropTemplate")
    b:Hide();b:EnableMouse(true);b:RegisterForClicks("AnyUp","AnyDown")
    b:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=1})
    b.caption=text(b,T["传送"],11,"accent");b.caption:SetPoint("CENTER")
    local highlight=b:CreateTexture(nil,"HIGHLIGHT");highlight:SetAllPoints();highlight:SetColorTexture(1,1,1,.08)
    paint(function() b:SetBackdropColor(unpack(UI.palette.hover));b:SetBackdropBorderColor(unpack(UI.palette.accent)) end)
    b:SetScript("OnEnter",function(self) PortalTooltip(f,self) end);b:SetScript("OnLeave",leave)
    f.portal=b;tiles[index]=f
    return f
end
local function syncPortal(tile,layoutChanged)
    local b=tile.portal
    if InCombatLockdown() then pending=true;return end
    local id,state
    if tile.map then id,state=D.Portal(tile.map.id) end
    local enabled=DB().teleport
    local usable=not not (active and tile:IsShown() and enabled and id and state==T["点击传送"])
    local scale,strata,level
    if usable then
        scale=tile:GetEffectiveScale()/UIParent:GetEffectiveScale()
        strata=host:GetFrameStrata();level=host:GetFrameLevel()+30
    end
    if not layoutChanged and tile.portalCached and tile.portalID==id and tile.portalState==state
        and tile.portalEnabled==enabled and tile.portalUsable==usable
        and tile.portalScale==scale and tile.portalStrata==strata and tile.portalLevel==level then return end
    tile.portalCached=true;tile.portalID=id;tile.portalState=state
    tile.portalEnabled=enabled;tile.portalUsable=usable
    tile.portalScale=scale;tile.portalStrata=strata;tile.portalLevel=level
    if GameTooltip and (GameTooltip:IsOwned(b) or GameTooltip:IsOwned(tile.portalStatus)) then leave() end
    setText(tile.state,usable and "" or (DB().teleport and (state==T["冷却状态暂不可用"] and T["状态未知"] or state or T["未收录传送"]) or T["传送已关闭"]))
    tile.portalStatus:SetShown(not usable)
    if not usable then
        if b.driver and UnregisterStateDriver then UnregisterStateDriver(b,"visibility");b.driver=nil end
        b:Hide();b:SetAttribute("type1",nil);b:SetAttribute("spell",nil);return
    end
    b:SetScale(scale);b:SetSize(84,20);b:ClearAllPoints();b:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-8,4)
    b:SetFrameStrata(strata);b:SetFrameLevel(level)
    b:SetAttribute("type1","spell");b:SetAttribute("spell",id)
    setText(b.caption,T["点击传送"])
    if RegisterStateDriver and not b.driver then RegisterStateDriver(b,"visibility","[combat] hide; show");b.driver=true end
    b:Show()
end
HidePortals=function()
    if InCombatLockdown() then pending=true;return end
    for _,tile in ipairs(tiles) do
        tile.portalCached=false
        local b=tile.portal
        if b.driver and UnregisterStateDriver then UnregisterStateDriver(b,"visibility");b.driver=nil end
        b:Hide();b:SetAttribute("type1",nil);b:SetAttribute("spell",nil)
    end
end
-- Keep one summary row per dungeon; retain every completion for its tooltip.
local function summaryRows()
    local grouped,list,seen={},{},{}
    for _,run in ipairs(snapshot.runs) do
        local group=grouped[run.id]
        if not group then group={};grouped[run.id]=group end
        group[#group+1]=run
    end
    local function append(map)
        seen[map.id]=true
        local group=grouped[map.id] or {}
        list[#list+1]={item=map,runs=group}
    end
    for _,map in ipairs(sortedMaps()) do append(map) end
    -- History can arrive before the season map list or contain a removed map.
    -- Do not discard those completions merely because no current card exists.
    for _,run in ipairs(snapshot.runs) do
        if not seen[run.id] then append(D.Map(run.id)) end
    end
    return list
end
-- Fit complete level tokens, reserving room for an ellipsis while more remain.
-- Measure the actual font, not byte lengths (names, colors and outlines vary).
local function SummaryLevels(font,runs)
    local path,size,flags=font:GetFont()
    local width=font:GetWidth()
    local cache=font._bmSummaryMeasure
    if cache and cache.count==#runs and cache.width==width and cache.path==path
        and cache.size==size and cache.flags==flags and cache.measure==font.GetUnboundedStringWidth then
        local same=true
        for i,token in ipairs(cache.checked) do
            if Level(runs[i].level,runs[i].timed)~=token then same=false;break end
        end
        if same then setText(font,cache.text);return end
    end
    if not cache then cache={checked={}};font._bmSummaryMeasure=cache end
    wipe(cache.checked)
    local prefix=#runs..T["次  "]
    local parts,shown={},0
    for i,run in ipairs(runs) do
        parts[i]=Level(run.level,run.timed)
        -- Remember only the visible prefix plus the first token that did not fit.
        -- Its changes can make room for another token; never retain run records.
        cache.checked[i]=parts[i]
        setText(font,prefix..table.concat(parts,"/")..(i<#runs and "/…" or ""))
        if font:GetUnboundedStringWidth()>width then parts[i]=nil;break end
        shown=i
    end
    cache.text=prefix..table.concat(parts,"/")..(shown<#runs and (shown>0 and "/…" or "…") or "")
    cache.count=#runs;cache.width=width;cache.path=path;cache.size=size;cache.flags=flags
    cache.measure=font.GetUnboundedStringWidth
    setText(font,cache.text)
end
local function SummaryTooltip(owner,map,runs)
    local lines={}
    if not snapshot.historyReady then lines[1]=T["本周记录待同步"]
    elseif #runs==0 then lines[1]=T["本周尚未完成"]
    else
        lines[1]=T["本周完成 "]..#runs..T[" 次"]
        for i,run in ipairs(runs) do
            lines[#lines+1]={i..". "..Level(run.level,run.timed).." "..TimePair(run),Timed(run)}
        end
    end
    tip(owner,map.name,lines)
end
local function RenderRows()
    if not snapshot or not canvas then return end
    local summary=mode=="maps"
    local list=summary and summaryRows() or snapshot.runs
    local visible=10
    rowOffset=math.max(0,math.min(rowOffset,math.max(0,#list-visible)))
    for i,f in ipairs(rows) do
        if GameTooltip and GameTooltip:IsOwned(f) then leave() end
        local entry=list[rowOffset+i]
        local item=entry and (summary and entry.item or entry)
        f.item=item;f.summary=summary;f.runs=summary and entry and entry.runs or nil
        f:SetShown(item~=nil)
        if item then
            setText(f.left,summary and item.name or (Level(item.level,item.timed).."  "..item.name))
            styleText(f.left,summary and "accent" or "text")
            setText(f.time,summary and "" or TimePair(item))
            f.time:SetShown(not summary)
            if f._bmSummaryLayout~=summary then
                f._bmSummaryLayout=summary
                setWidth(f.left,summary and 142 or 150)
                f.right:ClearAllPoints();f.right:SetPoint("TOPLEFT",summary and 154 or 276,-6)
                setWidth(f.right,summary and 150 or 28)
            end
            if summary then
                if not snapshot.historyReady then setText(f.right,T["待同步"])
                elseif #entry.runs==0 then setText(f.right,T["未完成"])
                else SummaryLevels(f.right,entry.runs) end
            else setText(f.right,item.timed==nil and T["未知"] or Timed(item)) end
            styleText(f.right,not summary and (item.timed==true and "accent" or item.timed==false and "danger") or "muted")
        end
    end
    setText(canvas.empty,summary and (#list==0 and T["等待游戏同步赛季地下城…"] or "")
        or (snapshot.historyReady and (#list==0 and T["本周还没有大秘境记录"] or "") or T["等待游戏同步本周记录…"]))
    setText(canvas.range,#list==0 and "" or string.format("%d–%d / %d",rowOffset+1,math.min(#list,rowOffset+visible),#list)..(#list>visible and T["  ·  滚轮查看更多"] or ""))
    setText(canvas.runTab.caption,T["本周记录  "]..#snapshot.runs)
    setText(canvas.mapTab.caption,T["副本汇总  "]..#snapshot.maps)
    canvas.runTab:UpdateSelection();canvas.mapTab:UpdateSelection()
end
-- Compact teammate rows only. Keep full names in tooltips, dungeon cards and
-- the data/sync layer; unfamiliar dungeons continue to use their native name.
local partyDungeonNames={
    [T["纳洛拉克的洞穴"]]=T["洞穴"],
    [T["虚空之痕竞技场"]]=T["竞技场"],
    [T["虚空之痕"]]=T["竞技场"],
    [T["塞塔里斯神庙"]]=T["神庙"],
    [T["红玉新生法池"]]=T["红玉"],
}
local function RenderParty(members)
    for i,f in ipairs(partyRows)do
        local entry=members[i];f.entry=entry;f:SetShown(entry~=nil)
        if GameTooltip and GameTooltip:IsOwned(f) then leave()end
        if entry then
            setText(f.owner,tint(entry.shortName,D.ClassColor(entry.class)))
            setText(f.level,entry.level and entry.level>0 and Level(entry.level) or "")
            local name=entry.status or D.Map(entry.mapID).name
            setText(f.dungeon,partyDungeonNames[name] or name)
        end
    end
end
-- Shared by full refreshes and small key/roster updates; no history or portal work.
local function RenderHeader()
    local leftWidth=DB().showWeekly and 456 or 796
    local partyLeft=leftWidth+12-PARTY_ROW_WIDTH
    local members=ns.PartyKeystones and ns.PartyKeystones.Snapshot() or {}
    local hasParty=#members>0
    setWidth(canvas.score,hasParty and partyLeft-22 or leftWidth-82)
    local changed=setText(canvas.key,snapshot.keyName and (T["当前钥石  "]..Level(snapshot.keyLevel).."  "..snapshot.keyName) or T["当前未持有钥石"])
    local keyWidth=hasParty and partyLeft-22 or leftWidth-4
    local keyFont=STANDARD_TEXT_FONT or GameFontNormal:GetFont()
    local key=canvas.key
    local font,size,flags=key:GetFont()
    if changed or key._bmFitWidth~=keyWidth or key._bmFitParty~=hasParty or key._bmFitBaseFont~=keyFont
        or key._bmFitFont~=font or key._bmFitSize~=size or key._bmFitFlags~=flags
        or key._bmFitMeasure~=key.GetStringWidth then
        UI.SetRuntimeFont(key,keyFont,18);setWidth(key,0)
        local naturalWidth=key:GetStringWidth()
        if hasParty and naturalWidth>keyWidth then
            UI.SetRuntimeFont(key,keyFont,math.max(14,math.floor(18*keyWidth/naturalWidth)))
        end
        setWidth(key,keyWidth)
        key._bmFitWidth=keyWidth;key._bmFitParty=hasParty;key._bmFitBaseFont=keyFont
        key._bmFitFont,key._bmFitSize,key._bmFitFlags=key:GetFont()
        key._bmFitMeasure=key.GetStringWidth
    end
    RenderParty(members)
end
local function updateOwnKey()
    local map=D.Number(D.Call(C_MythicPlus,"GetOwnedKeystoneChallengeMapID"))
    local level=D.Number(D.Call(C_MythicPlus,"GetOwnedKeystoneLevel"))
    if map==snapshot.keyMap and level==snapshot.keyLevel then return false end
    snapshot.keyMap=map;snapshot.keyLevel=level
    snapshot.keyName=map and (snapshot.byMap[map] or D.Map(map)).name or nil
    return true
end
local function build()
    host=surface(ChallengesFrame,"bg",true);_G.BaimiaoMythicPanel=host;host:Hide();host:EnableMouse(true)
    -- Keep the opaque HIGH-strata mask down to the native icons' bottom edge.
    -- The visible border belongs to the inset canvas, not this cover.
    host:SetPoint("TOPLEFT",ChallengesFrame,"TOPLEFT",8,-30)
    host:SetPoint("BOTTOMRIGHT",ChallengesFrame,"BOTTOMRIGHT",-8,0)
    -- Blizzard dungeon icons explicitly use HIGH strata. Frame levels alone
    -- cannot cover them (or the Kogo secure click layers parented to them).
    host:SetFrameStrata("HIGH")
    host:SetFrameLevel(ChallengesFrame:GetFrameLevel()+200)
    canvas=surface(host,"bg");host.canvas=canvas;canvas.tiles=tiles;canvas.rows=rows;canvas.vaults=vaults;canvas:SetSize(W,H);canvas:SetPoint("TOPLEFT",host,"TOPLEFT",2,-2)
    canvas.title=label(canvas,T["赛季地下城"],19,12,10,300)
    canvas.key=label(canvas,"",18,12,36,450,"accent")
    canvas.score=label(canvas,"",12,12,62,370,"muted")
    canvas.settings=button(canvas,T["设置"],66,function()ns.OpenOptions(ID)end)
    canvas.refresh=button(canvas,T["刷新"],66,function()RequestData();Queue()end)
    canvas.partyRows=partyRows
    for i=1,4 do
        local f=CreateFrame("Frame",nil,canvas);f:SetSize(PARTY_ROW_WIDTH,12);f:EnableMouse(true)
        f.owner=label(f,"",10,0,0,PARTY_NAME_WIDTH)
        f.level=label(f,"",10,PARTY_NAME_WIDTH+2,0,24);f.level:SetJustifyH("RIGHT")
        f.dungeon=label(f,"",10,PARTY_NAME_WIDTH+30,0,62,"muted")
        f:SetScript("OnEnter",function(self)
            local e=self.entry;if not e then return end
            local lines={e.status or (Level(e.level).."  "..D.Map(e.mapID).name)}
            if e.source then lines[#lines+1]=T[e.source]
            elseif e.status==T["待同步"] then lines[#lines+1]=T["等待兼容插件同步，或队友在小队频道分享钥石链接。"]end
            tip(self,e.name,lines)
        end);f:SetScript("OnLeave",leave);partyRows[i]=f
    end
    canvas.affixTitle=label(canvas,T["本周词缀"],11,12,93,68,"muted")
    for i=1,8 do
        local f=CreateFrame("Button",nil,canvas);f:SetSize(26,26);f:SetPoint("TOPLEFT",84+(i-1)*32,-85)
        f.icon=f:CreateTexture(nil,"ARTWORK");f.icon:SetAllPoints();f.icon:SetTexCoord(.08,.92,.08,.92)
        f:SetScript("OnEnter",function(self) if self.info then tip(self,self.info.name,{self.info.description or ""}) end end)
        f:SetScript("OnLeave",leave);affixes[i]=f
    end
    canvas.affixEmpty=label(canvas,T["等待词缀数据…"],11,84,93,280,"muted")
    canvas.mapsTitle=label(canvas,T["副本概览 · 赛季 / 本周"],11,12,121,330,"muted")
    canvas.prev=button(canvas,"‹",26,function()page=math.max(1,page-1);Render()end)
    canvas.next=button(canvas,"›",26,function()page=page+1;Render()end)
    for i=1,8 do makeTile(i) end
    canvas.noMaps=label(canvas,T["赛季地下城数据暂不可用"],13,24,172,400,"muted")
    canvas.weekly=surface(canvas);place(canvas.weekly,480,8,328,CONTENT_BOTTOM-8)
    canvas.weekTitle=label(canvas.weekly,T["本周大秘境"],18,10,10,200)
    canvas.vaultButton=button(canvas.weekly,T["宝库"],60,openVault);canvas.vaultButton:SetPoint("TOPRIGHT",-10,-8)
    canvas.weekStats=label(canvas.weekly,"",11,10,37,308,"muted")
    for i=1,3 do
        local f=surface(canvas.weekly,"bg");f:SetPoint("TOPLEFT",10+(i-1)*104,-58);f:SetSize(100,52)
        f.title=label(f,"",10,7,5,86,"muted");f.value=label(f,"",14,7,20,86,"accent")
        f.detail=label(f,"",10,7,37,86,"muted")
        f:EnableMouse(true)
        f:SetScript("OnEnter",function(self)
            tip(self,T["地下城宝库进度"],{T["含符合条件的英雄 / 史诗地下城。"], T["奖励详情见右上角「宝库」。"]})
        end);f:SetScript("OnLeave",leave);vaults[i]=f
    end
    canvas.selector=surface(canvas.weekly,"bg");canvas.selector:SetPoint("TOPLEFT",10,-116);canvas.selector:SetSize(308,26)
    local function segment(value,x)
        local b=CreateFrame("Button",nil,canvas.selector,"BackdropTemplate")
        b:SetPoint("TOPLEFT",x,-3);b:SetSize(150,20);b:SetBackdrop({bgFile=WHITE})
        b.caption=text(b,"",12);b.caption:SetPoint("CENTER")
        b.indicator=b:CreateTexture(nil,"OVERLAY");b.indicator:SetHeight(2)
        b.indicator:SetPoint("BOTTOMLEFT",4,0);b.indicator:SetPoint("BOTTOMRIGHT",-4,0)
        function b:UpdateSelection()
            self.selected=mode==value
            self:SetBackdropColor(unpack(UI.palette[self.selected and "hover" or (self.hovered and "card" or "bg")]))
            styleText(self.caption,self.selected and "accent" or "muted")
            self.indicator:SetColorTexture(unpack(UI.palette.accent));self.indicator:SetShown(self.selected)
        end
        b:SetScript("OnEnter",function(self)self.hovered=true;self:UpdateSelection()end)
        b:SetScript("OnLeave",function(self)self.hovered=false;self:UpdateSelection()end)
        b:SetScript("OnClick",function()mode=value;rowOffset=0;RenderRows()end)
        paint(function()b:UpdateSelection()end)
        return b
    end
    canvas.runTab=segment("runs",3);canvas.mapTab=segment("maps",155)
    canvas.list=CreateFrame("Frame",nil,canvas.weekly);canvas.list:SetPoint("TOPLEFT",10,-146);canvas.list:SetSize(308,240)
    canvas.list:EnableMouseWheel(true)
    canvas.list:SetScript("OnMouseWheel",function(_,delta)rowOffset=rowOffset-delta*3;RenderRows()end)
    for i=1,10 do
        local f=CreateFrame("Button",nil,canvas.list);f:SetPoint("TOPLEFT",0,-(i-1)*24);f:SetSize(308,23)
        f.bg=f:CreateTexture(nil,"BACKGROUND");f.bg:SetAllPoints()
        local stripe=i%2==0
        paint(function()f.bg:SetColorTexture(unpack(UI.palette[stripe and "bg" or "card"]))end)
        f.left=label(f,"",11,4,6,150)
        f.time=label(f,"",11,158,6,112,"muted");f.time:SetJustifyH("RIGHT")
        f.right=label(f,"",11,276,6,28,"muted");f.right:SetJustifyH("RIGHT")
        f._bmSummaryLayout=false -- initial anchors above already use the run-list layout
        f:EnableMouseWheel(true);f:SetScript("OnMouseWheel",canvas.list:GetScript("OnMouseWheel"))
        f:SetScript("OnEnter",function(self)
            local item=self.item;if not item then return end
            if self.summary then SummaryTooltip(self,item,self.runs) else RunTooltip(self,item) end
        end);f:SetScript("OnLeave",leave);rows[i]=f
    end
    canvas.empty=label(canvas.weekly,"",12,16,189,296,"muted")
    canvas.range=label(canvas.weekly,"",10,10,390,308,"muted")
end
Render=function()
    if InCombatLockdown() then pending=true;return end
    if not snapshot or not canvas then return end
    local db=DB();local leftWidth=db.showWeekly and 456 or 796
    canvas.weekly:SetShown(db.showWeekly)
    place(canvas.settings,leftWidth-114,8,60,24)
    place(canvas.refresh,leftWidth-48,8,60,24)
    -- Grow names leftward; keep the level/dungeon columns and right edge fixed.
    local partyLeft=leftWidth+12-PARTY_ROW_WIDTH
    for i,f in ipairs(partyRows)do place(f,partyLeft,36+(i-1)*12,PARTY_ROW_WIDTH,12)end
    RenderHeader()
    setText(canvas.score,T["赛季评分  "]..Score(snapshot.rating,"rating"))
    for i,f in ipairs(affixes) do
        f.info=snapshot.affixes[i];f:SetShown(f.info~=nil)
        if f.info then setTexture(f.icon,f.info.texture) end
    end
    canvas.affixEmpty:SetShown(#snapshot.affixes==0)
    local list=sortedMaps();local pages=math.max(1,math.ceil(#list/8));page=math.max(1,math.min(page,pages))
    place(canvas.prev,leftWidth-44,116,24,20);place(canvas.next,leftWidth-12,116,24,20)
    canvas.prev:SetShown(pages>1);canvas.next:SetShown(pages>1)
    setText(canvas.mapsTitle,T["副本概览 · 赛季 / 本周"]..(pages>1 and ("  "..page.."/"..pages) or ""))
    local width=(leftWidth-8)/2
    for i,tile in ipairs(tiles) do
        local map=list[(page-1)*8+i];tile.map=map;tile:SetShown(map~=nil)
        if map then
            place(tile,12+((i-1)%2)*(width+8),TILE_TOP+math.floor((i-1)/2)*TILE_PITCH,width,TILE_HEIGHT)
            setTexture(tile.icon,map.texture or 134400);setText(tile.name,map.name);setWidth(tile.name,width-54)
            local best=db.showBest and (not map.ratingReady and T["赛季 —"] or (map.best>0 and (T["赛季 "]..Level(map.best,map.bestTimed)) or T["赛季未完成"])) or ""
            local score=db.showScore and (T["评分 "]..(map.ratingReady and Score(map.score) or "—")) or ""
            setText(tile.stats,best..(best~="" and score~="" and " · " or "")..score);setWidth(tile.stats,width-54)
            setText(tile.week,snapshot.historyReady and (T["本周 "]..map.count..T[" 次"]..(map.weekly>0 and (" · "..Level(map.weekly,map.weeklyRun and map.weeklyRun.timed)) or "")) or T["本周待同步"])
        end
        syncPortal(tile,true)
    end
    canvas.noMaps:SetShown(#list==0)
    local timed=0;for _,run in ipairs(snapshot.runs) do if run.timed then timed=timed+1 end end
    setText(canvas.weekStats,snapshot.historyReady and string.format(T["完成 %d 次  ·  限时 %d 次  ·  最高 %s"],#snapshot.runs,timed,snapshot.weeklyBest and Level(snapshot.weeklyBest.level,snapshot.weeklyBest.timed) or "—") or T["正在同步本周记录…"])
    for i,f in ipairs(vaults) do
        local a=snapshot.vault[i]
        setText(f.title,a and (a.threshold..T[" 次奖励"]) or (T["宝库槽位 "]..i))
        setText(f.value,a and (math.min(a.progress,a.threshold).." / "..a.threshold) or "—")
        styleText(f.value,a and a.progress>=a.threshold and "accent" or "muted")
        setText(f.detail,a and (a.progress>=a.threshold and T["已解锁"] or T["尚未解锁"]) or T["等待游戏数据"])
    end
    RenderRows()
end
local function suppressKogo()
    local frame=_G.KogoMPlusPanel
    if frame and kogoHooked~=frame then
        kogoHooked=frame
        frame:HookScript("OnShow",function(self)
            if active and DB().replaceKogo then kogoWasShown=true;self:Hide() end
        end)
    end
    if frame and active and DB().replaceKogo then
        if frame:IsShown() then kogoWasShown=true;frame:Hide() end
    elseif frame and kogoWasShown then
        kogoWasShown=false
        if ChallengesFrame and ChallengesFrame:IsVisible() then frame:Show() end
    end
end
local function restore()
    active=false
    if host then host:Hide() end
    HidePortals()
    if original and PVEFrame then
        -- PvP updates its width before ChallengesFrame.OnHide. Restore only
        -- dimensions still owned by us, not the new tab's native dimensions.
        if applied and PVEFrame:GetWidth()==applied.width then PVEFrame:SetWidth(original.width) end
        if applied and PVEFrame:GetHeight()==applied.height then PVEFrame:SetHeight(original.height) end
        if applied and PVEFrame:GetScale()==applied.scale then PVEFrame:SetScale(original.scale) end
        original,applied=nil,nil
    end
    suppressKogo()
end
local function fit()
    if not original then original={width=PVEFrame:GetWidth(),height=PVEFrame:GetHeight(),scale=PVEFrame:GetScale()} end
    local percent=math.max(70,math.min(130,tonumber(DB().scalePercent) or 100))/100
    local fitScale=math.min(UIParent:GetWidth()/872,UIParent:GetHeight()/542)
    PVEFrame:SetSize(W+20,H+40);PVEFrame:SetScale(math.min(original.scale*percent,fitScale))
    -- WoW can round scale/geometry internally; compare read-back values on exit.
    applied={width=PVEFrame:GetWidth(),height=PVEFrame:GetHeight(),scale=PVEFrame:GetScale()}
    local scale=math.min(1,(PVEFrame:GetWidth()-20)/W,(PVEFrame:GetHeight()-40)/H)
    canvas:SetScale(scale)
end
Refresh=function()
    if InCombatLockdown() then pending=true;SyncEvents();return end
    pending=false
    SyncEvents()
    local visible=Enabled() and ChallengesFrame and ChallengesFrame:IsVisible() and PVEFrame
    if not visible then restore();return end
    if not host then build() end
    active=true;fit();host:Show()
    snapshot=D.Snapshot();Render();suppressKogo()
end
Queue=function(scope)
    if not Enabled() and not active and not pending then return end
    if scope=="party" or scope=="key" then
        if not active or not ChallengesFrame or not ChallengesFrame:IsVisible() then return end
        if scope=="party" then queuedParty=true else queuedKey=true end
    else queuedFull=true end
    if queued then return end
    queued=true
    C_Timer.After(0,function()
        local full,party,key=queuedFull,queuedParty,queuedKey
        queued=false;queuedFull=false;queuedParty=false;queuedKey=false
        -- Full data/layout changes win regardless of event order. Combat and hide
        -- transitions retain the original restore/defer path for secure buttons.
        if full or pending or not active or not snapshot or not Enabled() or InCombatLockdown()
            or not ChallengesFrame or not ChallengesFrame:IsVisible() then Refresh();return end
        local keyChanged=key and updateOwnKey()
        if party or keyChanged then RenderHeader() end
    end)
end
local function hookChallenges()
    if hooked or not ChallengesFrame then return end
    hooked=true
    ChallengesFrame:HookScript("OnShow",function()
        if not Enabled() then return end
        if ns.PartyKeystones then ns.PartyKeystones.Request()end
        Queue()
        -- Kogo creates its independent panel on a delayed callback. A bounded
        -- discovery window handles that load order; there is no polling ticker.
        for _,delay in ipairs({0.2,1,2}) do C_Timer.After(delay,function()
            if active then suppressKogo() end
        end) end
    end)
    ChallengesFrame:HookScript("OnHide",function()
        if not InCombatLockdown() then restore() else pending=true end
    end)
    if type(ChallengesFrame.Update)=="function" then hooksecurefunc(ChallengesFrame,"Update",Queue) end
    if PVEFrame then
        PVEFrame:HookScript("OnHide",function()if not InCombatLockdown() then restore() else pending=true end end)
    end
    if type(PVEFrame_ShowFrame)=="function" then hooksecurefunc("PVEFrame_ShowFrame",Queue) end
end
local lastRequest=-100
RequestData=function()
    if InCombatLockdown() or not Enabled() then return end
    local now=GetTime();if now-lastRequest<3 then return end
    lastRequest=now
    if ns.PartyKeystones then ns.PartyKeystones.Request()end
    D.Call(C_MythicPlus,"RequestMapInfo");D.Call(C_MythicPlus,"RequestCurrentAffixes");D.Call(C_MythicPlus,"RequestRewards")
end
local function ReportTeam()
    if not lastTeamMapID then ns.Print(T["请先把鼠标移到要检查的副本卡片或本周记录，再输入 /bmmp team。"]);return end
    local best,candidates=D.BestDetails(lastTeamMapID,lastTeamWeekly)
    ns.Print(T["队伍诊断："]..D.Map(lastTeamMapID).name.."（"..lastTeamMapID.."）；"..
        (lastTeamWeekly and T["本周看板"] or T["副本卡片"])..T["采用："]..(best and T[best.source] or T["暂无最佳成绩"]).."。")
    for _,entry in ipairs(candidates) do
        local count,named=D.MemberCounts(entry.members)
        ns.Print(T[entry.source].." +"..entry.level..T["：名单 "]..count..T[" 人 / 有姓名 "]..named..T[" 人。"])
    end
end
local eventMode
SyncEvents=function()
    local mode=Enabled() and "enabled" or (pending and "restore" or "off")
    if eventMode==mode then return end
    eventMode=mode;events:UnregisterAllEvents()
    if mode=="enabled" then
        for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED",
            "CHALLENGE_MODE_MAPS_UPDATE","CHALLENGE_MODE_LEADERS_UPDATE","CHALLENGE_MODE_COMPLETED",
            "WEEKLY_REWARDS_UPDATE","MYTHIC_PLUS_CURRENT_AFFIX_UPDATE","MYTHIC_PLUS_NEW_WEEKLY_RECORD",
            "BAG_UPDATE_DELAYED","SPELLS_CHANGED","SPELL_UPDATE_COOLDOWN","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
            events:RegisterEvent(event)
        end
    elseif mode=="restore" then
        -- Secure portals/native geometry must be restored only after combat.
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end
local registered=false
local function init()
    if ns.PartyKeystones then ns.PartyKeystones.Start(function()Queue("party")end,Enabled)end
    if not registered then
        registered=true
        SLASH_BMMYTHICPLUS1="/bmmp"
        SlashCmdList.BMMYTHICPLUS=function(msg)
            if (msg or ""):lower():match("^%s*team%s*$") then ReportTeam() else openTab() end
        end
        UI.OnTheme(function()Paint();if active then Queue() end end)
    end
    SyncEvents();hookChallenges();Queue()
end
events:SetScript("OnEvent",function(_,event,name)
    if event=="ADDON_LOADED" then
        if name=="Blizzard_ChallengesUI" or name=="EUI_Kogotool" or name=="AngryKeystones" then hookChallenges();Queue() end
    elseif event=="PLAYER_REGEN_DISABLED" then
        if active and canvas then
            for _,tile in ipairs(tiles) do if tile.map then
                tile.portalCached=false
                if GameTooltip and (GameTooltip:IsOwned(tile.portal) or GameTooltip:IsOwned(tile.portalStatus)) then leave() end
                local _,state=D.Portal(tile.map.id)
                setText(tile.state,DB().teleport and state or T["传送已关闭"]);tile.portalStatus:Show()
            end end
        end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if pending or active or Enabled() then hookChallenges();Queue() end
    elseif event=="PLAYER_ENTERING_WORLD" then
        hookChallenges();RequestData();Queue()
    elseif event=="SPELL_UPDATE_COOLDOWN" then
        if active and not InCombatLockdown() then for _,tile in ipairs(tiles) do syncPortal(tile) end end
    elseif Enabled() and ChallengesFrame and ChallengesFrame:IsVisible() then
        if event=="CHALLENGE_MODE_COMPLETED" then RequestData() end
        Queue(event=="BAG_UPDATE_DELAYED" and "key" or nil)
    end
end)
local function BuildOptions(panel,m,L)
    L:Title(T["大秘境信息优化"])
    L:Row({
        function(c)c:Button(280,T["打开史诗钥石地下城"],openTab)end,
        function(c)c:Button(240,T["查看宏伟宝库"],openVault)end,
    },280)
    L:Section(T["显示内容"])
    L:Check(T["显示大秘境增强界面"],function()return DB().show end,function(v)DB().show=v end,Refresh)
    L:Row({
        function(c)c:Check(T["显示右侧本周看板"],function()return DB().showWeekly end,function(v)DB().showWeekly=v end,Refresh)end,
        function(c)c:Check(T["启用手动点击传送"],function()return DB().teleport end,function(v)DB().teleport=v end,Refresh)end,
    },260)
    L:Row({
        function(c)c:Check(T["显示赛季最佳层数"],function()return DB().showBest end,function(v)DB().showBest=v end,Refresh)end,
        function(c)c:Check(T["显示副本赛季评分"],function()return DB().showScore end,function(v)DB().showScore=v end,Refresh)end,
    },260)
    L:Section(T["看板布局"])
    L:Row({
        function(c)c:Slider("BaimiaoMythicScale",T["窗口缩放（%）"],70,130,5,
            function()return DB().scalePercent end,function(v)DB().scalePercent=v end,Refresh)end,
        function(c)c:step(18);c:Dropdown(310,T["副本排序："],{
            {text=T["赛季评分"],value="score"},{text=T["本周最高层数"],value="weekly"},{text=T["副本名称"],value="name"}},
            function()return DB().sortBy end,function(v)DB().sortBy=v;page=1 end,Refresh)end,
    },280)
    m.compatibilityOptions=UI.OptionGroups(panel,L,{{title=T["兼容与刷新"],collapsed=true,build=function(_,c)
        c:Check(T["隐藏 Kogo 旧本周看板"],function()return DB().replaceKogo end,function(v)DB().replaceKogo=v end,Refresh)
        c:Button(260,T["重新请求游戏数据"],function()RequestData();Queue()end)
    end}})
end

ns.MythicPlus={Refresh=Refresh,GetDB=DB,RequestData=RequestData}
ns.RegisterModule({id=ID,name=T["大秘境信息优化"],desc=T["副本成绩、本周记录与传送。"],
    defaults=defaults,BuildOptions=BuildOptions,OnEnable=init,
    OnDisable=function()if ns.PartyKeystones then ns.PartyKeystones.Stop()end;Refresh()end,
    OnToggle=function(_,on)if on then init()end;Refresh()end})

if ns.PerfWatchFrame then ns.PerfWatchFrame("MythicPlus", events, "OnEvent") end

if ns.StartupCheckpoint then ns.StartupCheckpoint("MythicPlus.lua") end
