"""Follow-up regressions: weekly roster source and inferred lust after leaving an instance."""
import unittest
import test_raid_music
import test_mythicplus_details

class LustBoundaryTests(unittest.TestCase):
 setUp=test_raid_music.RaidMusicTests.setUp
 runlua=test_raid_music.RaidMusicTests.runlua
 fixture=test_raid_music.RaidMusicTests.fixture

 def instance_fixture(self):
  self.fixture('inInstance=true;instanceType="party";function IsInInstance()return inInstance,instanceType end;d.music.loop=true')

 def test_leaving_dungeon_clears_inferred_lust_without_waiting_for_world_event(self):
  self.instance_fixture()
  self.runlua('''combat=true;auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   combat=false;inInstance=false;instanceType="none";tick()
   assert(not BaimiaoRaidCDFrame.rows[1].text:GetText():find("嗜血中",1,true),"outside with no buff still shows active lust")
   assert(tickers[1].cancelled and #stopped==1,"inferred music outlived dungeon context")''')

 def test_late_old_sated_after_zone_in_does_not_restart_outside(self):
  self.instance_fixture()
  self.runlua('''inInstance=false;instanceType="none";event("PLAYER_ENTERING_WORLD")
   auras[57724]={duration=600,expirationTime=now+400};tick()
   assert(#played==0,"old Sated loaded after zoning manufactured fresh lust")
   assert(not BaimiaoRaidCDFrame.rows[1].text:GetText():find("嗜血中",1,true))''')

 def test_old_sated_arriving_late_inside_does_not_manufacture_new_lust(self):
  self.instance_fixture()
  self.runlua('''auras[57724]={duration=600,expirationTime=now+400};tick();assert(#played==0)
   auras={};tick();auras[57724]={duration=600,expirationTime=now+600};tick();assert(#played==1)''')

 def test_real_buff_outdoors_still_works_without_fatigue_inference(self):
  self.instance_fixture()
  self.runlua('''inInstance=false;instanceType="none";tick()
   auras[57724]={duration=600,expirationTime=now+600};tick();assert(#played==0)
   auras[2825]={expirationTime=now+30};tick();assert(#played==1)
   assert(not BaimiaoRaidCDFrame.rows[1].text:GetText():find("约",1,true))
   auras[2825]=nil;tick();assert(#stopped==1)''')

 def test_loading_screen_stops_inference_and_old_sated_is_not_replayed(self):
  self.instance_fixture()
  self.runlua('''auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   event("PLAYER_LEAVING_WORLD");assert(#stopped==1 and tickers[1].cancelled)
   tick();assert(#played==1)
   event("PLAYER_ENTERING_WORLD");tick();assert(#played==1)
   auras={};tick();auras[57724]={expirationTime=now+600};tick();assert(#played==2)''')

 def test_disable_during_loading_then_reenable_does_not_stick_in_loading(self):
  self.instance_fixture()
  self.runlua('''event("PLAYER_LEAVING_WORLD");ns.SetModuleEnabled("raidcd",false)
   event("PLAYER_ENTERING_WORLD");ns.SetModuleEnabled("raidcd",true)
   auras[2825]={expirationTime=now+30};tick();assert(#played==1,"loading flag stuck after reenable")''')

 def test_timer_also_stops_on_exit_before_next_poll(self):
  self.instance_fixture()
  self.runlua('''auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   inInstance=false;instanceType="none";tickers[1].fn()
   assert(#played==1 and tickers[1].cancelled and #stopped==1)''')

 def test_unknown_instance_never_infers_and_secret_duration_is_not_used(self):
  self.instance_fixture()
  self.runlua('''IsInInstance=function()return secret,secret end
   auras[57724]={expirationTime=now+600};tick();assert(#played==0)
   IsInInstance=function()return true,"party" end;auras={};tick()
   auras[57724]={duration=secret,expirationTime=now+600};tick();assert(#played==1)''')

 def test_changing_zone_immediately_refreshes_inferred_state(self):
  self.instance_fixture()
  self.runlua('''auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   inInstance=false;instanceType="none";event("ZONE_CHANGED_NEW_AREA")
   assert(not BaimiaoRaidCDFrame.rows[1].text:GetText():find("嗜血中",1,true) and #stopped==1)''')

