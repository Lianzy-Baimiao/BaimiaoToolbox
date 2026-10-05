-- Small, user-triggered menu actions. No automatic invitations or menu replacement.
local ADDON, ns = ...
local T = ns.L
local ID="smalltools"
local defaults={guildInvite=true,multiInvite=true,copyName=true}
local function DB() return ns.GetDB(ID,defaults) end
local function enabled(key) return ns.IsModuleEnabled(ID) and DB()[key] end
local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function text(v) if public(v) and type(v)=="string" and v~="" then return v end end
local function number(v)
    if public(v) and type(v)=="number" and v>0 and v<math.huge and v==math.floor(v) then return v end
end
local function plain(v) return public(v) and type(v)=="table" end
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b=pcall(fn,...)
    if ok and public(a) and public(b) then return a,b end
end
local function fullName(name,realm)
    name=text(name);realm=text(realm)
    if not name or name:find("[|%s]") then return end
    if name:find("-",1,true) then return name end
    realm=realm or text(call(GetNormalizedRealmName))
    if realm then return name.."-"..realm:gsub("%s","") end
end
local function selfName()
    local name,realm=call(UnitFullName,"player")
    return fullName(name,realm)
end
local function accountID(context)
    local id=number(context.bnetIDAccount)
    if id then return id end
    if plain(context.accountInfo) then id=number(context.accountInfo.bnetAccountID) end
    if id then return id end
    if UnitPopupSharedUtil then return number(call(UnitPopupSharedUtil.GetBNetIDAccount,context)) end
end
local function character(info)
    if not plain(info) or not public(info.isOnline) or info.isOnline~=true
        or text(info.clientProgram)~=(BNET_CLIENT_WOW or "WoW")
        or number(info.wowProjectID)~=WOW_PROJECT_ID or not number(info.realmID)
        or not public(info.isInCurrentRegion) or info.isInCurrentRegion~=true then return end
    local name=fullName(info.characterName,text(info.realmName))
    local id,guid=number(info.gameAccountID),text(info.playerGuid)
    if not text(info.realmName) or not name or not id or not guid or name==selfName() or guid==call(UnitGUID,"player") then return end
    return {name=name,id=id,guid=guid,faction=text(info.factionName),classID=number(info.classID)}
