"""Tests through the real module's data/presentation interfaces; no live account data."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
class MythicTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  for path in ['tests/wow_ui_stub.lua','tests/mythic_stub.lua']:
   self.lua.execute((ROOT/path).read_text(encoding='utf-8'))
  for path in ['Core.lua','Workspace.lua','Modules/MythicPlusData.lua','Modules/PartyKeystones.lua','Modules/MythicPlus.lua']:
   self.lua.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/path).read_text(encoding='utf-8'))
  self.runlua('m=ns.modules.mythicplus;d=ns.MythicPlus.GetDB();m.OnEnable();advance();D=ns.MythicPlusData')
 def runlua(self,code):self.lua.execute(code)
 def open(self):self.runlua('PVEFrame_ShowFrame("ChallengesFrame");advance();h=BaimiaoMythicPanel;c=h.canvas')
 def test_snapshot_counts_and_never_mutates_blizzard_tables(self):
  self.runlua('''local s=D.Snapshot();assert(#s.maps==8 and #s.runs==3)
   assert(s.byMap[399].weekly==16 and s.byMap[399].count==2 and s.byMap[399].timed==1)
   assert(s.runs[1].timed==true and s.runs[2].timed==false)
   assert(s.byMap[399].score==428 and s.rating==3204)
   assert(history[4].level==30 and #history==4 and history[1].index==nil)
   assert(s.vault[1].threshold==1 and s.vault[2].threshold==4)
   assert(s.keyMap==586 and s.keyLevel==15)''')
 def test_construct_open_and_restore_native_size(self):
  self.open()
  self.runlua('''assert(h:IsVisible() and PVEFrame:GetWidth()==840)
   assert(#c.tiles==8 and c.tiles[1].name:GetText()=="红玉新生法池")
   assert(c.tiles[1].portal.attributes.spell==393256)
   assert(c.tiles[1].portal:GetParent()==UIParent)
   assert(c.vaults[1].value:GetText()=="1 / 1")
   PVEFrame_ShowFrame("LFGListFrame");advance()
   assert(not h:IsVisible() and not c.tiles[1].portal:IsShown())
   assert(PVEFrame:GetWidth()==563 and PVEFrame:GetHeight()==428 and PVEFrame:GetScale()==.9)
   PVEFrame_ShowFrame("ChallengesFrame");advance();d.show=false;ns.MythicPlus.Refresh()
   assert(not h:IsShown() and PVEFrame:GetWidth()==563)''')
 def test_ak_enabled_and_disabled_do_not_change_or_mutate_layout(self):
  self.open()
  self.runlua('''local count=#frames;local info=ChallengesFrame.WeeklyInfo
   loaded={AngryKeystones=true};info.AffixFrame=CreateFrame("Frame",nil,info)
   local ak=info.AffixFrame;ak:SetPoint("CENTER",7,9)
   local before=ak.point;ChallengesFrame:Update();advance()
   assert(ak:IsShown() and ak.point==before)
   assert(h:IsShown() and ChallengesFrame.updates==1)
   loaded.AngryKeystones=false;ChallengesFrame:Update();advance()
   assert(PVEFrame:GetWidth()==840 and #frames==count+1)''')
 def test_kogo_late_show_and_restore_without_db_writes(self):
  self.open()
  self.runlua('''EllesmereUIPlusAccountDB={keep="untouched"}
   KogoMPlusPanel=CreateFrame("Frame",nil,UIParent)
   advance(.2);assert(not KogoMPlusPanel:IsShown())
   KogoMPlusPanel:Show();assert(not KogoMPlusPanel:IsShown())
   d.replaceKogo=false;ns.MythicPlus.Refresh();assert(KogoMPlusPanel:IsShown())
   d.replaceKogo=true;ns.MythicPlus.Refresh();assert(not KogoMPlusPanel:IsShown())
   ns.SetModuleEnabled("mythicplus",false);assert(KogoMPlusPanel:IsShown())
   assert(EllesmereUIPlusAccountDB.keep=="untouched" and EllesmereUIPlusAccountDB.gameplay==nil)''')
 def test_combat_defers_first_build_and_hides_existing_secure_targets(self):
  self.runlua('''setCombat(true);PVEFrame_ShowFrame("ChallengesFrame");advance()
   assert(BaimiaoMythicPanel==nil and PVEFrame:GetWidth()==563)
   setCombat(false);assert(BaimiaoMythicPanel:IsShown())
   local b=BaimiaoMythicPanel.canvas.tiles[1].portal;assert(b:IsShown())
   setCombat(true);assert(not b:IsShown());ns.SetModuleEnabled("mythicplus",false)
   assert(PVEFrame:GetWidth()==840)
   setCombat(false);assert(not BaimiaoMythicPanel:IsShown() and not b:IsShown())
   assert(PVEFrame:GetWidth()==563)''')
 def test_close_in_combat_does_not_leave_portals_on_screen(self):
  self.open()
  self.runlua('''setCombat(true);PVEFrame_ShowFrame("LFGListFrame");advance();setCombat(false)
   for _,t in ipairs(c.tiles)do assert(not t.portal:IsShown())end
   assert(PVEFrame:GetWidth()==563)''')
 def test_unknown_unlearned_and_faction_portals(self):
  self.runlua('''assert(D.PortalID(99999)==nil)
   local id,state=D.Portal(250);assert(id==1286828 and state=="未学会传送")
   known[159898]=true;assert(D.PortalID(161)==159898)
   known[1254557]=true;assert(D.PortalID(161)==1254557)
   faction="Horde";assert(D.PortalID(161)==159898)
   C_Spell.GetSpellCooldown=function()return {startTime=100,duration=300}end
   id,state=D.Portal(399);assert(state=="冷却 5 分钟")''')
 def test_teleport_toggle_clears_action_and_keeps_card_tooltip(self):
  self.open()
  self.runlua('''local b=c.tiles[1].portal;assert(b.driverRule)
   d.teleport=false;ns.MythicPlus.Refresh()
   assert(not b:IsShown() and b.attributes.type1==nil and b.attributes.spell==nil and not b.driverRule)
   c.tiles[1]:GetScript("OnEnter")(c.tiles[1]);assert(GameTooltip:IsShown())''')
 def test_paging_scroll_and_counts_beyond_first_eight(self):
  self.open()
  self.runlua('''for i=1,4 do table.insert(mapIDs,9000+i)end
   for i=1,30 do table.insert(history,{mapChallengeModeID=399,level=2,thisWeek=true,durationSec=1600})end
   ns.MythicPlus.Refresh();assert(c.next:IsShown())
   c.next:GetScript("OnClick")();assert(c.tiles[1].map.id>=9000)
   c.list:GetScript("OnMouseWheel")(c.list,-100)
   assert(c.range:GetText():find("33 / 33",1,true))
   c.mapTab:GetScript("OnClick")();assert(c.rows[1].summary)
   d.sortBy="weekly";ns.MythicPlus.Refresh()''')
 def test_no_history_no_maps_unavailable_apis(self):
  self.runlua('''history={};C_ChallengeMode.GetMapTable=function()return {}end
   C_WeeklyRewards.GetActivities=function()return nil end
   C_MythicPlus.GetCurrentAffixes=function()return nil end''')
  self.open()
  self.runlua('''assert(c.noMaps:IsShown());assert(c.empty:GetText()=="本周还没有大秘境记录")
   assert(c.vaults[1].value:GetText()=="—")
   C_MythicPlus.GetRunHistory=function()error("not ready")end;ns.MythicPlus.Refresh()
   assert(c.empty:GetText():find("等待",1,true))''')
 def test_data_events_refresh_without_click_and_no_network_storm(self):
  self.open()
  self.runlua('''history={};fire("WEEKLY_REWARDS_UPDATE");advance();assert(c.rows[1]:IsShown()==false)
   ns.MythicPlus.RequestData();ns.MythicPlus.RequestData();assert(requests==1)
   local count=#frames
   for i=1,50 do fire("WEEKLY_REWARDS_UPDATE");fire("SPELL_UPDATE_COOLDOWN");advance()end
   assert(#frames==count and requests==1)''')
 def test_theme_settings_and_small_screen_fit(self):
  self.open()
  self.runlua('''ns.UI.BuildWorkspace();ns.OpenOptions("mythicplus")
   assert(#m.mythicTabs.pages==3 and #messages==0,table.concat(messages,";"))
   for i=1,3 do m.mythicTabs.Select(i)end
   local count=#frames
   BaimiaoToolboxWorkspace.theme:GetScript("OnClick")();advance()
   assert(h.bg[1]>.9 and #frames==count)
   UIParent:SetSize(800,600);ns.MythicPlus.Refresh()
   assert(PVEFrame:GetScale()*840<800 and PVEFrame:GetScale()*494<600)
   d.showWeekly=false;ns.MythicPlus.Refresh();assert(not c.weekly:IsShown() and c.tiles[1]:GetWidth()>380)''')
 def test_secret_or_unknown_timings_are_not_called_failures(self):
  self.runlua('''local secret={};issecretvalue=function(v)return v==secret end
   history={{mapChallengeModeID=399,level=16,thisWeek=true,durationSec=secret}}
   local s=D.Snapshot();assert(#s.runs==1 and s.runs[1].timed==nil)
   C_Spell.GetSpellCooldown=function()return {startTime=secret,duration=secret}end
   local _,state=D.Portal(399);assert(state=="冷却状态暂不可用")''')

 def test_unknown_history_is_not_displayed_as_zero_and_vault_is_not_guessed(self):
  self.runlua('C_MythicPlus.GetRunHistory=function()return nil end')
  self.open()
  self.runlua("""assert(c.tiles[1].week:GetText()=="本周待同步")
   assert(c.vaults[1].detail:GetText()=="已解锁")
   c.mapTab:GetScript("OnClick")();assert(c.rows[1].right:GetText()=="待同步")
   assert(c.empty:GetText()=="")
   c.vaults[1]:GetScript("OnEnter")(c.vaults[1]);assert(GameTooltip:GetText()=="地下城宝库进度")""")
 def test_native_ui_late_load_and_reopen_does_not_grow_widgets(self):
  self.runlua("""ns.SetModuleEnabled("mythicplus",false)
   local old=ChallengesFrame;ChallengesFrame=nil
   PVEFrame:Show();ns.SetModuleEnabled("mythicplus",true);advance()
   assert(BaimiaoMythicPanel==nil)
   ChallengesFrame=old;fire("ADDON_LOADED","Blizzard_ChallengesUI");advance()""")
  self.open()
  self.runlua("""local count=#frames
   for i=1,25 do
    PVEFrame:Hide();advance();assert(not c.tiles[1].portal:IsShown())
    assert(PVEFrame:GetWidth()==563)
    PVEFrame_ShowFrame("ChallengesFrame");ChallengesFrame:Update();advance()
    assert(c.tiles[1].portal:IsShown())
   end
   assert(#frames==count)
   c.refresh:GetScript("OnClick")();advance();assert(requests==1)""")
 def test_partial_rating_and_portal_cooldown_updates(self):
  self.runlua('C_PlayerInfo.GetPlayerMythicPlusRatingSummary=function()return nil end')
  self.open()
  self.runlua("""assert(c.tiles[1].stats:GetText():find("—",1,true))
   C_Spell.GetSpellCooldown=function()return {startTime=100,duration=7200}end
   fire("SPELL_UPDATE_COOLDOWN")
   local found=false
   for _,tile in ipairs(c.tiles)do
    if tile.map.id==399 then
     assert(tile.state:GetText()=="冷却 2 小时" and tile.portalStatus:IsShown())
     assert(not tile.portal:IsShown() and tile.portal.attributes.spell==nil);found=true end
   end
   assert(found)""")

if __name__=='__main__':unittest.main()