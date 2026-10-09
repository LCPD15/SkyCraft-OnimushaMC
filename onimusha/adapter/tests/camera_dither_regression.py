"""Production camera consumer scope: disable/readback, original call, exact restoration and retries."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
source=(Path(__file__).resolve().parents[1]/'onimusha_mc.lua').read_text(encoding='utf-8-sig')
start=source.index("    local dither=td('app.mcCamSys_DitherDepth')")
end=source.index('\n    end', source.index('        end,function(retval)',start))+8
restore=source[source.index('local function restore_camera_dither()'):source.index('local function restoration_pending()')]
LuaRuntime().execute(r'''
local state={active=false,frame=9,hooks={}}
local pre,post,writes
local function td(_) return {get_method=function(_,n)
 assert(n=='onLateUpdateEnd');return {get_function=function() return 123 end} end} end
local function typename(o) return o.type end
local function strictcall(o,n,v,t,e)
 if n=='get_IsEnable' then return o.enabled or o.transition end
 assert(n=='setEnable(System.Boolean, System.Single, via.curve.EaseType)')
 assert(type(v)=='boolean' and t==0 and e==0)
 if v and o.fail_restore then error('temporary restore failure') end
 if o.silent then return end
 writes=writes+1;o.enabled=v;o.transition=true
end
sdk={to_managed_object=function(o) return o end,hook=function(_,a,b) pre=a;post=b end}
writes=0
''' + restore + r'''
local function fail_open() state.active=false;restore_camera_dither() end
''' + source[start:end] + r'''
local obj={type='app.mcCamSys_DitherDepth',enabled=true,get_field=function(self,n)
 if n=='_IsDestroy' then return self.destroyed or false end
 if n=='_Enable' then return self.enabled end
 assert(n=='_CurrentParam');return {get_field=function() return 1 end} end}
assert(pre({[2]=obj})==nil and post(99)==99 and writes==0)
state.active=true;assert(pre({[2]=obj})==nil and not obj.enabled and state.dither_restore.original==true)
assert(strictcall(obj,'get_IsEnable')==true and not state.hooks.camera_dither.error)
obj.transition=false -- original consumer finishes the zero-duration transition
assert(post(99)==99 and obj.enabled and not state.dither_restore)
assert(state.hooks.camera_dither.enabled_during_consumer==false and state.hooks.camera_dither.near_alpha==1)
print('PASS active consumer sees disabled dither and always returns original result; baseline restored')
obj.enabled=false;pre({[2]=obj});obj.transition=false;post(5);assert(not obj.enabled and not state.dither_restore)
state.active=false;local old=writes;pre({[2]=obj});post(1);assert(writes==old)
print('PASS an originally disabled camera stays disabled; inactive callback has no writes')
state.active=true;obj.enabled=true;obj.silent=true;pre({[2]=obj});post(6)
assert(state.hooks.camera_dither.error and not state.dither_restore and obj.enabled);obj.silent=false
pre({[2]={type='wrong'}});post(7);assert(not state.dither_restore)
print('PASS rejected/invalid setter never claims suppression; no baseline mutation from wrong owner')
pre({[2]=obj});obj.fail_restore=true;assert(post(42)==42)
assert(state.dither_restore and not state.active and not obj.enabled)
obj.fail_restore=false;restore_camera_dither();assert(obj.enabled and not state.dither_restore)
state.active=true;pre({[2]=obj});obj.destroyed=true;old=writes;restore_camera_dither()
assert(not state.dither_restore and writes==old)
print('PASS failed restoration closes takeover and retries exact owner; destroyed owner is released without write')
''')
