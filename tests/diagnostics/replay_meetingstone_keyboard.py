"""Read-only replay of an installed AutoHideController keyboard callback.
The WoW combat/taint engine is NOT emulated: only the reported setter restriction.
Original: nonzero exit if the callback attempts the setter under simulated lockdown.
--guard-candidate changes a string only in memory; never writes the addon file.
"""
import argparse
from pathlib import Path
from lupa.lua51 import LuaRuntime

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source',type=Path)
parser.add_argument('--guard-candidate',action='store_true')
args=parser.parse_args()
source=args.source.read_text(encoding='utf-8')
needle='    self:SetPropagateKeyboardInput(not found)'
if args.guard_candidate:
    assert source.count(needle)==1,'Installed source differs; review before applying candidate'
    source=source.replace(needle,'    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not found) end')
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''combat=false;blocked=0
UIParent={};function InCombatLockdown()return combat end
function CreateFrame()return {Hide=function()end,SetScript=function(self,k,fn)self[k]=fn end,
SetPropagateKeyboardInput=function(self,v)
 if combat then blocked=blocked+1;error("ADDON_ACTION_BLOCKED: Frame:SetPropagateKeyboardInput()")end
end}end
controller={};gui={NewClass=function()return controller end};timer={Embed=function()end}
function LibStub(name)if name=="NetEaseGUI-2.0"then return gui else return timer end end
function GetBindingKey()return "ESCAPE"end
''')
lua.execute(source)
failures=0
for combat in [False,True]:
    for key in ['A','ESCAPE']:
        lua.globals().combat=combat
        try:
            lua.execute('controller.ESCHandler.OnKeyDown(controller.ESCHandler,...)',key)
            print('PASS',f'combat={combat}',f'key={key}')
        except Exception as error:
            failures+=1
            print('FAIL',f'combat={combat}',f'key={key}',str(error).splitlines()[0])
print(f'blocked={lua.globals().blocked}; failures={failures}; no toolbox loaded; no files modified')
raise SystemExit(1 if failures else 0)
