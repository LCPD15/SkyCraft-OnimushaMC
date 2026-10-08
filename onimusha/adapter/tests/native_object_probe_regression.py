"""Exercise the actual isolated native probe lifecycle; no game required."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'onimusha_combat_inventory.lua').read_text(encoding='utf-8-sig')
probe = source[source.index("do\nlocal CONTROL='onimusha_native_object_probe_control.json'"):source.index('-- END NATIVE OBJECT PROBE')]
assert "'hasEffectNodes(System.String)'" not in probe
assert "'via.navigation.AIMapEffector'" not in probe
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local seq=0
function obj(t, methods)
 seq=seq+1;local id=seq
 return {get_address=function() return id end, add_ref=function(self) return self end,
  get_type_definition=function() return {get_full_name=function() return t end} end,
  call=function(_,n,...) assert(methods[n],t..'.'..n);return methods[n](...) end}
end
function call(o,n,...) assert(o,n);return o:call(n,...) end
function typ(o) return o and o:get_type_definition():get_full_name() end
function snapshot() return {} end
Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end};Vector4f=Vector3f
ValueType={new=function() return {set_field=function() end} end}
local filter=obj('filter',{get_Layer=function() return 1 end,get_Group=function() return 0 end,
 get_SubGroup=function() return 0 end,get_IgnoreSubGroup=function() return 0 end,get_MaskBits=function() return 0 end})
local cc=obj('cc',{get_FilterInfo=function() return filter end})
local folder=obj('folder',{get_Path=function() return 'test' end})
local player_go=obj('via.GameObject',{
 get_Transform=function() return {get_position=function() return {x=0,y=0,z=0} end} end,
 get_Folder=function() return folder end,
 ['getComponent(System.Type)']=function(t) assert(t=='via.physics.CharacterController');return cc end})
local player=obj('player',{get_GameObject=function() return player_go end})
local info=obj('info',{get_Character=function() return player end})
local pm=obj('pm',{isPlayerReady=function() return true end,getControllingPlayerInfo=function() return info end})
paused=false
local pause=obj('app.PauseManager',{get_IsMenuPause=function() return paused end,get_IsPlayerPause=function() return paused end})
scene=obj('scene',{});enabled=false;prefab_ready=false;mesh_ready=false;hit_own=false
control={enabled=true,id='physics1',action='physics_cube'}
instantiations=0;render_creates=0;resources={};destroys=0;standby=false;valid=false;draw=false;collider_enabled=true;nav_enabled=false
local loaded_stem='unit_collision'
local maps={'AIMap_Zako','AIMap_MidBoss','AIMap_Boss','AIMap_Water'}
local nav=obj('via.navigation.AIMapEffector',{
 getMapNamesCount=function() return 4 end,['getMapNames(System.UInt32)']=function(i) return maps[i+1] end,
 ['hasEffectNodes(System.String)']=function() return true end,get_Enabled=function() return nav_enabled end,
 set_Enabled=function(b) nav_enabled=b end,get_Affected=function() return true end,
 getEffectType=function() return 1 end,getShapeType=function() return 2 end,get_Fixed=function() return false end})
local shape=obj('via.physics.BoxShape',{})
local go,col,cs,mesh
local other=obj('via.physics.Collider',{})
col=obj('via.physics.Collider',{get_Shape=function() return shape end,get_GameObject=function() return go end,
 get_Ready=function() return true end,get_FilterInfo=function() return filter end,get_Enabled=function() return collider_enabled end})
cs=obj('via.physics.Colliders',{getCollidersCount=function() return 1 end,get_Ready=function() return true end,
 ['getCollider(System.UInt32)']=function() return col end,get_BoundingAabb=function() return {} end,
 set_Enabled=function(b) collider_enabled=b end,get_Enabled=function() return collider_enabled end})
mesh=obj('via.render.Mesh',{set_Enabled=function() end,set_StaticMesh=function() end,setMesh=function() end,
 set_Material=function() end,set_RenderOutputID=function() end,set_DrawShadowCast=function() end,
 get_MeshReady=function() return mesh_ready end,get_MaterialReady=function() return mesh_ready end,
 get_MaterialNum=function() return 1 end,get_Enabled=function() return true end,
 get_RenderOutputID=function() return 31 end,get_DrawShadowCast=function() return true end,get_WorldAABB=function() return {} end})
go=obj('via.GameObject',{get_Valid=function() return valid end,set_Name=function() end,set_DrawSelf=function(b) draw=b end,
 get_Transform=function() return {set_position=function(_,p) last_position=p end} end,
 get_Draw=function() return draw end,get_Update=function() return true end,get_Folder=function() return folder end,
 ['getComponent(System.Type)']=function(t)
  if t=='via.navigation.AIMapEffector' then return nav end
  assert(t=='via.physics.Colliders');return cs
 end,
 ['createComponent(System.Type)']=function(t) assert(t=='via.render.Mesh');return mesh end})
local prefab=obj('via.Prefab',{get_Path=function() return 'mod/onimusha_mc/probe/'..loaded_stem..'.pfb' end,
 set_Standby=function(b) standby=b end,get_Ready=function() return prefab_ready end,
 ['instantiate(via.vec3, via.Folder)']=function(p,f)
  assert(prefab_ready and f==folder and p.x==3 and p.y==.55 and p.z==3)
  instantiations=instantiations+1;valid=true;collider_enabled=true;nav_enabled=loaded_stem=='unit_navigation';return go
 end})
local area_result=obj('area_result',{get_NumTriangles=function() return 0 end})
local ray_result=obj('ray_result',{get_NumContactPoints=function() return 1 end,get_Finished=function() return true end,
 ['getContactCollidable(System.UInt32)']=function() return hit_own and col or other end})
_G.onimusha_mc={status=function() return {enabled=enabled} end}
json={load_file=function(path)
 if path=='onimusha_mc/unit_collision_loader.json' then
  local a={82,83,90,0};for i=5,170 do a[i]=0 end;return a
 end
 return control
end,dump_file=function(_,r) status=r end}
re={on_application_entry=function(_,fn) tick=fn end,on_script_reset=function(fn) reset=fn end}
sdk={get_tdb_version=function() return 82 end,get_managed_singleton=function(t) if t=='app.PauseManager' then return pause end;return pm end,
 get_native_singleton=function(t) return t end,
 call_native_func=function(_,_,name)
  if name=='get_CurrentScene' then return scene end
  if name=='getAreaPrimitive' then return area_result end
  if name=='castRay' then return ray_result end
  error(name)
 end,
 create_userdata=function(t,p)
  loaded_stem=p:match('^mod/onimusha_mc/probe/(%w+_%w+)_loader%.user$')
  assert(t=='app.user_data.AmuletPrefabHolder' and (loaded_stem=='unit_collision' or loaded_stem=='unit_navigation'))
  local loader=obj(t,{})
  loader.get_field=function(_,n) assert(n=='_BeadsPrefab');return prefab end
  return loader
 end,
 create_instance=function(t)
  local methods={set_Area=function() end,set_FilterInfo=function() end,copyFilterInfo=function(f) assert(f==filter) end,
   enableAllHits=function() end,enableNearSort=function() end,
   get_Ray=function() return {} end,get_RayDistance=function() return 4 end,
   ['setRay(via.vec3, via.vec3)']=function(a,b) assert(b.x-a.x==4 and b.y==a.y and b.z==a.z) end}
  return obj(t,methods)
 end,
 create_resource=function(t,p) resources[#resources+1]=p;return {add_ref=function() end,release=function() end,
  create_holder_global=function() return obj('holder',{}) end} end,
 find_type_definition=function(t) return {get_runtime_type=function() return t end,get_method=function(_,m)
  if t=='via.GameObject' and m=='create(System.String, via.Folder)' then
   return {call=function(_,_,name,f) assert(f==folder);render_creates=render_creates+1;valid=true;return go end}
  end
  assert(t=='via.GameObject' and m=='destroy(via.GameObject)')
  return {call=function(_,_,o) assert(o==go and not collider_enabled and not nav_enabled);destroys=destroys+1;valid=false end}
 end} end}
function frames(n) for _=1,n do tick() end end
''')
lua.execute(probe)
lua.execute(r'''
tick();assert(status.phase=='loading_userdata' and instantiations==0)
frames(60);assert(instantiations==0)
print('PASS prefab readiness gates instantiation')
prefab_ready=true;frames(2);assert(instantiations==1 and not draw)
mesh_ready=true;frames(32)
assert(draw and status.phase=='checking_collision' and not status.ready and not status.collision.registered)
print('PASS other native ray hits do not prove registration')
hit_own=true;frames(30)
assert(status.phase=='visible_collision_verified' and status.ready and status.collision.registered)
print('PASS exact owned collider hit proves ray registration')
control={enabled=true,id='remove1',action='remove'};frames(42)
assert(destroys==1 and status.destroyed and not valid and not standby and not collider_enabled)
print('PASS remove disables collision and waits for deferred destruction')
prefab_ready=false;control={enabled=true,id='physics2',action='physics_cube'};frames(30)
enabled=true;tick();assert(status.phase=='removed_guard' and not standby and status.destroyed and instantiations==1)
print('PASS takeover aborts pending prefab load without spawning')
enabled=false;control={enabled=true,id='physics3',action='physics_cube'};frames(30)
scene=obj('scene2',{});tick();assert(status.phase=='removed_guard' and not standby)
print('PASS scene change aborts pending prefab load')
control={enabled=true,id='physics4',action='physics_cube'};frames(30)
prefab_ready=true;frames(12);assert(instantiations==2 and valid)
reset();assert(destroys==2 and not valid and not collider_enabled)
print('PASS script reset destroys only its owned probe object')
frames(12);control={enabled=true,id='navigation1',action='navigation_cube'};frames(60)
assert(status.phase=='failed' and status.error:find('Unsupported probe action') and instantiations==2)
control={enabled=true,id='remove-nav',action='remove'};frames(45)
assert(status.destroyed and not nav_enabled and not collider_enabled)
print('PASS quarantined navigation action is refused before allocating any object')
local old_resources=#resources
control={enabled=true,id='bad-section',action='render_section',asset_id='../not-owned',section_min={x=1,y=2,z=3}};frames(30)
assert(status.phase=='failed' and #resources==old_resources and render_creates==0)
print('PASS section resource paths cannot escape the private asset directory')
control={enabled=true,id='merged-section',action='render_section',asset_id='section_0123456789abcdef0123',section_min={x=1,y=2,z=3}}
paused=true;frames(660)
assert(status.phase=='waiting_gameplay' and status.pending_id=='merged-section' and render_creates==0 and #resources==old_resources)
print('PASS paused gameplay waits without allocating or consuming the request')
paused=false
mesh_ready=false;frames(30);assert(render_creates==1 and not draw)
assert(last_position.x==2 and last_position.y==-1.95 and last_position.z==0)
assert(resources[#resources]=='mod/onimusha_mc/sections/section_0123456789abcdef0123/section_0123456789abcdef0123.mdf2')
paused=true;frames(660);assert(valid and status.phase=='loading' and not draw and not status.error)
paused=false
print('PASS pausing during resource load does not consume the unpaused timeout')
mesh_ready=true;frames(30);assert(status.phase=='visible' and status.ready and draw and not status.collision)
assert(instantiations==2 and render_creates==1)
print('PASS merged section waits for mesh/material, preserves section-local placement, creates no collider')
enabled=true;tick();assert(status.phase=='removed_guard' and not valid and not draw)
frames(15);assert(status.destroyed and not status.ready)
print('PASS takeover removes the independent section display probe')
''')
