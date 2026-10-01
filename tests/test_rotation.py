"""Offline rotation UI and cooldown contract checks, not in-game verification."""
import unittest
from test_workspace import WorkspaceTests
class RotationTests(WorkspaceTests):
 initial_lua='GetSpecializationInfo=function() return 70 end; UnitClass=function() return "圣骑士","PALADIN",2 end'

 def setUp(self):
  super().setUp()
  self.runlua("C_Spell.GetSpellInfo=function(id) return {iconID=123,name=tostring(id)} end; r=ns.RotationGuide; d=r.GetDB(); rows=r.Profile(70).rows")
 def test_presets_and_parser(self):
  self.runlua('''assert(#r.Parse(rows[1].sequence)==8)
  local n=r.Parse(rows[2].sequence);assert(#n==8);assert(n[6].count=="1-2");assert(n[4].join=="+")
  assert(#r.Parse(rows[3].sequence)==8)
  assert(#r.Parse("审判 → 公正之剑 ＋ 53385*1-2")==3)
  for _,s in ipairs({"0","-1","1 >", "1 ++ 2","1*0","1*3-2","1*10","|T123|t",string.rep("1 > ",25).."1"}) do
   local nodes,err=r.Parse(s);assert(nodes==nil and err,s)
  end''')
 def test_visibility_combat_scope_and_invalid(self):
  self.runlua('''r.Refresh();assert(not BaimiaoRotationGuide1)
  rows[1].enabled=true;rows[2].enabled=true;r.Refresh()
  assert(BaimiaoRotationGuide1:IsShown() and BaimiaoRotationGuide2:IsShown())
  combat=true;r.Refresh();assert(BaimiaoRotationGuide1:IsShown())
  GetSpecializationInfo=function() return 71 end;r.Refresh();assert(not BaimiaoRotationGuide1:IsShown())
  GetSpecializationInfo=function() return 70 end;r.Refresh();assert(BaimiaoRotationGuide1:IsShown())
  rows[1].sequence="1 >";r.Refresh();assert(not BaimiaoRotationGuide1:IsShown())
  ns.SetModuleEnabled("rotation",false);assert(not BaimiaoRotationGuide2:IsShown())''')
 def test_cooldown_and_charges(self):
  self.runlua('''rows[1].enabled=true
  C_Spell.GetSpellCooldown=function() return {startTime=10,duration=30} end
  r.Refresh();local c=BaimiaoRotationGuide1.cells[1]
  assert(c.cooldown.cooldownValue[2]==30)
  C_Spell.GetSpellCooldownDuration=function() return "nativeDuration" end
  r.UpdateCooldowns();assert(c.cooldown.durationObject=="nativeDuration")
  C_Spell.GetSpellCharges=function() return {currentCharges=1,maxCharges=2} end
  C_Spell.GetSpellChargeDuration=function() return "recharge" end
  r.UpdateCooldowns();assert(c.cooldown.durationObject=="recharge");assert(tostring(c.charges:GetText())=="1")
  d.showCooldowns=false;r.UpdateCooldowns();assert(c.cooldown.durationObject==nil);assert(c.charges:GetText()=="")''')
 def test_unknown_spell_is_safe(self):
  self.runlua('''C_Spell.GetSpellInfo=function() error("unavailable") end
  rows[1].enabled=true;r.Refresh();assert(BaimiaoRotationGuide1:IsShown())
  assert(BaimiaoRotationGuide1.cells[1].spell==nil)
  assert(r.Status(1):find("未识别"))''')
 def test_tab_pages_and_saved_settings(self):
  self.runlua('''local m=ns.modules.rotation;local tabs=m.rotationTabs;local rows=m.rotationRowTabs
  assert(#tabs.pages==3 and #rows.pages==6);assert(tabs.pages[3].panel:GetHeight()>200)
  assert(tabs.pages[1].panel:IsShown() and not tabs.pages[2].panel:IsShown())
  local generalHeight=m._syncLayout.panel:GetHeight()
  tabs.Select(2);rows.Select(6)
  assert(tabs.pages[2].panel:IsShown() and not tabs.pages[1].panel:IsShown())
  assert(rows.pages[6].panel:IsShown() and not rows.pages[1].panel:IsShown())
  assert(m._syncLayout.panel:GetHeight()<1100)
  r.Profile(70).rows[6].name="My saved rotation";r.Profile(70).rows[6].sequence="123 > 456"
  tabs.Select(3);tabs.Select(2);rows.Select(1);rows.Select(6)
  assert(r.Profile(70).rows[6].sequence=="123 > 456")
  assert(#messages==0,table.concat(messages,"; "))''')
 def test_close_only_unlocked_row_and_reenable(self):
  self.runlua('''rows[1].enabled=true;rows[2].enabled=true;r.Refresh()
  local f=BaimiaoRotationGuide1
  assert(not f.close:IsShown());f.close:GetScript("OnClick")();assert(rows[1].enabled)
  f.layoutDB.locked=false;r.Refresh();assert(f.close:IsShown())
  local sequence=rows[1].sequence;f.close:GetScript("OnClick")()
  assert(not rows[1].enabled and not f:IsShown())
  assert(BaimiaoRotationGuide2:IsShown() and rows[1].sequence==sequence)
  rows[1].enabled=true;r.Refresh();assert(f:IsShown())''')
 def test_icon_tooltip_and_lock_mouse_passthrough(self):
  self.runlua('''rows[1].enabled=true;r.Refresh()
  local f=BaimiaoRotationGuide1;local hit=f.cells[1].hit
  assert(not hit.mouseEnabled)
  f.layoutDB.locked=false;r.Refresh();assert(hit.mouseEnabled)
  hit:GetScript("OnEnter")(hit)
  assert(GameTooltip:IsOwned(hit));assert(GameTooltip.spellID==20271)
  hit:GetScript("OnDragStart")();assert(f._moving)
  f.layoutDB.locked=true;r.Refresh();assert(not hit.mouseEnabled);assert(not f.close:IsShown())
  assert(not GameTooltip:IsShown())''')
 def test_specialization_editor_does_not_switch_live_rows(self):
  self.runlua('''rows[1].enabled=true;r.Refresh()
  local m=ns.modules.rotation
  m.rotationClassSelect:GetScript("OnClick")()
  assert(m.rotationClassSelect:GetText():find("战士"));assert(m.rotationSpecSelect:GetText():find("武器"))
  assert(r.EditorRows()==r.Profile(71).rows)
  local other=r.EditorRows()[1];assert(other.sequence=="" and not other.enabled)
  other.sequence="100 > 200";other.enabled=true;r.Refresh()
  assert(BaimiaoRotationGuide1.cells[1].spell==20271)
  m.rotationSpecSelect:GetScript("OnClick")();assert(r.EditorRows()==r.Profile(72).rows)
  assert(r.EditorRows()[1].sequence=="")
  GetSpecializationInfo=function() return 71 end;r.Refresh()
  assert(BaimiaoRotationGuide1.cells[1].spell==100 and BaimiaoRotationGuide1.specID==71)
  BaimiaoRotationGuide1.layoutDB.locked=false;r.Refresh()
  BaimiaoRotationGuide1.close:GetScript("OnClick")()
  assert(not other.enabled and rows[1].enabled)
  GetSpecializationInfo=function() return nil end;r.Refresh();assert(not BaimiaoRotationGuide1:IsShown())
  GetSpecializationInfo=function() return 70 end;r.Refresh();assert(BaimiaoRotationGuide1:IsShown())
  assert(#messages==0,table.concat(messages,"; "))''')
 def test_legacy_migration_is_non_destructive_and_once(self):
  self.runlua('''d.profileVersion=nil;d.profiles={};d.rows=rows
  rows[1].enabled=true;rows[4].name="My custom";rows[4].sequence="100 > 200";rows[4].enabled=true
  GetSpecializationInfo=function() return 71 end
  r.GetDB()
  assert(d.profileVersion==1 and d.legacyRows[4].sequence=="100 > 200")
  assert(r.Profile(70).rows[1].enabled and r.Profile(70).rows[4].name=="My custom")
  assert(r.Profile(71).rows[1].sequence=="")
  assert(r.Profile(71).rows[4].sequence=="100 > 200")
  r.Profile(71).rows[4].sequence="300";r.GetDB()
  assert(r.Profile(71).rows[4].sequence=="300")
  assert(d.legacyRows[4].sequence=="100 > 200" and rows[4].sequence=="100 > 200")
  assert(r.Profile(70).rows[4].sequence=="100 > 200")''')
 def test_locked_background_and_scale(self):
  self.runlua('''rows[1].enabled=true;r.Refresh();local f=BaimiaoRotationGuide1
  assert(f.card:IsShown() and f:GetScale()==1)
  d.hideBackgroundLocked=true;d.scalePercent=150;r.Refresh()
  assert(not f.card:IsShown() and not f.bg:IsShown());assert(f:GetScale()==1.5)
  assert(f.cells[1]:IsShown() and f.title:IsShown())
  BaimiaoToolboxWorkspace.theme:GetScript("OnClick")()
  assert(not f.card:IsShown())
  f.layoutDB.locked=false;r.Refresh();assert(f.card:IsShown() and f.bg:IsShown())
  f.layoutDB.locked=true;d.hideBackgroundLocked=false;r.Refresh();assert(f.card:IsShown())
  d.scalePercent=999;r.Refresh();assert(f:GetScale()==2)
  d.scalePercent=1;r.Refresh();assert(f:GetScale()==0.5)
  d.scalePercent=150;UIParent:SetSize(800,600);r.Refresh()
  assert(f:GetWidth()*f:GetScale()<=800)
  assert(#messages==0,table.concat(messages,"; "))''')
if __name__=='__main__':unittest.main()
