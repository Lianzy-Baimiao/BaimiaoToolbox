"""Offline settings schematic driven by real controls; not a WoW screenshot."""
from render_workspace_preview import Canvas, labels, VERSION
from test_workspace import WorkspaceTests

def draw_panel(c, case, panel, ox, oy):
    c.rect(ox,oy,panel.GetWidth(panel),panel.GetHeight(panel),'bg')
    for _,f in panel.children.items():
        if f.kind=='Frame' and f.points and f.points.TOPLEFT and f.points.TOPRIGHT:
            p=f.points.TOPLEFT
            if isinstance(p[2],(int,float)):
                c.rect(ox+p[2],oy-p[3],panel.GetWidth(panel)-16,f.h)
    for _,f in labels(case,panel).items():
        if f.point and isinstance(f.point[2],(int,float)):
            c.label(f,ox,oy)
        elif f.point and f.point[1]=='LEFT' and f.point[2].kind=='FontString':
            title=f.point[2]
            width=c.draw.textlength(title.GetText(title),font=c.font(title.fontSize or 12))/c.scale
            c.text(ox+title.point[2]+width+8,oy-title.point[3],f.GetText(f),11,'accent')
    for _,f in panel.children.items():
        if not f.point or not isinstance(f.point[2],(int,float)):continue
        x,y=ox+f.point[2],oy-f.point[3]
        if f.kind=='CheckButton':
            checked=f.GetChecked(f);role='accent' if checked else 'rail'
            c.rect(x,y,f.w,f.h,role,'accent' if checked else 'border')
            knob='bg' if checked else 'muted'
            c.rect(x+f.thumb.point[4],y+3,f.thumb.w,f.thumb.h,knob,knob)
            label=f.label.GetText(f.label)
            assert c.draw.textlength(label,font=c.font(f.label.fontSize))/c.scale <= f.label.GetWidth(f.label), label
            c.text(x+f.w+8,y,label,f.label.fontSize)
        elif f.sw:
            rgb=tuple(round(f.sw.colorTexture[i]*255) for i in range(1,4))
            c.colors['swatch']=rgb;c.rect(x,y,f.w,f.h,'swatch')
            for _,label in labels(case,f).items():c.text(x+30,y+5,label.GetText(label),12)
        elif f.kind=='Button':
            c.button(x,y,f.w,f.h,f.GetText(f))
        elif f.kind=='Frame':
            for _,s in f.children.items():
                if s.kind!='Slider':continue
                c.button(x,y,22,22,'−');c.rect(x+30,y+7,s.w,8,'rail')
                frac=(s.GetValue(s)-s.min)/(s.max-s.min)
                c.rect(x+30,y+7,max(1,s.w*frac),8,'accent','accent')
                c.rect(x+30+s.w*frac-5,y+1,10,20,'accent','accent')
                c.button(x+30+s.w+8,y,22,22,'+')
                value=s.GetValue(s);value=int(value) if value==int(value) else value
                c.button(x+30+s.w+42,y,56,22,str(value))

def main():
    case=WorkspaceTests()
    case.initial_lua='local m=getmetatable(UIParent).__index;function m:SetColorTexture(...)self.colorTexture={...}end'
    case.setUp();g=case.lua.globals()
    c=Canvas(1532,530,g.ns.UI.palette)
    c.text(20,10,'设置页 · 同类选项并排',20)
    c.text(20,42,'v'+VERSION+' / 离线布局示意，非游戏截图；保留 26×14 开关、13 号标签与原有设置值',11,'muted')
    c.text(20,80,'坐标喊话 · 屏幕显示',16,'accent')
    c.text(778,80,'小工具集合',16,'accent')
    draw_panel(c,case,g.ns.modules.coordshout.optionTabs.pages[1].panel,20,116)
    draw_panel(c,case,g.ns.modules.smalltools._syncLayout.panel,778,116)
    c.save('settings-rows.png')

if __name__=='__main__':main()
