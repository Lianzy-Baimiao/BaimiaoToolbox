"""Real party-key service/protocol tests; no network or saved teammate history."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
import test_mythicplus
ROOT=Path(__file__).resolve().parents[1]
STUB=r'''
party={
 {name="甲",realm="本服",guid="Player-2",class="WARRIOR",online=true},
 {name="乙",realm="外服",guid="Player-3",class="PALADIN",online=true},
 {name="丙",realm="外服",guid="Player-4",class="MAGE",online=true},
 {name="丁",realm="本服",guid="Player-5",class="PRIEST",online=true}}
raid=false;instance=false;sent={};prefixes={};updates=0;chatLocked=false
function IsInRaid()return raid end
function IsInGroup(category)return #party>0 and (instance and category==2 or not instance and category~=2)end
function unitData(unit)return party[tonumber(unit:match("^party(%d)$"))]end
function UnitExists(unit)return unitData(unit)~=nil end
function UnitFullName(unit)if unit=="player"then return "本人","本服"end;local p=unitData(unit);if p then return p.name,p.realm end end
function UnitGUID(unit)if unit=="player"then return "Player-1"end;local p=unitData(unit);return p and p.guid end
function UnitClass(unit)local p=unitData(unit);return "职业",p and p.class or "WARRIOR"end
function UnitIsConnected(unit)local p=unitData(unit);return p and p.online end
function GetNormalizedRealmName()return "本服"end
C_ChatInfo={RegisterAddonMessagePrefix=function(p)prefixes[p]=true end,
 SendAddonMessage=function(p,msg,ch)sent[#sent+1]={prefix=p,message=msg,channel=ch}end,
 InChatMessagingLockdown=function()return chatLocked end}
'''
class PartyKeystoneTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  for p in ['tests/wow_ui_stub.lua','tests/mythic_stub.lua']:
   self.lua.execute((ROOT/p).read_text(encoding='utf-8'))
  self.lua.execute(STUB)
  for p in ['Core.lua','Modules/PartyKeystones.lua']:
   self.lua.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/p).read_text(encoding='utf-8'))
  self.lua.execute('K=ns.PartyKeystones;K.Start(function()updates=updates+1 end)')
 def runlua(self,s):self.lua.execute(s)
 def test_only_four_teammates_no_self_and_no_raid(self):
  self.runlua('''local rows=K.Snapshot();assert(#rows==4 and rows[1].name=="甲-本服" and rows[2].name=="乙-外服")
   for _,r in ipairs(rows)do assert(r.name~="本人-本服" and r.status=="待同步")end
   raid=true;fire("GROUP_ROSTER_UPDATE");assert(#K.Snapshot()==0)
   raid=false;party={};fire("GROUP_ROSTER_UPDATE");assert(#K.Snapshot()==0)''')
 def test_two_protocols_and_class_names(self):
  self.runlua('''fire("CHAT_MSG_ADDON","LibKS","17,587,3120","PARTY","甲-本服")
   fire("CHAT_MSG_ADDON","WA-KeyStGrList","KSGL:Send:588:15:0:0:1","PARTY","乙-外服")
   local r=K.Snapshot();assert(r[1].level==17 and r[1].mapID==587 and r[1].class=="WARRIOR")
   assert(r[2].level==15 and r[2].mapID==588 and r[3].status=="待同步")
   assert(BaimiaoToolboxDB==nil or BaimiaoToolboxDB.partyKeystones==nil)''')
 def test_reject_outsiders_wrong_channels_and_identity_collisions(self):
  self.runlua('''for _,sender in ipairs({"路人-本服","乙-错误服","本人-本服"})do
    fire("CHAT_MSG_ADDON","LibKS","20,587,0","PARTY",sender)
   end
   fire("CHAT_MSG_ADDON","LibKS","20,587,0","GUILD","甲-本服")
   fire("CHAT_MSG_ADDON","LibKS","20,587,0","WHISPER","甲-本服")
   for _,r in ipairs(K.Snapshot())do assert(r.level==nil)end
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲")
   assert(K.Snapshot()[1].level==17)
   fire("CHAT_MSG_ADDON","LibKS","19,587,0","PARTY","乙")
   assert(K.Snapshot()[2].level==nil)''')
 def test_malformed_secret_and_out_of_range_values(self):
  self.runlua('''local secret={};issecretvalue=function(v)return v==secret end
   for _,msg in ipairs({"-1,-1,0","201,587,0","17,1000000,0","2,0,0","0,587,0","17,587,0extra",string.rep("1",110),secret})do
    fire("CHAT_MSG_ADDON","LibKS",msg,"PARTY","甲-本服")
   end
   fire("CHAT_MSG_ADDON",secret,"17,587,0","PARTY","甲-本服")
   fire("CHAT_MSG_ADDON","LibKS","17,587,0",secret,"甲-本服")
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY",secret)
   assert(K.Snapshot()[1].status=="待同步")''')
 def test_explicit_no_key_is_distinct_from_pending(self):
  self.runlua('''fire("CHAT_MSG_ADDON","LibKS","0,0,0","PARTY","甲-本服")
   assert(K.Snapshot()[1].status=="无钥石" and K.Snapshot()[2].status=="待同步")''')
 def test_leave_rejoin_and_replaced_guid_do_not_reuse_history(self):
  self.runlua('''fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服")
   local p=table.remove(party,1);fire("GROUP_ROSTER_UPDATE")
   table.insert(party,1,p);fire("GROUP_ROSTER_UPDATE");assert(K.Snapshot()[1].status=="待同步")
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服")
   party[1].guid="Player-new";fire("GROUP_ROSTER_UPDATE");assert(K.Snapshot()[1].status=="待同步")''')
 def test_offline_expired_zoned_and_dungeon_start_clear_values(self):
  self.runlua('''function key()fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服")end
   key();party[1].online=false;fire("GROUP_ROSTER_UPDATE");assert(K.Snapshot()[1].status=="离线")
   party[1].online=true;fire("GROUP_ROSTER_UPDATE");assert(K.Snapshot()[1].status=="待同步")
   key();advance(601);assert(K.Snapshot()[1].status=="待同步")
   key();fire("CHALLENGE_MODE_START");assert(K.Snapshot()[1].status=="待同步")
   key();fire("PLAYER_LEAVING_WORLD");assert(K.Snapshot()[1].status=="待同步")''')
 def test_party_chat_link_fallback_requires_current_sender(self):
  self.runlua('''fire("CHAT_MSG_PARTY","|cffa335ee|Hkeystone:180653:587:16:10:9:0:0|h[钥石]|h|r","甲-本服")
   assert(K.Snapshot()[1].level==16 and K.Snapshot()[1].source:find("链接"))
   fire("CHAT_MSG_PARTY","|Hkeystone:180653:587:20:|h[钥石]|h","路人-本服")
   assert(K.Snapshot()[1].level==16)''')
 def test_instance_group_uses_instance_channel_only(self):
  self.runlua('''instance=true;fire("GROUP_ROSTER_UPDATE");sent={};advance(6);K.Request()
   for _,m in ipairs(sent)do assert(m.channel=="INSTANCE_CHAT")end
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服");assert(K.Snapshot()[1].level==nil)
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","INSTANCE_CHAT","甲-本服");assert(K.Snapshot()[1].level==17)''')
 def test_requests_throttle_and_replies_do_not_echo_responses(self):
  self.runlua('''assert(prefixes.LibKS and prefixes["WA-KeyStGrList"] and #sent==4)
   for i=1,50 do K.Request();fire("GROUP_ROSTER_UPDATE");fire("CHAT_MSG_ADDON","LibKS","R","PARTY","甲-本服")end
   assert(#sent==4)
   advance(4);fire("CHAT_MSG_ADDON","LibKS","R","PARTY","甲-本服");assert(#sent==5)
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服");assert(#sent==5)
   advance(4);fire("CHAT_MSG_ADDON","LibKS","R","PARTY","路人-本服");assert(#sent==5)''')
 def test_combat_or_chat_lockdown_blocks_outgoing_not_public_receiving(self):
  self.runlua('''sent={};advance(6);combat=true;K.Request();fire("CHAT_MSG_ADDON","LibKS","R","PARTY","甲-本服");assert(#sent==0)
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服");assert(K.Snapshot()[1].level==17)
   combat=false;chatLocked=true;K.Request();assert(#sent==0)
   chatLocked=false;K.Request();assert(#sent==4)''')
 def test_stop_reenable_and_secret_own_key_never_announce_guesses(self):
  self.runlua('''K.Stop();sent={};advance(6);fire("CHAT_MSG_ADDON","LibKS","R","PARTY","甲-本服");assert(#sent==0 and #K.Snapshot()==0)
   local secret={};issecretvalue=function(v)return v==secret end
   C_MythicPlus.GetOwnedKeystoneLevel=function()return secret end
   K.Start(function()end);assert(#sent==2,"only requests; never announce guessed zero")
   assert(K.Snapshot()[1].status=="待同步")''')

 def test_bag_changes_coalesce_and_do_not_repeat_unchanged_keys(self):
  self.runlua('''sent={};local level=16
   C_MythicPlus.GetOwnedKeystoneLevel=function()return level end
   fire("BAG_UPDATE_DELAYED");level=17;fire("BAG_UPDATE_DELAYED");assert(#sent==0)
   advance(4);assert(#sent==2)
   assert(sent[1].message=="17,586,3204" and sent[2].message=="KSGL:Send:586:17:0:0:0")
   for i=1,20 do fire("BAG_UPDATE_DELAYED")end
   advance(4);assert(#sent==2,"unchanged bag events must not broadcast")''')
 def test_stale_own_change_timer_does_not_cross_stop_start(self):
  self.runlua('''C_MythicPlus.GetOwnedKeystoneLevel=function()return 16 end
   fire("BAG_UPDATE_DELAYED");K.Stop();K.Start(function()end);sent={}
   advance(4);assert(#sent==0,"old lifecycle must not send into new session")''')
 def test_rating_preserved_but_unreadable_rating_not_propagated(self):
  self.runlua('''assert(sent[3].prefix=="LibKS" and sent[3].message=="15,586,3204")
   local secret={};issecretvalue=function(v)return v==secret end
   C_PlayerInfo.GetPlayerMythicPlusRatingSummary=function()return {currentSeasonScore=secret}end
   advance(6);sent={};K.Request();assert(sent[3].message=="15,586,0")''')

class PartyKeyLayoutTests(unittest.TestCase):
 setUp=test_mythicplus.MythicTests.setUp
 runlua=test_mythicplus.MythicTests.runlua
 open=test_mythicplus.MythicTests.open
 def test_four_rows_below_buttons_no_other_coordinates_changed(self):
  self.lua.execute(STUB);self.open()
  self.runlua('''assert(#c.partyRows==4)
   for i,f in ipairs(c.partyRows)do
    assert(f:IsVisible() and f.point[4]==276 and -f.point[5]==36+(i-1)*12)
    assert(f:GetWidth()==192 and f:GetHeight()==12)
   end
   assert(c.settings.point[4]==342 and c.settings.point[5]==-8)
   assert(c.refresh.point[4]==408 and c.refresh.point[5]==-8)
   assert(c.key.point[2]==12 and c.key.point[3]==-36)
   assert(c.score.point[2]==12 and c.score.point[3]==-62)
   assert(c.affixTitle.point[2]==12 and c.affixTitle.point[3]==-93)
   assert(c.tiles[1].point[4]==12 and c.tiles[1].point[5]==-140)
   assert(PVEFrame:GetWidth()==840 and PVEFrame:GetHeight()==462)
   fire("CHAT_MSG_ADDON","LibKS","17,587,0","PARTY","甲-本服");advance()
   assert(c.partyRows[1].level:GetText():find("+17",1,true))
   assert(c.partyRows[1].dungeon:GetText()==D.Map(587).name)
   c.partyRows[1]:GetScript("OnEnter")(c.partyRows[1]);assert(GameTooltip:GetText()=="甲-本服")
   raid=true;fire("GROUP_ROSTER_UPDATE");advance();assert(not c.partyRows[1]:IsShown())
   assert(c.key:GetWidth()==452 and #c.tiles==8)
  ''')
 def test_page_switch_hides_party_and_does_not_grow_frames(self):
  self.lua.execute(STUB);self.open()
  self.runlua('''local count=#frames
   PVEFrame_ShowFrame("PVPUIFrame");advance();assert(not c.partyRows[1]:IsVisible())
   PVEFrame_ShowFrame("ChallengesFrame");advance();assert(c.partyRows[1]:IsVisible())
   assert(#frames==count)
   ns.SetModuleEnabled("mythicplus",false);assert(#ns.PartyKeystones.Snapshot()==0)
  ''')
 def test_six_character_names_fit_and_key_text_does_not_overlap(self):
  self.lua.execute(STUB)
  self.runlua('party[1].name="这是六字队友";party[2].name="Warriorxxxxx"')
  self.open()
  self.runlua('''local f=c.partyRows[1]
   assert(f.owner:GetWidth()>=100,"34px name column truncates normal teammate names")
   assert(f.owner:GetText():find("这是六字队友",1,true))
   assert(f.point[4]+f.level.point[2]==378,"keep level column in place")
   assert(f.point[4]+f.dungeon.point[2]==406,"keep dungeon column in place")
   assert(c.key.point[2]+c.key:GetWidth()+10<=f.point[4])
   assert(c.score.point[2]+c.score:GetWidth()+10<=f.point[4])
   assert(f.point[4]+f:GetWidth()==468 and c.partyRows[4].point[5]==-72)
   ns.GetDB("mythicplus").showWeekly=false;ns.MythicPlus.Refresh();advance()
   assert(c.partyRows[1].point[4]+c.partyRows[1]:GetWidth()==808)
   assert(c.partyRows[1].owner:GetWidth()>=100)
  ''')
 def test_long_current_key_scales_to_fit_without_moving(self):
  self.lua.execute(STUB);self.open()
  self.runlua('''c.key.GetStringWidth=function()return 300 end
   ns.MythicPlus.Refresh();advance()
   assert(c.key.fontSize==15 and c.key:GetWidth()==254)
   assert(c.key.point[2]==12 and c.key.point[3]==-36)
   raid=true;fire("GROUP_ROSTER_UPDATE");advance()
   assert(c.key.fontSize==18 and c.key:GetWidth()==452)''')
if __name__=='__main__':unittest.main()
