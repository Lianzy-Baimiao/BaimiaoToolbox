"""Music trigger regressions through the actual module; not a client/secret-value runtime."""
import unittest
import test_workspace

class RaidMusicTests(unittest.TestCase):
 setUp=test_workspace.WorkspaceTests.setUp
 runlua=test_workspace.WorkspaceTests.runlua

 def fixture(self, initial=''):
  self.runlua('''now=100;auras={};played={};stopped={};tickers={};raid=false;party=true;dead=false
   function GetTime()return now end
   function IsInRaid()return raid end
   function IsInGroup()return party or raid end
   inInstance=true;instanceType="party"
   function IsInInstance()return inInstance,instanceType end
   function UnitIsDeadOrGhost()return dead end
   C_UnitAuras={GetPlayerAuraBySpellID=function(id)return auras[id]end}
   function PlaySoundFile(file,channel)played[#played+1]={file,channel};return true,#played end
   function StopSound(handle)stopped[#stopped+1]=handle end
   C_Timer.NewTicker=function(interval,fn)
    local t={interval=interval,fn=fn};function t:Cancel()self.cancelled=true end
    tickers[#tickers+1]=t;return t end
   d=ns.GetDB("raidcd");d.music.enabled=true;d.music.loop=false
   function tick(dt)now=now+(dt or .3);BaimiaoRaidCDPoll:GetScript("OnUpdate")(BaimiaoRaidCDPoll,dt or .3)end
   function event(name,unit)local f=BaimiaoRaidCDPoll;local fn=f:GetScript("OnEvent");if fn then fn(f,name,unit)end end
   secret=setmetatable({}, {__sub=function()error("secret arithmetic")end,__lt=function()error("secret compare")end})
   issecretvalue=function(v)return rawequal(v,secret)end
  ''')
  self.runlua(initial)
  self.runlua('ns.modules.raidcd.OnEnable()')

 def test_mplus_nil_buff_new_sated_starts_without_lua_error(self):
  self.fixture()
  self.runlua('''combat=true;auras[57724]={expirationTime=now+600};tick()
   assert(#played==1,"new readable Sated was classified as cooldown, so no music request")
   assert(BaimiaoRaidCDFrame.rows[1].text:GetText():find("约",1,true),"estimated timer must be labelled")
   tick();assert(#played==1,"one application must not restart every poll")''')

 def test_noncombat_direct_buff_still_plays(self):
  self.fixture()
  self.runlua('''auras[2825]={expirationTime=now+40};tick();assert(#played==1)
   assert(not BaimiaoRaidCDFrame.rows[1].text:GetText():find("约",1,true))
   auras={};tick();assert(#stopped==1)''')

 def test_secret_expiration_does_not_block_direct_or_fallback_music(self):
  for aura_id in (2825,57724):
   with self.subTest(aura_id=aura_id):
    self.setUp();self.fixture()
    self.runlua(f'''combat=true;auras[{aura_id}]={{expirationTime=secret}};tick();assert(#played==1)''')

 def test_existing_sated_at_login_or_zone_in_never_triggers(self):
  self.fixture('auras[57724]={expirationTime=now+500}')
  self.runlua('''combat=true;tick();assert(#played==0)
   event("PLAYER_ENTERING_WORLD");tick();assert(#played==0)
   auras={};tick();auras[57724]={expirationTime=now+600};event("PLAYER_ENTERING_WORLD");tick()
   assert(#played==0,"carried-in Sated must be seeded, not treated as a new cast")''')

 def test_guess_expires_once_then_waits_for_a_fresh_application(self):
  self.fixture()
  self.runlua('''combat=true;auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   tick(41);assert(#stopped==1);tick(40);assert(#played==1,"old Sated retriggered")
   auras={};tick();auras[57724]={expirationTime=now+600};tick();assert(#played==2)''')

 def test_sated_removal_and_death_stop_inferred_music(self):
  for ending in ('auras={}', 'dead=true;event("PLAYER_DEAD")'):
   with self.subTest(ending=ending):
    self.setUp();self.fixture('d.music.loop=true')
    self.runlua('''combat=true;auras[57724]={expirationTime=now+600};tick();assert(#played==1)''')
    self.runlua(ending+';tick();assert(#stopped==1 and tickers[1].cancelled)')
    self.runlua('dead=false;tick();assert(#played==1,"old Sated restarted after death/removal")')

 def test_hidden_party_or_raid_does_not_gate_music(self):
  for setup in ('d.showParty=false','raid=true;d.showRaid=false'):
   with self.subTest(setup=setup):
    self.setUp();self.fixture(setup+';ns.GetLayoutDB("raidcd").locked=true')
    self.runlua('''combat=true;auras[2825]={expirationTime=now+40};tick()
     assert(not BaimiaoRaidCDFrame:IsShown() and #played==1)
     auras={};tick();assert(#stopped==1)''')

 def test_toggle_music_during_buff_starts_and_stops_immediately(self):
  self.fixture('d.music.enabled=false;d.music.loop=true')
  self.runlua('''combat=true;auras[2825]={expirationTime=now+40};tick();assert(#played==0)
   d.music.enabled=true;tick();assert(#played==1)
   d.music.enabled=false;tick();assert(#stopped==1 and tickers[1].cancelled)''')

 def test_unknown_sated_sample_does_not_manufacture_new_edge(self):
  self.fixture()
  self.runlua('''local original=C_UnitAuras.GetPlayerAuraBySpellID
   C_UnitAuras.GetPlayerAuraBySpellID=function()error("unavailable")end;tick();assert(#played==0)
   C_UnitAuras.GetPlayerAuraBySpellID=original;auras[57724]={expirationTime=now+500};tick()
   assert(#played==0,"unknown-to-present is not evidence of a new application")
   auras={};tick();auras[57724]={expirationTime=now+600};tick();assert(#played==1)''')

 def test_direct_and_fallback_do_not_double_trigger(self):
  self.fixture()
  self.runlua('''auras[2825]={expirationTime=now+40};auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   combat=true;auras[2825]=nil;tick();assert(#played==1 and #stopped==0)
   auras[2825]={expirationTime=now+10};tick();assert(#played==1)''')

 def test_delayed_sound_library_is_not_cached_as_permanently_missing(self):
  self.fixture('d.music.sound="late sound"')
  self.runlua('''LibStub=function()return {Fetch=function(_,kind,name)if name=="late sound" then return "late.ogg"end end}end
   combat=true;auras[2825]={expirationTime=now+40};tick()
   assert(#played==1 and played[1][1]=="late.ogg","absent LSM was permanently cached")''')

 def test_diagnostic_distinguishes_trigger_from_playback_failure(self):
  self.fixture()
  self.runlua('''PlaySoundFile=function()return false end
   combat=true;auras[57724]={expirationTime=now+600};tick()
   SlashCmdList.BMRAIDCD("music")
   local text=table.concat(messages," | ")
   assert(text:find("新疲惫",1,true) and text:find("拒绝",1,true),"diagnostic misses trigger or playback result")
   assert(not text:find("已播放",1,true),"failed request reported success")''')

 def test_all_known_sated_variants_trigger_and_preserve_selected_sound(self):
  for aura_id in (57723,57724,80354,95809,160455,264689,390435):
   with self.subTest(aura_id=aura_id):
    self.setUp();self.fixture('d.music.sound="__custom__";d.music.file="selected.ogg";d.music.channel="SFX"')
    self.runlua(f'''combat=true;auras[{aura_id}]={{expirationTime=now+600}};event("UNIT_AURA","player")
     assert(#played==1 and played[1][1]=="selected.ogg" and played[1][2]=="SFX")
     assert(d.music.file=="selected.ogg" and d.music.channel=="SFX" and d.music.sound=="__custom__")''')

 def test_secret_aura_object_invalidates_absent_baseline(self):
  self.fixture()
  self.runlua('''auras[57724]=secret;tick();assert(#played==0)
   auras[57724]={expirationTime=now+500};tick();assert(#played==0)
   auras={};tick();auras[57724]={expirationTime=now+600};tick();assert(#played==1)''')

 def test_module_disable_cancels_and_reenable_seeds_carried_sated(self):
  self.fixture('d.music.loop=true')
  self.runlua('''auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   ns.SetModuleEnabled("raidcd",false);assert(#stopped==1 and tickers[1].cancelled)
   tick();assert(#played==1)
   ns.SetModuleEnabled("raidcd",true);tick();assert(#played==1)
   auras={};tick();auras[57724]={expirationTime=now+600};tick();assert(#played==2)''')

 def test_loop_repeats_but_does_not_play_after_deadline_between_polls(self):
  self.fixture('d.music.loop=true')
  self.runlua('''auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   now=now+3;tickers[1].fn();assert(#played==2 and #stopped==1)
   now=now+40;tickers[1].fn();assert(#played==2 and tickers[1].cancelled)''')

 def test_stop_and_preview_are_not_overridden_by_auto_poll(self):
  for button in ('停止','试听'):
   with self.subTest(button=button):
    self.setUp();self.fixture('d.music.loop=true')
    self.runlua(f'''auras[57724]={{expirationTime=now+600}};tick();assert(#played==1)
     local button
     for _,f in ipairs({{ns.modules.raidcd.optionTabs.pages[2].panel:GetChildren()}}) do
      if f:GetText()=="{button}" then button=f end
     end
     assert(button);button:GetScript("OnClick")();assert(tickers[1].cancelled)
     local count=#played;tick();assert(#played==count,"automatic playback overrode explicit user action")''')

 def test_zero_value_buff_response_does_not_require_errors_to_trigger_fallback(self):
  self.fixture()
  self.runlua('''C_UnitAuras.GetPlayerAuraBySpellID=function(id)if auras[id] then return auras[id] end end
   combat=true;auras[57724]={expirationTime=now+600};tick();assert(#played==1 and #messages==0)''')

 def test_diagnostics_distinguish_no_trigger_missing_resource_and_api_error(self):
  self.fixture('d.music.sound="__custom__";d.music.file=""')
  self.runlua('''SlashCmdList.BMRAIDCD("music")
   local text=table.concat(messages," | ");assert(text:find("未检测到",1,true) and text:find("尚未请求",1,true))
   messages={};auras[57724]={expirationTime=now+600};tick();SlashCmdList.BMRAIDCD("music")
   text=table.concat(messages," | ");assert(text:find("新疲惫",1,true) and text:find("声音资源未找到",1,true))
   messages={};auras={};tick();d.music.file="chosen.ogg";PlaySoundFile=function()error("failure")end
   auras[57724]={expirationTime=now+600};tick();SlashCmdList.BMRAIDCD("music")
   text=table.concat(messages," | ");assert(text:find("播放接口调用失败",1,true))''')

 def test_exact_remaining_time_caps_inferred_window(self):
  self.fixture()
  self.runlua('''auras[2825]={expirationTime=now+5};auras[57724]={expirationTime=now+600};tick();assert(#played==1)
   combat=true;auras[2825]=nil;tick();assert(#stopped==0)
   tick(6);assert(#stopped==1);tick();assert(#played==1)''')

if __name__=='__main__':unittest.main()
