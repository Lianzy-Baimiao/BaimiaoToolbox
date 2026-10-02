"""Offline marker toolbar schematic; no game textures or live account data."""
from test_marker_assist import MarkerAssistTests
from render_workspace_preview import Canvas, labels, VERSION

def main():
    case=MarkerAssistTests();case.setUp();g=case.lua.globals();bar=g.b
    c=Canvas(720,364,g.ns.UI.palette)
    c.text(20,12,'标记助手 · 三行按需启用',20)
    c.text(20,44,'v'+VERSION+' / 离线示意，非游戏截图；标记图标以编号占位',11,'muted')
    def toolbar(x,y,caption,settings):
        case.runlua(settings+';M.Refresh()')
        c.text(x,y-25,caption,12,'muted')
        c.rect(x,y,bar.w,bar.h)
        for _,f in labels(case,bar).items():
            if f.IsShown(f):c.label(f,x,y)
        for group in (bar.targets,bar.worlds):
            for i,b in group.items():
                if b.IsShown(b):c.button(x+b.point[2],y-b.point[3],b.w,b.h,str(i) if i<=8 else '×')
        for _,b in bar.children.items():
            if b.kind=='Button' and b.IsShown(b) and (b.attributes is None or b.attributes.type is None):
                bx=x+b.point[2] if b.point[1]=='TOPLEFT' else x+bar.w+b.point[2]-b.w
                c.button(bx,y-b.point[3],b.w,b.h,b.GetText(b))
    toolbar(20,102,'全部启用 · 314 × 118','d.showTargets=true;d.showWorlds=true;d.showManagement=true')
    toolbar(366,102,'仅地面标记 · 314 × 60','d.showTargets=false;d.showWorlds=true;d.showManagement=false')
    toolbar(366,218,'仅团队管理 · 314 × 60','d.showTargets=false;d.showWorlds=false;d.showManagement=true')
    c.text(20,312,'关闭即收紧，不留空行；三行全关时隐藏整条工具栏。',12,'muted')
    c.text(20,337,'保留原生倒数与安全标记；战斗中布局变更延后到脱战。',11,'muted')
    c.save('marker-assist.png')

if __name__=='__main__':main()
