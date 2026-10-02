import unittest
import test_workspace

class MountRaidTests(unittest.TestCase):
 setUp=test_workspace.WorkspaceTests.setUp
 runlua=test_workspace.WorkspaceTests.runlua
 def test_unbound_water_does_not_summon_random(self):
  self.runlua('''ns.modules.quickmount.OnEnable()
  summoned={};C_MountJournal.SummonByID=function(id) summoned[#summoned+1]=id end
  SlashCmdList.BMQUICKMOUNT("water");assert(#summoned==0,"unbound water summoned random mount")
  SlashCmdList.BMQUICKMOUNT("fly");assert(#summoned==1 and summoned[1]==0)
  ''')
 def test_independent_raid_rows(self):
  self.runlua('''function IsInRaid() return false end;function IsInGroup() return false end
  ns.modules.raidcd.OnEnable();local f=BaimiaoRaidCDFrame;local d=ns.GetDB("raidcd")
  assert(d.showLust==true,"missing lust visibility option")
  function tick() BaimiaoRaidCDPoll:GetScript("OnUpdate")(BaimiaoRaidCDPoll,0.3) end
  assert(f.rows[1]:IsShown() and f.rows[2]:IsShown())
  d.showLust=false;tick();assert(not f.rows[1]:IsShown() and f.rows[2]:IsShown())
  assert(f.rows[2].points.TOPLEFT[2]==f);assert(f:GetHeight()==28)
  d.showBrez=false;tick();assert(not f:IsShown())
  d.showLust=true;tick();assert(f:IsShown() and f.rows[1]:IsShown() and not f.rows[2]:IsShown())
  d.showBrez=true;tick();assert(f.rows[2].points.TOPLEFT[2]==f.rows[1] and f:GetHeight()==48)
  ''')

 def test_special_mount_bindings_and_defaults(self):
  self.runlua('''ns.modules.quickmount.OnEnable();local d=ns.GetDB("quickmount")
  summoned={};C_MountJournal.SummonByID=function(id) summoned[#summoned+1]=id end
  C_MountJournal.GetMountInfoByID=function(id)
   return id==42 and "驯服的海马" or "其他坐骑",123,456,false,true,nil,false,nil,nil,nil,id==42
  end
  for _,cat in ipairs({"water","repair","ah","passenger"}) do
   d.mounts[cat]=99;SlashCmdList.BMQUICKMOUNT(cat);assert(#summoned==0)
  end
  d.mounts.water=42;SlashCmdList.BMQUICKMOUNT("water");assert(summoned[1]==42)
  d.mounts.water=nil;C_MountJournal.GetMountIDs=function() return {42} end
  local b=BaimiaoQuickMountButton;b:GetScript("OnEvent")(b,"NEW_MOUNT_ADDED")
  SlashCmdList.BMQUICKMOUNT("water");assert(summoned[2]==42)
  combat=true;SlashCmdList.BMQUICKMOUNT("water");assert(#summoned==2)
  ''')
 def test_hidden_rows_keep_music_polling(self):
  self.runlua('''function IsInRaid() return false end;function IsInGroup() return false end
  local d=ns.GetDB("raidcd");d.showLust=false;d.showBrez=false;d.music.enabled=true;d.music.loop=false
  d.music.sound="__custom__";d.music.file="test-fixture.ogg"
  local active=false;local played=0;local stopped=0
  C_UnitAuras={GetPlayerAuraBySpellID=function() if active then return {expirationTime=40} end end}
  function PlaySoundFile() played=played+1;return true,123 end
  function StopSound() stopped=stopped+1 end
  ns.modules.raidcd.OnEnable();assert(not BaimiaoRaidCDFrame:IsShown())
  local p=BaimiaoRaidCDPoll;assert(p:IsVisible())
  active=true;p:GetScript("OnUpdate")(p,0.3);assert(played==1)
  active=false;p:GetScript("OnUpdate")(p,0.3);assert(stopped==1)
  ns.modules.raidcd.OnDisable();active=true;p:GetScript("OnUpdate")(p,0.3);assert(played==1)
  ''')
