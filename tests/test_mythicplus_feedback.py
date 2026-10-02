"""Regression cases from the 2026-10-02 live-client screenshots.
Models Blizzard's explicit HIGH dungeon-icon strata and PvP-before-Challenges hide
ordering, not a renderer, hardware input implementation or taint checker.
"""
import unittest
import test_mythicplus as baseline

class MythicFeedbackTests(unittest.TestCase):
 setUp = baseline.MythicTests.setUp
 runlua = baseline.MythicTests.runlua
 open = baseline.MythicTests.open

 def test_native_icon_row_cannot_draw_over_replacement(self):
  self.open()
  self.runlua('''local strata={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5}
   for _,icon in ipairs(ChallengesFrame.DungeonIcons)do
    assert(not icon:IsVisible() or (strata[h:GetFrameStrata()]>=strata[icon:GetFrameStrata()]
     and h:GetFrameLevel()>icon:GetFrameLevel()),"old HIGH-strata dungeon row is above replacement")
   end''')

 def test_current_key_is_emphasized_and_rating_has_no_source_suffix(self):
  self.open()
  self.runlua('''assert(not c.score:GetText():find("数据来自游戏",1,true),"redundant rating suffix")
   local r,g,b=c.key:GetTextColor();local nr,ng,nb=c.title:GetTextColor()
   assert(r~=nr or g~=ng or b~=nb,"current key needs a distinct highlight")
   local _,size=c.key:GetFont();assert(size>=17,"current key too small")''')

 def test_retail_spellbook_known_portal_has_click_action(self):
  self.runlua('''IsPlayerSpell=nil;IsSpellKnown=nil;C_Spell.IsSpellKnown=nil
   Enum.SpellBookSpellBank={Player=0}
   C_SpellBook={IsSpellKnown=function(id,bank)assert(bank==0);return known[id]==true end}''')
  self.open()
  self.runlua('''local b=c.tiles[1].portal
   assert(b:IsVisible(),"known retail spell has no portal button")
   assert(b.attributes.type1=="spell" and b.attributes.spell==393256)
   assert(b.clicks[1]=="AnyUp" and b.clicks[2]=="AnyDown")
   assert(b.attributes.type2==nil,"right click must not cast")''')

 def test_portal_stays_above_host_on_high_strata(self):
  self.runlua('ChallengesFrame:SetFrameStrata("HIGH")')
  self.open()
  self.runlua('''local b=c.tiles[1].portal
   assert(b:GetFrameStrata()==h:GetFrameStrata(),"portal below HIGH replacement")
   assert(b:GetFrameLevel()>h:GetFrameLevel())''')

 def test_levels_and_ratings_use_separate_rarity_colors(self):
  self.runlua('''C_ChallengeMode.GetKeystoneLevelRarityColor=function(level)
    return level>=15 and {r=1,g=.5,b=0} or {r=.2,g=.7,b=1} end
   C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor=function()return {r=.6,g=.2,b=1}end
   C_ChallengeMode.GetDungeonScoreRarityColor=function()return {r=1,g=.5,b=0}end''')
  self.open()
  self.runlua('''assert(c.tiles[1].stats:GetText():find("|cffff8000+16|r",1,true),"season level lacks game rarity color")
   assert(c.tiles[1].stats:GetText():find("|cff9933ff428|r",1,true),"individual score uses wrong scale")
   assert(c.score:GetText()=="赛季评分  |cffff80003204|r","overall rating uses wrong scale")
   assert(c.tiles[1].week:GetText():find("|cff",1,true),"weekly level uncolored")
   assert(c.rows[1].left:GetText():find("|cff",1,true),"run level uncolored")
   assert(c.rows[3].left:GetText():find("|cff33b3ff+12|r",1,true),"different tier needs different color")''')

 def test_pvp_width_selected_before_challenges_hide_is_not_overwritten(self):
  self.open()
  self.runlua('''-- PVEFrame_ShowFrame selects/shows PvP (index 2) before hiding Challenges (index 3).
   -- PVPUIFrame update sets its desired width before ChallengesFrame.OnHide runs.
   PVEFrame_ShowFrame("PVPUIFrame");advance()
   assert(PVEFrame:GetWidth()==800,"old mythic width overwrites new PvP width")
   assert(PVEFrame:GetHeight()==428 and PVEFrame:GetScale()==.9)
   assert(not h:IsVisible())
   for _,t in ipairs(c.tiles)do assert(not t.portal:IsShown())end''')


 def test_repeated_tab_switches_restore_only_our_geometry(self):
  self.open()
  self.runlua('''local count=#frames
   for i=1,20 do
    PVEFrame_ShowFrame("PVPUIFrame");advance();assert(PVEFrame:GetWidth()==800)
    PVEFrame_ShowFrame("GroupFinderFrame");advance();assert(PVEFrame:GetWidth()==563)
    PVEFrame_ShowFrame("ChallengesFrame");advance();assert(PVEFrame:GetWidth()==840)
   end
   assert(#frames==count)
   d.show=false;ns.MythicPlus.Refresh();assert(PVEFrame:GetWidth()==563)
   for _,icon in ipairs(ChallengesFrame.DungeonIcons)do assert(icon:IsVisible())end''')

 def test_combat_pvp_switch_keeps_new_page_width_after_regen(self):
  self.open()
  self.runlua('''setCombat(true);PVEFrame_ShowFrame("PVPUIFrame");advance()
   assert(PVEFrame:GetWidth()==800)
   setCombat(false);assert(PVEFrame:GetWidth()==800 and PVEFrame:GetHeight()==428)
   for _,t in ipairs(c.tiles)do assert(not t.portal:IsShown())end''')

 def test_later_layout_owner_is_not_reset_on_exit(self):
  self.open()
  self.runlua('''PVEFrame:SetSize(850,620);PVEFrame:SetScale(.8)
   ChallengesFrame:Hide();advance()
   assert(PVEFrame:GetWidth()==850 and PVEFrame:GetHeight()==620 and PVEFrame:GetScale()==.8)''')

 def test_spellbook_unknown_restricted_and_legacy_fallback(self):
  self.runlua('''local secret={};issecretvalue=function(v)return v==secret end
   C_SpellBook={IsSpellKnown=function()return secret end}
   assert(D.Known(393256))
   IsPlayerSpell=nil;assert(not D.Known(393256))
   C_SpellBook.IsSpellKnown=function()error("not ready")end;assert(not D.Known(393256))
   C_SpellBook.IsSpellKnown=function()return false end;assert(not D.Known(393256))''')

 def test_restricted_or_missing_colors_keep_readable_numbers(self):
  self.runlua('''local secret={};issecretvalue=function(v)return v==secret end
   C_ChallengeMode.GetKeystoneLevelRarityColor=function()return {r=secret,g=1,b=1}end
   C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor=function()error("not ready")end
   C_ChallengeMode.GetDungeonScoreRarityColor=function()return secret end''')
  self.open()
  self.runlua('''assert(c.tiles[1].stats:GetText()=="赛季 +16 · 评分 428")
   assert(c.score:GetText()=="赛季评分  3204")
   assert(c.key:GetText():find("+15",1,true))''')

 def test_restore_uses_applied_scale_readback_not_unrounded_request(self):
  self.runlua('''local setScale=PVEFrame.SetScale
   function PVEFrame:SetScale(value) setScale(self,math.floor(value*100+.5)/100)end
   d.scalePercent=113''')
  self.open()
  self.runlua('''assert(PVEFrame:GetScale()==1.02)
   PVEFrame_ShowFrame("PVPUIFrame");advance()
   assert(PVEFrame:GetScale()==.9,"rounded applied scale was not restored")''')

if __name__=='__main__': unittest.main()
