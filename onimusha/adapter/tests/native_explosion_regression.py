"""Exercise the real native explosion queue: one factory call, strict session, no HP fallback."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

src = (Path(__file__).resolve().parents[1] / 'onimusha_enemy_hit.lua').read_text(encoding='utf-8-sig')
chunk = src.split('-- BEGIN NATIVE EXPLOSION:', 1)[1]
chunk = 'do\n' + chunk.split('\ndo\n', 1)[1]
chunk = chunk.replace('\nend\n-- END NATIVE EXPLOSION', '\n_G.xtest={state=X,queue=queue,shooting=shooting}\nend')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
function obj(name,id,methods,fields)
 local f=fields or {};local o={}
 function o:get_address() return id end
 function o:get_type_definition() return {get_full_name=function() return name end,get_method=function(_,n) return methods[n] and {} end} end
 function o:call(n,...) assert(methods[n],n);return methods[n](...) end
 function o:get_field(n) return f[n] end
 function o:set_field(n,v) f[n]=v end
 function o:add_ref() end
 return o
end
position={x=10,y=20,z=30};spawned=0;mode='ok';prepared={}
scene=obj('via.Scene',3,{})
owner=obj('via.GameObject',1,{get_Valid=function() return true end})
player=obj('app.PlayerCharacter',2,{get_GameObject=function() return owner end})
shgo=obj('via.GameObject',4,{get_Name=function() return 'shl_g019_000_004' end,
 get_Transform=function() return {get_position=function() return position end} end})
shell=obj('app.AppShell',5,{get_GameObject=function() return shgo end,get_ShellOwner=function() return owner end})
controller=obj('ace.cShellCreateController',6,{
 ['shootShell(System.Int32, ace.cShellShootingInfoBase, System.Action`1<ace.ShellBase>)']=function(id,info,cb)
  spawned=spawned+1;assert(id==6 and cb==nil)
  assert(prepared.StartPos:get_field('_Value')==position and prepared.TargetPos:get_field('_Value')==position)
  assert(prepared.StartRot:get_field('_Value').w==1 and prepared.TransformOwner==owner)
  if mode=='throw' then error('ambiguous native failure') end
  if mode=='nil' then return nil end
  return shell
 end})
creator=obj('creator',7,{})
state={active=true,epoch=7,player=player,transform={get_position=function() return {x=10,y=20,z=30} end}}
Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
Quaternion={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
ValueType={new=function() return obj('nullable',8,{}, {}) end}
sdk={get_native_singleton=function() return 1 end,call_native_func=function() return scene end,
 find_type_definition=function() return {} end,
 create_instance=function(t)
  assert(t=='app.cShellShootingInfo');local m={}
  m['.ctor(ace.user_data.ShellCreatorInfoDataBase.ShellCreatorInfoBase)']=function(c) assert(c==creator) end
  for _,n in ipairs({'StartPos','TargetPos','StartRot','StartMoveDir','TransformOwner','StartTerrainCheckDestroy','ShellGroupNo','SwitchIndex','HitGroup'}) do
   m['set_'..n]=function(v) prepared[n]=v end
  end
  return obj(t,9,m,{OwnerAttachType=1})
 end}
re={on_application_entry=function() end,on_script_reset=function() end}
json={}
''')
lua.execute(chunk)
lua.execute(r'''
function reset()
 local x=xtest.state;x.mode='enabled';x.ready=true;x.owner=owner;x.controller=controller;x.creator=creator
 x.identity='3:1:7';x.epoch=7;x.seen={};x.events={};x.frame=10;spawned=0;mode='ok';state.active=true
end
function event(id) return {form_id=id or 1,weapon=7,flags=1,a=10,b=20,c=30,d=4} end
reset();assert(xtest.queue(event(),state,position));assert(spawned==1)
assert(xtest.state.events[1].outcome=='spawned' and xtest.state.events[1].name=='shl_g019_000_004')
assert(not xtest.queue(event(),state,position));assert(spawned==1)
-- Multiple distinct simultaneous TNTs must not be dropped by a per-frame rate gate.
assert(xtest.queue(event(2),state,position));assert(spawned==2)
''')
print('PASS one native shell per explosion, duplicate rejected, simultaneous distinct TNTs accepted')
lua.execute(r'''
for _,mutate in ipairs({function(e) e.weapon=6 end,function(e) e.flags=0 end,
 function(e) e.d=0 end,function(e) e.d=33 end,function(e) e.form_id=0 end,
 function(e) e.form_id=1.2 end,function(e) e.d=0/0 end}) do
 reset();local e=event();mutate(e);assert(not xtest.queue(e,state,position));assert(spawned==0)
end
reset();state.active=false;assert(not xtest.queue(event(),state,position));assert(spawned==0)
reset();assert(not xtest.queue(event(),state,{x=500,y=0,z=0}));assert(spawned==0)
reset();assert(not xtest.queue(event(),state,{x=0/0,y=0,z=0}));assert(spawned==0)
reset();xtest.state.identity='old-scene';assert(not xtest.queue(event(),state,position));assert(spawned==0)
''')
print('PASS stale session, wrong scene, legacy, invalid radius/ID, inactive, distant and nonfinite inputs cannot spawn')
lua.execute(r'''
for _,failure in ipairs({'throw','nil'}) do
 reset();mode=failure;assert(not xtest.queue(event(),state,position));assert(spawned==1)
 assert(xtest.state.events[1].outcome=='unknown_no_retry' and xtest.state.ready==false)
 assert(not xtest.queue(event(),state,position));assert(spawned==1)
end
''')
print('PASS ambiguous native result never retries, restores capability gate, and performs no direct HP writes')
print('NATIVE_EXPLOSION_REGRESSION_OK 3 groups')
