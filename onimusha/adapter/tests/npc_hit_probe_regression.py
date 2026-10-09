"""Actual observer Lua with SDK mocks: no native damage or hit replay is permitted."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
callbacks={};hooks={};control={enabled=false};output=nil
re={on_application_entry=function(_,f)callbacks.tick=f end,on_script_reset=function(f)callbacks.reset=f end}
json={load_file=function()return control end,dump_file=function(_,v)output=v end}
local enemy_td={is_a=function(_,n)return n=='app.EnemyCharacter'end,get_full_name=function()return 'app.EmTest'end}
local hit_td={get_full_name=function()return 'app.HitInfo'end}
local arg_td={get_full_name=function()return 'app.HitInfo'end}
local void_td={get_full_name=function()return 'System.Void'end}
local method={is_static=function()return false end,get_num_params=function()return 1 end,
 get_param_types=function()return {arg_td}end,get_return_type=function()return void_td end,get_function=function()return 1234 end}
local td={get_method=function(_,n)assert(n=='notifyHitProc(app.HitInfo)');return method end,get_runtime_type=function()return 'enemy'end}
local scene={call=function(_,n,...)assert(n=='findComponents(System.Type)');return {get_elements=function()return {}end}end}
sdk={get_tdb_version=function()return 82 end,get_native_singleton=function()return {}end,
 find_type_definition=function()return td end,call_native_func=function(_,_,n)assert(n=='get_CurrentScene');return scene end,
 to_int64=function(n)return n end,to_managed_object=function(v)return v end,
 hook=function(_,pre,post)hooks.pre=pre;hooks.post=post end}
function call(o,n,...)return o:call(n,...)end
function typ(o)return o and o:get_type_definition():get_full_name()end
function snapshot(o)return o end
local transform={get_position=function()return {x=1,y=2,z=3}end}
local go={get_address=function()return 42 end,call=function(_,n)
 if n=='get_Valid'then return true elseif n=='get_Name'then return 'observed' elseif n=='get_Transform'then return transform end
 error('Mutation or unexpected call '..n)
end}
local shape={get_type_definition=function()return {get_full_name=function()return 'via.physics.CapsuleShape'end}end,
 call=function(_,n)assert(n=='get_BoundingAabb');return {min={x=0,y=0,z=0},max={x=1,y=1,z=1}}end}
local col={call=function(_,n)if n=='get_Enabled'then return true end;assert(n=='get_TransformedShape');return shape end}
attacker={get_type_definition=function()return enemy_td end}
hit_fields={['<AttackCharacter>k__BackingField']=attacker,['<AttackOwner>k__BackingField']=go,
 ['<DamageOwner>k__BackingField']=go,['<HitID>k__BackingField']=7,['<AttackUniqueID>k__BackingField']=123,
 ['<AttackCollidable>k__BackingField']=col}
hit={get_type_definition=function()return hit_td end,get_field=function(_,n)return hit_fields[n]end}
function advance(n)for i=1,n do callbacks.tick()end end
''')
src=(Path(__file__).resolve().parents[1]/'onimusha_combat_inventory.lua').read_text(encoding='utf-8')
probe=src.split('-- NPC incoming-hit research, Onimusha TDB82.',1)[1]
lua.execute('-- NPC incoming-hit research, Onimusha TDB82.'+probe)
lua.execute(r'''
advance(60);assert(hooks.pre==nil and output==nil)
control={id='one',enabled=true,max_frames=120,max_events=2};advance(60)
assert(output.armed and output.inventory.enemy_count==0)
assert(hooks.pre({nil,nil,hit})==nil and hooks.post(77)==77)
hooks.pre({nil,nil,hit});assert(#output.events==1 and output.events[1].data.shape=='via.physics.CapsuleShape')
advance(1);hooks.pre({nil,nil,hit});assert(#output.events==2)
advance(1);hooks.pre({nil,nil,hit});assert(#output.events==2)
advance(120);assert(not output.armed and output.expired)
hooks.pre({nil,nil,hit});assert(#output.events==2)
control={id='two',enabled=true,max_frames=120};advance(60)
assert(output.armed and not output.expired and #output.events==0)
hit_fields['<AttackCharacter>k__BackingField']=nil;hooks.pre({nil,nil,hit});assert(#output.events==0)
hit_fields['<AttackCharacter>k__BackingField']=attacker
control.enabled=false;advance(60);hooks.pre({nil,nil,hit});assert(not output.armed and #output.events==0)
control={id='three',enabled=true,max_frames=120};advance(60);callbacks.reset();hooks.pre({nil,nil,hit})
assert(not output.armed and #output.events==0)
print('PASS observer opt-in, exact signature, original-call preservation, enemy filter, duplicate suppression, capacity, expiry, disable and reset')
''')
