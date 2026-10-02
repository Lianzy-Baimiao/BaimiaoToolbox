"""Compact settings use actual layout geometry, callbacks, and shared hit bounds."""
import unittest
from pathlib import Path
import test_workspace

class SettingsRowTests(unittest.TestCase):
 setUp=test_workspace.WorkspaceTests.setUp
 runlua=test_workspace.WorkspaceTests.runlua
 def helpers(self):
  self.runlua('''function checks(panel)
   local t={};for _,f in ipairs({panel:GetChildren()})do
    if f:GetObjectType()=="CheckButton"then t[f.label:GetText()]=f end
   end;return t end
   function sameRow(list)
    for i,f in ipairs(list)do
     assert(f.point[3]==list[1].point[3],"options should share a row")
     if i>1 then local previous=list[i-1]
      assert(previous.point[2]+previous:GetWidth()-previous.hitInsets[2]+12<=f.point[2],"adjacent label hit regions overlap")
     end
    end
   end''')
 def test_coordinate_switches_and_colors_share_rows(self):
  self.helpers()
  self.runlua('''local page=ns.modules.coordshout.optionTabs.pages[1];local c=checks(page.panel)
   sameRow({c["显示坐标"],c["显示移速"],c["显示目标距离"]})
   sameRow({c["锁定位置（Alt+左键可拖动）"],c["轮廓字体"]})
   local swatches={};for _,f in ipairs({page.panel:GetChildren()})do if f.sw then swatches[#swatches+1]=f end end
   assert(#swatches==3)
   for i=2,3 do assert(swatches[i].point[3]==swatches[1].point[3] and swatches[i].point[2]>swatches[i-1].point[2])end
   assert(page.panel:GetHeight()<300 and ns.modules.coordshout._syncLayout.panel:GetHeight()<470)''')
 def test_coordinate_sliders_share_row_and_keep_writeback(self):
  self.runlua('''local font=BaimiaoCoordShoutFontSlider:GetParent();local scale=BaimiaoCoordShoutScaleSlider:GetParent()
   assert(font.point[3]==scale.point[3])
   assert(font.point[2]+font:GetWidth()+12<=scale.point[2])
   assert(scale.point[2]+scale:GetWidth()<=scale:GetParent():GetWidth()-20)
   local d=ns.GetDB("coordshout").display
   BaimiaoCoordShoutFontSlider:SetValue(22);BaimiaoCoordShoutScaleSlider:SetValue(125)
   assert(d.fontSize==22 and d.scale==1.25)
   d.fontSize=18;d.scale=.8;ns.modules.coordshout._syncLayout:SyncAll()
   assert(BaimiaoCoordShoutFontSlider:GetValue()==18 and BaimiaoCoordShoutScaleSlider:GetValue()==80)''')
 def test_smalltools_options_share_logical_rows(self):
  self.helpers()
  self.runlua('''local page=ns.modules.smalltools._syncLayout;local c=checks(page.panel)
   sameRow({c["公会邀请"],c["多角色在线：选择角色邀请组队"]})
   sameRow({c["目标标记"],c["地面标记"],c["团队管理（就位 / 倒数）"]})
   sameRow({c["仅在小队 / 团队中显示"],c["仅队长显示"],c["锁定位置"]})
   assert(page.panel:GetHeight()<430)
   local reset;for _,f in ipairs({page.panel:GetChildren()})do if f:GetText()=="重置标记助手位置"then reset=f end end
   local slider=BaimiaoMarkerScale:GetParent()
   assert(reset and reset.point[3]==slider.point[3] and reset.point[2]>=slider.point[2]+slider:GetWidth()+12)''')
 def test_row_switches_keep_independent_writeback_and_combat_guard(self):
  self.helpers()
  self.runlua('''local c=checks(ns.modules.coordshout.optionTabs.pages[1].panel);local d=ns.GetDB("coordshout").display
   local s=c["显示移速"];local before=d.speed;local coord=d.coord
   s:SetChecked(not before);s:GetScript("OnClick")(s)
   assert(d.speed~=before and d.coord==coord)
   combat=true;s:SetChecked(before);s:GetScript("OnClick")(s);assert(d.speed~=before)
   combat=false;d.speed=before;ns.modules.coordshout._syncLayout:SyncAll();assert(s:GetChecked()==before)''')
 def test_narrow_rows_wrap_and_parent_cursor_uses_tallest_cell(self):
  self.runlua('''local p=CreateFrame("Frame",nil,UIParent);p:SetWidth(430);local l=ns.UI.NewLayout(p);local controls={}
   l:Row({function(cell)controls[1]=cell:Check(string.rep("长说明",30),function()return false end,function()end)end,
    function(cell)controls[2]=cell:Check("短选项",function()return false end,function()end)end,
    function(cell)controls[3]=cell:Check("第三项",function()return false end,function()end)end})
   local nextControl=l:Check("下一行",function()return false end,function()end);l:SyncAll()
   assert(controls[1].point[3]==controls[2].point[3] and controls[3].point[3]<controls[1].point[3])
   local bottom=-controls[1].point[3]+controls[1]:GetHeight()-controls[1].hitInsets[4]
   assert(bottom+8<=-controls[3].point[3])
   assert(nextControl.point[2]==16 and nextControl.point[3]<controls[3].point[3])
   assert(controls[2].point[2]+controls[2]:GetWidth()-controls[2].hitInsets[2]<=p:GetWidth()-20)''')
 def test_switching_tabs_does_not_rebuild_or_lose_row_values(self):
  self.runlua('''local m=ns.modules.coordshout;local count=#frames;local height=m._syncLayout.panel:GetHeight()
   ns.GetDB("coordshout").display.speed=false
   for i=1,8 do m.optionTabs.Select(2);m.optionTabs.Select(3);m.optionTabs.Select(1)end
   m._syncLayout:SyncAll()
   assert(#frames==count and m._syncLayout.panel:GetHeight()==height and not ns.GetDB("coordshout").display.speed)''')
 def test_coordinate_color_controls_keep_separate_callbacks(self):
  self.runlua('''local page=ns.modules.coordshout.optionTabs.pages[1];local colors={}
   for _,f in ipairs({page.panel:GetChildren()})do if f.sw then colors[#colors+1]=f end end
   local keys={"coordColor","speedColor","distColor"}
   for i,f in ipairs(colors)do
    ns.UI.OpenColorPicker=function(r,g,b,apply)apply(i/10,.4,.7)end
    f:GetScript("OnClick")()
   end
   local d=ns.GetDB("coordshout").display
   for i,key in ipairs(keys)do assert(d[key].r==i/10 and d[key].g==.4 and d[key].b==.7)end''')
 def test_single_column_fallback_keeps_sliders_inside_panel(self):
  self.runlua('''local p=CreateFrame("Frame",nil,UIParent);p:SetWidth(300);local l=ns.UI.NewLayout(p);local h={}
   l:Row({function(cell)h[1]=cell:Slider("CompactSliderA","A",1,10,1,function()return 4 end,function()end)end,
    function(cell)h[2]=cell:Slider("CompactSliderB","B",1,10,1,function()return 5 end,function()end)end},260)
   assert(h[1].point[2]==h[2].point[2] and h[2].point[3]<h[1].point[3])
   for _,f in ipairs(h)do assert(f.point[2]+f:GetWidth()<=p:GetWidth()-24)end''')
 def test_readme_stays_minimal_with_author_supplied_preview(self):
  text=(Path(__file__).resolve().parents[1]/'README.md').read_text(encoding='utf-8')
  self.assertLessEqual(len(text.splitlines()),35)
  # The author added a real preview after release; images are allowed now.
  for forbidden in ('CHANGELOG','更新日志','1.9.','⚠','📍','⏱'):
   self.assertNotIn(forbidden,text)
  for feature in ('坐标喊话','快捷按钮','光环 / 宠物提示','嗜血 / 战复监控','技能顺序','大秘境','小工具集合'):
   self.assertIn(feature,text)

if __name__=='__main__':unittest.main()
