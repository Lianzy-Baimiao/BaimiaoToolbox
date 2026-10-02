"""Overtime level color follows the displayed run, including summary ties."""
import unittest
import test_mythicplus_details

class OvertimeColorTests(unittest.TestCase):
 setUp=test_mythicplus_details.MythicDetailTests.setUp
 runlua=test_mythicplus_details.MythicDetailTests.runlua
 open=test_mythicplus_details.MythicDetailTests.open
 tooltip_stub=test_mythicplus_details.MythicDetailTests.tooltip_stub

 def fixture(self):
  self.tooltip_stub()
  self.runlua('''mapIDs={399};history={{mapChallengeModeID=399,level=17,thisWeek=true,durationSec=1900}}
   C_ChallengeMode.GetKeystoneLevelRarityColor=function()return {r=1,g=.5,b=0}end
   C_PlayerInfo.GetPlayerMythicPlusRatingSummary=function()return {currentSeasonScore=100,runs={
    {challengeModeID=399,bestRunLevel=17,bestRunDurationMS=1900000,mapScore=100}}}end
   function dim(level)local p=ns.UI.palette.muted
    return string.format("|cff%02x%02x%02x+%d|r",math.floor(p[1]*255+.5),math.floor(p[2]*255+.5),math.floor(p[3]*255+.5),level)end
   bright="|cffff8000+17|r"''')

 def test_overtime_dimmed_on_cards_history_summary_and_weekly_header(self):
  self.fixture();self.open()
  self.runlua('''for _,text in ipairs({c.tiles[1].stats:GetText(),c.tiles[1].week:GetText(),c.rows[1].left:GetText(),c.weekStats:GetText()})do
    assert(text:find(dim(17),1,true),"overtime level is not dim: "..text)end
   c.rows[1]:GetScript("OnEnter")(c.rows[1]);assert(tooltipText():find(dim(17),1,true))
   c.mapTab:GetScript("OnClick")();assert(c.rows[1].right:GetText():find(dim(17),1,true))
   assert(c.key:GetText():find("|cffff8000",1,true),"owned keystone is not a failed run")''')

 def test_equal_highest_timed_run_keeps_normal_color_regardless_of_order(self):
  self.fixture()
  self.runlua('''history[2]={mapChallengeModeID=399,level=17,thisWeek=true,durationSec=1700}
   for i=1,2 do local s=D.Snapshot();assert(s.byMap[399].weeklyRun.timed==true and s.weeklyBest.timed==true)
    history[1],history[2]=history[2],history[1] end''')
  self.open()
  self.runlua('''assert(c.tiles[1].week:GetText():find(bright,1,true) and c.weekStats:GetText():find(bright,1,true))
   assert(c.rows[1].left:GetText():find(dim(17),1,true) and c.rows[2].left:GetText():find(bright,1,true))
   c.mapTab:GetScript("OnClick")();assert(c.rows[1].right:GetText():find(bright,1,true))
   assert(c.tiles[1].stats:GetText():find(dim(17),1,true),"season status must not be replaced by weekly status")''')

 def test_lower_timed_run_does_not_brighten_higher_overtime(self):
  self.fixture();self.runlua('history[2]={mapChallengeModeID=399,level=16,thisWeek=true,durationSec=1700}')
  self.open();self.runlua('assert(c.tiles[1].week:GetText():find(dim(17),1,true) and c.weekStats:GetText():find(dim(17),1,true))')

 def test_unknown_or_secret_duration_not_mislabeled_overtime(self):
  self.fixture();self.runlua('''local secret={};issecretvalue=function(v)return rawequal(v,secret)end
   history[1].durationSec=secret
   C_PlayerInfo.GetPlayerMythicPlusRatingSummary=function()return {runs={{challengeModeID=399,bestRunLevel=17,bestRunDurationMS=secret}}}end''')
  self.open();self.runlua('''assert(c.tiles[1].stats:GetText():find(bright,1,true) and c.tiles[1].week:GetText():find(bright,1,true))
   assert(c.rows[1].left:GetText():find(bright,1,true) and c.rows[1].right:GetText()=="未知")''')

 def test_best_tooltip_uses_its_own_timing_and_color_survives_theme_change(self):
  self.fixture();self.runlua('''C_MythicPlus.GetWeeklyBestForMap=function()return 1900,17,nil,{},{{name="本人"}},100 end''')
  self.open();self.runlua('''c.rows[1]:GetScript("OnEnter")(c.rows[1]);assert(tooltipText():find(dim(17),1,true))
   ns.UI.BuildWorkspace();BaimiaoToolboxWorkspace.theme:GetScript("OnClick")();ns.MythicPlus.Refresh()
   c.tiles[1]:GetScript("OnEnter")(c.tiles[1]);assert(tooltipText():find(dim(17),1,true))
   assert(c.tiles[1].week:GetText():find(dim(17),1,true))''')

 def test_explicit_season_overtime_source_without_duration_still_dimmed(self):
  self.fixture();self.runlua('''C_MythicPlus.GetWeeklyBestForMap=function()end
   C_MythicPlus.GetSeasonBestForMap=function()return nil,{level=17,members={{name="本人"}},dungeonScore=100}end''')
  self.open();self.runlua('''c.tiles[1]:GetScript("OnEnter")(c.tiles[1]);assert(tooltipText():find(dim(17),1,true))''')

 def test_unknown_highest_tie_not_declared_overtime(self):
  self.fixture();self.runlua('''history[2]={mapChallengeModeID=399,level=17,thisWeek=true}
   for i=1,2 do local s=D.Snapshot();assert(s.byMap[399].weeklyRun.timed==nil and s.weeklyBest.timed==nil)
    history[1],history[2]=history[2],history[1] end''')

if __name__=='__main__':unittest.main()
