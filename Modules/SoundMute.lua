-- Sound mute: checked mount presets, custom FileDataIDs and (on chosen conditions)
-- the party invite/join chime go through the client's MuteSoundFile API. Only IDs
-- this module muted are ever unmuted, so other mute addons keep their own lists.
-- Idle unless an invite condition needs group/LFG events; a speaker preview
-- releases an owned file for one playback and polls only until it ends.
local _, ns = ...
local T = ns.L
local ID="soundmute"
local MAX_CUSTOM=200
local INVITE_WINDOW=120
local INVITE_CHIME=567451   -- sound/interface/iplayerinvitea.ogg: invite popup and member joined
local MIMIRON_SPELL=63796   -- example mount for continuous sounds
local DATA=ns.SoundMuteData or {}
local defaults={presets={},custom={},invite={}}
-- Mount lists are generated per sound folder (see SoundMuteData.lua).
local PRESETS={
    {key="mountSummon",records=DATA.summon or {},label=T["坐骑召唤音效（已收录 %d 种坐骑造型）"]},
    {key="mountLoop",records=DATA.continuous or {},label=T["坐骑持续音效：移动、悬停、待机循环（已收录 %d 种）"]},
}
for _,p in ipairs(PRESETS) do
    p.count=0
    for _,r in ipairs(p.records) do p.count=p.count+#r[3] end
end
local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b=pcall(fn,...)
    if ok and public(a) and public(b) then return a,b end
end
local function on() return ns.IsModuleEnabled(ID) end
local function validID(v) return type(v)=="number" and v>0 and v<1e9 and v==math.floor(v) end
-- The first test build stored one invite checkbox plus a leader-and-listing
-- flag, and four single-mount presets; map them onto the current settings once.
local migrated=false
local function DB()
    local d=ns.GetDB(ID,defaults)
    if not migrated then
        migrated=true
        if type(d.invite)~="table" then d.invite={} end
        if d.presets.invite then
            if d.inviteRecruitOnly==false then d.invite.always=true else d.invite.recruiting=true end
        end
        if d.presets.furline or d.presets.peafowl then d.presets.mountSummon=true end
        for _,k in ipairs({"invite","yak","brutosaur","furline","peafowl"}) do d.presets[k]=nil end
        d.inviteRecruitOnly=nil
    end
    return d
end
-- Group finder listing, for the leader and members alike. Unknown counts as no.
local function recruiting()
    return type(C_LFGList)=="table" and call(C_LFGList.HasActiveEntryInfo)==true
end
local function leading()
    return call(IsInGroup)==true and call(UnitIsGroupLeader,"player")==true
end
local inviteUntil=0
-- Any checked condition mutes the chime; restricted state never does.
local function inviteWanted()
    local c=DB().invite
    if not on() then return false end
    if c.always then return true end
    return (c.recruiting and recruiting()) or (c.leader and leading())
        or (c.invited and (call(GetTime) or 0)<inviteUntil) or false
end
local lastInvite=false
local function wanted()
    local out,d={},DB()
    lastInvite=inviteWanted()
    if not on() then return out end
    for _,p in ipairs(PRESETS) do
        if d.presets[p.key]==true then
            for _,r in ipairs(p.records) do for _,id in ipairs(r[3]) do out[id]=true end end
        end
    end
    if lastInvite then out[INVITE_CHIME]=true end
    for _,e in ipairs(d.custom) do
        if type(e)=="table" and e.enabled and validID(e.id) then out[e.id]=true end
    end
    return out
end
-- IDs this module has muted, persisted so a later login can release them.
local function applied()
    local d=DB()
    if type(d.applied)~="table" then d.applied={} end
    return d.applied
end
local function setMuted(id,muted)
    if muted then call(MuteSoundFile,id) else call(UnmuteSoundFile,id) end
end
-- Speaker preview. A muted file only plays while released, so an owned ID is
-- unmuted for this one playback and muted again once it ends (or after 20s).
local preview
local function endPreview()
    local p=preview
    if not p then return end
    preview=nil
    if p.ticker then p.ticker:Cancel() end
    if p.handle then call(StopSound,p.handle) end
    if p.owned and applied()[p.id] then setMuted(p.id,true) end
