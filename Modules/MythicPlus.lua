-- A reversible presentation of the native Mythic Keystone tab.
-- Does not replace Blizzard methods, touch other addons' saved settings, or cast
-- from Lua. Teleports use hardware-click secure buttons, prepared out of combat.
local ADDON, ns = ...
local ID, D, UI = "mythicplus", ns.MythicPlusData, ns.UI
local WHITE="Interface\\Buttons\\WHITE8x8"
local defaults={show=true,showWeekly=true,showBest=true,showScore=true,teleport=true,
    replaceKogo=true,scalePercent=100,sortBy="score"}
local function DB() return ns.GetDB(ID,defaults) end
local function Enabled() return ns.IsModuleEnabled(ID) and DB().show end
local host, canvas, original, applied, snapshot
local active, pending, queued, hooked, kogoHooked=false,false,false,false,nil
local kogoWasShown=false
local tiles, affixes, rows, vaults, painters = {},{},{},{},{}
local page, rowOffset, mode=1,0,"runs"
local lastTeamMapID,lastTeamWeekly
local W,H=820,422
local CONTENT_BOTTOM=H-8
local TILE_HEIGHT,TILE_PITCH=64,70
local TILE_TOP=CONTENT_BOTTOM-3*TILE_PITCH-TILE_HEIGHT
local Refresh, Queue, Render, HidePortals, RequestData
local events=CreateFrame("Frame")
local function Paint()
    for _,fn in ipairs(painters) do fn() end
end
local function paint(fn) painters[#painters+1]=fn;fn() end
local function text(parent,value,size,role)
    local fs=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    fs:SetFont(STANDARD_TEXT_FONT or GameFontNormal:GetFont(),size or 13,"")
    fs:SetJustifyH("LEFT");fs:SetWordWrap(false);fs:SetText(value)
    paint(function() fs:SetTextColor(unpack(UI.palette[role or "text"])) end)
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
    f:ClearAllPoints();f:SetPoint("TOPLEFT",canvas,"TOPLEFT",x,-y);f:SetSize(w,h)
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
    b:SetSize(width,26);b:SetText(value);UI.SkinTextButton(b)
    UI.StyleText(b:GetFontString(),"text")
    b:SetScript("OnClick",fn);return b
end
local function openVault()
    if InCombatLockdown() then ns.Print("请脱离战斗后查看宏伟宝库。");return end
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WeeklyRewards") end
    if WeeklyRewardsFrame then ShowUIPanel(WeeklyRewardsFrame) else ns.Print("宏伟宝库界面暂不可用。") end
end
local function openTab()
    if InCombatLockdown() then ns.Print("请脱离战斗后打开大秘境页签。");return end
    if PVEFrame_ShowFrame then
        PVEFrame_ShowFrame("ChallengesFrame")
        if PVEFrame then ShowUIPanel(PVEFrame) end
    elseif PVEFrame_ToggleFrame then PVEFrame_ToggleFrame("ChallengesFrame") end
end
local function Duration(seconds)
    if not seconds or seconds<=0 then return "用时未知" end
    return string.format("%d:%02d",math.floor(seconds/60),math.floor(seconds%60))
end
local function tint(display,r,g,b)
    if not r then return display end
    return string.format("|cff%02x%02x%02x%s|r",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),display)
end
local function colored(kind,value,display) return tint(display,D.RarityColor(kind,value)) end
local function Level(value) return colored("level",value,"+"..(value or 0)) end
local function Score(value,kind)
    return value and colored(kind or "mapScore",value,tostring(math.floor(value+.5))) or "—"
end
local function Points(value) return value and (Score(value).."分") or "—" end
local function Timed(run)
    if run.timed==nil then return "时间未知" end
    return run.timed and "限时" or "超时"
end
local function TimePair(run)
    local elapsed=run.duration and run.duration>0 and Duration(run.duration) or "—"
    local limit=run.limit and run.limit>0 and (run.limit%60==0 and tostring(math.floor(run.limit/60)) or Duration(run.limit)) or "—"
    return "("..elapsed.."/"..limit..")"
end
local function AddMembers(lines,members)
    if not members or #members==0 then lines[#lines+1]="暂无队伍名单";return end
    for _,member in ipairs(members) do
        local class,classFile
        if member.classID then class,classFile=D.Call(_G,"GetClassInfo",member.classID) end
        local _,spec=D.Call(_G,"GetSpecializationInfoByID",member.specID)
        local name=member.name and member.name~="" and member.name or "姓名未提供"
        -- Name and specialization have fixed columns, rather than free-form prose.
        lines[#lines+1]={tint(name,D.ClassColor(classFile)),
            (spec or "")..(class and ((spec and " " or "")..class) or "")}
    end
