"""Manual marker and native countdown safety checks; secure engine is not emulated."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
STUB=r'''
group=true;raid=false;leader=true;assistant=false;countdowns={};readyCount=0;accepted=true
function IsInGroup()return group end
function IsInRaid()return raid end
function UnitIsGroupLeader()return leader end
function UnitIsGroupAssistant()return assistant end
C_PartyInfo={DoCountdown=function(n)countdowns[#countdowns+1]=n;return accepted end,
 DoReadyCheck=function()readyCount=readyCount+1 end}
function SendChatMessage()error("never chat broadcast")end
C_ChatInfo={SendAddonMessage=function()error("never timer addon broadcast")end}
function SetRaidTarget()error("insecure direct raid target call")end
function PlaceRaidMarker()error("insecure direct world marker call")end
function ClearRaidMarker()error("insecure direct world clear call")end
function RemoveRaidTargets()error("insecure direct clear call")end
function GetRaidTargetIndex()error("never inspect potentially secret markers")end
function IsRaidMarkerActive()error("never inspect potentially secret markers")end
'''
class MarkerAssistTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  for p in ['tests/wow_ui_stub.lua','tests/mythic_stub.lua']:
   self.lua.execute((ROOT/p).read_text(encoding='utf-8'))
  self.lua.execute(STUB)
  for p in ['Core.lua','Workspace.lua','Modules/MarkerAssist.lua','Modules/SmallTools.lua']:
   self.lua.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/p).read_text(encoding='utf-8'))
  self.lua.execute('m=ns.modules.smalltools;m.OnEnable();M=ns.MarkerAssist;b=BaimiaoMarkerAssist;d=ns.GetDB("smalltools").marker')
 def runlua(self,s):self.lua.execute(s)
 def test_builds_compact_two_rows_and_four_management_buttons(self):
  self.runlua('''assert(b:IsShown() and b:GetWidth()==314 and b:GetHeight()==118)
   assert(#b.targets==9 and #b.worlds==9)
   assert(b.ready and b.pull5 and b.pull10 and b.cancel)
   assert(#countdowns==0 and readyCount==0 and #messages==0)
   local count=#frames;M.Start();M.Refresh();assert(#frames==count)''')
 def test_target_actions_are_secure_left_set_right_clear_current_target(self):
  self.runlua('''for i,button in ipairs(b.targets)do
    local a=button.attributes;assert(button.template:find("SecureActionButtonTemplate",1,true))
    assert(a.type=="raidtarget" and a.unit=="target")
    assert(button.clicks[1]=="AnyDown" and button.clicks[2]=="AnyUp")
    assert(not button:GetScript("OnClick"),"do not overwrite secure template click")
    if i<=8 then assert(a.marker==i and a.action1=="set" and a.action2=="clear")
    else assert(a.action=="clear")end
   end''')
 def test_world_mapping_and_clear_all_has_no_marker(self):
  self.runlua('''local world={5,6,3,2,7,1,4,8}
   for i,button in ipairs(b.worlds)do
    local a=button.attributes;assert(a.type=="worldmarker" and not button:GetScript("OnClick"))
    if i<=8 then assert(a.marker==world[i] and a.action1=="set" and a.action2=="clear")
    else assert(a.marker==nil and a.action=="clear" and a.macrotext==nil)end
   end''')
 def test_countdowns_use_native_api_5_10_zero_and_ready_namespace(self):
  self.runlua('''b.pull5:GetScript("OnClick")();b.pull10:GetScript("OnClick")();b.cancel:GetScript("OnClick")()
   assert(#countdowns==3 and countdowns[1]==5 and countdowns[2]==10 and countdowns[3]==0)
   b.ready:GetScript("OnClick")();assert(readyCount==1)
   assert(#messages==0)''')
 def test_no_leader_or_solo_blocks_management_not_marker_creation(self):
  self.runlua('''leader=false;b.pull5:GetScript("OnClick")();b.ready:GetScript("OnClick")()
   assert(#countdowns==0 and readyCount==0 and #messages==2)
   assert(b.targets[1].attributes.type=="raidtarget","party members can mark")
   assistant=true;raid=false;b.pull10:GetScript("OnClick")();assert(#countdowns==0)
   raid=true;b.pull10:GetScript("OnClick")();assert(#countdowns==1)
   group=false;leader=true;b.cancel:GetScript("OnClick")();assert(#countdowns==1)''')
 def test_failed_missing_secret_countdown_reports_without_fallback(self):
  self.runlua('''accepted=false;b.pull5:GetScript("OnClick")();assert(#messages==1)
   C_PartyInfo.DoCountdown=function()error("restricted")end;b.pull5:GetScript("OnClick")();assert(#messages==2)
   C_PartyInfo.DoCountdown=nil;b.pull5:GetScript("OnClick")();assert(#messages==3)
   local secret={};issecretvalue=function(v)return v==secret end
   C_PartyInfo.DoCountdown=function()return secret end;b.pull5:GetScript("OnClick")();assert(#messages==4)''')
 def test_ready_fallback_and_rejected_operation(self):
  self.runlua('''C_PartyInfo.DoReadyCheck=nil;DoReadyCheck=function()readyCount=readyCount+1 end
   b.ready:GetScript("OnClick")();assert(readyCount==1)
   DoReadyCheck=function()error("not allowed")end;b.ready:GetScript("OnClick")();assert(#messages==1)''')
 def test_combat_defers_parent_geometry_hiding_and_stops_management(self):
  self.runlua('''local oldShow=b.Show;local oldHide=b.Hide;local oldScale=b.SetScale
   b.Show=function(self)assert(not combat,"protected parent show");oldShow(self)end
   b.Hide=function(self)assert(not combat,"protected parent hide");oldHide(self)end
   b.SetScale=function(self,v)assert(not combat,"protected parent scale");oldScale(self,v)end
   setCombat(true);b.pull5:GetScript("OnClick")();b.ready:GetScript("OnClick")()
   assert(#countdowns==0 and readyCount==0)
   group=false;fire("GROUP_ROSTER_UPDATE");M.Refresh();assert(b:IsShown())
   ns.SetModuleEnabled("smalltools",false);assert(b:IsShown())
   setCombat(false);assert(not b:IsShown())
   group=true;ns.SetModuleEnabled("smalltools",true);assert(b:IsShown())''')
 def test_cold_start_in_combat_does_not_create_secure_frames(self):
  # Separate fresh instance prevents a previously created bar from hiding a bug.
  fresh=LuaRuntime(unpack_returned_tuples=True)
  for p in ['tests/wow_ui_stub.lua','tests/mythic_stub.lua']:
   fresh.execute((ROOT/p).read_text(encoding='utf-8'))
  fresh.execute(STUB+'\ncombat=true')
  for p in ['Core.lua','Workspace.lua','Modules/MarkerAssist.lua']:
   fresh.execute('assert(loadstring(...))("BaimiaoToolbox",ns)',(ROOT/p).read_text(encoding='utf-8'))
  fresh.execute('''ns.MarkerAssist.Start();assert(BaimiaoMarkerAssist==nil)
   setCombat(false);assert(BaimiaoMarkerAssist:IsShown())''')
 def test_subfeature_group_visibility_scale_and_parent_module(self):
  self.runlua('''group=false;fire("GROUP_ROSTER_UPDATE");assert(not b:IsShown())
   d.groupOnly=false;M.Refresh();assert(b:IsShown())
   d.enabled=false;M.Refresh();assert(not b:IsShown())
   d.enabled=true;d.scalePercent=85;M.Refresh();assert(b:IsShown() and b:GetScale()==.85)
   ns.SetModuleEnabled("smalltools",false);assert(not b:IsShown())
   ns.SetModuleEnabled("smalltools",true);assert(b:IsShown() and d.scalePercent==85)''')
 def test_position_drag_lock_and_reset_are_character_only(self):
  self.runlua('''local moves=0;b.StartMoving=function()moves=moves+1 end;b.StopMovingOrSizing=function()end
   b.drag:GetScript("OnDragStart")();assert(moves==0)
   d.locked=false;b.drag:GetScript("OnDragStart")();b.drag:GetScript("OnDragStop")();assert(moves==1)
   local layout=ns.GetLayoutDB("markerassist");assert(layout.x~=nil and layout.y~=nil)
   assert(d.x==nil and d.y==nil)
   combat=true;b.drag:GetScript("OnDragStart")();assert(moves==1);combat=false
   ns.OpenOptions("smalltools");local reset
   for _,f in ipairs(frames)do if f:GetObjectType()=="Button" and f:GetText()=="重置标记助手位置" then reset=f end end
   assert(reset);reset:GetScript("OnClick")();assert(layout.x==nil and layout.y==nil)''')
 def test_no_ping_chat_timer_or_automatic_marker_code(self):
  source=(ROOT/'Modules/MarkerAssist.lua').read_text(encoding='utf-8')
  for forbidden in ['C_Ping','SendChatMessage','SendAddonMessage','DoEmote','SetRaidTarget(', 'PlaceRaidMarker(', 'IsRaidMarkerActive(']:
   self.assertNotIn(forbidden,source)
  self.runlua('''for _,f in ipairs({b:GetChildren()})do assert(not f:GetScript("OnUpdate"))end
   local count=#frames;ns.OpenOptions("smalltools");BaimiaoToolboxWorkspace.theme:GetScript("OnClick")()
   assert(#countdowns==0 and readyCount==0)''')
 def test_all_eight_row_combinations_compact_without_blank_rows(self):
  self.runlua('''assert(d.showTargets and d.showWorlds and d.showManagement,"existing users retain all three rows")
   local original=#frames
   for bits=0,7 do
    d.showTargets=bits%2==1;d.showWorlds=math.floor(bits/2)%2==1;d.showManagement=bits>=4
    M.Refresh();local y=28;local n=0;local bottom=32
    for _,entry in ipairs({{d.showTargets,b.targets,b.targetLabel},{d.showWorlds,b.worlds,b.worldLabel}})do
     local show,buttons,label=unpack(entry);assert(label:IsShown()==show)
     for i,f in ipairs(buttons)do
      assert(f:IsShown()==show)
      if show then assert(f.point[2]==46+(i-1)*29 and f.point[3]==-y)end
     end
     if show then assert(label.point[3]==-y-6);bottom=y+32;y=y+28;n=n+1 end
    end
    if d.showManagement and n>0 then y=y+2 end
    for _,f in ipairs({b.ready,b.pull5,b.pull10,b.cancel})do
     assert(f:IsShown()==d.showManagement)
     if d.showManagement then assert(f.point[3]==-y)end
    end
    if d.showManagement then bottom=y+32;n=n+1 end
    assert(b:IsShown()==(n>0) and b:GetHeight()==bottom)
    assert(b:GetWidth()==314 and #frames==original)
   end
   d.showTargets=true;d.showWorlds=true;d.showManagement=true;M.Refresh()
   assert(b:GetHeight()==118 and b.targets[1].attributes.action1=="set" and b.worlds[1].attributes.marker==5)''')
 def test_row_changes_defer_all_protected_geometry_until_regen(self):
  self.runlua('''for _,f in ipairs({b,b.targets[1],b.worlds[1],b.ready})do
    for _,name in ipairs({"SetHeight","SetShown","ClearAllPoints","SetPoint"})do
     local original=f[name];f[name]=function(self,...)assert(not combat,"combat geometry: "..name);return original(self,...)end
    end
   end
   setCombat(true);d.showTargets=false;d.showWorlds=false;d.showManagement=false;M.Refresh()
   assert(b:IsShown() and b:GetHeight()==118 and b.targets[1]:IsShown())
   setCombat(false);assert(not b:IsShown() and not b.targets[1]:IsShown())
   d.showWorlds=true;M.Refresh();assert(b:IsShown() and b:GetHeight()==60 and b.worlds[1].point[3]==-28)''')
 def test_disabled_management_rejects_stale_callbacks_and_clears_own_tooltip(self):
  self.runlua('''GameTooltip:SetOwner(b.pull5,"ANCHOR_CURSOR");GameTooltip:Show()
   d.showManagement=false;M.Refresh();assert(not GameTooltip:IsShown())
   b.pull5:GetScript("OnClick")();b.ready:GetScript("OnClick")();assert(#countdowns==0 and readyCount==0)
   local other=CreateFrame("Button",nil,UIParent);GameTooltip:SetOwner(other,"ANCHOR_CURSOR");GameTooltip:Show()
   d.showTargets=false;M.Refresh();assert(GameTooltip:IsShown() and GameTooltip:IsOwned(other))''')
 def test_row_settings_click_and_restore_saved_preferences(self):
  self.runlua('''ns.OpenOptions("smalltools");local checks={}
   for _,f in ipairs(frames)do if f:GetObjectType()=="CheckButton" and f.label then checks[f.label:GetText()]=f end end
   for _,entry in ipairs({{"目标标记","showTargets"},{"地面标记","showWorlds"},{"团队管理（就位 / 倒数）","showManagement"}})do
    local f=checks[entry[1]];assert(f and f:GetChecked())
    f:SetChecked(false);f:GetScript("OnClick")(f);assert(d[entry[2]]==false)
   end
   assert(not b:IsShown());M.Stop();M.Start();assert(not b:IsShown() and not d.showTargets)
   local f=checks["地面标记"];f:SetChecked(true);f:GetScript("OnClick")(f)
   assert(b:IsShown() and b:GetHeight()==60 and not b.targets[1]:IsShown())''')
 def test_leader_only_hides_members_assistants_and_solo(self):
  self.runlua('''assert(d.leaderOnly==false,"new preference must preserve existing visibility")
   d.leaderOnly=true;M.Refresh();assert(b:IsShown())
   leader=false;fire("PARTY_LEADER_CHANGED");assert(not b:IsShown())
   raid=true;assistant=true;fire("GROUP_ROSTER_UPDATE");assert(not b:IsShown(),"assistant is not raid leader")
   leader=true;fire("PARTY_LEADER_CHANGED");assert(b:IsShown())
   group=false;d.groupOnly=false;M.Refresh();assert(not b:IsShown(),"solo is never party leader")
   d.leaderOnly=false;M.Refresh();assert(b:IsShown())''')
 def test_leader_transfer_defers_visibility_both_directions_in_combat(self):
  self.runlua('''d.leaderOnly=true;M.Refresh()
   local show=b.SetShown;b.SetShown=function(self,v)assert(not combat);show(self,v)end
   setCombat(true);leader=false;fire("PARTY_LEADER_CHANGED");assert(b:IsShown())
   setCombat(false);assert(not b:IsShown())
   setCombat(true);leader=true;fire("PARTY_LEADER_CHANGED");assert(not b:IsShown())
   setCombat(false);assert(b:IsShown())''')
 def test_leader_setting_persists_without_resetting_rows(self):
  self.runlua('''ns.OpenOptions("smalltools");local toggle
   for _,f in ipairs(frames)do if f:GetObjectType()=="CheckButton" and f.label and f.label:GetText()=="仅队长显示"then toggle=f end end
   assert(toggle and not toggle:GetChecked());leader=false
   toggle:SetChecked(true);toggle:GetScript("OnClick")(toggle);assert(d.leaderOnly and not b:IsShown())
   d.showTargets=false;d.showManagement=false;M.Stop();M.Start()
   assert(d.leaderOnly and not b:IsShown() and not d.showTargets and not d.showManagement)
   leader=true;fire("PARTY_LEADER_CHANGED");assert(b:IsShown() and b:GetHeight()==60)
   d.enabled=false;M.Refresh();assert(not b:IsShown())''')
 def test_missing_or_secret_leader_status_is_not_treated_as_leader(self):
  self.runlua('''d.leaderOnly=true
   local secret={};issecretvalue=function(v)return v==secret end
   UnitIsGroupLeader=function()return secret end;M.Refresh();assert(not b:IsShown())
   UnitIsGroupLeader=nil;M.Refresh();assert(not b:IsShown())
   d.leaderOnly=false;M.Refresh();assert(b:IsShown())''')
if __name__=='__main__':unittest.main()
