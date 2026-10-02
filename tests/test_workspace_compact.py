"""Homepage density checks through actual Lua frames; not a WoW rendering test."""
import unittest
import test_workspace

class CompactWorkspaceTests(unittest.TestCase):
 setUp=test_workspace.WorkspaceTests.setUp
 runlua=test_workspace.WorkspaceTests.runlua

 def test_all_seven_modules_and_footer_fit_without_home_scroll(self):
  self.runlua('''ns.OpenOptions();local w=BaimiaoToolboxWorkspace
   local home=w.minimap:GetParent();local scroll=home:GetParent()
   local content=w.content
   local visibleHeight=w:GetHeight()+content.points.TOPLEFT[3]-content.points.BOTTOMRIGHT[3]-4
   local visibleWidth=w:GetWidth()-content.points.TOPLEFT[2]+content.points.BOTTOMRIGHT[2]-30
   assert(home:GetHeight()<=visibleHeight,"home exceeds viewport: "..home:GetHeight().." > "..visibleHeight)
   assert(#ns.orderedModules==7)
   for _,m in ipairs(ns.orderedModules)do
    local card=m._workspaceStatus:GetParent();local x,y=card.point[2],-card.point[3]
    assert(card:IsVisible() and x>=0 and y>=0,m.id)
    assert(x+card:GetWidth()<=visibleWidth and y+card:GetHeight()<=visibleHeight,m.id.." is clipped")
    assert(m._workspaceStatus.fontSize>=11 and m._workspaceToggle:GetHeight()>=26)
   end
   assert(-w.minimap.point[3]+w.minimap:GetHeight()<=visibleHeight,"footer clipped")
   -- The test double has no anchor solver: model only this viewport's range,
   -- then exercise the real scrollbar update/wheel callbacks.
   scroll.GetVerticalScrollRange=function()return math.max(0,home:GetHeight()-visibleHeight)end
   scroll:GetScript("OnShow")(scroll)
   local host=scroll:GetParent();local bar
   for _,f in ipairs({host:GetChildren()})do if f:GetObjectType()=="Slider" then bar=f end end
   assert(bar and not bar:IsShown(),"unneeded home scrollbar visible")
   scroll:GetScript("OnMouseWheel")(scroll,-20);assert(scroll:GetVerticalScroll()==0)
  ''')

 def test_only_card_descriptions_are_small_and_buttons_do_not_overlap_them(self):
  self.runlua('''for _,m in ipairs(ns.orderedModules)do
   local card=m._workspaceStatus:GetParent();local description,title
   for _,f in ipairs({card:GetRegions()})do if f:GetObjectType()=="FontString" then
    if f._bmTextRole=="muted" then description=f end
    if f:GetText()==m.name then title=f end
   end end
   assert(description and title and description.fontSize==11 and title.fontSize>=15,m.id)
   local descBottom=-description.point[3]+description:GetHeight()
   local toggle=m._workspaceToggle
   local buttonTop=card:GetHeight()-toggle.point[3]-toggle:GetHeight()
   assert(descBottom+4<=buttonTop,m.id.." description overlaps button")
   assert(description:GetWidth()<=card:GetWidth()-28)
  end''')

 def test_smaller_window_fits_720p_without_shrinking_text(self):
  self.runlua('''local w=BaimiaoToolboxWorkspace
   assert(w:GetWidth()<=1000 and w:GetHeight()<=660,"window footprint not compact")
   UIParent:SetSize(1280,720);ns.OpenOptions();assert(w:GetScale()==1,"720p should not need downscaling")
   UIParent:SetSize(800,600);w:GetScript("OnEvent")(w,"DISPLAY_SIZE_CHANGED")
   assert(w:GetWidth()*w:GetScale()<=768 and w:GetHeight()*w:GetScale()<=568)
   UIParent:SetSize(1920,1080);w:GetScript("OnEvent")(w,"UI_SCALE_CHANGED")
   assert(w:GetScale()==1)
  ''')

 def test_home_restores_title_banner_and_actions_remain_usable(self):
  self.runlua('''ns.OpenOptions();local w=BaimiaoToolboxWorkspace
   assert(w.heading:GetText()=="旅程，从容开始。")
   local home=w.minimap:GetParent()
   assert(w.eyebrow:GetText()=="YOUR ADVENTURE, ORGANIZED")
   assert(w.hero:IsVisible() and w.heroTitle:GetText()=="少一点繁琐，多一点冒险。")
   assert(w.heroSubtitle:GetText()=="轻量工具，自由组合。一个属于你的游戏工作台。")
   local first=ns.orderedModules[1]._workspaceStatus:GetParent()
   assert(-first.point[3]>=w.hero:GetHeight()+32,"cards overlap restored header")
   for _,m in ipairs(ns.orderedModules)do
    local card=m._workspaceStatus:GetParent();local configure
    for _,f in ipairs({card:GetChildren()})do if f:GetText()=="打开设置" then configure=f end end
    assert(configure and configure:GetHeight()>=26)
    configure:GetScript("OnClick")();assert(w.heading:GetText()==m.name)
    ns.OpenOptions();assert(card:IsVisible())
   end
   local m=ns.orderedModules[1];m._workspaceToggle:GetScript("OnClick")()
   assert(not ns.IsModuleEnabled(m.id) and m._workspaceStatus:GetText()=="已停用")
   m._workspaceToggle:GetScript("OnClick")();assert(ns.IsModuleEnabled(m.id))
   local old=ns.IsMinimapButtonShown();w.minimap:GetScript("OnClick")()
   assert(ns.IsMinimapButtonShown()~=old)
   w.theme:GetScript("OnClick")();assert(ns.UI.palette.bg[1]>0.9)
   w.theme:GetScript("OnClick")();assert(ns.UI.palette.bg[1]<0.1)
   assert(#messages==0,table.concat(messages,"; "))
  ''')

if __name__=='__main__':unittest.main()
