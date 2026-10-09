"""Exercise real Lua soul hooks: held command lifetime, native success and rollback."""
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local methods={};hooks={};callbacks={};enabled=true;held=true;rewarded=0;refs=0
local names={'updateBeforeAction','updateAfterActionFromBoneEntity','lateUpdate','executeSoulAbsorptionSuccess'}
for i,name in ipairs(names)do
 local params=name=='executeSoulAbsorptionSuccess' and {{get_full_name=function()return 'app.SoulBase'end}} or {}
 methods[name]={is_static=function()return false end,get_return_type=function()return{get_full_name=function()return'System.Void'end}end,
 get_num_params=function()return #params end,get_param_types=function()return params end,get_function=function()return i end,name=name}
end
local td={get_method=function(_,name)return methods[name]end,get_full_name=function()return'app.cPlayerSoulAbsorptionSupporter'end}
go={call=function(_,n)assert(n=='get_Valid');return true end}
entity={get_address=function()return 20 end,call=function(_,n)assert(n=='get_OwnerCharacter');return player end}
soul={flag=false,get_address=function()return 30 end,get_type_definition=function()return td end,
 get_field=function(self,n)if n=='_PlayerCharacterEntity'then return entity end;if n=='_IsCommandAbsorb'then return self.flag end;return false end,
 set_field=function(self,n,v)assert(n=='_IsCommandAbsorb');self.flag=v end,
 add_ref=function()refs=refs+1 end,release=function()refs=refs-1 end}
local ec=entity.call;entity.call=function(self,n)if n=='get_SoulAbsorption'then return soul end;return ec(self,n)end
player={call=function(_,n)if n=='get_GameObject'then return go end;assert(n=='get_CharacterEntityHolder');return{call=function()return entity end}end}
info={call=function(_,n)if n=='get_CharacterValid'then return true end;assert(n=='get_Character');return player end}
pm={call=function(_,n)if n=='isPlayerReady'then return true end;assert(n=='getControllingPlayerInfo');return info end}
storage={};thread={get_hook_storage=function()return storage end}
sdk={get_tdb_version=function()return 82 end,get_managed_singleton=function()return pm end,find_type_definition=function()return td end,
 to_int64=function(n)return n end,hook=function(m,pre,post)hooks[m.name]={pre=pre,post=post}end}
re={on_application_entry=function(_,f)callbacks.tick=f end,on_script_reset=function(f)callbacks.stop=f end}
json={dump_file=function()end}
onimusha_mc={status=function()return{ready=enabled,enabled=enabled,collision_epoch=7}end,
 read_mc=function()return{in_world=true,absorb_souls=held}end,
 reward_absorbed_soul=function(r)assert(r.epoch==7);rewarded=rewarded+1;return true end}
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_soul.lua').read_text('utf-8'))
lua.execute(r'''
callbacks.tick();assert(hooks.updateBeforeAction)
hooks.updateBeforeAction.pre({[2]=30});assert(soul.flag and refs==1)
-- The game reads its sealed command AFTER updateBeforeAction. Reproduce that
-- overwrite before the actual absorption decision in the bone-entity pass.
soul.flag=false
hooks.updateAfterActionFromBoneEntity.pre({[2]=30});assert(soul.flag and refs==1)
hooks.updateAfterActionFromBoneEntity.post(0)
hooks.executeSoulAbsorptionSuccess.pre({[2]=30});hooks.executeSoulAbsorptionSuccess.post(99)
assert(rewarded==0);callbacks.tick();assert(not soul.flag and refs==0 and rewarded==1)
callbacks.tick();assert(rewarded==1)
held=false;hooks.updateBeforeAction.pre({[2]=30});assert(not soul.flag);hooks.lateUpdate.post(0);assert(refs==0)
held=true;hooks.updateBeforeAction.pre({[2]=30});enabled=false;callbacks.tick();assert(not soul.flag and refs==0)
hooks.executeSoulAbsorptionSuccess.pre({[2]=30});hooks.executeSoulAbsorptionSuccess.post(99);callbacks.tick();assert(rewarded==1)
enabled=true;hooks.updateBeforeAction.pre({[2]=31});assert(refs==0)
hooks.updateBeforeAction.pre({[2]=30});callbacks.stop();assert(not soul.flag and refs==0)
print('PASS held/released C or RMB, native success once, F10 off, wrong owner and reset restoration')
''')
