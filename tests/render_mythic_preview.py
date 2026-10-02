"""Render a labelled schematic from real module labels/geometry and offline fixtures.
Not a WoW screenshot, texture renderer, or substitute for in-game QA.
Run: python tests/render_mythic_preview.py [path/to/CJK-font]
Requires Pillow and lupa; never reads live account data.
"""
from pathlib import Path
import sys
import re
from PIL import Image, ImageDraw, ImageFont
from test_mythicplus import MythicTests, ROOT
from test_party_keystones import STUB as PARTY_STUB
VERSION = re.search(r"^## Version: (.+)$", (ROOT/"BaimiaoToolbox.toc").read_text(encoding="utf-8"), re.M).group(1)

def main():
    case = MythicTests(); case.setUp()
    # Representative API-color fixtures for the schematic, not game thresholds.
    case.runlua('''C_ChallengeMode.GetKeystoneLevelRarityColor=function(level)
        return level>=15 and {r=1,g=.5,b=0} or {r=.2,g=.7,b=1} end
      C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor=function()return {r=.64,g=.21,b=.93}end
      C_ChallengeMode.GetDungeonScoreRarityColor=function()return {r=1,g=.5,b=0}end''')
    case.runlua('''for i=1,9 do history[#history+1]={mapChallengeModeID=mapIDs[i%8+1],
      level=14-i,thisWeek=true,durationSec=1400+i*60}end
      C_Spell.GetSpellCooldown=function(id)return id==1286831 and {startTime=100,duration=7200} or {startTime=0,duration=0}end''')
    case.open()
    c = case.lua.globals().c
    palette = case.lua.globals().ns.UI.palette
    colors = {key: tuple(round(palette[key][i] * 255) for i in range(1, 4))
              for key in ('bg', 'card', 'border', 'text', 'muted', 'accent', 'hover')}
    font_path = next((arg for arg in sys.argv[1:] if not arg.startswith('--')), 'C:/Windows/Fonts/msyh.ttc')
    scale = 2
    image = Image.new('RGB', (900*scale, 580*scale), colors['bg'])
    draw = ImageDraw.Draw(image)
    def font(size): return ImageFont.truetype(font_path, round(size*scale))
    def rect(box, fill='card', border=True):
        draw.rectangle(tuple(round(v*scale) for v in box), fill=colors[fill],
                       outline=colors['border'] if border else None, width=scale)
    def text(x, y, value, size=13, role='text', width=None):
        f = font(size); ink = colors[role]; chars = []
        for token in re.split(r'(\|cff[0-9a-fA-F]{6}|\|r)', str(value)):
            if re.fullmatch(r'\|cff[0-9a-fA-F]{6}', token):
                ink = tuple(int(token[i:i+2],16) for i in (4,6,8))
            elif token == '|r': ink = colors[role]
            else: chars.extend((char, ink) for char in token)
        if width:
            full = len(chars)
            while chars and draw.textlength(''.join(c for c,_ in chars),font=f)>width*scale:
                chars.pop()
            if len(chars)<full and chars: chars[-1]=('…',chars[-1][1])
        px=x*scale
        for char,ink in chars:
            draw.text((round(px),round((y+size)*scale)),char,font=f,fill=ink,anchor='ls')
            px+=draw.textlength(char,font=f)
    def button(x,y,w,h,value):
        rect((x,y,x+w,y+h));f=font(12)
        tw=draw.textlength(value,font=f)/scale
        text(x+(w-tw)/2,y+(h-12)/2,value,12)
    def value(f): return f.GetText(f)
    def dashboard(filename):
        nonlocal image,draw
        image=Image.new('RGB',(900*scale,548*scale),colors['bg'])
        draw=ImageDraw.Draw(image)
        ox,oy=40,96
        text(40,20,'大秘境信息优化 · 紧凑布局',24)
        text(40,57,'v'+VERSION+' / 布局示意，非游戏截图 / 离线样例，图标为占位',12,'muted')
        rect((ox,oy,ox+c.w,oy+c.h),'bg')
        def label_at(f,px,py,role='text',right=False):
            value_text=value(f); x=px+f.point[2]; y=py-f.point[3]
            if right:
                plain=re.sub(r'\|cff[0-9a-fA-F]{6}|\|r','',str(value_text))
                x+=max(0,f.w-draw.textlength(plain,font=font(f.fontSize))/scale)
            text(x,y,value_text,f.fontSize,role,width=f.w)
        for f,role in [(c.title,'text'),(c.key,'accent'),(c.score,'muted'),
                       (c.affixTitle,'muted'),(c.mapsTitle,'muted')]:
            label_at(f,ox,oy,role)
        for f in [c.settings,c.refresh]:
            button(ox+f.point[4],oy-f.point[5],f.w,f.h,value(f))
        for _,row in c.partyRows.items():
            if row.IsShown(row):
                x,y=ox+row.point[4],oy-row.point[5]
                label_at(row.owner,x,y)
                label_at(row.level,x,y,right=True)
                label_at(row.dungeon,x,y,'muted')
        for i in range(5):
            x=ox+84+i*32;rect((x,oy+85,x+26,oy+111),'hover')
            text(x+9,oy+90,str(i+1),12,'accent')
        for _,tile in c.tiles.items():
            x,y=ox+tile.point[4],oy-tile.point[5];w=tile.w
            rect((x,y,x+w,y+tile.h))
            rect((x+8,y+8,x+38,y+38),'hover');text(x+15,y+14,'图',13,'accent')
            label_at(tile.name,x,y)
            label_at(tile.stats,x,y,'muted');label_at(tile.week,x,y,'muted')
            b=tile.portal
            if b.IsShown(b):
                sx,sy=x+w-8-b.w,y+tile.h-4-b.h
                rect((sx,sy,sx+b.w,sy+b.h),'hover',False)
                draw.rectangle(tuple(round(v*scale) for v in (sx,sy,sx+b.w,sy+b.h)),outline=colors['accent'],width=scale)
                caption=value(b.caption);tw=draw.textlength(caption,font=font(11))/scale
                text(sx+(b.w-tw)/2,sy+4,caption,11,'accent')
            else:
                s=tile.portalStatus
                sx,sy=x+w-8-s.w,y+tile.h-4-s.h
                rect((sx,sy,sx+s.w,sy+s.h),'bg')
                state=value(tile.state);tw=draw.textlength(state,font=font(10))/scale
                text(sx+(s.w-tw)/2,sy+5,state,10,'muted',width=80)
        x,y=ox+c.weekly.point[4],oy-c.weekly.point[5]
        rect((x,y,x+c.weekly.w,y+c.weekly.h))
        label_at(c.weekTitle,x,y);label_at(c.weekStats,x,y,'muted')
        button(x+c.weekly.w-70,y+8,60,26,'宝库')
        for _,slot in c.vaults.items():
            sx=x+slot.point[2];sy=y-slot.point[3]
            rect((sx,sy,sx+slot.w,sy+slot.h),'bg')
            label_at(slot.title,sx,sy,'muted');label_at(slot.value,sx,sy,'accent')
            label_at(slot.detail,sx,sy,'muted')
        bar=c.selector;bx,by=x+bar.point[2],y-bar.point[3]
        rect((bx,by,bx+bar.w,by+bar.h),'bg')
        for segment in (c.runTab,c.mapTab):
            sx,sy=bx+segment.point[2],by-segment.point[3]
            rect((sx,sy,sx+segment.w,sy+segment.h),'hover' if segment.selected else 'bg',False)
            caption=value(segment.caption);tw=draw.textlength(caption,font=font(12))/scale
            text(sx+(segment.w-tw)/2,sy+4,caption,12,'accent' if segment.selected else 'muted')
            if segment.selected:
                rect((sx+4,sy+segment.h-2,sx+segment.w-4,sy+segment.h),'accent',False)
        for i,row in c.rows.items():
            if row.IsShown(row):
                rx=x+c.list.point[2];sy=y-c.list.point[3]-row.point[3]
                rect((rx,sy,rx+row.w,sy+row.h),'bg' if i%2==0 else 'card',False)
                label_at(row.left,rx,sy)
                if row.time.IsShown(row.time): label_at(row.time,rx,sy,'muted',right=True)
                status_color=tuple(round(row.right.color[j]*255) for j in range(1,4))
                colors['status']=status_color
                label_at(row.right,rx,sy,'status',right=True)
        label_at(c.range,x,y,'muted')
        target=ROOT/'docs/previews'/filename;target.parent.mkdir(parents=True,exist_ok=True)
        image.save(target);print(target)

    # Four visible teammate rows, with no other anchors changed.
    case.lua.execute(PARTY_STUB)
    case.runlua('''party[1].name="这是六字队友";party[2].name="Warriorxxxxx";party[3].name="法师队友名字";party[4].name="牧师队友名字"
      RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43},PALADIN={r=.96,g=.55,b=.73},MAGE={r=.25,g=.78,b=.92},PRIEST={r=1,g=1,b=1}}
      fire("GROUP_ROSTER_UPDATE")
      for i=1,4 do fire("CHAT_MSG_ADDON","LibKS",(18-i)..","..mapIDs[i]..",0","PARTY",party[i].name.."-"..party[i].realm)end
      advance()''')
    dashboard('mythicplus-party.png')
    if '--party-only' in sys.argv:return
    case.runlua('party={};fire("GROUP_ROSTER_UPDATE");advance()')
    dashboard('mythicplus.png')
    case.runlua('c.mapTab:GetScript("OnClick")()')
    dashboard('mythicplus-summary.png')

    # Separate tooltip schematic, driven by actual OnEnter callbacks.
    from test_mythicplus_details import MythicDetailTests
    detail = MythicDetailTests(); detail.setUp(); detail.class_fixture()
    detail.runlua('''for i=3,5 do roster[i]={name="示例队员"..i,classID=i%2+1,specID=i%2==0 and 73 or 65}end
      local methods=getmetatable(GameTooltip).__index
      function methods:SetOwner(owner,anchor)self.owner=owner;self.anchor=anchor;self.preview={}end
      function methods:AddLine(line)self.preview[#self.preview+1]={line}end
      function methods:AddDoubleLine(left,right)self.preview[#self.preview+1]={left,right}end''')
    detail.open()
    image = Image.new('RGB', (920*scale, 360*scale), colors['bg'])
    draw = ImageDraw.Draw(image)
    text(24,16,'悬停提示 · 精简双列',22)
    text(24,49,'v'+VERSION+' / 离线示意，非游戏截图 / 示例队员',11,'muted')
    for column, (target, caption) in enumerate([('c.tiles[1]','副本卡片'),('c.rows[2]','本周记录')]):
        detail.runlua(f'{target}:GetScript("OnEnter")({target})')
        tooltip = detail.lua.globals().GameTooltip
        lines = list(tooltip.preview.values())
        x,y,w=24+column*450,100,422
        text(x,77,caption,12,'muted')
        rect((x,y,x+w,y+40+len(lines)*21),'card')
        text(x+12,y+8,tooltip.GetText(tooltip),15)
        for i,line in enumerate(lines):
            yy=y+35+i*21
            text(x+12,yy,line[1],12)
            if line[2] is not None:
                right=str(line[2]);plain=re.sub(r'\|cff[0-9a-fA-F]{6}|\|r','',right)
                width=draw.textlength(plain,font=font(12))/scale
                text(x+w-12-width,yy,right,12,'muted')
    target=ROOT/'docs/previews/mythicplus-tooltip.png'
    image.save(target);print(target)

if __name__=='__main__':main()