end
local function AddBest(lines,best,limit)
    local count,named=D.MemberCounts(best.members)
    local suffix=count==1 and "（仅1人资料）" or (named<count and "（姓名不全）" or "")
    lines[#lines+1]={tint(best.source.."队伍"..suffix,unpack(UI.palette.accent)),Level(best.level).." · "..Points(best.score)}
    lines[#lines+1]="用时 / 限时  "..TimePair({duration=best.duration,limit=limit})
    AddMembers(lines,best.members)
end
local function MapLines(map,weekly)
    local lines={}
    lastTeamMapID,lastTeamWeekly=map.id,weekly
    local best=D.BestDetails(map.id,weekly)
    if best then AddBest(lines,best,map.limit)
    else
        lines[#lines+1]=not map.ratingReady and "赛季成绩待同步"
            or (map.best>0 and ("赛季 "..Level(map.best).." · "..Points(map.score)) or "赛季未完成")
        lines[#lines+1]="暂无最佳队伍信息"
    end
    return lines
end
local function RunTooltip(owner,run)
    local lines={{"本次 "..Level(run.level).." "..TimePair(run).." "..Timed(run),Points(run.score)}}
    lastTeamMapID,lastTeamWeekly=run.id,true
    local best=D.BestDetails(run.id,true)
    if best then lines[#lines+1]=" ";AddBest(lines,best,run.limit)
    else lines[#lines+1]="暂无最佳队伍信息" end
    tip(owner,run.name,lines)
end
local function sortedMaps()
    local list={}
    for i,map in ipairs(snapshot.maps) do list[i]=map end
    table.sort(list,function(a,b)
        local sort=DB().sortBy
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
    if state=="点击传送" and owner~=tile.portal then state="传送已就绪" end
    tip(owner,tile.map.name,{DB().teleport and state or "传送已关闭"})
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
    b.caption=text(b,"传送",11,"accent");b.caption:SetPoint("CENTER")
    local highlight=b:CreateTexture(nil,"HIGHLIGHT");highlight:SetAllPoints();highlight:SetColorTexture(1,1,1,.08)
    paint(function() b:SetBackdropColor(unpack(UI.palette.hover));b:SetBackdropBorderColor(unpack(UI.palette.accent)) end)
    b:SetScript("OnEnter",function(self) PortalTooltip(f,self) end);b:SetScript("OnLeave",leave)
    f.portal=b;tiles[index]=f
    return f
end
local function syncPortal(tile)
    local b=tile.portal
    if InCombatLockdown() then pending=true;return end
    local id,state
    if tile.map then id,state=D.Portal(tile.map.id) end
    local usable=active and tile:IsShown() and DB().teleport and id and state=="点击传送"
    if GameTooltip and (GameTooltip:IsOwned(b) or GameTooltip:IsOwned(tile.portalStatus)) then leave() end
    tile.state:SetText(usable and "" or (DB().teleport and (state=="冷却状态暂不可用" and "状态未知" or state or "未收录传送") or "传送已关闭"))
    tile.portalStatus:SetShown(not usable)
    if not usable then
        if b.driver and UnregisterStateDriver then UnregisterStateDriver(b,"visibility");b.driver=nil end
        b:Hide();b:SetAttribute("type1",nil);b:SetAttribute("spell",nil);return
    end
    local scale=tile:GetEffectiveScale()/UIParent:GetEffectiveScale()
    b:SetScale(scale);b:SetSize(84,20);b:ClearAllPoints();b:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",-8,4)
    b:SetFrameStrata(host:GetFrameStrata());b:SetFrameLevel(host:GetFrameLevel()+30)
    b:SetAttribute("type1","spell");b:SetAttribute("spell",id)
    b.caption:SetText("点击传送")
    if RegisterStateDriver and not b.driver then RegisterStateDriver(b,"visibility","[combat] hide; show");b.driver=true end
    b:Show()
end
HidePortals=function()
    if InCombatLockdown() then pending=true;return end
    for _,tile in ipairs(tiles) do
        local b=tile.portal
        if b.driver and UnregisterStateDriver then UnregisterStateDriver(b,"visibility");b.driver=nil end
        b:Hide();b:SetAttribute("type1",nil);b:SetAttribute("spell",nil)
    end
end
local function RenderRows()
    if not snapshot or not canvas then return end
    local summary=mode=="maps"
    local list=summary and sortedMaps() or snapshot.runs
    local visible=10
    rowOffset=math.max(0,math.min(rowOffset,math.max(0,#list-visible)))
    for i,f in ipairs(rows) do
        if GameTooltip and GameTooltip:IsOwned(f) then leave() end
        local item=list[rowOffset+i];f.item=item;f.summary=summary;f:SetShown(item~=nil)
        if item then
            f.left:SetText(summary and item.name or (Level(item.level).."  "..item.name))
            f.time:SetText(summary and "" or TimePair(item))
            f.time:SetShown(not summary)
            f.left:SetWidth(summary and 204 or 150)
            f.right:ClearAllPoints();f.right:SetPoint("TOPLEFT",summary and 212 or 276,-6);f.right:SetWidth(summary and 92 or 28)
            f.right:SetText(summary and (not snapshot.historyReady and "待同步" or (item.count>0 and (item.count.."次 / "..Level(item.weekly)) or "未完成")) or (item.timed==nil and "未知" or Timed(item)))
            f.right:SetTextColor(unpack(UI.palette[(not summary and item.timed==true) and "accent" or "muted"]))
            if not summary and item.timed==false then f.right:SetTextColor(1,.45,.35) end
        end
    end
    canvas.empty:SetText(summary and (#list==0 and "等待游戏同步赛季地下城…" or "")
        or (snapshot.historyReady and (#list==0 and "本周还没有大秘境记录" or "") or "等待游戏同步本周记录…"))
    canvas.range:SetText(#list==0 and "" or string.format("%d–%d / %d",rowOffset+1,math.min(#list,rowOffset+visible),#list)..(#list>visible and "  ·  滚轮查看更多" or ""))
    canvas.runTab.caption:SetText("本周记录  "..#snapshot.runs)
    canvas.mapTab.caption:SetText("副本汇总  "..#snapshot.maps)
    canvas.runTab:UpdateSelection();canvas.mapTab:UpdateSelection()
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
    canvas.title=label(canvas,"赛季地下城",19,12,10,300)
    canvas.key=label(canvas,"",18,12,36,450,"accent")
    canvas.score=label(canvas,"",12,12,62,370,"muted")
    canvas.settings=button(canvas,"设置",66,function()ns.OpenOptions(ID)end)
    canvas.refresh=button(canvas,"刷新",66,function()RequestData();Queue()end)
    canvas.affixTitle=label(canvas,"本周词缀",11,12,93,68,"muted")
    for i=1,8 do
        local f=CreateFrame("Button",nil,canvas);f:SetSize(26,26);f:SetPoint("TOPLEFT",84+(i-1)*32,-85)
        f.icon=f:CreateTexture(nil,"ARTWORK");f.icon:SetAllPoints();f.icon:SetTexCoord(.08,.92,.08,.92)
        f:SetScript("OnEnter",function(self) if self.info then tip(self,self.info.name,{self.info.description or ""}) end end)
        f:SetScript("OnLeave",leave);affixes[i]=f
    end
    canvas.affixEmpty=label(canvas,"等待词缀数据…",11,84,93,280,"muted")
    canvas.mapsTitle=label(canvas,"副本概览 · 赛季 / 本周",11,12,121,330,"muted")
    canvas.prev=button(canvas,"‹",26,function()page=math.max(1,page-1);Render()end)
    canvas.next=button(canvas,"›",26,function()page=page+1;Render()end)
    for i=1,8 do makeTile(i) end
    canvas.noMaps=label(canvas,"赛季地下城数据暂不可用",13,24,172,400,"muted")
    canvas.weekly=surface(canvas);place(canvas.weekly,480,8,328,CONTENT_BOTTOM-8)
    canvas.weekTitle=label(canvas.weekly,"本周大秘境",18,10,10,200)
    canvas.vaultButton=button(canvas.weekly,"宝库",60,openVault);canvas.vaultButton:SetPoint("TOPRIGHT",-10,-8)
    canvas.weekStats=label(canvas.weekly,"",11,10,37,308,"muted")
    for i=1,3 do
        local f=surface(canvas.weekly,"bg");f:SetPoint("TOPLEFT",10+(i-1)*104,-58);f:SetSize(100,52)
        f.title=label(f,"",10,7,5,86,"muted");f.value=label(f,"",14,7,20,86,"accent")
        f.detail=label(f,"",10,7,37,86,"muted")
        f:EnableMouse(true)
        f:SetScript("OnEnter",function(self)
            tip(self,"地下城宝库进度",{"含符合条件的英雄 / 史诗地下城。", "奖励详情见右上角「宝库」。"})
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
            self.caption:SetTextColor(unpack(UI.palette[self.selected and "accent" or "muted"]))
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
        f:EnableMouseWheel(true);f:SetScript("OnMouseWheel",canvas.list:GetScript("OnMouseWheel"))
        f:SetScript("OnEnter",function(self)
            local item=self.item;if not item then return end
            if self.summary then tip(self,item.name,MapLines(item,true)) else RunTooltip(self,item) end
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
    canvas.score:SetWidth(leftWidth-82)
    canvas.key:SetText(snapshot.keyName and ("当前钥石  "..Level(snapshot.keyLevel).."  "..snapshot.keyName) or "当前未持有钥石")
    canvas.key:SetWidth(leftWidth-4)
    canvas.score:SetText("赛季评分  "..Score(snapshot.rating,"rating"))
    for i,f in ipairs(affixes) do
        f.info=snapshot.affixes[i];f:SetShown(f.info~=nil)
        if f.info then f.icon:SetTexture(f.info.texture) end
    end
    canvas.affixEmpty:SetShown(#snapshot.affixes==0)
    local list=sortedMaps();local pages=math.max(1,math.ceil(#list/8));page=math.max(1,math.min(page,pages))
    place(canvas.prev,leftWidth-44,116,24,20);place(canvas.next,leftWidth-12,116,24,20)
    canvas.prev:SetShown(pages>1);canvas.next:SetShown(pages>1)
    canvas.mapsTitle:SetText("副本概览 · 赛季 / 本周"..(pages>1 and ("  "..page.."/"..pages) or ""))
    local width=(leftWidth-8)/2
    for i,tile in ipairs(tiles) do
        local map=list[(page-1)*8+i];tile.map=map;tile:SetShown(map~=nil)
        if map then
            place(tile,12+((i-1)%2)*(width+8),TILE_TOP+math.floor((i-1)/2)*TILE_PITCH,width,TILE_HEIGHT)
            tile.icon:SetTexture(map.texture or 134400);tile.name:SetText(map.name);tile.name:SetWidth(width-54)
            local best=db.showBest and (not map.ratingReady and "赛季 —" or (map.best>0 and ("赛季 "..Level(map.best)) or "赛季未完成")) or ""
            local score=db.showScore and ("评分 "..(map.ratingReady and Score(map.score) or "—")) or ""
            tile.stats:SetText(best..(best~="" and score~="" and " · " or "")..score);tile.stats:SetWidth(width-54)
            tile.week:SetText(snapshot.historyReady and ("本周 "..map.count.." 次"..(map.weekly>0 and (" · "..Level(map.weekly)) or "")) or "本周待同步")
        end
        syncPortal(tile)
    end
    canvas.noMaps:SetShown(#list==0)
    local timed=0;for _,run in ipairs(snapshot.runs) do if run.timed then timed=timed+1 end end
    canvas.weekStats:SetText(snapshot.historyReady and string.format("完成 %d 次  ·  限时 %d 次  ·  最高 %s",#snapshot.runs,timed,snapshot.runs[1] and Level(snapshot.runs[1].level) or "—") or "正在同步本周记录…")
    for i,f in ipairs(vaults) do
        local a=snapshot.vault[i]
        f.title:SetText(a and (a.threshold.." 次奖励") or ("宝库槽位 "..i))
        f.value:SetText(a and (math.min(a.progress,a.threshold).." / "..a.threshold) or "—")
        f.value:SetTextColor(unpack(UI.palette[a and a.progress>=a.threshold and "accent" or "muted"]))
        f.detail:SetText(a and (a.progress>=a.threshold and "已解锁" or "尚未解锁") or "等待游戏数据")
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
    if InCombatLockdown() then pending=true;return end
    pending=false
    local visible=Enabled() and ChallengesFrame and ChallengesFrame:IsVisible() and PVEFrame
    if not visible then restore();return end
    if not host then build() end
    active=true;fit();host:Show()
    snapshot=D.Snapshot();Render();suppressKogo()
end
Queue=function()
    if queued then return end
    queued=true
    C_Timer.After(0,function()queued=false;Refresh()end)
end
local function hookChallenges()
    if hooked or not ChallengesFrame then return end
    hooked=true
    ChallengesFrame:HookScript("OnShow",function()
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
    D.Call(C_MythicPlus,"RequestMapInfo");D.Call(C_MythicPlus,"RequestCurrentAffixes");D.Call(C_MythicPlus,"RequestRewards")
end
local function ReportTeam()
    if not lastTeamMapID then ns.Print("请先把鼠标移到要检查的副本卡片或本周记录，再输入 /bmmp team。");return end
    local best,candidates=D.BestDetails(lastTeamMapID,lastTeamWeekly)
    ns.Print("队伍诊断："..D.Map(lastTeamMapID).name.."（"..lastTeamMapID.."）；"..
        (lastTeamWeekly and "本周看板" or "副本卡片").."采用："..(best and best.source or "暂无最佳成绩").."。")
    for _,entry in ipairs(candidates) do
        local count,named=D.MemberCounts(entry.members)
        ns.Print(entry.source.." +"..entry.level.."：名单 "..count.." 人 / 有姓名 "..named.." 人。")
    end
end
local registered=false
local function init()
    if not registered then
        registered=true
        SLASH_BMMYTHICPLUS1="/bmmp"
        SlashCmdList.BMMYTHICPLUS=function(msg)
            if (msg or ""):lower():match("^%s*team%s*$") then ReportTeam() else openTab() end
        end
        for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED",
            "CHALLENGE_MODE_MAPS_UPDATE","CHALLENGE_MODE_LEADERS_UPDATE","CHALLENGE_MODE_COMPLETED",
            "WEEKLY_REWARDS_UPDATE","MYTHIC_PLUS_CURRENT_AFFIX_UPDATE","MYTHIC_PLUS_NEW_WEEKLY_RECORD",
            "BAG_UPDATE_DELAYED","SPELLS_CHANGED","SPELL_UPDATE_COOLDOWN","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
            events:RegisterEvent(event)
        end
        UI.OnTheme(function()Paint();if active then Queue() end end)
    end
    hookChallenges();Queue()
end
events:SetScript("OnEvent",function(_,event,name)
    if event=="ADDON_LOADED" then
        if name=="Blizzard_ChallengesUI" or name=="EUI_Kogotool" or name=="AngryKeystones" then hookChallenges();Queue() end
    elseif event=="PLAYER_REGEN_DISABLED" then
        if active and canvas then
            for _,tile in ipairs(tiles) do if tile.map then
                if GameTooltip and (GameTooltip:IsOwned(tile.portal) or GameTooltip:IsOwned(tile.portalStatus)) then leave() end
                local _,state=D.Portal(tile.map.id)
                tile.state:SetText(DB().teleport and state or "传送已关闭");tile.portalStatus:Show()
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
        Queue()
    end
end)
local function BuildOptions(panel,m,L)
    L:Title("大秘境信息优化")
    m.mythicTabs=UI.OptionTabs(panel,L,{
        {name="显示与布局",width=150,build=function(_,L)
            L:Section("开始使用")
            L:Check("启用大秘境信息优化",function()return DB().show end,function(v)DB().show=v end,Refresh)
            L:Button(200,"打开史诗钥石地下城",openTab)
            L:Section("看板布局")
            L:Check("显示右侧本周看板",function()return DB().showWeekly end,function(v)DB().showWeekly=v end,Refresh)
            L:Slider("BaimiaoMythicScale","窗口缩放（%）",70,130,5,function()return DB().scalePercent end,function(v)DB().scalePercent=v end,Refresh)
            L:Dropdown(260,"副本排序：",{{text="赛季评分",value="score"},{text="本周最高层数",value="weekly"},{text="副本名称",value="name"}},
                function()return DB().sortBy end,function(v)DB().sortBy=v;page=1 end,Refresh)
        end},
        {name="副本与传送",width=150,build=function(_,L)
            L:Section("副本卡片")
            L:Check("显示赛季最佳层数",function()return DB().showBest end,function(v)DB().showBest=v end,Refresh)
            L:Check("显示副本赛季评分",function()return DB().showScore end,function(v)DB().showScore=v end,Refresh)
            L:Check("启用手动点击传送",function()return DB().teleport end,function(v)DB().teleport=v end,Refresh)
            L:Section("宝库")
            L:Button(200,"查看宏伟宝库",openVault)
        end},
        {name="兼容与刷新",width=150,build=function(_,L)
            L:Check("隐藏 Kogo 旧本周看板",function()return DB().replaceKogo end,function(v)DB().replaceKogo=v end,Refresh)
            L:Button(200,"重新请求游戏数据",function()RequestData();Queue()end)
        end},
    })
end
ns.MythicPlus={Refresh=Refresh,GetDB=DB,RequestData=RequestData}
ns.RegisterModule({id=ID,name="大秘境信息优化",desc="副本成绩、本周记录与传送。",
    defaults=defaults,BuildOptions=BuildOptions,OnEnable=init,
    OnDisable=function()Refresh()end,
    OnToggle=function(_,on)if on then init()end;Refresh()end})
