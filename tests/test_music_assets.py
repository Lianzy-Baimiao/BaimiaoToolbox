"""Removed private media must not be shipped, registered, or used as the default."""
from pathlib import Path
import unittest
import test_workspace
import test_raid_music
ROOT=Path(__file__).resolve().parents[1]

class MusicAssetTests(unittest.TestCase):
 setUp=test_workspace.WorkspaceTests.setUp
 runlua=test_workspace.WorkspaceTests.runlua
 fixture=test_raid_music.RaidMusicTests.fixture

 def test_private_file_is_absent_and_not_referenced_by_runtime(self):
  self.assertFalse((ROOT/'media/lust_ball.ogg').exists())
  for path in [*ROOT.glob('*.lua'),*ROOT.glob('Modules/*.lua'),ROOT/'BaimiaoToolbox.toc']:
   self.assertNotIn('lust_ball.ogg',path.read_text(encoding='utf-8'),str(path))

 def test_default_is_unconfigured_custom_sound(self):
  self.runlua('''local m=ns.GetDB("raidcd").music
   assert(m.sound=="__custom__" and m.file=="" and not m.enabled)''')
  self.fixture('d.music.file=""')
  self.runlua('auras[2825]={expirationTime=now+40};tick();assert(#played==0)')

 def test_removed_selection_migrates_without_changing_custom_file_or_channel(self):
  self.fixture('d.music.sound="白描：嗜血球";d.music.file="user-selected.ogg";d.music.channel="SFX"')
  self.runlua('''assert(d.music.sound=="__custom__" and d.music.file=="user-selected.ogg" and d.music.channel=="SFX")
   auras[2825]={expirationTime=now+40};tick()
   assert(#played==1 and played[1][1]=="user-selected.ogg" and played[1][2]=="SFX")''')

 def test_missing_library_only_lists_custom_path(self):
  self.runlua('''local labels={}
   MenuUtil={CreateContextMenu=function(_,build)
    build(nil,{CreateButton=function(_,label)labels[#labels+1]=label end}) end}
   local found=false
   for _,f in ipairs(frames)do
    if f:GetObjectType()=="Button" and (f:GetText() or ""):find("音乐：",1,true)==1 then
     f:GetScript("OnClick")();found=true;break
    end
   end
   assert(found and #labels==1 and labels[1]=="自定义路径…")''')

 def test_other_library_sound_plays_without_registering_private_media(self):
  self.fixture('''d.music.sound="Other sound";registered={}
   LibStub=function()return {
    Register=function(_,kind,name,file)registered[#registered+1]={kind,name,file}end,
    Fetch=function(_,kind,name)if name=="Other sound"then return "other-addon.ogg"end end
   }end''')
  self.runlua('''assert(#registered==0)
   auras[2825]={expirationTime=now+40};tick()
   assert(#played==1 and played[1][1]=="other-addon.ogg")''')

if __name__=='__main__':unittest.main()
