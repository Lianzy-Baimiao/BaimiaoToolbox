"""Offline schematics from real Lua geometry, NOT game screenshots.
Run python tests/render_workspace_preview.py (Pillow/lupa and msyh.ttc).
"""
import re
from PIL import Image, ImageDraw, ImageFont
from test_workspace import WorkspaceTests, ROOT

VERSION = re.search(r"^## Version: (.+)$", (ROOT/'BaimiaoToolbox.toc').read_text(encoding='utf-8'), re.M).group(1)

class Canvas:
    scale = 2
    def __init__(self, width, height, palette):
        self.palette(palette)
        self.image = Image.new('RGB', (width*self.scale, height*self.scale), self.colors['bg'])
        self.draw = ImageDraw.Draw(self.image)
    def palette(self, palette):
        self.colors = {key: tuple(round(palette[key][i]*255) for i in range(1,4))
                       for key in ('bg','rail','card','border','text','muted','accent','hover')}
    def font(self, size):
        return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', round(size*self.scale))
    def rect(self, x, y, width, height, role='card', border='border'):
        self.draw.rectangle(tuple(round(v*self.scale) for v in (x,y,x+width,y+height)),
                            fill=self.colors[role], outline=self.colors[border], width=self.scale)
    def text(self, x, y, value, size=13, role='text'):
        self.draw.text((round(x*self.scale),round((y+size)*self.scale)), str(value),
                       font=self.font(size),fill=self.colors[role],anchor='ls')
    def right(self, x, y, value, size=13, role='text'):
        self.text(x-self.draw.textlength(value,font=self.font(size))/self.scale,y,value,size,role)
    def button(self, x, y, width, height, value):
        self.rect(x,y,width,height)
        length=self.draw.textlength(value,font=self.font(12))/self.scale
        self.text(x+(width-length)/2,y+(height-12)/2,value,12)
    def label(self, f, x, y):
        self.text(x+f.point[2],y-f.point[3],f.GetText(f),f.fontSize or 12,f._bmTextRole or 'text')
    def save(self, name):
        path=ROOT/'docs/previews'/name
        self.image.save(path);print(path)

def labels(case, parent):
    # Compare inside Lua: Python wrappers are not stable identity handles.
    case.lua.globals().previewParent=parent
    return case.lua.eval('''function() local t={} for _,f in ipairs(frames)do
      if f:GetParent()==previewParent and f:GetObjectType()=="FontString" then t[#t+1]=f end
      end return t end''')()

