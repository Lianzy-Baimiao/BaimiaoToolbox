"""Live feedback: cursor tooltip, labelled best roster, inline timing, compact layout."""
import unittest
import test_mythicplus as baseline

class MythicDetailTests(unittest.TestCase):
 setUp=baseline.MythicTests.setUp
 runlua=baseline.MythicTests.runlua
 open=baseline.MythicTests.open

 def tooltip_stub(self):
  self.runlua('''local methods=getmetatable(GameTooltip).__index
   function methods:SetOwner(owner,anchor)self.owner=owner;self.anchor=anchor;self.lines={};self.columns={}end
   function methods:AddLine(line)self.lines[#self.lines+1]=line end
   function methods:AddDoubleLine(left,right)self.lines[#self.lines+1]=left.."  ·  "..right;self.columns[#self.columns+1]={left,right}end
   function tooltipText()return table.concat(GameTooltip.lines," ; ")end''')

 def detail_fixture(self):
  self.tooltip_stub()
  self.runlua('''history[1].completionDate={year=2026,month=10,monthDay=2,hour=14,minute=25}
   history[1].runScore=428
   roster={{name="队友甲-测试服",classID=1,specID=73},{name="队友乙",classID=2,specID=65}}
   C_MythicPlus.GetWeeklyBestForMap=function(id)
    if id==399 then return 1799,16,history[1].completionDate,{1,2},roster,428 end end
   function GetSpecializationInfoByID(id) return id,id==73 and "防护" or "神圣" end''')

 def test_tooltips_use_cursor_anchor_for_cards_buttons_and_rows(self):
  self.tooltip_stub(); self.open()
  self.runlua('''for _,f in ipairs({c.tiles[1],c.tiles[1].portal,c.rows[1],c.vaults[1]})do
    f:GetScript("OnEnter")(f);assert(GameTooltip.anchor=="ANCHOR_CURSOR","tooltip anchored to frame, not cursor")
    f:GetScript("OnLeave")(f);assert(not GameTooltip:IsShown())end''')

 def test_history_row_shows_elapsed_and_limit_before_status(self):
  self.open()
  self.runlua('''assert(c.rows[1].time,"missing elapsed/limit column")
   assert(c.rows[1].time:GetText()=="(29:59/30)")
   assert(c.rows[2].time:GetText()=="(31:40/30)" and c.rows[2].right:GetText()=="超时")
   assert(c.rows[1].right:GetText()=="限时")
   assert(c.rows[1].time.point[2]<c.rows[1].right.point[2])''')

 def test_run_tooltip_has_compact_score_and_labelled_best_teammates(self):
  self.detail_fixture();self.open()
  self.runlua('''local f=c.rows[1];f:GetScript("OnEnter")(f);local t=tooltipText()
   assert(not t:find("2026-10-02",1,true),"completion date clutters compact tooltip")
   assert(t:find("428",1,true),"missing run score")
   assert(t:find("队友甲-测试服",1,true) and t:find("防护",1,true),"missing actual teammates/specs")
   assert(t:find("29:59",1,true) and t:find("/30)",1,true))
   assert(history[1].members==nil and roster[1].name=="队友甲-测试服")''')

 def test_any_history_row_shows_best_roster_as_a_separate_section(self):
  self.detail_fixture();self.open()
  self.runlua('''local f=c.rows[2];f:GetScript("OnEnter")(f);local t=tooltipText()
   assert(t:find("队友甲",1,true),"best roster should be available on any run")
   assert(t:find("本周最佳队伍",1,true),"must label roster as best, not the hovered run")
   assert(t:find("31:40",1,true) and t:find("29:59",1,true),"show both hovered and best times")''')

 def test_compact_window_and_all_eight_cards_stay_inside_canvas(self):
  self.open()
  self.runlua('''assert(PVEFrame:GetWidth()<=840 and PVEFrame:GetHeight()<=494,"window is not compact")
   assert(#c.tiles==8 and c.rows[1]:IsShown())
   for _,tile in ipairs(c.tiles)do
    assert(tile:IsShown());assert(tile:GetHeight()<=68,"cards too tall")
    local x,y=tile.point[4],-tile.point[5]
    assert(x+tile:GetWidth()<=c:GetWidth() and y+tile:GetHeight()<c:GetHeight())
   end
   assert(c.rows[1].left:GetWidth()>=140 and c.rows[1].time:GetWidth()>=80)''')


 def test_cards_use_season_best_score_while_weekly_rows_use_weekly_team(self):
  self.detail_fixture()
  self.runlua('''C_MythicPlus.GetSeasonBestForMap=function(id)
    if id==399 then return
     {level=15,durationSec=1700,dungeonScore=410,members={{name="赛季限时队友"}}},
     {level=18,durationSec=1900,dungeonScore=450,members={{name="赛季高分队友"},{name="赛季高分队友乙"}}} end end''')
  self.open()
  self.runlua('''for _,f in ipairs({c.tiles[1]})do
    f:GetScript("OnEnter")(f);local t=tooltipText()
    assert(t:find("赛季超时最佳队伍",1,true) and t:find("赛季高分队友",1,true))
    assert(not t:find("队友甲",1,true) and not t:find("赛季限时队友",1,true))
   end
   c.rows[2]:GetScript("OnEnter")(c.rows[2]);local t=tooltipText()
   assert(t:find("本周最佳队伍",1,true) and t:find("队友甲",1,true))
   assert(not t:find("赛季高分队友",1,true))''')

 def test_timing_example_unknown_values_and_nonminute_limits(self):
  self.runlua('''history[1].durationSec=1524
   C_ChallengeMode.GetMapUIInfo=function(id)return "测试副本",id,1920,123 end''')
  self.open()
  self.runlua('''assert(c.rows[1].time:GetText()=="(25:24/32)")
   history[1].durationSec=nil;ns.MythicPlus.Refresh()
   assert(c.rows[1].time:GetText()=="(—/32)" and c.rows[1].right:GetText()=="未知")
   C_ChallengeMode.GetMapUIInfo=function(id)return "测试副本",id,1950,123 end
   history[1].durationSec=3601;ns.MythicPlus.Refresh()
   assert(c.rows[1].time:GetText()=="(60:01/32:30)")
   c.mapTab:GetScript("OnClick")();assert(not c.rows[1].time:IsShown())
   c.runTab:GetScript("OnClick")();assert(c.rows[1].time:IsShown())''')

 def test_missing_best_roster_is_clear_and_private_fields_are_ignored(self):
  self.tooltip_stub();self.open()
  self.runlua('''local f=c.rows[1];f:GetScript("OnEnter")(f)
   assert(tooltipText():find("暂无最佳队伍信息",1,true))
   c.tiles[1]:GetScript("OnEnter")(c.tiles[1]);assert(tooltipText():find("暂无最佳队伍信息",1,true))
   local secret={};issecretvalue=function(v)return v==secret end
   C_MythicPlus.GetSeasonBestForMap=function()return {level=15,durationSec=1800,dungeonScore=secret,
    completionDate=secret,members={{name=secret,specID=secret,classID=secret}}}end
   f:GetScript("OnEnter")(f);local t=tooltipText()
   assert(t:find("姓名未提供",1,true) and not t:find("完成时间",1,true))
   assert(not t:find("—分",1,true),"unknown score should be a plain dash")''')

 def test_scrolling_dismisses_stale_row_tooltip(self):
  self.tooltip_stub();self.open()
  self.runlua('''local f=c.rows[1];f:GetScript("OnEnter")(f);assert(GameTooltip:IsShown())
   c.list:GetScript("OnMouseWheel")(c.list,-1);assert(not GameTooltip:IsShown())''')

 def class_fixture(self):
  self.detail_fixture()
  self.runlua('''function GetClassInfo(id)
    if id==1 then return "战士","WARRIOR" elseif id==2 then return "圣骑士","PALADIN" end end
   RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43},PALADIN={r=.96,g=.55,b=.73}}
   C_ClassColor={GetClassColor=function(file)return RAID_CLASS_COLORS[file] end}''')

 def test_best_roster_names_use_class_colors_without_color_bleed(self):
  self.class_fixture();self.open()
  self.runlua('''for _,f in ipairs({c.tiles[1],c.rows[1]})do
    f:GetScript("OnEnter")(f);local t=tooltipText()
    assert(t:find("|cffc79c6e队友甲-测试服|r  ·  防护 战士",1,true),"warrior name needs class color and reset")
    assert(t:find("|cfff58cba队友乙|r  ·  神圣 圣骑士",1,true),"paladin name needs a different class color")
   end
   C_ClassColor.GetClassColor=function()return {r=0,g=1,b=1}end
   c.rows[1]:GetScript("OnEnter")(c.rows[1])
   assert(tooltipText():find("|cff00ffff队友甲-测试服|r",1,true),"prefer game class-color API")
   assert(roster[1].name=="队友甲-测试服","must not recolor the API-owned roster")''')

 def test_class_color_fallback_and_unknown_or_restricted_color(self):
  self.class_fixture();self.open()
  self.runlua('''local f=c.rows[1]
   C_ClassColor=nil;f:GetScript("OnEnter")(f)
   assert(tooltipText():find("|cffc79c6e队友甲-测试服|r",1,true),"fallback to RAID_CLASS_COLORS")
   local secret={};issecretvalue=function(v)return v==secret end
   C_ClassColor={GetClassColor=function()return {r=secret,g=1,b=1}end}
   RAID_CLASS_COLORS=nil;f:GetScript("OnEnter")(f)
   assert(tooltipText():find("队友甲-测试服  ·  防护 战士",1,true),"restricted color should stay neutral")
   roster[1].classID=999;f:GetScript("OnEnter")(f)
   assert(tooltipText():find("队友甲-测试服",1,true),"unknown class must retain name")''')

 def test_header_buttons_are_grouped_without_overlapping_title_or_key(self):
  self.open()
  self.runlua('''for _,weekly in ipairs({true,false})do
    d.showWeekly=weekly;ns.MythicPlus.Refresh()
    local a,b=c.settings,c.refresh
    assert(a.point[5]==b.point[5],"header actions should share a row")
    local gap=b.point[4]-(a.point[4]+a:GetWidth())
    assert(gap>=4 and gap<=8,"header actions are too far apart")
    assert(c.title.point[2]+c.title:GetWidth()<=a.point[4],"buttons overlap title")
    assert(-a.point[5]+a:GetHeight()<=-c.key.point[3],"buttons overlap keystone")
    assert(b.point[4]+b:GetWidth()<= (weekly and 468 or 808))
   end''')

 def test_teleport_hint_is_exclusive_to_the_actual_button(self):
  self.detail_fixture();self.open()
  self.runlua('''local tile=c.tiles[1];local b=tile.portal
   b:GetScript("OnEnter")(b);assert(tooltipText():find("点击传送",1,true))
   b:GetScript("OnLeave")(b);tile:GetScript("OnEnter")(tile)
   assert(not tooltipText():find("传送",1,true),"non-clickable card advertises teleport")
   assert(tooltipText():find("队友甲",1,true),"card must retain best roster")
   assert(GameTooltip.owner==tile and GameTooltip.anchor=="ANCHOR_CURSOR")
   d.teleport=false;ns.MythicPlus.Refresh();tile:GetScript("OnEnter")(tile)
   assert(not tooltipText():find("传送",1,true),"disabled teleport hint leaks onto card")
   d.teleport=true;ns.MythicPlus.Refresh();b:GetScript("OnEnter")(b)
   assert(tooltipText():find("点击传送",1,true) and b.attributes.type1=="spell")''')

 def test_compatibility_options_only_build_functional_controls(self):
  self.runlua('''local entries
   local original=ns.UI.OptionTabs
   ns.UI.OptionTabs=function(_,_,tabs)entries=tabs;return {}end
   local introText=0
   m.BuildOptions({},m,{Title=function()end,Text=function()introText=introText+1 end})
   assert(introText==0,"shared intro still adds explanatory text above compatibility page")
   ns.UI.OptionTabs=original
   local controls={}
   local L=setmetatable({}, {__index=function(_,kind)return function(_,...)controls[#controls+1]={kind=kind,args={...}}end end})
   entries[3].build({},L)
   assert(#controls==2,"compatibility page still contains explanatory text/labels")
   assert(controls[1].kind=="Check" and controls[2].kind=="Button")
   local check=controls[1].args
   assert(check[2]()==true);check[3](false);check[4]();assert(d.replaceKogo==false)
   check[3](true);check[4]();assert(d.replaceKogo==true)
   local requested=0;C_MythicPlus.RequestMapInfo=function()requested=requested+1 end
   advance(4);controls[2].args[3]();advance();assert(requested==1,"refresh action broken")''')

 def test_tooltip_keeps_only_compact_best_roster_and_run_summary(self):
  self.class_fixture()
  self.runlua('''for i=3,5 do roster[i]={name="队友"..i,classID=1,specID=73}end''')
  self.open()
  self.runlua('''local tile=c.tiles[1];tile:GetScript("OnEnter")(tile)
   assert(#GameTooltip.lines<=7,"card tooltip repeats too much information")
   assert(#GameTooltip.columns==6,"best header and five members should use aligned columns")
   local text=tooltipText()
   assert(text:find("本周最佳队伍",1,true) and text:find("队友5",1,true))
   for _,word in ipairs({"完成时间","2026-10-02","词缀","队伍成员"})do
    assert(not text:find(word,1,true),"redundant tooltip field: "..word)end
   c.rows[2]:GetScript("OnEnter")(c.rows[2])
   assert(#GameTooltip.lines<=9,"run tooltip is too long")
   assert(tooltipText():find("31:40",1,true) and tooltipText():find("29:59",1,true))
   assert(tooltipText():find("本周最佳队伍",1,true),"best roster needs an explicit source")''')

 def test_portal_and_vault_tooltips_stay_action_focused(self):
  self.detail_fixture();self.open()
  self.runlua('''local b=c.tiles[1].portal;b:GetScript("OnEnter")(b)
   assert(#GameTooltip.lines==1 and tooltipText():find("点击传送",1,true))
   assert(not tooltipText():find("队友",1,true),"portal should not repeat dungeon details")
   c.vaults[1]:GetScript("OnEnter")(c.vaults[1])
   assert(#GameTooltip.lines<=2 and #tooltipText()<150,"vault tooltip too verbose")''')

 def test_mythic_page_and_options_have_no_explanatory_paragraphs(self):
  self.open()
  self.runlua('''assert(c.footer==nil,"removed page footer still allocates space")
   local entries;local original=ns.UI.OptionTabs
   ns.UI.OptionTabs=function(_,_,tabs)entries=tabs;return {}end
   local prose=0
   local L=setmetatable({Text=function()prose=prose+1 end}, {__index=function()return function()end end})
   m.BuildOptions({},m,L);ns.UI.OptionTabs=original
   for _,entry in ipairs(entries)do entry.build({},L)end
   assert(prose==0,"settings still contain long descriptions under the keystone entry")
   setCombat(true);assert(c.tiles[1].state:GetText()=="战斗中不可传送")
   setCombat(false);advance();assert(not c.tiles[1].portalStatus:IsShown())''')

if __name__=='__main__':unittest.main()
