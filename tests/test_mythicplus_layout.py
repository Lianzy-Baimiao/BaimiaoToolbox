"""Regression checks for footerless layout, portal availability and view selection."""
import unittest
import test_mythicplus as baseline

class MythicLayoutTests(unittest.TestCase):
 setUp=baseline.MythicTests.setUp
 runlua=baseline.MythicTests.runlua
 open=baseline.MythicTests.open

 def test_left_right_bottoms_align_and_no_removed_footer_gutter(self):
  self.open()
  self.runlua('''local last=c.tiles[8]
   local bottom=-last.point[5]+last:GetHeight()
   assert(bottom==-c.weekly.point[5]+c.weekly:GetHeight(),"left/right bottom borders misaligned")
   assert(c:GetHeight()-bottom<=10,"removed footer still reserves blank space")
   assert(c.footer==nil,"combat status must not allocate a page footer")''')

 def test_cooldown_does_not_offer_an_armed_click_target(self):
  self.open()
  self.runlua('''C_Spell.GetSpellCooldown=function()return {startTime=100,duration=300}end
   fire("SPELL_UPDATE_COOLDOWN");advance()
   local t=c.tiles[1];assert(not t.portal:IsShown(),"cooldown still has an active teleport button")
   assert(t.portal.attributes.type1==nil and t.portal.attributes.spell==nil)
   assert(t.state:GetText()=="冷却 5 分钟")''')

 def test_visible_border_is_inset_without_exposing_native_high_icons(self):
  self.open()
  self.runlua('''assert(h.backdrop.bgFile and not h.backdrop.edgeFile,"cover must not draw a border at native bottom")
   assert(c.backdrop.edgeFile,"inset canvas must own the visible border")
   assert(h.points.BOTTOMRIGHT[5]==0,"opaque native-icon cover must extend to bottom")
   assert(h:GetFrameStrata()=="HIGH")
   local borderBottom=-h.points.TOPLEFT[5]-c.point[5]+c:GetHeight()*c:GetScale()
   local margin=PVEFrame:GetHeight()-borderBottom
   assert(margin>=8 and margin<=12,"visible bottom border is not safely inset")
   assert(PVEFrame:GetHeight()<=462,"window did not shrink after removing footer")
   for _,percent in ipairs({70,100,130})do
    d.scalePercent=percent;ns.MythicPlus.Refresh()
    assert(c:GetScale()==1 and c:GetHeight()==422)
   end
   d.showWeekly=false;ns.MythicPlus.Refresh()
   local last=c.tiles[8];assert(c:GetHeight()-(-last.point[5]+last:GetHeight())==8)
   assert(not c.weekly:IsShown())
   PVEFrame_ShowFrame("PVPUIFrame");advance()
   assert(PVEFrame:GetWidth()==800 and PVEFrame:GetHeight()==428 and not h:IsShown())''')

 def test_status_slot_survives_unlearned_unknown_disabled_and_relearned(self):
  self.open()
  self.runlua('''local t=c.tiles[1];local b=t.portal;local s=t.portalStatus
   assert(not s:IsShown() and b:IsShown())
   assert(s:GetWidth()==b:GetWidth() and s:GetHeight()==b:GetHeight())
   for i=1,5 do assert(s.point[i]==b.point[i],"status/action geometry differs")end
   known[393256]=nil;fire("SPELLS_CHANGED");advance()
   assert(s:IsShown() and not b:IsShown() and t.state:GetText()=="未学会传送")
   assert(b.attributes.spell==nil and not b.driverRule)
   known[393256]=true;fire("SPELLS_CHANGED");advance();assert(b:IsShown() and not s:IsShown())
   C_Spell.GetSpellCooldown=nil;fire("SPELL_UPDATE_COOLDOWN");advance()
   assert(s:IsShown() and t.state:GetText()=="状态未知" and not b:IsShown())
   assert(b.attributes.type1==nil)
   d.teleport=false;ns.MythicPlus.Refresh()
   assert(s:IsShown() and t.state:GetText()=="传送已关闭" and not b:IsShown())
   mapIDs={99999};ns.MythicPlus.Refresh();d.teleport=true;ns.MythicPlus.Refresh()
   assert(c.tiles[1].state:GetText()=="未收录传送" and not c.tiles[1].portal:IsShown())
   for i=2,8 do assert(not c.tiles[i]:IsShown() and not c.tiles[i].portal:IsShown())end''')

 def test_cooldown_recovers_and_combat_uses_only_nonsecure_placeholder(self):
  self.open()
  self.runlua('''local t=c.tiles[1];local b=t.portal
   C_Spell.GetSpellCooldown=function()return {startTime=100,duration=300}end
   fire("SPELL_UPDATE_COOLDOWN");advance();assert(not b.driverRule)
   advance(300);fire("SPELL_UPDATE_COOLDOWN");advance()
   assert(b:IsShown() and b.attributes.spell==393256 and b.driverRule)
   b:GetScript("OnEnter")(b);assert(GameTooltip:IsShown())
   setCombat(true)
   assert(not GameTooltip:IsShown(),"stale click tooltip survives entering combat")
   assert(not b:IsShown() and t.portalStatus:IsShown() and t.state:GetText()=="战斗中不可传送")
   assert(not t.portalStatus.template:find("Secure"))
   setCombat(false);assert(b:IsShown() and not t.portalStatus:IsShown())
   setCombat(true);PVEFrame_ShowFrame("LFGListFrame");advance();setCombat(false)
   assert(not h:IsShown() and not b:IsShown() and not t.portalStatus:IsVisible())''')

 def test_unavailable_tooltip_never_advertises_a_click_or_roster(self):
  from test_mythicplus_details import MythicDetailTests
  MythicDetailTests.tooltip_stub(self)
  self.open()
  self.runlua('''local t=c.tiles[1];known[393256]=false;fire("SPELLS_CHANGED");advance()
   t.portalStatus:GetScript("OnEnter")(t.portalStatus)
   assert(GameTooltip.anchor=="ANCHOR_CURSOR" and #GameTooltip.lines==1)
   assert(tooltipText():find("未学会传送",1,true) and not tooltipText():find("点击",1,true))
   known[393256]=true
   t.portalStatus:GetScript("OnEnter")(t.portalStatus)
   assert(not tooltipText():find("点击",1,true),"status surface advertises secure action before refresh")
   fire("SPELLS_CHANGED");advance();assert(not GameTooltip:IsShown())
   t.portal:GetScript("OnEnter")(t.portal);assert(tooltipText():find("点击传送",1,true))
   C_Spell.GetSpellCooldown=nil;fire("SPELL_UPDATE_COOLDOWN");advance()
   assert(not GameTooltip:IsShown(),"stale click tooltip survives unavailable state")''')

 def test_segmented_selector_has_explicit_selection_and_stable_geometry(self):
  self.open()
  self.runlua('''local a,b=c.runTab,c.mapTab
   assert(a:GetParent()==c.selector and b:GetParent()==c.selector)
   assert(a.selected and a.indicator:IsShown() and not b.selected and not b.indicator:IsShown())
   assert(a.caption:GetText()=="本周记录  3" and b.caption:GetText()=="副本汇总  8")
   assert(a.bg[1]~=b.bg[1],"selected view lacks a distinct background")
   local before=#frames;local listTop=c.list.point[3];local listHeight=c.list:GetHeight()
   for i=1,8 do
    b:GetScript("OnClick")();assert(b.selected and b.indicator:IsShown() and not a.indicator:IsShown())
    assert(c.rows[1].summary and not c.rows[1].time:IsShown())
    a:GetScript("OnClick")();assert(a.selected and c.rows[1].time:IsShown())
   end
   assert(#frames==before and c.list.point[3]==listTop and c.list:GetHeight()==listHeight)
   b:GetScript("OnEnter")(b);assert(not b.selected and not b.indicator:IsShown())
   b:GetScript("OnLeave")(b)
   assert(-c.selector.point[3]+c.selector:GetHeight()<=-c.list.point[3])
   assert(-c.list.point[3]+c.list:GetHeight()<=-c.range.point[3])
   assert(-c.range.point[3]+10<=c.weekly:GetHeight()-4)
   assert(not c.range:GetText():find("滚轮",1,true),"no-scroll list shows a scroll instruction")''')

 def test_segment_switch_resets_scroll_and_keeps_theme_selection(self):
  self.open()
  self.runlua('''for i=1,30 do history[#history+1]={mapChallengeModeID=399,level=2,thisWeek=true,durationSec=1500}end
   ns.MythicPlus.Refresh();c.list:GetScript("OnMouseWheel")(c.list,-100)
   assert(c.range:GetText():find("33 / 33",1,true))
   c.mapTab:GetScript("OnClick")();assert(c.rows[1].item.id==399)
   c.runTab:GetScript("OnClick")();assert(c.rows[1].item.level==16)
   assert(c.range:GetText():find("1–10 / 33",1,true))
   ns.UI.BuildWorkspace();BaimiaoToolboxWorkspace.theme:GetScript("OnClick")();advance()
   assert(c.runTab.selected and not c.mapTab.selected)
   assert(c.runTab.bg[1]==ns.UI.palette.hover[1])
   assert(c.runTab.caption.color[1]==ns.UI.palette.accent[1])
   assert(c.tiles[1].portal.caption.color[1]==ns.UI.palette.accent[1])
   assert(c.tiles[1].state.color[1]==ns.UI.palette.muted[1])''')

if __name__=='__main__':unittest.main()