end
-- The enumeration API takes friend INDEX, while the invitation API takes GAME
-- account ID. Neither is the Battle.net account ID in the menu context.
local function characters(id)
    local result,seen={},{}
    local index=number(call(BNGetFriendIndex,id))
    if not index or not C_BattleNet then return result end
    local count=number(call(C_BattleNet.GetFriendNumGameAccounts,index)) or 0
    for i=1,math.min(count,100) do
        local entry=character(call(C_BattleNet.GetFriendGameAccountInfo,index,i))
        if entry and not seen[entry.id] then result[#result+1]=entry;seen[entry.id]=true end
    end
    table.sort(result,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.id<b.id end)
    return result
end
local function findCharacter(account,expected)
    for _,entry in ipairs(characters(account)) do
        if entry.id==expected.id and entry.guid==expected.guid and entry.name==expected.name then return entry end
    end
end
local function canParty(entry)
    if not C_PartyInfo or call(C_PartyInfo.CanInvite)~=true or call(C_PartyInfo.IsPartyFull)==true then return false end
    if call(IsInGroup)==true and call(UnitInParty,entry.name) then return false end
    if call(UnitInRaid,entry.name) then return false end
    local faction=text(call(UnitFactionGroup,"player"))
    if not faction or not entry.faction then return false end
    if entry.faction~=faction and (call(C_PartyInfo.CanFormCrossFactionParties)~=true
        or (C_QuestSession and call(C_QuestSession.Exists)==true)) then return false end
    if C_GameRules and Enum and Enum.GameMode then
        local mode=call(C_GameRules.GetActiveGameMode)
        if not public(mode) then return false end
        local other=CLASS_ID_TO_GAME_MODE and entry.classID and CLASS_ID_TO_GAME_MODE[entry.classID]
        if mode~=(other or Enum.GameMode.Standard) then return false end
    end
    return type(C_BattleNet and C_BattleNet.InviteFriend or BNInviteFriend)=="function"
end
local function canGuild(name,unit)
    if call(IsInGuild)~=true or call(CanGuildInvite)~=true or not name or name==selfName() then return false end
    if unit and call(GetGuildInfo,unit) then return false end
    if C_GuildInfo and call(C_GuildInfo.MemberExistsByName,name)==true then return false end
    return type(C_GuildInfo and C_GuildInfo.Invite or GuildInvite)=="function"
end
local function unitTarget(context,tag,copy)
    local unit=text(context.unit)
    if unit then
        if call(UnitIsPlayer,unit)~=true or (not copy and (call(UnitIsUnit,unit,"player")==true
            or call(UnitIsConnected,unit)==false)) then return end
        local name,realm=call(UnitFullName,unit)
        return fullName(name,realm),unit,text(call(UnitGUID,unit))
    end
    -- TARGET/FOCUS can also describe non-player units; without a unit
    -- token they are not a verified character-name source.
    if tag=="TARGET" or tag=="FOCUS" then return end
    if not public(context.isMobile) or context.isMobile==true then return end
    return fullName(context.name,context.server)
end
local function feedback() ns.Print(T["目标状态或邀请权限已变化，请重新打开右键菜单。"]) end
local function inviteParty(account,expected)
    if not enabled("multiInvite") then return end
    local entry=findCharacter(account,expected)
    if not entry or not canParty(entry) then feedback();return end
    -- Use the normal invitation API, not ConfirmInvite*; game restrictions and
    -- any confirmation remain owned by Blizzard.
    local fn=C_BattleNet and C_BattleNet.InviteFriend or BNInviteFriend
    local ok=pcall(fn,entry.id)
    if not ok then feedback() end
end
local function inviteGuild(name,unit,guid,account,expected,context,tag)
    if not enabled("guildInvite") then return end
    if account then
        if not findCharacter(account,expected) then feedback();return end
    elseif context then
        local current,_,currentGUID=unitTarget(context,tag)
        if current~=name or (guid and currentGUID~=guid) then feedback();return end
    end
    if not canGuild(name,unit) then feedback();return end
    local fn=C_GuildInfo and C_GuildInfo.Invite or GuildInvite
    local ok=pcall(fn,name)
    if not ok then feedback() end
end
-- Copy is deliberately independent of invitation permissions. The text is the
-- exact character chosen when the menu opened; never substitute a BNet nickname.
local copyDialog
local function copyName(name)
    if not enabled("copyName") then return end
    if not copyDialog then
        local f=CreateFrame("Frame","BaimiaoCopyNameDialog",UIParent,"BackdropTemplate")
        f:SetSize(380,118);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true);f:EnableMouse(true)
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
        f:SetBackdropColor(.055,.065,.075,.98);f:SetBackdropBorderColor(0,.65,.5,1)
        local title=f:CreateFontString(nil,"ARTWORK","GameFontNormal")
        ns.UI.RegisterRuntimeFont(title)
        title:SetPoint("TOPLEFT",16,-14);title:SetText(T["复制角色名 · Ctrl+C 复制，Esc 关闭"])
        local edit=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
        ns.UI.RegisterRuntimeFont(edit)
        edit:SetSize(342,28);edit:SetPoint("TOPLEFT",20,-48)
        edit:SetAutoFocus(false);edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed",function()f:Hide()end)
        edit:SetScript("OnEnterPressed",function()f:Hide()end)
        f:SetScript("OnHide",function()edit:ClearFocus()end)
        local close=CreateFrame("Button",nil,f,"UIPanelCloseButton")
        close:SetPoint("TOPRIGHT",2,2);close:SetScript("OnClick",function()f:Hide()end)
        f.edit=edit;copyDialog=f
    end
    copyDialog:Show();copyDialog.edit:SetText(name)
    copyDialog.edit:SetFocus();copyDialog.edit:HighlightText()
