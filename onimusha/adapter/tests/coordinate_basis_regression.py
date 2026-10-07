"""Verify the production identity-XYZ conversion, camera handedness and F5 pose in Lua 5.4."""
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime

adapter = Path(__file__).resolve().parents[1]
source = (adapter / "onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua = LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
print("LUA54_COMPLETE_SYNTAX_OK")
views = source[source.index("local function camera_angles_from_look("):source.index("-- Traverse only live object references.")]
positions = source[source.index("local function mcpos("):source.index("local function new_object(")]
collision = source[source.index("local function collision_counters("):source.index("local function create_direct_box(")]
run = lua.execute(r"""
local cfg={units_per_block=2.5,collision_radius=16,collision_triangles_per_frame=2,collision_max_triangles=100}
local state={tile={x=8192,z=-24576},world_key='test',frame=1}
local function invalidate_collision_coverage() error('Unexpected collision context invalidation') end
Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
local function close(a,b) assert(math.abs(a-b)<0.00000001,tostring(a)..' != '..tostring(b)) end
local function close3(a,b) close(a.x,b.x);close(a.y,b.y);close(a.z,b.z) end
local function difference(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function normalized(v)
 local n=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
 return {x=v.x/n,y=v.y/n,z=v.z/n}
end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function forward(yaw,pitch)
 local y,p=math.rad(yaw),math.rad(pitch)
 return {x=-math.sin(y)*math.cos(p),y=-math.sin(p),z=math.cos(y)*math.cos(p)}
end
local function mc_right(yaw)
 local y=math.rad(yaw);return {x=-math.cos(y),y=0,z=-math.sin(y)}
end
-- Decode the camera's local -Z and +X using its produced Y-yaw/X-pitch Euler pose.
local function native_basis(rotation)
 local y,p=math.rad(rotation.yaw),math.rad(rotation.pitch)
 return {x=-math.sin(y)*math.cos(p),y=math.sin(p),z=-math.cos(y)*math.cos(p)},
        {x=math.cos(y),y=0,z=-math.sin(y)}
end
""" + views + positions + collision + r"""
return function()
 for _,scale in ipairs({0.25,1,2.5}) do
  cfg.units_per_block=scale
  local p={x=23.125,y=-0.625,z=-31.75}
  local m=mcpos(p)
  close(m.x,state.tile.x+p.x/scale);close(m.z,state.tile.z+p.z/scale)
  close3(repos(m.x,m.y,m.z),p)
  local moved=mcpos({x=p.x+3,y=p.y+2,z=p.z+7})
  close3(difference(moved,m),{x=3/scale,y=2/scale,z=7/scale})
 end
 print('PASS production XYZ positions and displacements roundtrip with nonzero tiles and three scales')
 cfg.units_per_block=2.5
 for _,yaw in ipairs({-179,-90,0,45,179}) do
  for _,pitch in ipairs({-60,0,60}) do
   local f,r=forward(yaw,pitch),mc_right(yaw)
   local angles=camera_angles_from_look({x=0,y=0,z=0},f)
   close(((angles.yaw-yaw+180)%360)-180,0);close(angles.pitch,pitch)
   local rotation=assert(native_camera_rotation_from_mc(angles.yaw,angles.pitch,-1,true))
   local native_f,native_r=native_basis(rotation)
   local origin=repos(0,0,0)
   local re_f=normalized(difference(repos(f.x,f.y,f.z),origin))
   local re_r=normalized(difference(repos(r.x,r.y,r.z),origin))
   close3(native_f,re_f);close3(native_r,re_r)
   close(dot(native_r,re_r),1);close(dot(native_r,{x=-re_r.x,y=-re_r.y,z=-re_r.z}),-1)
   local turned=forward(yaw+0.001,pitch)
   assert(dot(normalized(difference(turned,f)),native_r)>0.99999999)
  end
 end
 print('PASS fifteen heading/slope cases preserve forward, D/right, A/left and positive-yaw screen direction')
 for _,yaw in ipairs({-90,0,45,179}) do
  local native_yaw=assert(native_player_yaw_from_mc(yaw));local y=math.rad(native_yaw)
  close3({x=math.sin(y),y=0,z=math.cos(y)},forward(yaw,0))
 end
 print('PASS hidden native local +Z player faces the same horizontal forward as Minecraft')
 local mc={eye_x=8215.25,eye_y=2.75,eye_z=-24577.5,yaw=45,pitch=30,camera_distance=4}
 local f=forward(mc.yaw,mc.pitch)
 for mode=0,2 do
  mc.camera_mode=mode
  local eye=assert(mc_camera_eye(mc));local sign=mode==0 and 0 or mode==1 and -1 or 1
  close3(eye,{x=mc.eye_x+f.x*4*sign,y=mc.eye_y+f.y*4*sign,z=mc.eye_z+f.z*4*sign})
  close3(mcpos(repos(eye.x,eye.y,eye.z)),eye)
  local rotation=assert(native_camera_rotation_from_mc(eye.yaw,eye.pitch,-1,true))
  local native_f,native_r=native_basis(rotation);local direction=mode==2 and -1 or 1
  close3(native_f,{x=f.x*direction,y=f.y*direction,z=f.z*direction})
  local r=mc_right(mc.yaw);close3(native_r,{x=r.x*direction,y=0,z=r.z*direction})
 end
 mc.camera_mode=1;mc.camera_distance=100
 local eye=assert(mc_camera_eye(mc));close3(eye,{x=mc.eye_x-f.x*32,y=mc.eye_y-f.y*32,z=mc.eye_z-f.z*32})
 print('PASS all three F5 eye offsets, view directions, right directions and RE/MC roundtrips agree')
 assert(not native_camera_rotation_from_mc(0,0,-1,false))
 assert(not native_camera_rotation_from_mc(0,0,1,true))
 assert(not native_camera_rotation_from_mc(0,0,nil,true))
 assert(not native_camera_rotation_from_mc(0/0,0,-1,true))
 assert(not native_camera_rotation_from_mc(0,91,-1,true))
 assert(not native_player_yaw_from_mc(math.huge))
 mc.camera_mode=3;assert(not mc_camera_eye(mc))
 mc.camera_mode=0;mc.eye_x=math.huge;assert(not mc_camera_eye(mc))
 print('PASS unknown or unsupported camera axes and malformed angles/eyes never become a calibrated pose')
 local function cross(a,b)
  return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x}
 end
 local vertices={{x=3,y=2,z=-5},{x=7,y=3,z=-5},{x=3,y=5,z=1}}
 local native_normal=cross(difference(vertices[2],vertices[1]),difference(vertices[3],vertices[1]))
 local centre={x=23.125,y=2.625,z=-31.75}
 state.epoch=42
 local native={connected=true,mc_pid=10,collision_epoch=42,collision_ring_valid=true,collision_generation=1,
  collision_publish_seq=0,collision_consumed_seq=0,collision_ready=false}
 local job=assert(collision_context(native));state.collision=job
 job.shapes={{vertices=vertices,count=1}};job.shape_index=1;job.triangle_index=0
 job.triangles={};job.centre=centre;job.unsupported=0;job.complete_query=true;job.max_triangles=100
 local mapped=mcpos(centre);job.bounds={}
 for _,axis in ipairs({'x','y','z'}) do
  job.bounds['min_'..axis]=math.floor((mapped[axis]-cfg.collision_radius)/8)*8
  job.bounds['max_'..axis]=math.ceil((mapped[axis]+cfg.collision_radius)/8)*8
 end
 local published
 advance_collision({publish_collision_tris=function(region) published=region;native.collision_publish_seq=1;return true end,
   status=function() return native end},native)
 assert(published and published.epoch==42 and #published.triangles==1)
 assert(state.collision==nil and state.collision_pending and not state.collision_ready)
 native.collision_consumed_seq=1;native.collision_ready=true;reconcile_collision(native)
 assert(state.collision==nil and state.collision_ready and state.collision_count==1)
 local triangle=published.triangles[1];assert(triangle.flags==0)
 local exported={}
 for i,letter in ipairs({'a','b','c'}) do
  exported[i]={x=triangle[letter..'x'],y=triangle[letter..'y'],z=triangle[letter..'z']}
  close3(exported[i],mcpos(vertices[i]))
 end
 local exported_normal=cross(difference(exported[2],exported[1]),difference(exported[3],exported[1]))
 local scale_squared=cfg.units_per_block*cfg.units_per_block
 close3(exported_normal,{x=native_normal.x/scale_squared,y=native_normal.y/scale_squared,z=native_normal.z/scale_squared})
 assert(dot(native_normal,exported_normal)>0)
 local mapped_centre=mcpos(centre)
 close(published.min_x,math.floor((mapped_centre.x-cfg.collision_radius)/8)*8)
 close(published.max_x,math.ceil((mapped_centre.x+cfg.collision_radius)/8)*8-1)
 close(published.min_y,math.floor((mapped_centre.y-cfg.collision_radius)/8)*8)
 close(published.max_y,math.ceil((mapped_centre.y+cfg.collision_radius)/8)*8-1)
 close(published.min_z,math.floor((mapped_centre.z-cfg.collision_radius)/8)*8)
 close(published.max_z,math.ceil((mapped_centre.z+cfg.collision_radius)/8)*8-1)
 print('PASS actual collision exporter preserves A/B/C and surface normal with nonzero tile/scale and region readiness')
 for _,case in ipairs({{radius=8,blocks=4},{radius=16,blocks=8},{radius=32,blocks=12},{radius=64,blocks=12}}) do
  cfg.collision_radius=case.radius
  for _,scale in ipairs({0.25,1,2.5}) do
   cfg.units_per_block=scale
   close(collision_resample_distance(),case.blocks*scale)
   assert(case.radius-collision_resample_distance()/scale>=case.radius*0.5)
   close(collision_vertical_resample_distance(),math.min(case.blocks,math.max(0,(case.radius-12)*0.5))*scale)
  end
 end
 print('PASS production resampling threshold retains at least half-radius margin at three unit scales')
end
""")
run()
for path in sorted((adapter.parent / "config").glob("onimusha_mc_config*.json")):
    config = json.loads(path.read_text(encoding="utf-8-sig"))
    assert (config["camera_yaw_sign"], config["camera_yaw_offset"], config["camera_pitch_sign"]) == (-1, 180, -1), path
    assert config["collision_radius"] == 16, path
assert "collision_radius=16," in source[source.index("local defaults = {"):source.index("local function read_config(")]
print("PASS all default/A/B/C configs use verified local -Z camera conversion and 16-block collision radius")
print("COORDINATE_BASIS_REGRESSION_OK 8 actual-production Lua/config cases")
