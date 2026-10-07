"""Execute the separate read-only probe with strict native-object/hook mocks."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / "onimusha_guard_probe.lua").read_text(encoding="utf-8")

class Pointer:
    def __init__(self, value): self.value = value

fixture = r'''
local APPLY="app.cCharacterApplyDamage.cApplyParam"
T={control=nil,hooks={},callbacks={},objects={},definitions={},writes=0,conversions=0,clock=100,
   enabled=false,host_ready=true,storage={},thread=1,metadata_override=nil}
local function typ(name)
 if T.definitions[name] then return T.definitions[name] end
 local t={name=name,fields={}}
 function t:get_full_name() return self.name end
 function t:get_runtime_type() return self end
 function t:get_parent_type() return nil end
 function t:is_value_type() return T.value_type==true end
 function t:is_by_ref() return false end
 function t:is_pointer() return false end
 function t:is_a(n) return self.name==n end
 function t:get_fields() return self.fields end
 function t:get_methods() return {} end
 function t:get_method(n)
  local spec=T.signatures and T.signatures[self.name..":"..n]
  if spec then return spec end
  return {getter=true}
 end
 T.definitions[name]=t;return t
end
local function obj(id,name,values)
 local o={id=id,typename=name,values=values or {},fields={}}
 function o:get_address() return self.id end
 function o:get_type_definition() return typ(self.typename) end
 function o:call(n,...)
  local v=self.values[n];assert(v~=nil,"Unexpected getter "..self.typename.."."..n)
  if type(v)=='function' then return v(...) end
  return v
 end
 function o:get_field(n) assert(self.fields[n]~=nil,'Unexpected field '..n);return self.fields[n] end
 T.objects[id]=o;return o
end
local transform={get_position=function() return {x=1,y=2,z=3} end}
T.go=obj(1,'via.GameObject',{get_Valid=true,get_Transform=transform})
T.player=obj(2,'app.PlayerCharacter',{get_GameObject=T.go})
T.entity=obj(3,'app.cPlayerCharacterEntity',{get_OwnerCharacter=T.player})
T.holder=obj(4,'holder',{get_Entity=T.entity});T.player.values.get_CharacterEntityHolder=T.holder
T.damage=obj(5,'app.cPlayerApplyDamage',{get_Valid=true,get_IsDestroy=false,get_OwnerCharacter=T.player,get__PlayerEntity=T.entity})
T.guard=obj(6,'app.cPlayerGuardController',{get_Valid=true,get_IsDestroy=false,get_OwnerCharacter=T.player,get_CharacterEntity=T.entity,get_IsGuard=true})
T.entity.fields._DamageInterface=T.damage;T.entity.values.get_PlayerGuardController=T.guard
T.health=obj(7,'app.cHealthManager',{get_Health=1000,get_MaxHealth=2000})
T.chara=obj(8,'chara',{get_HealthManager=T.health});T.context=obj(9,'context',{get_Chara=T.chara})
T.info=obj(10,'info',{get_Valid=true,get_CharacterValid=true,get_Character=T.player,get_Context=T.context})
T.pm=obj(11,'app.PlayerManager',{getControllingPlayerInfo=T.info,isPlayerReady=true})
T.scene=obj(12,'via.Scene');T.param=obj(13,APPLY)
T.attacker=obj(14,'via.GameObject',{get_Valid=true,get_Transform=transform})
T.battle_info=obj(15,'app.BattleInfo.cDamageInfoBase',{get_ApplyParam=T.param,get_Attacker=T.attacker,get_AttackObj=T.attacker,
 get_HitPosition={x=1,y=2,z=3},get_AttackVector={x=0,y=0,z=1},get_Damage=200,get_HealthDecrease=0})
T.battle=obj(16,'app.BattleComponent',{get_DamageInfo=T.battle_info});T.entity.values.get_BattleComponent=T.battle
T.input=obj(17,'input',{get_IsGuard=true});T.arg=obj(18,'argument',{get_Input=T.input});T.player.values.get_ArgumentData=T.arg
T.signatures={}
for i,s in ipairs({{'stock','app.cPlayerApplyDamage','doApplyStockDamage','System.Void'},
 {'guard_test','app.cCharacterApplyDamage','isEnableGuardDamage','System.Boolean'},
 {'guard_reaction','app.cCharacterApplyDamage','applyGuardDamageReaction','System.Void'},
 {'hit_sound','app.cCharacterApplyDamage','applyHitSound','System.Void'},
 {'first','app.cCharacterApplyDamage','execFirstDamage','System.Void'},
 {'second','app.cCharacterApplyDamage','execSecondDamage','System.Void'},
 {'third','app.cCharacterApplyDamage','execThirdDamage','System.Void'},
 {'enemy_first','app.cEnemyApplyDamage','execFirstDamage','System.Void'},
 {'enemy_reaction','app.cEnemyApplyDamage','applyDamageReaction','System.Void'},
 {'effect','app.cCharacterApplyDamage','applyHitEffect','System.Void'}}) do
 local m={key=s[1],declaring=s[2],name=s[3],returns=s[4],id=100+i}
 function m:is_static() return false end
 function m:get_num_params() return 1 end
 function m:get_param_types() return {typ(APPLY)} end
 function m:get_return_type() return typ(self.returns) end
 function m:get_declaring_type() return typ(self.declaring) end
 function m:get_function() return ptr(T.duplicate_address and 101 or self.id) end
 T.signatures[s[2]..':'..s[3]..'('..APPLY..')']=m
end
sdk={get_tdb_version=function() return 82 end,
 get_managed_singleton=function(n) assert(n=='app.PlayerManager');return T.pm end,
 get_native_singleton=function(n) assert(n=='via.SceneManager');return 'scene_manager' end,
 call_native_func=function(_,_,n) assert(n=='get_CurrentScene');return T.scene end,
 find_type_definition=typ,
 to_ptr=function(v) return ptr(v) end,
 to_int64=function(v) assert(type(v)=='userdata','Must inspect real pointer wrapper');return v.value end,
 is_managed_object=function(v) return T.objects[v.value]~=nil end,
 to_managed_object=function(v) T.conversions=T.conversions+1;return T.objects[v.value] end,
 hook=function(m,pre,post) assert(not T.hooks[m.key]);T.hooks[m.key]={pre=pre,post=post} end}
thread={get_hash=function() return T.thread end,get_hook_storage=function() return T.storage end}
_G.onimusha_mc={status=function() return {enabled=T.enabled,host_ready=T.host_ready} end}
json={load_file=function() return T.control end,dump_file=function(_,v)
 local function pure(x,seen)
  if type(x)=='table' then assert(not x.get_address and not x.get_data,'Managed reference in report')
   seen=seen or {};assert(not seen[x],'Cyclic report');seen[x]=true;for _,y in pairs(x) do pure(y,seen) end;seen[x]=nil
  else assert(type(x)=='string' or type(x)=='number' or type(x)=='boolean','Bad report value') end
 end
 pure(v);T.writes=T.writes+1;T.report=v
end}
re={on_application_entry=function(n,f) assert(n=='LateUpdateBehavior');T.callbacks.frame=f end,
 on_script_reset=function(f) T.callbacks.reset=f end,on_draw_ui=function(f) T.callbacks.ui=f end}
os.time=function() return T.clock end
function tick(n) for _=1,n do T.callbacks.frame() end end
function arm() T.control={enabled=true,arm_id='test-1'};tick(31) end
function enter(key,id,param)
 local old=T.storage;T.storage={};local s=T.storage
 local r=T.hooks[key].pre({[2]=ptr(id or 5),[3]=ptr(param or 13)})
 assert(r==nil,'Pre must preserve original call');return {old=old,storage=s,key=key}
end
function leave(token,result)
 T.storage=token.storage;local v=ptr(result or 0xFF01)
 assert(T.hooks[token.key].post(v)==v,'Post must return identical pointer');T.storage=token.old
end
function invoke(key,id,param,result) local t=enter(key,id,param);leave(t,result) end
function enemy_fixture()
 T.enemy_go=obj(31,'via.GameObject',{get_Valid=true,get_Transform=transform,get_Name='test_enemy'})
 T.enemy=obj(32,'app.EnemyCharacter',{get_GameObject=T.enemy_go,get_Context=T.context})
 T.enemy_entity=obj(33,'app.cEnemyCharacterEntity',{get_OwnerCharacter=T.enemy})
 T.enemy_holder=obj(34,'holder',{get_Entity=T.enemy_entity});T.enemy.values.get_CharacterEntityHolder=T.enemy_holder
 T.enemy_damage=obj(35,'app.cEnemyApplyDamage',{get_Valid=true,get_IsDestroy=false,get_OwnerCharacter=T.enemy})
 T.enemy_entity.fields._DamageInterface=T.enemy_damage
 T.scene.values['findComponents(System.Type)']={get_elements=function() return {T.enemy} end}
end
function arm_flow()
 enemy_fixture();T.control={enabled=true,arm_id='flow-1',profile='flow'};tick(31)
 assert(TEST.state.armed,TEST.state.status)
end
'''

def run_case(label, script):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ptr = Pointer
    lua.execute(fixture)
    lua.execute(source + "\nTEST={state=state,install=install_hooks,snapshot=snapshot,disarm=disarm}")
    lua.execute(script)
    print("PASS " + label)

run_case("default disarmed, metadata and status only, no hooks or argument conversion", "tick(120);assert(not TEST.state.armed and next(T.hooks)==nil and T.conversions==0 and T.writes==2)")
run_case("explicit one-shot arm requires stable owner and installs only four methods", "T.control={enabled=true,arm_id='test-1'};tick(29);assert(not TEST.state.armed);tick(2);assert(TEST.state.armed);local n=0;for _ in pairs(T.hooks) do n=n+1 end;assert(n==4)")
run_case("foreign this is rejected before argument conversion", "arm();invoke('stock',999);assert(T.conversions==0 and #TEST.state.events==0)")
run_case("nested callbacks retain per-call order and same-call parent without retaining parameter", "arm();local a=enter('stock');local b=enter('guard_test');leave(b,0xFA01);leave(a);local e=TEST.state.events;assert(#e==4 and e[2].parent==e[1].id and e[3].guard_result==true and e[4].id==e[1].id);assert(e[1].sample.attacker_address==14);tick(89);assert(T.writes==2 and next(TEST.state.stacks)==nil)")
run_case("low Boolean result byte ignores unrelated high register bits", "arm();invoke('guard_test',nil,nil,0xFA00);assert(TEST.state.events[2].guard_result==false)")
run_case("different threads and reused parameter addresses never imply same-hit parent", "arm();local a=enter('stock');T.thread=2;invoke('guard_test');T.thread=1;leave(a);assert(TEST.state.events[2].parent==nil);invoke('guard_test');assert(TEST.state.events[5].parent==nil)")
run_case("by-value parameter mode only records identities, never dereferences raw parameter", "T.value_type=true;arm();invoke('stock');assert(T.conversions==0 and TEST.state.events[1].sample.param_decoded==false)")
run_case("invalid argument pointer and unmatched battle-info do not invent attackers", "arm();invoke('stock',nil,999);assert(T.conversions==0 and not TEST.state.events[1].sample.attacker_address);T.battle_info.values.get_ApplyParam=T.damage;invoke('stock');assert(TEST.state.events[3].sample.battle_param_matches==false and TEST.state.events[3].sample.attacker_address==nil)")
run_case("live takeover gate stops capture and reused arm request cannot auto-rearm", "arm();T.enabled=true;invoke('stock');assert(not TEST.state.armed and #TEST.state.events==0);T.enabled=false;tick(150);assert(not TEST.state.armed)")
run_case("native host readiness does not cancel an otherwise valid native combat sample", "arm();T.host_ready=false;tick(10);invoke('stock');assert(TEST.state.armed and #TEST.state.events==2)")
run_case("owner replacement mid-call suppresses stale post reads, original result survives", "arm();local a=enter('stock');T.entity.fields._DamageInterface=T.guard;leave(a);assert(#TEST.state.events==1 and next(TEST.state.stacks)==nil)")
run_case("scene replacement disarms and does not auto-rearm the previous request", "arm();T.scene.id=444;tick(40);assert(not TEST.state.armed and TEST.state.status=='Scene/player owner changed')")
run_case("read exception preserves both calls and returns, cleans call stack", "arm();T.health.values.get_Health=function() error('injected') end;invoke('stock');assert(not TEST.state.armed and #TEST.state.errors==1 and next(TEST.state.stacks)==nil)")
run_case("256-event limit and time limit bound passive capture", "arm();for _=1,130 do invoke('stock') end;assert(#TEST.state.events==256 and not TEST.state.armed);T.control.arm_id='test-2';tick(35);assert(TEST.state.armed);T.clock=401;tick(1);assert(not TEST.state.armed)")
run_case("duplicate implementation address rejects entire hook plan before mutation", "T.duplicate_address=true;arm();assert(next(T.hooks)==nil and not TEST.state.armed and #TEST.state.errors>0)")
run_case("disable control and reset erase active ownership without modifying native state", "arm();T.control.enabled=false;tick(31);assert(not TEST.state.armed);T.callbacks.reset();assert(TEST.state.owner==nil and next(TEST.state.stacks)==nil)")
run_case("same-call DamageInfo field produces only reflected scalars, vectors and validated game-object identities", r'''
local st=sdk.find_type_definition('app.cStockDamageInfoCharacter')
local stock={get_type_definition=function() return st end,get_address=function() return 250 end}
local function f(name,typename,value)
 return {get_name=function() return name end,is_static=function() return false end,
  get_type=function() return sdk.find_type_definition(typename) end,get_data=function() return value end}
end
sdk.find_type_definition('app.cCharacterApplyDamage.cApplyParam').fields={f('DamageInfo','app.cStockDamageInfoCharacter',stock)}
st.fields={f('Attacker','via.GameObject',T.attacker),f('Direction','via.vec3',{x=0,y=1,z=0}),
 f('Power','System.Single',2.5),f('Unexamined','app.Unexamined',function() error('must not read') end)}
arm();invoke('stock');local s=TEST.state.events[1].sample.stock_info
assert(s.game_objects.Attacker.address==14 and s.vectors.Direction.y==1 and s.scalars.Power==2.5)
tick(89);assert(#TEST.state.errors==0)
''')
run_case("flow profile installs its six methods only and identifies real enemy ownership", r'''
arm_flow();local n=0;for _ in pairs(T.hooks) do n=n+1 end;assert(n==6 and not T.hooks.guard_test)
invoke('enemy_reaction',35);assert(#TEST.state.events==2 and TEST.state.events[1].role=='enemy')
assert(TEST.state.events[1].sample.game_object==31 and TEST.state.events[2].sample.hp==1000)
local c=T.conversions;invoke('effect',999);assert(T.conversions==c)
''')
run_case("flow nested stages record current HP at both boundaries without merging different owners", r'''
arm_flow();local outer=enter('enemy_first',35);local inner=enter('first',35)
T.health.values.get_Health=800;leave(inner);leave(outer)
assert(TEST.state.events[2].parent==TEST.state.events[1].id)
assert(TEST.state.events[1].sample.hp==1000 and TEST.state.events[4].hp==800)
outer=enter('enemy_first',35);inner=enter('first',5);leave(inner);leave(outer)
assert(TEST.state.events[6].parent==nil)
tick(89);assert(#TEST.state.errors==0)
''')
run_case("flow rejects changed enemy holder in callback and skips invalid candidates", r'''
arm_flow();T.enemy_holder.values.get_Entity=T.entity
invoke('enemy_reaction',35);assert(not TEST.state.armed and #TEST.state.events==0)
''')
run_case("profile change requires reset, unknown profile cannot install hooks", r'''
arm();T.control={enabled=true,arm_id='flow-2',profile='flow'};tick(30)
assert(TEST.state.profile=='guard' and not T.hooks.enemy_first)
assert(TEST.state.status=='Profile changed; Reset Scripts required')
''')
run_case("invalid enemy module owner is excluded from the bounded registry", r'''
enemy_fixture();T.enemy_damage.values.get_OwnerCharacter=T.player
T.control={enabled=true,arm_id='flow-1',profile='flow'};tick(31)
assert(TEST.state.armed and TEST.state.targets[35]==nil)
local c=T.conversions;invoke('enemy_reaction',35);assert(T.conversions==c)
''')
print("22 guard/flow probe regression groups passed")