def home(case):
    g=case.lua.globals();w=g.BaimiaoToolboxWorkspace
    c=Canvas(1040,750,g.ns.UI.palette);ox=20;oy=66
    c.text(20,12,'v'+VERSION+' · 标题保留，功能卡片紧凑',20)
    c.text(20,40,'离线布局示意，非游戏截图；文字和锚点来自实际 Lua，副本图标使用占位',11,'muted')
    c.rect(ox,oy,w.w,w.h,'bg');c.rect(ox,oy+52,w.rail.w,w.h-52,'rail')
    c.text(ox+20,oy+16,'白描工具箱',20)
    c.text(ox+136,oy+22,'BAIMIAO TOOLBOX  /  '+VERSION,10,'muted')
    c.button(ox+w.w-16-60,oy+12,60,28,'关闭')
    c.button(ox+w.w-16-60-8-90,oy+12,90,28,'切换浅色')
    c.text(ox+16,oy+72,'功能导航',13,'muted')
    for index,label in enumerate(['工作台总览']+[m.name for _,m in g.ns.orderedModules.items()]):
        x=ox+12;y=oy+104+44*index
        if index==0:
            c.rect(x,y,168,38,'hover');c.rect(x,y+7,3,24,'accent','accent')
        c.text(x+10,y+13,f'{index+1:02}',10,'muted');c.text(x+38,y+11,label,13)
    c.text(ox+16,oy+w.h-52,'拖动顶栏移动窗口',11,'muted')
    c.text(ox+16,oy+w.h-32,'/bm 打开 · Esc 关闭',11,'muted')
    c.label(w.eyebrow,ox,oy);c.label(w.heading,ox,oy)
    cx=ox+w.content.points.TOPLEFT[2]+2;cy=oy-w.content.points.TOPLEFT[3]+2
    c.rect(cx,cy,738,w.hero.h,'rail')
    for _,f in labels(case,w.hero).items():c.label(f,cx,cy)
    cat=Image.open(ROOT/'media/cat_icon.tga').convert('RGBA').resize((140,140),Image.Resampling.LANCZOS)
    cat.putalpha(cat.getchannel('A').point(lambda a:round(a*.7)))
    c.image.paste(cat,(round((cx+738-25-70)*2),round((cy+(w.hero.h-70)/2)*2)),cat)
    c.label(w.toolsTitle,cx,cy)
    c.right(cx+738+w.summary.point[2],cy-w.summary.point[3],w.summary.GetText(w.summary),12,'muted')
    for _,m in g.ns.orderedModules.items():
        card=m._workspaceStatus.GetParent(m._workspaceStatus);x=cx+card.point[2];y=cy-card.point[3]
        c.rect(x,y,card.w,card.h);c.rect(x+14,y+10,30,30,'hover');c.text(x+22,y+17,'图',12,'accent')
        for _,f in labels(case,card).items():c.label(f,x,y)
        for _,f in card.children.items():
            if f.kind=='Button':
                bx=x+f.point[2] if f.point[1]=='BOTTOMLEFT' else x+card.w+f.point[2]-f.w
                c.button(bx,y+card.h-f.point[3]-f.h,f.w,f.h,f.GetText(f))
    b=w.minimap;y=cy-b.point[3];c.button(cx,y,b.w,b.h,b.GetText(b))
    c.right(cx+736,y+8,'Alt + 右键屏上工具可直达设置',11,'muted')
    c.save('workspace-compact.png')

def switches(case):
    g=case.lua.globals();w=g.BaimiaoToolboxWorkspace
    case.runlua('ns.GetDB("smalltools").multiInvite=false; ns.OpenOptions("smalltools")')
    panel=g.ns.modules.smalltools._syncLayout.panel
    c=Canvas(790,558,g.ns.UI.palette)
    c.text(20,10,'26 × 14 矩形 Switch · 明暗主题',20)
    c.text(20,40,'离线设置局部示意，非游戏截图；演示一开一关，不修改真实游戏配置',11,'muted')
    for theme,oy in [('dark',76),('light',318)]:
        if theme=='light':w.theme.GetScript(w.theme,'OnClick')()
        c.palette(g.ns.UI.palette);c.rect(12,oy,766,224,'bg')
        c.right(752,oy+12,'深色主题' if theme=='dark' else '浅色主题',11,'muted')
        for _,f in panel.children.items():
            if f.kind=='Frame' and f.point and f.point[1]=='TOPRIGHT' and -f.point[3]<150:
                c.rect(28,oy-f.point[3],722,f.h,'card')
        for _,f in labels(case,panel).items():
            if isinstance(f.point[2],(int,float)) and -f.point[3]<150:c.label(f,20,oy)
        for _,f in panel.children.items():
            if f.kind=='CheckButton' and -f.point[3]<150:
                x=20+f.point[2];y=oy-f.point[3];checked=f.GetChecked(f)
                c.rect(x,y,f.w,f.h,'accent' if checked else 'rail','accent' if checked else 'border')
                role='bg' if checked else 'muted'
                c.rect(x+f.thumb.point[4],y+3,f.thumb.w,f.thumb.h,role,role)
                c.text(x+f.w+8,y,f.label.GetText(f.label),f.label.fontSize)
    c.save('workspace-switches.png')

def main():
    case=WorkspaceTests();case.initial_lua='C_AddOns.GetAddOnMetadata=function() return "'+VERSION+'" end'
    case.setUp();case.runlua('ns.OpenOptions()')
    home(case);switches(case)

if __name__=='__main__':main()
