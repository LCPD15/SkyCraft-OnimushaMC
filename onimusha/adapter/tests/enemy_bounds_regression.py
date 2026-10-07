"""Generic damage bounds and the actual publish_actors coordinate conversion."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

s=(Path(__file__).resolve().parents[1]/'onimusha_mc.lua').read_text(encoding='utf-8-sig')
code=s[s.index('local function valid_enemy_aabb('):s.index('local function apply_events(')]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
function obj(methods,fields)
 return {call=function(_,n,...) assert(methods[n],n);return methods[n](...) end,get_field=function(_,n) return fields[n] end}
end
function attempt(fn) local ok,v=pcall(fn);if ok then return v end end
function call(o,n,...) if o then local a=table.pack(...);return attempt(function() return o:call(n,table.unpack(a,1,a.n)) end) end end
function addr() return 77 end
function typename() return 'mock type' end
function td() return {get_runtime_type=function() return 1 end} end
function mcpos(p) return {x=p.x+8192,y=p.y,z=p.z} end
function scene_components() return {enemy} end
cfg={units_per_block=1};state={actors={},actor_seq=0,transform={get_position=function() return {x=50,y=3,z=20} end}}
local boxes={
 {minpos={x=49,y=2,z=19},maxpos={x=51,y=4,z=21}},
 {minpos={x=48,y=4,z=19},maxpos={x=52,y=5,z=21}},
 {minpos={x=-9999,y=-9999,z=-9999},maxpos={x=9999,y=9999,z=9999}},
}
function fixture()
 active={true,true,false};enabled={true,true,true}
 local group=obj({get_Id=function() return 823 end,get_NumRequestSets=function() return 3 end},{})
 local rsc=obj({
 ['getNumCollidablesFromIndex(System.UInt32, System.UInt32)']=function(g,j) assert(g==823);return 1 end,
 ['getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)']=function(g,j,k)
  assert(g==823 and k==0)
  return obj({get_Enabled=function() return enabled[j+1] end,get_BoundingAabb=function() return boxes[j+1] end,
   get_UserData=function() return obj({get_ParentUserData=function() return obj({}, {_PartsIndex=j}) end},{}) end},{})
 end},{})
 local switch=obj({['getGroupFromType(app.ColliderSwitcher.COLLIDER_TYPE)']=function(t) assert(t==0);return group end,
 ['isRequestSetActiveFromIndex(app.ColliderSwitcher.COLLIDER_TYPE, System.UInt32)']=function(t,j) assert(t==0);return active[j+1] end},{_RequestSetCollider=rsc})
 local components=obj({}, {['<ColliderSwitcher>k__BackingField']=switch})
 local entity=obj({}, {['<CharacterComponents>k__BackingField']=components})
 local holder=obj({get_Entity=function() return entity end},{})
 local health=obj({get_Health=function() return 1000 end,get_MaxHealth=function() return 1000 end},{})
 local context=obj({get_Chara=function() return obj({get_HealthManager=function() return health end},{}) end},{})
 local go=obj({get_Valid=function() return true end,get_Name=function() return 'arbitrary non-whitelisted enemy' end,
  get_Transform=function() return {get_position=function() return {x=50,y=3,z=20} end} end,
  ['getComponent(System.Type)']=function() return nil end},{})
 enemy=obj({get_CharacterEntityHolder=function() return holder end,get_GameObject=function() return go end,get_Context=function() return context end},{})
 return enemy
end
''')
test=lua.execute(code+r'''
return function()
 local e=fixture();local p={x=50,y=3,z=20}
 local b=enemy_damage_bounds(e,p);assert(b.min.x==48 and b.max.y==5 and #b.parts==2)
 print('PASS active damage group only, correct group ID and current enabled parts')
 active[2]=false;b=enemy_damage_bounds(e,p);assert(b.min.x==49 and #b.parts==1)
 enabled[1]=false;assert(enemy_damage_bounds(e,p)==nil)
 print('PASS phase-disabled / disabled colliders do not enlarge hittable area')
 assert(valid_enemy_aabb({minpos={x=0,y=0,z=0},maxpos={x=1,y=1,z=1}},p)==nil)
 assert(valid_enemy_aabb({minpos={x=50,y=5,z=20},maxpos={x=49,y=3,z=21}},p)==nil)
 assert(valid_enemy_aabb({minpos={x=0/0,y=0,z=0},maxpos={x=math.huge,y=1,z=1}},p)==nil)
 print('PASS distant uninitialized/local bounds, reversed boxes and nonfinite values rejected')
 fixture();local rows;local bridge={publish_actors=function(v) rows=v end};publish_actors({},bridge)
 assert(#rows==1 and rows[1].x==8242 and rows[1].y==2 and rows[1].height==3 and rows[1].width==4)
 assert(state.enemy_diagnostic.damage_bounds==1 and state.actors[77].bounds_native.min.y==2)
 print('PASS actual publish_actors uses damage center/bottom, supporting floating or large enemies')
 enabled[1]=false;enabled[2]=false;publish_actors({},bridge)
 assert(rows[1].y==3 and rows[1].height==1.8 and state.enemy_diagnostic.fallback_bounds==1)
 print('PASS unavailable runtime geometry uses explicit diagnosed capsule fallback, no guessed monster table')
 print('ENEMY_BOUNDS_REGRESSION_OK 5 groups')
end
''')
test()
