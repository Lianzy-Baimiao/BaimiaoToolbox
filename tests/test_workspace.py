"""Offline Lua 5.1 construction/interaction checks; not a WoW rendering test.
Development dependency only: pip install lupa. No dependency in game.
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]
class WorkspaceTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute((ROOT/'tests/wow_ui_stub.lua').read_text(encoding='utf-8'))
  self.lua.execute(getattr(self,'initial_lua',''))
  for path in ['Core.lua','Workspace.lua','Modules/CoordShout.lua','Modules/Reminder.lua','Modules/QuickMount.lua','Modules/RaidCooldowns.lua','Modules/RotationGuide.lua']:
   self.lua.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/path).read_text(encoding='utf-8'))
  self.lua.execute('for _,m in ipairs(ns.orderedModules) do m.db=ns.GetDB(m.id,m.defaults) end; ns.UI.BuildWorkspace()')
 def runlua(self, code):self.lua.execute(code)
 def test_all_real_option_pages_construct(self):
  self.runlua('assert(#ns.orderedModules==5); assert(#messages==0,table.concat(messages,"; ")); for _,m in ipairs(ns.orderedModules) do assert(m._syncLayout); assert(m._syncLayout.panel:GetHeight()>0) end')
 def test_navigation_and_theme(self):
  self.runlua('''ns.OpenOptions("quickmount"); local w=BaimiaoToolboxWorkspace
  assert(w:IsShown());assert(w.heading:GetText()=="快捷按钮")
  w.theme:GetScript("OnClick")(w.theme);assert(BaimiaoToolboxDBPC.workspace.theme=="light")
  assert(ns.UI.palette.bg[1]>0.9)
  ns.OpenOptions();assert(w.heading:GetText()=="旅程，从容开始。")
  w.theme:GetScript("OnClick")(w.theme);assert(ns.UI.palette.bg[1]<0.1)
  assert(#messages==0,table.concat(messages,"; "))''')
 def test_combat_guard(self):
  self.runlua('''ns.OpenOptions();local w=BaimiaoToolboxWorkspace
  combat=true;w:GetScript("OnEvent")(w,"PLAYER_REGEN_DISABLED");assert(w.guard:IsShown())
  w:Hide();ns.OpenOptions("quickmount");assert(not w:IsShown())
  combat=false;w:GetScript("OnEvent")(w,"PLAYER_REGEN_ENABLED");ns.OpenOptions("quickmount");assert(w:IsShown());assert(not w.guard:IsShown())''')
 def test_build_once_and_fit(self):
  self.runlua('''local count=#frames;ns.UI.BuildWorkspace();assert(#frames==count)
  UIParent:SetSize(1280,720);ns.OpenOptions();assert(BaimiaoToolboxWorkspace:GetScale()<1)
  assert(UISpecialFrames[1]=="BaimiaoToolboxWorkspace")''')
 def test_scroll_clamps_to_content(self):
  self.runlua('''local host=CreateFrame("Frame",nil,UIParent)
  local child,scroll=ns.UI.MakeScrollable(host)
  local wheel=scroll:GetScript("OnMouseWheel")
  wheel(scroll,-20);assert(scroll:GetVerticalScroll()==100)
  wheel(scroll,20);assert(scroll:GetVerticalScroll()==0)
  scroll:GetScript("OnSizeChanged")(scroll,738);assert(child:GetWidth()==738)''')
 def test_existing_preferences_survive(self):
  self.runlua('''local d=ns.GetDB("quickmount");d.testSentinel="preserve"
  local pc=ns.GetPCDB();pc.layout=pc.layout or {};pc.layout.testSentinel="preserve"
  ns.OpenOptions("reminder");ns.OpenOptions("raidcd")
  BaimiaoToolboxWorkspace.theme:GetScript("OnClick")()
  assert(d.testSentinel=="preserve");assert(pc.layout.testSentinel=="preserve")
  for _,m in ipairs(ns.orderedModules) do assert(ns.IsModuleEnabled(m.id)) end''')
 def test_original_module_tabs_are_bounded_and_independent(self):
  self.runlua('''for id,count in pairs({coordshout=3,quickmount=4,reminder=3,raidcd=3}) do
   local m=ns.modules[id];local t=m.optionTabs;assert(#t.pages==count,id)
   for i,page in ipairs(t.pages) do
    t.Select(i);assert(page.panel:IsShown());assert(t.buttons[i].tabIndicator:IsShown())
    for j,p in ipairs(t.pages) do if j~=i then assert(not p.panel:IsShown()) end end
    assert(page.panel:GetHeight()<800,id)
   end
  end
  BaimiaoToolboxWorkspace.theme:GetScript("OnClick")()
  assert(#messages==0,table.concat(messages,"; "))''')
 def test_mount_subtabs_keep_bindings_separate(self):
  self.runlua('''local m=ns.modules.quickmount;local tabs=m.mountTabs;assert(#tabs.pages==5)
  local d=ns.GetDB("quickmount");d.mounts.fly=111;d.mounts.repair=222
  tabs.Select(2);assert(tabs.pages[2].panel:IsShown())
  local clear
  for _,f in ipairs({tabs.pages[2].panel:GetChildren()}) do if f:GetText()=="清除" then clear=f end end
  assert(clear);clear:GetScript("OnClick")()
  assert(d.mounts.fly==111 and d.mounts.repair==nil)
  tabs.Select(1);assert(d.mounts.fly==111)''')
 def test_percentage_controls_keep_legacy_scale_storage(self):
  self.runlua('''local c=ns.GetDB("coordshout");local q=ns.GetDB("quickmount")
  c.display.scale=1.25;q.button.scale=0.75
  ns.modules.coordshout._syncLayout:SyncAll();ns.modules.quickmount._syncLayout:SyncAll()
  assert(BaimiaoCoordShoutScaleSlider:GetValue()==125)
  assert(BaimiaoQuickMountScaleSlider:GetValue()==75)
  BaimiaoCoordShoutScaleSlider:SetValue(150);BaimiaoQuickMountScaleSlider:SetValue(125)
  assert(c.display.scale==1.5 and q.button.scale==1.25)''')
if __name__=='__main__':unittest.main()
