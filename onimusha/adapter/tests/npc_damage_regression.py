"""Run the actual NPC exporter with narrow SDK doubles; no native mutation is available."""
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
callbacks={};active=true;registered=true;enabled=true;category=0;custom=0;missing=false;only_count=0
unique=77;hit=42;radius=.75;maxhealth=2000;sent={};output=nil;units=2
re={on_application_entry=function(_,f)callbacks.tick=f end,on_script_reset=function(f)callbacks.reset=f end}
json={dump_file=function(_,v)output=v end};sdk={get_tdb_version=function()return 82 end,find_type_definition=function()end}
function object(name,methods,fields)
 local t={get_full_name=function()return name end,is_a=function(_,n)return n==name or n=='app.col_user_data.AttackParamBase'end,
 get_method=function(_,n)return methods[n]~=nil end}
 return {get_type_definition=function()return t end,get_field=function(_,n)assert(fields and fields[n]~=nil,'Unexpected field '..n);return fields[n]end,
 call=function(_,n,...)assert(methods[n],'Unexpected/mutating SDK call '..n);return methods[n](...)end,get_address=function()return 123 end}
end
point={x=10,y=432,z=-90};caps=object('via.Capsule',{}, {p0=point,p1={x=10,y=433,z=-90},r=radius})
shape=object('via.physics.ContinuousCapsuleShape',{get_Capsule=function()return caps end,get_PreviousCapsule=function()return caps end})
info=object('app.col_user_data.AttackColliderInfo',{}, {_CustomShapeType=0})
col=object('via.physics.Collidable',{get_Enabled=function()return enabled end,get_UserData=function()return info end,get_TransformedShape=function()return shape end})
ud=object('app.col_user_data.AttackParamEnemy',{getAttackInfoCategory=function()return category end})
list=object('List',{get_Count=function()return only_count end})
runtime=object('app.col_user_data.cAttackRuntimeData',{getAttackUniqueID=function()return unique end,getHitID=function()return hit end},
 {['<IsInitialized>k__BackingField']=true,_OnlyAttackTargets=list})
dict=object('Dict',{get_Item=function(x)assert(x==ud);return runtime end})
origin=object('Origin',{get_MultiHitMaxCount=function()return 0 end})
param=object('Param',{get_Attack=function()return 160 end,get_OriginData=function()return origin end,
 get_IsMultiHitEnabled=function()return false end,get_IsMultiHit=function()return false end,get_MultiHitTimer=function()return 0 end})
support=object('Support',{['findAttackParamByKey(System.UInt32)']=function(id)assert(id==unique,'Wrong runtime lookup key');if not missing then return param end end})
group=object('Group',{get_Initialized=function()return true end,get_Id=function()return 300 end,get_NumRequestSets=function()return 1 end,
 ['getRequestSetIdFromIndex(System.UInt32)']=function()return 0 end})
rsc=object('RSC',{['isRegisteredRequestSet(System.UInt32, System.UInt32)']=function()return registered end,
 ['getRequestSetUserData(System.UInt32, System.UInt32)']=function()return ud end,
 ['getNumCollidablesFromIndex(System.UInt32, System.UInt32)']=function()return 1 end,
 ['getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)']=function()return col end})
children=object('List',{get_Count=function()return 0 end})
sw=object('Switch',{['getGroupFromType(app.ColliderSwitcher.COLLIDER_TYPE)']=function(t)assert(t==2);return group end},
 {_RequestSetCollider=rsc,_ReqSetRuntimeDataDic=dict,_Children=children})