end
local function modify(tag,_,root,context)
    if not ns.IsModuleEnabled(ID) or not plain(context) then return end
    local account=accountID(context)
    local bnet=tag=="BN_FRIEND" or account or plain(context.accountInfo)
    local entries=account and characters(account) or {}
    local divided=false
    local function divider() if not divided then root:QueueDivider();divided=true end end
    if enabled("copyName") then
        if bnet and #entries>0 then
            divider()
            if #entries==1 then
                local name=entries[1].name
                root:CreateButton(T["复制角色名"],function()copyName(name)end)
            else
                local menu=root:CreateButton(T["复制角色名"])
                for _,entry in ipairs(entries) do
                    local name=entry.name
                    menu:CreateButton(name,function()copyName(name)end)
                end
            end
        elseif not bnet then
            local name=unitTarget(context,tag,true)
            if name then divider();root:CreateButton(T["复制角色名"],function()copyName(name)end)end
        end
    end
    if enabled("multiInvite") and account and #entries>1 then
        divider()
        local menu=root:CreateButton(T["选择角色邀请"])
        for _,entry in ipairs(entries) do
            local target=entry
            local button=menu:CreateButton(target.name,function() inviteParty(account,target) end)
            button:SetEnabled(canParty(target))
        end
    end
    if not enabled("guildInvite") then return end
    if bnet then
        local eligible={}
        for _,entry in ipairs(entries) do if canGuild(entry.name) then eligible[#eligible+1]=entry end end
        if #eligible==0 then return end
        divider()
        if #entries==1 then
            local target=eligible[1]
            root:CreateButton(T["公会邀请"],function() inviteGuild(target.name,nil,nil,account,target) end)
        else
            local menu=root:CreateButton(T["公会邀请"])
            for _,entry in ipairs(eligible) do
                local target=entry
                menu:CreateButton(target.name,function() inviteGuild(target.name,nil,nil,account,target) end)
            end
        end
    else
        local name,unit,guid=unitTarget(context,tag)
        if not canGuild(name,unit) then return end
        divider()
        root:CreateButton(T["公会邀请"],function() inviteGuild(name,unit,guid,nil,nil,context,tag) end)
    end
end
local tags={"PLAYER","TARGET","FOCUS","PARTY","RAID_PLAYER","RAID","FRIEND","BN_FRIEND",
    "CHAT_ROSTER","COMMUNITIES_WOW_MEMBER","RECENT_ALLY"}
local registered=false
local events=CreateFrame("Frame")
local function register()
    if registered then return end
    if not Menu or type(Menu.ModifyMenu)~="function" then events:RegisterEvent("ADDON_LOADED");return end
    registered=true;events:UnregisterAllEvents()
    for _,tag in ipairs(tags) do
        local which=tag
        Menu.ModifyMenu("MENU_UNIT_"..which,function(...) modify(which,...) end)
    end
end
local function start()
    register()
    if ns.MarkerAssist then ns.MarkerAssist.Start()end
    if ns.SmallToolsExtras then ns.SmallToolsExtras.Start()end
end
local function stop()
    events:UnregisterAllEvents()
    if ns.MarkerAssist then ns.MarkerAssist.Stop()end
    if ns.SmallToolsExtras then ns.SmallToolsExtras.Stop()end
    if copyDialog then copyDialog:Hide()end
end
local function BuildOptions(panel,m,L)
    L:Title(T["小工具集合"])
    local groups={{title=T["右键菜单"],build=function(_,c)
        c:Row({
            function(cell)cell:Check(T["公会邀请"],function()return DB().guildInvite end,function(v)DB().guildInvite=v end)end,
            function(cell)cell:Check(T["多角色在线：选择角色邀请组队"],function()return DB().multiInvite end,function(v)DB().multiInvite=v end)end,
        },260)
        c:Check(T["复制角色名（名字-服务器）"],function()return DB().copyName end,function(v)
            DB().copyName=v;if not v and copyDialog then copyDialog:Hide()end
        end)
    end}}
    if ns.SmallToolsExtras then ns.SmallToolsExtras.AddOptionGroups(groups)end
    if ns.MarkerAssist then ns.MarkerAssist.AddOptionGroups(groups)end
    m.optionGroups=ns.UI.OptionGroups(panel,L,groups)
end

events:SetScript("OnEvent",function() if ns.IsModuleEnabled(ID) then register() end end)
ns.RegisterModule({id=ID,name=T["小工具集合"],desc=T["右键邀请与复制、进本与排队提醒、交易回执、标记与倒数。"],defaults=defaults,
    BuildOptions=BuildOptions,OnEnable=start,
    OnDisable=stop,
    OnToggle=function(_,on) if on then start() end end})
