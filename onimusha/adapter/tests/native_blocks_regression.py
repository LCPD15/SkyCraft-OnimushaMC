"""Production prefab sink: resource waits, block edits, bounds and context lifetime."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local sequence=100
function object(name, methods)
 sequence=sequence+1;local id=sequence
 return {add_ref=function(self)return self end,get_address=function()return id end,
  get_type_definition=function()return {get_full_name=function()return name end} end,
  call=function(_,m,...)assert(methods[m],name..'.'..m);return methods[m](...)end}
end
objects={};created=0;destroyed=0;userdata_ready=false;prefab_ready=false;standby=false
local prefab=object('via.Prefab',{
 get_Path=function()return 'mod/onimusha_mc/probe/unit_collision.pfb'end,
 set_Standby=function(b)standby=b end,get_Ready=function()return prefab_ready end,
 ['instantiate(via.vec3, via.Folder)']=function(p,folder)
  assert(folder=='folder' and standby);created=created+1
  local b={valid=true,enabled=true,p=p};local go,col,cs
  col=object('via.physics.Collider',{get_Shape=function()return object('via.physics.BoxShape',{})end,
   get_GameObject=function()return go end,get_Ready=function()return true end})
  cs=object('via.physics.Colliders',{get_Ready=function()return true end,getCollidersCount=function()return 1 end,
   ['getCollider(System.UInt32)']=function(i)assert(i==0)return col end,set_Enabled=function(v)b.enabled=v end,get_Enabled=function()return b.enabled end})
  go=object('via.GameObject',{get_Valid=function()return b.valid end,set_Name=function(n)b.name=n end,
   ['getComponent(System.Type)']=function(t)assert(t=='via.physics.Colliders')return cs end})
  b.go=go;objects[#objects+1]=b;return go
 end})
local loader=object('app.user_data.AmuletPrefabHolder',{})
loader.get_field=function(_,name)assert(name=='_BeadsPrefab');return userdata_ready and prefab or nil end
sdk={get_tdb_version=function()return 82 end,create_userdata=function(t,p)
 assert(t=='app.user_data.AmuletPrefabHolder' and p=='mod/onimusha_mc/probe/unit_collision_loader.user');return loader end,
 find_type_definition=function(t)return {get_runtime_type=function()return t end,
  get_method=function(_,m)assert(t=='via.GameObject' and m=='destroy(via.GameObject)')return {
   call=function(_,_,go)for _,b in ipairs(objects)do if b.go==go then assert(not b.enabled);destroyed=destroyed+1;b.destroy_requested=true;return end end;error('foreign GO')end}
  end}end}
Vector3f={new=function(x,y,z)return{x=x,y=y,z=z}end}
callbacks={};re={on_application_entry=function(name,fn)assert(name=='LateUpdateBehavior');callbacks.tick=fn end,
 on_script_reset=function(fn)callbacks.reset=fn end};log={error=function(e)last_error=e end}
sample={ready=true,epoch=81,world_id=9,mc_pid=1234,generation=1,revision=1,total=1,truncated=false,cubes={{x=100,y=2,z=3}}}
ctx={bridge={snapshot_full_cubes=function(a)assert(a.radius==16 and a.limit==1280 and a.epoch==ctx.epoch);return sample end},
 units=1,scene=1,epoch=81,world_id=9,mc_pid=1234,generation=1,x=100,y=2,z=3,folder='folder',
 to_native=function(x,y,z)return{x=x-100,y=y,z=z}end}
function advance(n,active)
 for i=1,n do
  if active~=false then onimusha_native_blocks.update(ctx)end
  callbacks.tick()
 end
end
function finish_destruction()for _,b in ipairs(objects)do if b.destroy_requested then b.valid=false end end end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_blocks.lua').read_text(encoding='utf-8-sig'))
lua.execute(r'''
advance(3);assert(created==0 and onimusha_native_blocks.status().phase=='loading_prefab')
userdata_ready=true;advance(3);assert(created==0 and standby)
prefab_ready=true;advance(2);assert(created==1 and onimusha_native_blocks.status().ready==1)
assert(objects[1].p.x==.5 and objects[1].p.y==2.5 and objects[1].p.z==3.5)
print('PASS asynchronous resource readiness and calibrated unit-box placement')
local result=onimusha_native_blocks.query_terrain(function()
 assert(not objects[1].enabled);return 'native scene only'
end)
assert(result=='native scene only' and objects[1].enabled)
local ok=pcall(onimusha_native_blocks.query_terrain,function()assert(not objects[1].enabled);error('query failed')end)
assert(not ok and objects[1].enabled)
objects[1].enabled=false
onimusha_native_blocks.query_terrain(function()assert(not objects[1].enabled)end)
assert(not objects[1].enabled);objects[1].enabled=true
print('PASS terrain query masks only owned MC collision, restores after exceptions and preserves predisabled state')
advance(12);assert(created==1)
sample.cubes={};sample.total=0;sample.revision=2;advance(6)
assert(destroyed==1 and not objects[1].enabled and onimusha_native_blocks.busy(),tostring(destroyed)..' '..tostring(objects[1].enabled)..' '..tostring(last_error))
finish_destruction();advance(12);assert(not onimusha_native_blocks.busy())
print('PASS repeated snapshots do not duplicate; removal/explosion retires exact owned collider')
sample.cubes={{x=101,y=2,z=3}};sample.total=1;advance(7);assert(created==2)
sample.epoch=80;advance(6);assert(destroyed==2 and onimusha_native_blocks.status().count==0)
finish_destruction();advance(12,false)
print('PASS stale producer snapshot destroys old collision instead of reusing a foreign epoch')
sample.epoch=81;sample.cubes={};for i=1,1280 do sample.cubes[i]={x=i,y=2,z=3}end;sample.total=5000;sample.truncated=true
advance(680);assert(onimusha_native_blocks.status().count==1280 and onimusha_native_blocks.status().truncated)
local before=created;advance(12);assert(created==before)
sample.cubes={};for i=1,1280 do sample.cubes[i]={x=i+4096,y=2,z=3}end
advance(6);assert(onimusha_native_blocks.status().count==0 and created==before)
finish_destruction();advance(12);assert(created>before and created-before<=24)
print('PASS live plus deferred objects stay bounded; nearest-set changes cannot spike allocations')
onimusha_native_blocks.stop();assert(onimusha_native_blocks.status().count==0)
finish_destruction();advance(12,false);assert(not onimusha_native_blocks.busy() and not standby)
print('PASS F10 suspension disables collision before destroy and releases prefab after retirement')
sample.cubes={{x=100,y=2,z=3}};sample.total=1;sample.truncated=false;advance(3)
assert(onimusha_native_blocks.status().count==1)
advance(2,false);assert(onimusha_native_blocks.status().count==0)
finish_destruction();advance(12,false)
print('PASS a stopped host tick cannot leave orphaned colliders')
ctx.units=2;advance(2);assert(onimusha_native_blocks.status().phase=='unsupported_runtime' and onimusha_native_blocks.status().count==0)
ctx.units=1;sample.cubes={{x=0/0,y=0,z=0}};advance(2);assert(last_error and onimusha_native_blocks.status().count==0)
before=created;advance(8);assert(created==before)
print('PASS unsupported scale and malformed snapshots fail closed without retry-allocation loops')
ctx.epoch=82;sample.epoch=82;sample.cubes={{x=100,y=2,z=3}};advance(3)
assert(onimusha_native_blocks.status().count==1)
callbacks.reset();finish_destruction();advance(12,false)
assert(onimusha_native_blocks==nil)
print('PASS new session can recover; script reset retires only owned objects')
''')