class WeeklyRosterTests(unittest.TestCase):
 setUp=test_mythicplus_details.MythicDetailTests.setUp
 runlua=test_mythicplus_details.MythicDetailTests.runlua
 open=test_mythicplus_details.MythicDetailTests.open
 tooltip_stub=test_mythicplus_details.MythicDetailTests.tooltip_stub

 def test_weekly_run_uses_weekly_team_not_season_self_only(self):
  self.tooltip_stub()
  self.runlua('''local roster={{name="我自己",classID=1,specID=73},{name="队友甲"},{name="队友乙"},{name="队友丙"},{name="队友丁"}}
   C_MythicPlus.GetWeeklyBestForMap=function(id)if id==399 then return 1799,16,nil,{},roster,428 end end
   C_MythicPlus.GetSeasonBestForMap=function(id)if id==399 then return {level=18,durationSec=1700,dungeonScore=450,members={roster[1]}} end end''')
  self.open()
  self.runlua('''c.rows[1]:GetScript("OnEnter")(c.rows[1]);local t=tooltipText()
   assert(t:find("本周最佳队伍",1,true) and t:find("队友丁",1,true),"weekly tooltip selected season self-only roster over weekly five-player roster")''')

 def test_weekly_summary_and_diagnostic_use_same_weekly_source(self):
  self.test_weekly_run_uses_weekly_team_not_season_self_only()
  self.runlua('''c.mapTab:GetScript("OnClick")();c.rows[1]:GetScript("OnEnter")(c.rows[1])
   assert(tooltipText():find("本周最佳队伍",1,true) and tooltipText():find("队友丁",1,true))
   messages={};SlashCmdList.BMMYTHICPLUS("team");local text=table.concat(messages," | ")
   assert(text:find("本周看板采用：本周最佳",1,true))
   assert(text:find("本周最佳 +16：名单 5 人 / 有姓名 5 人",1,true))
   assert(text:find("赛季限时最佳 +18：名单 1 人 / 有姓名 1 人",1,true))''')

 def test_cards_fall_back_to_whole_weekly_run_when_season_only_has_self(self):
  self.test_weekly_run_uses_weekly_team_not_season_self_only()
  self.runlua('''c.tiles[1]:GetScript("OnEnter")(c.tiles[1]);local text=tooltipText()
   assert(text:find("本周最佳队伍",1,true) and text:find("队友丁",1,true))
   assert(text:find("+16",1,true) and text:find("428",1,true))
   assert(not text:find("+18",1,true) and not text:find("450",1,true),"different runs must not have their rosters spliced together")
   messages={};SlashCmdList.BMMYTHICPLUS("team");assert(table.concat(messages," | "):find("副本卡片采用：本周最佳",1,true))''')

 def test_both_sources_only_self_are_explicitly_partial_not_fabricated(self):
  self.tooltip_stub()
  self.runlua('''C_MythicPlus.GetWeeklyBestForMap=function()return 1799,16,nil,{},{{name="我自己"}},428 end
   C_MythicPlus.GetSeasonBestForMap=function()return {level=18,durationSec=1700,dungeonScore=450,members={{name="我自己"}}}end
   UnitName=function()return "不属于最佳队伍的当前队友"end''')
  self.open()
  self.runlua('''c.rows[1]:GetScript("OnEnter")(c.rows[1]);local text=tooltipText()
   assert(text:find("仅1人资料",1,true) and text:find("我自己",1,true))
   assert(not text:find("不属于最佳队伍",1,true))''')

 def test_unnamed_members_keep_specs_but_do_not_pretend_names_available(self):
  self.tooltip_stub()
  self.runlua('''local secret={};issecretvalue=function(v)return rawequal(v,secret)end
   C_MythicPlus.GetWeeklyBestForMap=function()return 1799,16,nil,{},{{name="我自己",specID=73},{name=secret,specID=65},{specID=65},{specID=65},{specID=65}},428 end
   GetSpecializationInfoByID=function(id)return id,id==73 and "防护" or "神圣" end''')
  self.open()
  self.runlua('''c.rows[1]:GetScript("OnEnter")(c.rows[1]);local text=tooltipText()
   assert(text:find("姓名不全",1,true) and text:find("姓名未提供",1,true) and text:find("神圣",1,true))
   messages={};SlashCmdList.BMMYTHICPLUS("team");assert(table.concat(messages," | "):find("名单 5 人 / 有姓名 1 人",1,true))''')

 def test_missing_weekly_falls_back_to_correctly_labelled_season(self):
  self.tooltip_stub()
  self.runlua('''C_MythicPlus.GetSeasonBestForMap=function()return {level=18,durationSec=1700,dungeonScore=450,members={{name="赛季队友"}}}end''')
  self.open()
  self.runlua('''c.rows[1]:GetScript("OnEnter")(c.rows[1]);local text=tooltipText()
   assert(text:find("赛季限时最佳队伍",1,true) and text:find("赛季队友",1,true))
   assert(not text:find("本周最佳队伍",1,true))''')

 def test_team_command_before_hover_requests_specific_map(self):
  self.runlua('''SlashCmdList.BMMYTHICPLUS("team")
   assert(table.concat(messages," | "):find("请先把鼠标移到",1,true))''')

 def test_weekly_self_only_can_use_labelled_season_team_without_mixing_stats(self):
  self.tooltip_stub()
  self.runlua('''C_MythicPlus.GetWeeklyBestForMap=function()return 1799,16,nil,{},{{name="我自己"}},428 end
   C_MythicPlus.GetSeasonBestForMap=function()return {level=18,durationSec=1700,dungeonScore=450,members={{name="我自己"},{name="赛季队友"}}}end''')
  self.open()
  self.runlua('''local best=D.BestDetails(399,true)
   assert(best.source=="赛季限时最佳" and best.level==18 and best.duration==1700 and best.score==450)
   c.rows[1]:GetScript("OnEnter")(c.rows[1]);local text=tooltipText()
   assert(text:find("赛季限时最佳队伍",1,true) and text:find("赛季队友",1,true))
   assert(not text:find("本周最佳队伍",1,true))''')

if __name__=='__main__':unittest.main()
