"""Run the production camera-angle helper and capture lifecycle in real Lua 5.4."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / "onimusha_mc.lua").read_text(encoding="utf-8-sig")
fragment = source[source.index("local function camera_angles_from_look("):source.index("-- Traverse only live object references.")]
lua = LuaRuntime(unpack_returned_tuples=True)
run = lua.execute(r"""
local state={active=false,frame=1}
local reads=0
local function attempt(fn) local ok,value=pcall(fn);if ok then return value end end
local function call(obj,name) reads=reads+1;return obj[name](obj) end
""" + fragment + r"""
return function()
 local origin={x=0,y=0,z=0}
 local function check(target,yaw,pitch,previous)
  local angles,err=camera_angles_from_look(origin,target,previous)
  assert(angles,err)
  assert(math.abs(((angles.yaw-yaw+180)%360)-180)<0.000001)
  assert(math.abs(angles.pitch-pitch)<0.000001)
 end
 check({x=0,y=0,z=-1},0,0)
 check({x=0,y=0,z=1},180,0)
 check({x=1,y=0,z=0},-90,0)
 check({x=-1,y=0,z=0},90,0)
 check({x=1,y=1,z=-1},-45,-35.264389682754654)
 print('PASS RE axis directions convert to MC yaw/pitch')
 check({x=0,y=1,z=0},37,-90,37)
 check({x=0,y=-1,z=0},-52,90,-52)
 assert(not camera_angles_from_look(origin,{x=0,y=1,z=0}))
 print('PASS vertical view preserves verified yaw or refuses first capture')
 for _,point in ipairs({{x=0/0,y=0,z=1},{x=math.huge,y=0,z=1},
   {x=0,y=-math.huge,z=1},{x=0,y=0,z=0},{x=0,y=0,z=0.000000001}}) do
  assert(not camera_angles_from_look(origin,point))
 end
 assert(not camera_angles_from_look({x=-1e308,y=0,z=0},{x=1e308,y=0,z=0}))
 assert(not camera_angles_from_look(nil,{x=1,y=0,z=0}))
 check({x=1e308,y=0,z=-1e308},-45,0)
 print('PASS non-finite, missing and zero directions fail; finite normalization avoids overflow')
 state.camera_transform={get_position=function() reads=reads+1;return origin end}
 local look={x=1,y=0,z=0}
 state.camera={get_LookAtPosition=function() return look end}
 assert(refresh_camera_baseline() and state.host_camera_angles.yaw==-90)
 local count=reads
 state.active=true;look={x=-1,y=0,z=0}
 assert(refresh_camera_baseline() and reads==count and state.host_camera_angles.yaw==-90)
 state.active=false
 assert(refresh_camera_baseline() and state.host_camera_angles.yaw==90)
 look=origin
 assert(not refresh_camera_baseline() and not state.host_camera_angles and not state.host_camera_diagnostic.valid)
 print('PASS active baseline frozen; inactive recaptures and invalid view clears readiness')
end
""")
run()
print("CAMERA_BASELINE_REGRESSION_OK")