end
local function Preview(id)
    endPreview()
    if not validID(id) then return end
    local owned=applied()[id]==true
    if owned then setMuted(id,false) end
    local willPlay,handle=call(PlaySoundFile,id,"Master")
    if not willPlay or (type(handle)=="number" and handle>=1e8) then
        if owned then setMuted(id,true) end
        ns.Print((T["无法播放音效 %s，ID 可能不存在。"]):format(tostring(id)))
        return
    end
    preview={id=id,owned=owned,handle=handle}
    if owned then
        local p,started=preview,call(GetTime) or 0
        p.ticker=C_Timer.NewTicker(0.25,function()
            if preview~=p then return end
            local playing=handle and type(C_Sound)=="table" and call(C_Sound.IsPlaying,handle)
            if playing==false or (call(GetTime) or 0)-started>20 then endPreview() end
        end)
    end
end
local events=CreateFrame("Frame")
local listening=false
local function listen()
    local c=DB().invite
    local need=on() and not c.always and (c.recruiting or c.leader) and true or false
    if need==listening then return end
    listening=need
    if need then
        for _,e in ipairs({"LFG_LIST_ACTIVE_ENTRY_UPDATE","GROUP_ROSTER_UPDATE",
            "PARTY_LEADER_CHANGED","PLAYER_ENTERING_WORLD"}) do events:RegisterEvent(e) end
    else events:UnregisterAllEvents() end
end
-- The first pass of a session re-mutes everything: client mutes do not
-- survive a restart even though the saved list does.
local primed,hookInvites=false
local function Reconcile()
    local want,have=wanted(),applied()
    for id in pairs(have) do
        if not want[id] then setMuted(id,false);have[id]=nil end
    end
    for id in pairs(want) do
        if not primed or not have[id] then setMuted(id,true);have[id]=true end
    end
    primed=true
    listen()
    if on() and DB().invite.invited then hookInvites() end
end
events:SetScript("OnEvent",function()
    if inviteWanted()~=lastInvite then Reconcile() end
end)
-- Sending an invite arms the chime mute for INVITE_WINDOW seconds, so the
-- sound of that player joining stays quiet even while still solo.
local function OnInviteSent()
    local c=DB().invite
    if not on() or c.always or not c.invited then return end
    inviteUntil=(call(GetTime) or 0)+INVITE_WINDOW
    if inviteWanted()~=lastInvite then Reconcile() end
    C_Timer.After(INVITE_WINDOW+0.1,function()
        if inviteWanted()~=lastInvite then Reconcile() end
    end)
end
-- Post-hooks only observe the call; installed the first time the option is on.
local hooked=false
hookInvites=function()
    if hooked or type(hooksecurefunc)~="function" then return end
    hooked=true
    for _,spec in ipairs({{C_PartyInfo,"InviteUnit"},{C_PartyInfo,"ConfirmInviteUnit"},
        {C_BattleNet,"InviteFriend"},{C_LFGList,"InviteApplicant"}}) do
        local api,name=spec[1],spec[2]
        if type(api)=="table" and type(api[name])=="function" then hooksecurefunc(api,name,OnInviteSent) end
    end
    for _,name in ipairs({"InviteUnit","BNInviteFriend"}) do
        if type(_G[name])=="function" then hooksecurefunc(name,OnInviteSent) end
    end
end
local function AddFromText(text)
    if type(text)~="string" then return 0 end
    text=text:gsub("，"," "):gsub("、"," "):gsub("；"," ")
    local custom,added,valid,full=DB().custom,0,0,false
    for token in text:gmatch("[^%s,;]+") do
        local id=token:match("^%d+$") and tonumber(token)
        if validID(id) then
            valid=valid+1
            local found
            for _,e in ipairs(custom) do if type(e)=="table" and e.id==id then found=e;break end end
            if found then found.enabled=true
            elseif #custom<MAX_CUSTOM then custom[#custom+1]={id=id,enabled=true};added=added+1
            else full=true end
        end
    end
    if valid==0 and text:find("%S") then ns.Print(T["没有识别到音效 ID，请输入数字。"]) end
    if full then ns.Print((T["自定义音效最多 %d 个。"]):format(MAX_CUSTOM)) end
    Reconcile()
    return added
