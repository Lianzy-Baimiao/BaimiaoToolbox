"""Rectangular switches exercise the real shared layout and option pages."""
import unittest
import test_workspace

class SwitchTests(unittest.TestCase):
 setUp=test_workspace.WorkspaceTests.setUp
 runlua=test_workspace.WorkspaceTests.runlua
 def fixture(self):
  self.runlua('''p=CreateFrame("Frame",nil,UIParent);p:SetWidth(600);L=ns.UI.NewLayout(p)
   state=false;writes=0;changes=0
   switch=L:Check("矩形开关",function()return state end,function(v)state=v;writes=writes+1 end,function()changes=changes+1 end)
   L:SyncAll()
   function clickSwitch()switch:SetChecked(not switch:GetChecked());switch:GetScript("OnClick")(switch)end''')
 def test_rectangular_track_thumb_and_no_default_check_art(self):
  self.fixture();self.runlua('''assert(switch.template=="BackdropTemplate")
   assert(switch:GetWidth()==26 and switch:GetHeight()==14 and switch.thumb:GetWidth()==8)
   assert(not switch:GetChecked() and switch.thumb.point[4]==3)
   assert(switch:GetHeight()-switch.hitInsets[3]-switch.hitInsets[4]>=18,"keep a comfortable hit target")
   assert(switch.label.fontSize==13 and switch.hitInsets[2]<0,"label should also be clickable")''')
 def test_click_sync_and_theme_keep_saved_state(self):
  self.fixture();self.runlua('''clickSwitch();assert(state and writes==1 and changes==1 and switch:GetChecked())
   assert(switch.thumb.point[4]==15)
   local light=BaimiaoToolboxWorkspace.theme;light:GetScript("OnClick")()
   assert(state and switch:GetChecked() and switch.thumb.point[4]==15)
   assert(switch.backdropColor[1]==ns.UI.palette.accent[1])
   state=false;L:SyncAll();assert(not switch:GetChecked() and switch.thumb.point[4]==3 and writes==1)
   assert(switch.backdropColor[1]==ns.UI.palette.rail[1])
   clickSwitch();clickSwitch();assert(not state and writes==3 and changes==3)''')
 def test_hover_disabled_and_combat_do_not_mutate_preferences(self):
  self.fixture();self.runlua('''switch:GetScript("OnEnter")(switch);assert(switch.backdropBorder[1]==ns.UI.palette.accent[1])
   switch:GetScript("OnLeave")(switch);assert(switch.backdropBorder[1]==ns.UI.palette.border[1])
   switch:SetEnabled(false);switch:GetScript("OnDisable")(switch);assert(switch.alpha<1)
   clickSwitch();assert(not state and writes==0 and not switch:GetChecked())
   switch:SetEnabled(true);switch:GetScript("OnEnable")(switch);assert(switch.alpha==1)
   combat=true;clickSwitch();assert(not state and writes==0 and not switch:GetChecked())
   combat=false;clickSwitch();assert(state and writes==1)''')
 def test_wrapped_label_click_area_stays_clear_of_next_switch(self):
  self.runlua('''local p=CreateFrame("Frame",nil,UIParent);p:SetWidth(600)
   local l=ns.UI.NewLayout(p)
   local first=l:Check(string.rep("长说明",50),function()return false end,function()end)
   local second=l:Check("下一项",function()return false end,function()end)
   l:SyncAll()
   assert(first.label:GetStringHeight()>24,"fixture should span multiple lines")
   local firstY=-first.point[3];local nextY=-second.point[3]
   local clickableBottom=firstY+first:GetHeight()-first.hitInsets[4]
   local textBottom=firstY+first.label:GetStringHeight()
   assert(clickableBottom>=textBottom and clickableBottom+8<=nextY)
   assert(first:GetWidth()-first.hitInsets[2]+first.point[2]<=p:GetWidth(),"click area exceeds panel")
   first:GetScript("OnEnter")(first);first:Hide();first:Show()
   assert(first.backdropBorder[1]==ns.UI.palette.border[1])
   assert(not first:GetChecked() and not second:GetChecked())''')
 def test_all_settings_checks_are_switches_with_wrapping_space(self):
  self.runlua('''local count=0
   for _,f in ipairs(frames)do if f:GetObjectType()=="CheckButton" then
    count=count+1;assert(f.template=="BackdropTemplate" and f.thumb and f.label)
    assert(f.label:GetWidth()>100 and f.label.fontSize>=12)
   end end
   assert(count>30,"all existing modules should use shared switch")
   assert(#messages==0,table.concat(messages,"; "))''')

if __name__=='__main__':unittest.main()
