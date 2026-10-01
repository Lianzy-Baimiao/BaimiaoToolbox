"""Quick button runtime interactions under a Lua 5.1 WoW API mock."""
import unittest
import test_workspace

class QuickMountTests(unittest.TestCase):
 runlua=test_workspace.WorkspaceTests.runlua
 def setUp(self):
  test_workspace.WorkspaceTests.setUp(self)
  self.runlua('''d=ns.GetDB("quickmount");d.extra.text="小退";d.extra.enabled=true;d.extra.collapsed=false
  ns.modules.quickmount.OnEnable()
  main=BaimiaoQuickMountButton;tab=BaimiaoQuickMountCollapse;extra=BaimiaoQuickMountExtra1
  assert(not tab:IsShown());main:GetScript("OnEnter")(main)
  function click() tab:GetScript("OnClick")(tab) end
  function regen() combat=false;main:GetScript("OnEvent")(main,"PLAYER_REGEN_ENABLED") end
  ''')
 def test_click_and_middle_click(self):
  self.runlua('''assert(tab:GetWidth()>=80 and tab:GetHeight()>=26)
  assert(extra:IsShown() and tab:GetText()=="收起 1")
  click();assert(not extra:IsShown() and tab:GetText()=="展开 1")
  C_MountJournal.SummonByID=function() error("middle click summoned mount") end
  main:GetScript("OnClick")(main,"MiddleButton");assert(extra:IsShown())
  assert(main.clicks[3]=="MiddleButtonUp")
  ''')
 def test_combat_request_cancel_and_apply(self):
  self.runlua('''combat=true;click();assert(extra:IsShown() and tab:GetText()=="待收起")
  click();assert(extra:IsShown() and tab:GetText()=="收起 1")
  click();tab:GetScript("OnEnter")(tab);regen()
  assert(not extra:IsShown() and tab:GetText()=="展开 1")
  assert(GameTooltip:GetText()=="展开扩展按钮")
  combat=true;click();assert(not extra:IsShown() and tab:GetText()=="待展开")
  regen();assert(extra:IsShown() and tab:GetText()=="收起 1")
  ''')
 def test_position_and_visibility(self):
  self.runlua('''for _,grow in ipairs({"LEFT","RIGHT","UP","DOWN"}) do
   d.extra.grow=grow;main:GetScript("OnEvent")(main,"SPELLS_CHANGED")
   assert(tab.point[2]==main)
   assert(tab.point[3]==((grow=="LEFT" or grow=="RIGHT") and "TOP" or "RIGHT"))
  end
  BaimiaoToolboxWorkspace.theme:GetScript("OnClick")()
  assert(tab:IsShown() and tab:GetText()=="收起 1")
  d.extra.text="";main:GetScript("OnEvent")(main,"SPELLS_CHANGED");assert(not tab:IsShown())
  d.extra.text="小退";d.extra.enabled=false;main:GetScript("OnEvent")(main,"SPELLS_CHANGED");assert(not tab:IsShown())
  ''')

 def test_hover_delay_and_reentry(self):
  self.runlua('''assert(tab:IsShown())
  main:GetScript("OnLeave")(main);tab:GetScript("OnUpdate")(tab,0.2);assert(tab:IsShown())
  tab:GetScript("OnEnter")(tab);tab:GetScript("OnUpdate")(tab,1);assert(tab:IsShown())
  tab:GetScript("OnLeave")(tab);tab:GetScript("OnUpdate")(tab,0.5);assert(not tab:IsShown())
  assert(extra:IsShown())
  main:GetScript("OnEvent")(main,"SPELLS_CHANGED");assert(not tab:IsShown())
  main:GetScript("OnEnter")(main);assert(tab:IsShown())
  main:GetScript("OnLeave")(main);main:GetScript("OnEnter")(main)
  tab:GetScript("OnUpdate")(tab,1);assert(tab:IsShown())
  combat=true;click();tab:GetScript("OnLeave")(tab);tab:GetScript("OnUpdate")(tab,0.5)
  assert(not tab:IsShown() and extra:IsShown());regen();assert(not tab:IsShown() and not extra:IsShown())
  main:GetScript("OnEnter")(main);assert(tab:IsShown() and tab:GetText()=="展开 1")
  main:Hide();assert(not tab:IsShown());main:Show();assert(not tab:IsShown())
  ''')