end
local function RemoveUnchecked()
    local d,kept=DB(),{}
    for _,e in ipairs(d.custom) do
        if type(e)=="table" and e.enabled and validID(e.id) then kept[#kept+1]=e end
    end
    d.custom=kept
    Reconcile()
end
local function MutedCount()
    local n=0
    for _ in pairs(applied()) do n=n+1 end
    return n
end
local function presetLabel(p)
    local text=p.label:format(#p.records)
    if p.key=="mountLoop" then
        local name=type(C_Spell)=="table" and call(C_Spell.GetSpellName,MIMIRON_SPELL)
        if type(name)=="string" and name~="" then text=text..(T["，例如%s"]):format(name) end
    end
    return text
end
local function recordName(r)
    local name=r[2]>0 and type(C_MountJournal)=="table" and call(C_MountJournal.GetMountInfoByID,r[2])
    return type(name)=="string" and name~="" and name or r[1]
end
-- The n-th FileDataID of a preset, with its record (for the mount name).
local function presetAt(p,n)
    for _,r in ipairs(p.records) do
        if n<=#r[3] then return r[3][n],r end
        n=n-#r[3]
    end
end
-- Small speaker icon. source.play() returns the FileDataID to preview; source.tip()
-- an optional tooltip line. Drawn above its row so it never toggles the checkbox.
local function speakerButton(parent,source)
    local b=CreateFrame("Button",nil,parent)
    b:SetSize(18,18)
    if parent.GetFrameLevel then b:SetFrameLevel(parent:GetFrameLevel()+2) end
    local icon=b:CreateTexture(nil,"ARTWORK")
    icon:SetAllPoints();icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
    local glow=b:CreateTexture(nil,"HIGHLIGHT")
    glow:SetAllPoints();glow:SetTexture("Interface\\Common\\VoiceChat-On")
    local function tip()
        GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
        GameTooltip:SetText(T["试听"])
        local line=source.tip and source.tip()
        if line then GameTooltip:AddLine(line,1,1,1,true) end
        GameTooltip:Show()
    end
    b:SetScript("OnEnter",tip)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    b:SetScript("OnClick",function()
        Preview(source.play())
        if GameTooltip:IsOwned(b) then tip() end
    end)
    b.source=source
    return b
end
-- Sits right after the label text, inside the checkbox's existing click area.
local function placeSpeaker(cb)
    local label=cb.label
    local width=math.min(label:GetStringWidth() or 0,math.max(1,label:GetWidth() or 0))
    cb.speaker:ClearAllPoints()
    cb.speaker:SetPoint("LEFT",label,"LEFT",width+6,0)
end
local cursors={}
local function presetSource(p)
    return {
        play=function()
            if p.count==0 then return end
            cursors[p.key]=(cursors[p.key] or 0)%p.count+1
            return (presetAt(p,cursors[p.key]))
        end,
        tip=function()
            if p.count==0 then return end
            local n=(cursors[p.key] or 0)%p.count+1
            local _,r=presetAt(p,n)
            return (T["下一个：%s（%d/%d）"]):format(recordName(r),n,p.count)
        end,
    }
end
local function BuildOptions(panel,m,L)
    L:Title(T["音效屏蔽"])
    m.statusLabel=L:DynLabel(function() return (T["当前屏蔽 %d 个音效文件。"]):format(MutedCount()),"muted" end)
    L:Text(T["勾选即屏蔽，取消立即恢复；点小喇叭试听。每次登录自动重新屏蔽已勾选的音效。"],true)
    local function changed() Reconcile();L:SyncAll() end
    m.presetChecks={}
    L:Section(T["坐骑音效"])
    for _,p in ipairs(PRESETS) do
        local cb=L:Check(presetLabel(p),function() return DB().presets[p.key]==true end,
            function(v) DB().presets[p.key]=v and true or false end,changed)
        cb.speaker=speakerButton(cb,presetSource(p));placeSpeaker(cb)
        L.syncers[#L.syncers+1]=function() placeSpeaker(cb) end
        m.presetChecks[p.key]=cb
    end
    L:Section(T["组队提示音"])
    local headerY=L.y
    local header=L:Text(T["组队邀请 / 进组提示音（决斗、频道邀请共用同一音效）"],false)
    header:ClearAllPoints();header:SetPoint("TOPLEFT",L.indent+24,headerY)
    header:SetPoint("RIGHT",panel,"RIGHT",-(L.indent+6),0)
    header:SetWidth(math.max(80,(panel:GetWidth() or 738)-2*L.indent-30))
    m.inviteSpeaker=speakerButton(panel,{play=function() return INVITE_CHIME end})
    m.inviteSpeaker:SetPoint("TOPLEFT",L.indent,headerY+2)
    L:Text(T["满足任一勾选条件即屏蔽："],true)
    local indent=L.indent;L.indent=indent+20
    m.inviteChecks={}
    local function condition(key,label)
        m.inviteChecks[key]=L:Check(label,function() return DB().invite[key]==true end,
            function(v) DB().invite[key]=v and true or false end,changed)
    end
    condition("always",T["始终屏蔽"])
    condition("recruiting",T["正在招募时（集合石 / 预创建队伍，不论是否队长）"])
    condition("leader",T["我是队长时"])
    condition("invited",(T["我邀请别人后 %d 分钟内（单人直接组人也有效）"]):format(math.floor(INVITE_WINDOW/60)))
    L.indent=indent
    L.syncers[#L.syncers+1]=function()
        local free=not DB().invite.always
        for _,k in ipairs({"recruiting","leader","invited"}) do m.inviteChecks[k]:SetEnabled(free) end
    end
    L:Section(T["自定义音效"])
    L:Text(T["输入音效 ID（可用空格或逗号分隔多个）后回车添加；ID 可在 wago.tools/sounds 查询。"],true)
    m.customBox=L:Box(260,28,false,function() return "" end,AddFromText,function() L:SyncAll() end,true)
    -- Custom rows grow with the list: this block owns its card height, like the
    -- quick-button row editor. Rows are created on demand and reused.
    local card,cardTop,rowIndent,top=L._card,L._cardTopY,L.indent,L.y
    L._card=nil
    local rows=CreateFrame("Frame",nil,panel)
    rows:SetPoint("TOPLEFT",rowIndent,top)
    rows:SetWidth(math.max(200,(panel:GetWidth() or 738)-rowIndent-24))
    local R=ns.UI.NewLayout(rows);R.indent=0;R.y=0
    local checks={}
    m.customChecks=checks
    m.clearButton=L:Button(140,T["移除未勾选的音效"],function()
        if InCombatLockdown() then return end
        RemoveUnchecked();L:SyncAll()
    end)
    local function render()
        local list,unchecked,created=DB().custom,false,false
        for i,e in ipairs(list) do
            local cb=checks[i]
            if not cb then
                R.y=-(i-1)*32
                cb=R:Check("",function() local x=DB().custom[i];return type(x)=="table" and x.enabled end,
                    function(v) local x=DB().custom[i];if type(x)=="table" then x.enabled=v and true or false end end,
                    changed)
                cb.speaker=speakerButton(cb,{play=function() local x=DB().custom[i];return type(x)=="table" and x.id end})
                checks[i]=cb;created=true
            end
            cb.label:SetText((T["音效 %s"]):format(tostring(type(e)=="table" and e.id or "?")))
            placeSpeaker(cb);cb:Show()
            if not (type(e)=="table" and e.enabled) then unchecked=true end
        end
        for i=#list+1,#checks do checks[i]:Hide() end
        if created and ns.UI.StyleOptions then ns.UI.StyleOptions(rows) end
        R:SyncAll()
        local height=#list*32
        rows:SetHeight(math.max(1,height))
        local bottom=top-height
        m.clearButton:ClearAllPoints();m.clearButton:SetPoint("TOPLEFT",rowIndent,bottom-4)
        m.clearButton:SetShown(#list>0);m.clearButton:SetEnabled(unchecked)
        if #list>0 then bottom=bottom-36 end
        if card then card:SetHeight(math.max(cardTop-bottom+12,20)) end
        L.y=bottom-12;L:Finalize()
    end
    L.syncers[#L.syncers+1]=render
    render()
end
ns.RegisterModule({id=ID,name=T["音效屏蔽"],desc=T["屏蔽烦人的坐骑与组队提示音，也可添加自定义音效 ID。"],
    defaults=defaults,BuildOptions=BuildOptions,OnEnable=Reconcile,OnDisable=Reconcile,
    OnToggle=function(_,enabled) if enabled then Reconcile() end end})
ns.SoundMute={Reconcile=Reconcile,AddFromText=AddFromText,RemoveUnchecked=RemoveUnchecked,
    MutedCount=MutedCount,Preview=Preview,OnInviteSent=OnInviteSent,presets=PRESETS,frame=events}

if ns.PerfWatchFrame then ns.PerfWatchFrame("SoundMute", events, "OnEvent") end

if ns.StartupCheckpoint then ns.StartupCheckpoint("SoundMute.lua") end
