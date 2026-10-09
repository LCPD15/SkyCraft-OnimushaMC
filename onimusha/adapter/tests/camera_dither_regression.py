"""Execute the production late-update hook: one-frame camera request, no global fade override."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
source=(Path(__file__).resolve().parents[1]/'onimusha_mc.lua').read_text(encoding='utf-8-sig')
start=source.index("    local dither=td('app.mcCamSys_DitherDepth')")
end=source.index('\n    end', source.index('        end,function(retval)',start))+8
LuaRuntime().execute(r'''
local state={active=false,frame=9,hooks={}}
local pre,post,requests
local function td(_) return {get_method=function(_,n)
 assert(n=='onLateUpdateEnd');return {get_function=function() return 123 end} end} end
local function typename(o) return o.type end
local function strictcall(o,n,t,e) assert(n=='requestDisable(System.Single, via.curve.EaseType)')
 assert(t==0 and e==0);if o.fail then error('SDK failure') end;requests=requests+1 end
sdk={to_managed_object=function(o) return o end,hook=function(_,a,b) pre=a;post=b end}
requests=0
''' + source[start:end] + r'''
local obj={type='app.mcCamSys_DitherDepth'}
assert(pre({[2]=obj})==nil and post(99)==99 and requests==0)
state.active=true;assert(pre({[2]=obj})==nil and post(99)==99 and requests==1)
assert(state.hooks.camera_dither.last_request_frame==9)
state.active=false;pre({[2]=obj});assert(requests==1)
state.active=true;pre({[2]={type='wrong'}});assert(requests==1 and state.hooks.camera_dither.error)
obj.fail=true;assert(pre({[2]=obj})==nil and post(42)==42)
print('PASS only active takeover requests one-frame distance dither suppression; original executes on success/error/off')
''')