components=object('Components',{}, {['<ColliderSwitcher>k__BackingField']=sw})
entity=object('Entity',{get_AttackParamSupporter=function()return support end},{['<CharacterComponents>k__BackingField']=components})
holder=object('Holder',{get_Entity=function()return entity end})
go=object('GO',{get_Valid=function()return true end,get_Transform=function()return {get_position=function()return point end}end})
enemy=object('Enemy',{get_GameObject=function()return go end,get_CharacterEntityHolder=function()return holder end})
health=object('Health',{get_Health=function()return 100 end})
onimusha_mc={publish_attacks=function(on,rows)sent[#sent+1]={on=on,rows=rows};return true end}
onimusha_adapter_lifecycle={combat_context=function()if active then return {actors={{id=9,obj=enemy,health=health,name='generic'}},units=units,
 max_health=maxhealth,map=function(v)return {x=v.x/units+1024,y=v.y/units,z=v.z/units-1024}end}end end}
function advance()for i=1,120 do callbacks.tick()end return sent[#sent]end
''')
lua.globals().exporter=lua.execute((Path(__file__).resolve().parents[1]/'onimusha_npc_damage.lua').read_text('utf-8'))
lua.execute(r'''
local r=advance();assert(output.failed==0,output.error);assert(r.on and #r.rows==1)
local a=r.rows[1];assert(a.attack==77 and a.hit==42 and a.damage==1.6 and a.shape==1)
assert(a.geometry[1]==1029 and a.geometry[2]==216 and a.geometry[7]==.375)
assert(a.geometry[8]==a.geometry[1] and #a.geometry==24)
registered=false;assert(#advance().rows==0);registered=true
enabled=false;assert(#advance().rows==0);enabled=true
category=1;assert(#advance().rows==0);category=0
only_count=1;assert(#advance().rows==0);only_count=0
missing=true;assert(#advance().rows==0 and output.missing_param>0);missing=false
active=false;assert(not advance().on);active=true
hit=43;assert(advance().rows[1].hit==43)
callbacks.reset();assert(not sent[#sent].on)
local before=#sent;local diagnostic=exporter.preflight(onimusha_adapter_lifecycle.combat_context())
assert(#sent==before and diagnostic.read_only and #diagnostic.shapes==1 and #diagnostic.errors==0)
local oldshape=shape
local sphere=object('via.Sphere',{get_Center=function()return point end,get_Radius=function()return 2 end})
shape=object('via.physics.ContinuousSphereShape',{get_Sphere=function()return sphere end,get_PreviousSphere=function()return sphere end})
assert(advance().rows[1].geometry[7]==1)
local box=object('via.OBB',{get_Position=function()return point end},{coord={[0]={x=1,y=0,z=0},[1]={x=0,y=2,z=0},[2]={x=0,y=0,z=1}},extent={x=2,y=3,z=4}})
shape=object('via.physics.BoxShape',{get_Box=function()return box end})
local boxrow=advance().rows[1];assert(boxrow.shape==2 and boxrow.geometry[13]==1 and boxrow.geometry[14]==3 and boxrow.geometry[15]==2)
shape=object('via.physics.UnknownShape',{});assert(#advance().rows==0 and output.unsupported>0);shape=oldshape
local owner=go;local shellDisabled=false
local shellInfo=object('ShellInfo',{}, {AttackParam=param})
local shellHit=object('ShellHit',{}, {_ColSwitcher=sw,_DisableRequested=false,_UnregistRequested=false})
local shell=object('app.AppShell',{get_ShellOwner=function()return owner end,get_AttackInfo=function()return shellInfo end},
 {['<ShellShooter>k__BackingField']=false,_ColHitComponent=shellHit})
local scene=object('Scene',{['findComponents(System.Type)']=function()return {get_elements=function()return {shell}end}end})
sdk.find_type_definition=function(n)return {get_runtime_type=function()return n end}end
sdk.get_native_singleton=function()return {}end;sdk.call_native_func=function()return scene end
assert(#advance().rows==2 and output.failed==0,output.error)
-- No native shell->MC echo for player-owned TNT, and no idle registered=false hits.
owner={get_address=function()return 999 end};assert(#advance().rows==1)
owner=go;registered=false;assert(#advance().rows==0);registered=true
local publish=onimusha_mc.publish_attacks;onimusha_mc.publish_attacks=nil
advance();assert(output.mode=='requires_protocol_16');onimusha_mc.publish_attacks=publish
print('PASS registered windows, ordinary/enemy filtering, current unique lookup, target restrictions, coordinate scale/tile, no player damage fanout, disable/reset')
print('PASS read-only preflight, capsule/sphere/OBB conversion, unsupported-shape rejection, enemy shell ownership and player explosion exclusion, protocol gate')
''')
