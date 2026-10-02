"""Exercise real SmallTools menu callbacks; invitations only occur on explicit clicks."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
STUB=r'''
callbacks={};hookCount=0;guildInvites={};partyInvites={};guildPermission=true;inGuild=true;partyPermission=true;partyFull=false
WOW_PROJECT_ID=1;BNET_CLIENT_WOW="WoW"
Menu={ModifyMenu=function(tag,callback)assert(not callbacks[tag]);callbacks[tag]=callback;hookCount=hookCount+1 end}
function description(label,action)
 local d={label=label,action=action,children={},enabled=true}
 function d:QueueDivider()self.divider=true end
 function d:CreateButton(label,action)local c=description(label,action);self.children[#self.children+1]=c;return c end
 function d:SetEnabled(value)self.enabled=value end
 function d:find(label)for _,c in ipairs(self.children)do if c.label==label then return c end end end
 function d:click()if self.enabled and self.action then self.action()end end
 return d
end
function open(tag,context)local d=description();callbacks["MENU_UNIT_"..tag](nil,d,context);return d end
unitName="队友";unitRealm="远方";unitGUID="Player-2";unitPlayer=true;unitGuild=nil;connected=true
function UnitFullName(unit)if unit=="player"then return "本人","本服" end;return unitName,unitRealm end
function UnitGUID(unit)return unit=="player"and "Player-1"or unitGUID end
function UnitIsPlayer(unit)return unit=="player"or unitPlayer end
function UnitIsUnit(a,b)return a==b end
function UnitIsConnected()return connected end
function GetNormalizedRealmName()return "本服"end
function IsInGuild()return inGuild end
function CanGuildInvite()return guildPermission end
function GetGuildInfo()return unitGuild end
function IsInGroup()return false end
function UnitInParty()return false end
function UnitInRaid()return nil end
function UnitFactionGroup()return "Horde"end
C_PartyInfo={CanInvite=function()return partyPermission end,IsPartyFull=function()return partyFull end,CanFormCrossFactionParties=function()return true end}
C_QuestSession={Exists=function()return false end}
C_GuildInfo={Invite=function(name)guildInvites[#guildInvites+1]=name end,MemberExistsByName=function(name)return name==guildMember end}
friendIndex=3
function BNGetFriendIndex(id)assert(id==77,"battle.net account ID expected");return friendIndex end
function toon(id,name)
 return {gameAccountID=id,characterName=name,realmName="远方",realmID=1,playerGuid="Player-"..id,
 clientProgram="WoW",wowProjectID=1,isOnline=true,isInCurrentRegion=true,factionName="Horde",classID=1}
end
games={toon(101,"甲"),toon(202,"乙")}
C_BattleNet={GetFriendNumGameAccounts=function(index)assert(index==friendIndex and index~=77);return #games end,
 GetFriendGameAccountInfo=function(index,i)assert(index==friendIndex);return games[i]end,
 InviteFriend=function(id)assert(id~=77 and id~=friendIndex);partyInvites[#partyInvites+1]=id end}
'''
class SmallToolsTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute((ROOT/'tests/wow_ui_stub.lua').read_text(encoding='utf-8'))
  self.lua.execute(STUB)
  for path in ['Core.lua','Modules/SmallTools.lua']:
   self.lua.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/path).read_text(encoding='utf-8'))
  self.lua.execute('m=ns.modules.smalltools;m.db=ns.GetDB(m.id,m.defaults);m.OnEnable(m)')
 def runlua(self,code):self.lua.execute(code)
 def test_guild_invites_exact_full_name_only_on_click(self):
  self.runlua('''d=open("TARGET",{unit="target"});assert(#guildInvites==0)
   d:find("公会邀请"):click();assert(guildInvites[1]=="队友-远方")
   d=open("FRIEND",{name="路人",server="其他服"});d:find("公会邀请"):click();assert(guildInvites[2]=="路人-其他服")
   d=open("CHAT_ROSTER",{name="聊天人-其他服"});d:find("公会邀请"):click();assert(guildInvites[3]=="聊天人-其他服")''')
 def test_name_only_player_menu_supports_chat_links(self):
  self.runlua('d=open("PLAYER",{name="聊天人",server="其他服"});d:find("公会邀请"):click();assert(guildInvites[1]=="聊天人-其他服")')
 def test_guild_excludes_self_npc_members_and_no_permission(self):
  self.runlua('''assert(not open("TARGET",{unit="player"}):find("公会邀请"))
   assert(not open("FRIEND",{name="本人",server="本服"}):find("公会邀请"))
   unitPlayer=false;assert(not open("TARGET",{unit="target"}):find("公会邀请"));unitPlayer=true
   unitGuild="已入会";assert(not open("TARGET",{unit="target"}):find("公会邀请"));unitGuild=nil
   guildMember="路人-本服";assert(not open("FRIEND",{name="路人"}):find("公会邀请"))
   guildPermission=false;assert(not open("TARGET",{unit="target"}):find("公会邀请"));guildPermission=true
   inGuild=false;assert(not open("TARGET",{unit="target"}):find("公会邀请"))''')
 def test_guild_rechecks_unit_and_permission_at_click(self):
  self.runlua('''d=open("TARGET",{unit="target"});unitName="换目标";d:find("公会邀请"):click();assert(#guildInvites==0)
   d=open("TARGET",{unit="target"});guildPermission=false;d:find("公会邀请"):click();assert(#guildInvites==0)''')
 def test_multiple_characters_selects_specific_game_account(self):
  self.runlua('''d=open("BN_FRIEND",{bnetIDAccount=77});p=d:find("选择角色邀请");assert(#p.children==2 and #partyInvites==0)
   p:find("乙-远方"):click();assert(#partyInvites==1 and partyInvites[1]==202)
   p:find("甲-远方"):click();assert(partyInvites[2]==101)''')
 def test_account_info_context_and_guild_character_choice(self):
  self.runlua('''d=open("BN_FRIEND",{accountInfo={bnetAccountID=77},name="战网昵称"})
   d:find("公会邀请"):find("乙-远方"):click();assert(guildInvites[1]=="乙-远方")
   assert(d:find("选择角色邀请"))
   assert(#open("BN_FRIEND",{name="战网昵称"}).children==0)''')
 def test_filters_offline_other_games_projects_regions_and_duplicates(self):
  self.runlua('''for i=3,8 do games[i]=toon(i,"过滤"..i)end
   games[3].isOnline=false;games[4].clientProgram="D3";games[5].wowProjectID=2;games[6].isInCurrentRegion=false
   games[7].realmID=0;games[8].playerGuid=nil;games[9]=games[1]
   d=open("BN_FRIEND",{bnetIDAccount=77});assert(#d:find("选择角色邀请").children==2)
   games={games[1]};d=open("BN_FRIEND",{bnetIDAccount=77});assert(not d:find("选择角色邀请"));assert(d:find("公会邀请"))''')
 def test_stale_offline_replaced_character_and_removed_friend_not_invited(self):
  self.runlua('''d=open("BN_FRIEND",{bnetIDAccount=77});p=d:find("选择角色邀请");games[2].isOnline=false;p:find("乙-远方"):click();assert(#partyInvites==0)
   games[1].playerGuid="Player-new";p:find("甲-远方"):click();assert(#partyInvites==0)
   d:find("公会邀请"):find("甲-远方"):click();assert(#guildInvites==0)
   friendIndex=nil;p:find("甲-远方"):click();assert(#partyInvites==0)''')
 def test_party_permission_full_group_and_cross_faction_rules(self):
  self.runlua('''partyPermission=false;d=open("BN_FRIEND",{bnetIDAccount=77});assert(not d:find("选择角色邀请").children[1].enabled)
   partyPermission=true;d=open("BN_FRIEND",{bnetIDAccount=77});partyFull=true;d:find("选择角色邀请").children[1]:click();assert(#partyInvites==0)
   partyFull=false;games[1].factionName="Alliance";C_PartyInfo.CanFormCrossFactionParties=function()return false end
   d=open("BN_FRIEND",{bnetIDAccount=77});assert(not d:find("选择角色邀请"):find("甲-远方").enabled)
   C_PartyInfo.CanFormCrossFactionParties=function()return true end
   d=open("BN_FRIEND",{bnetIDAccount=77});assert(d:find("选择角色邀请"):find("甲-远方").enabled)
   C_QuestSession.Exists=function()return true end;d:find("选择角色邀请"):find("甲-远方"):click();assert(#partyInvites==0)''')
 def test_game_mode_mismatch_cannot_invite(self):
  self.runlua('''Enum.GameMode={Standard=0};C_GameRules={GetActiveGameMode=function()return 0 end};CLASS_ID_TO_GAME_MODE={[999]=1};games[1].classID=999
   d=open("BN_FRIEND",{bnetIDAccount=77});assert(not d:find("选择角色邀请"):find("甲-远方").enabled)''')
 def test_two_independent_switches_and_module_toggle_no_duplicate_hooks(self):
  self.runlua('''local count=hookCount;m.db.guildInvite=false
   d=open("BN_FRIEND",{bnetIDAccount=77});assert(d:find("选择角色邀请") and not d:find("公会邀请"))
   m.db.guildInvite=true;m.db.multiInvite=false;d=open("BN_FRIEND",{bnetIDAccount=77});assert(not d:find("选择角色邀请") and d:find("公会邀请"))
   m.db.multiInvite=true;d=open("BN_FRIEND",{bnetIDAccount=77});ns.SetModuleEnabled("smalltools",false)
   d:find("选择角色邀请").children[1]:click();d:find("公会邀请").children[1]:click();assert(#partyInvites==0 and #guildInvites==0)
   assert(#open("BN_FRIEND",{bnetIDAccount=77}).children==0)
   for i=1,4 do ns.SetModuleEnabled("smalltools",true);ns.SetModuleEnabled("smalltools",false)end
   m.OnEnable(m);assert(hookCount==count)''')
 def test_missing_secret_or_erroring_api_fails_closed(self):
  self.runlua('''local secret={};issecretvalue=function(v)return rawequal(v,secret)end
   games[1].gameAccountID=secret;games[2].isOnline=secret;assert(#open("BN_FRIEND",{bnetIDAccount=77}).children==0)
   C_BattleNet.GetFriendNumGameAccounts=function()error("restricted")end;assert(#open("BN_FRIEND",{bnetIDAccount=77}).children==0)
   assert(#open("FRIEND",{name=secret}).children==0)
   C_GuildInfo=nil;GuildInvite=nil;assert(#open("TARGET",{unit="target"}).children==0)''')
 def test_late_menu_loading_registers_once(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute((ROOT/'tests/wow_ui_stub.lua').read_text(encoding='utf-8'));self.lua.execute(STUB)
  self.lua.execute('savedMenu=Menu;Menu=nil')
  for path in ['Core.lua','Modules/SmallTools.lua']:
   self.lua.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/path).read_text(encoding='utf-8'))
  self.runlua('''m=ns.modules.smalltools;m.OnEnable(m);assert(hookCount==0);Menu=savedMenu
   for _,f in ipairs(frames)do local event=f:GetScript("OnEvent");if event then event(f,"ADDON_LOADED","Blizzard_Menu")end end
   assert(hookCount==11);m.OnEnable(m);assert(hookCount==11)''')
if __name__=='__main__':unittest.main()
