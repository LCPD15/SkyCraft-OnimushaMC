"""Exercise the actual native queue boundary, ownership and no-retry contract."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'onimusha_enemy_hit.lua').read_text(encoding='utf-8-sig')
lua = LuaRuntime(unpack_returned_tuples=True)
assert lua.eval('function(s) local f,e=load(s);assert(f,e);return true end')(source)
lua.execute(r'''
local nextaddr=100
function obj(name,methods,fields)
 nextaddr=nextaddr+1;local id=nextaddr
 return {get_address=function() return id end,
 get_type_definition=function() return {get_full_name=function() return name end,
  get_method=function() return true end,is_a=function(_,n) return n==name end} end,
 call=function(_,n,...) assert(methods[n],'Unexpected call '..name..'.'..n);return methods[n](...) end,
 get_field=function(_,n) return fields[n] end,add_ref=function() end}
end
local factory,engine
function setup()
 engine={queues=0,duplicates=0,hp=2000,origin={},fail=false}
 factory=function()
  local attack,fixed=100,0
  return obj('app.cAttackRuntimeParamPlayer',{
   ['duplicate()']=function() engine.duplicates=engine.duplicates+1;return factory() end,
   get_OriginData=function() return engine.asset end,
   get_Attack=function() return attack end,get_FixedAttack=function() return fixed end,
   get_RikidoAttack=function() return 150 end,get_BreakAttack=function() return 75 end,
   set_Attack=function(n) attack=n end,set_FixedAttack=function(n) fixed=n end,
  },{})
 end
 engine.asset=obj('app.cAttackParamDataPlayer',{}, {})
 engine.sc=obj('via.Scene',{}, {})
 engine.weapon=obj('via.GameObject',{get_Valid=function() return engine.weaponvalid~=false end},{})
 engine.health=obj('app.cHealthManager',{get_Health=function() return engine.hp end},{})
 local module=obj('app.cEnemyApplyDamage',{get_Valid=function() return true end,get_IsDestroy=function() return false end},{})
 local transform={get_position=function() return {x=engine.distance or 1,y=0,z=0} end}
 local pt={get_position=function() return {x=0,y=0,z=0} end}
 engine.pgo=obj('via.GameObject',{get_Valid=function() return true end,get_Transform=function() return pt end},{})
 engine.ego=obj('via.GameObject',{get_Valid=function() return engine.enemyvalid~=false end,get_Transform=function() return transform end},{})
 engine.entity=obj('app.cEnemyCharacterEntity',{get_OwnerCharacter=function() return engine.enemy end},{_DamageInterface=module})
 local nativecall=engine.entity.call
 engine.entity.call=function(self,n,...)
  if n:match('^stockDirectDamage') then
   local a,w,r,pos,dir,av,norm,ap,az,part,receiver=...
   assert(a==engine.pgo and w==engine.weapon and pos.y>0 and part==0 and receiver==nil)
   assert(not dir:get_field('_HasValue'))
   engine.queues=engine.queues+1;engine.queued_runtime=r
   if engine.fail then error('Injected ambiguous enqueue failure') end
   if engine.nilresult then return nil end
   return obj('app.cStockDamageInfoCharacter',{
    get_Receiver=function() return engine.wrongreceiver and engine.pgo or engine.ego end,
    get_Attacker=function() return a end,get_AttackParamData=function() return r end,
    get_Attack=function() return r:call('get_Attack') end,get_FixedDamageAttack=function() return r:call('get_FixedAttack') end},{})
  end
  return nativecall(self,n,...)
 end
 local holder=obj('holder',{get_Entity=function() return engine.entity end},{})
 local chara=obj('chara',{get_HealthManager=function() return engine.health end},{})
 local context=obj('context',{get_Chara=function() return chara end},{})
 engine.enemy=obj('app.EnemyCharacter',{get_GameObject=function() return engine.ego end,
  get_CharacterEntityHolder=function() return holder end,get_Context=function() return context end},{})
 engine.pe=obj('app.cPlayerCharacterEntity',{get_OwnerCharacter=function() return engine.player end},{})
 local ph=obj('holder',{get_Entity=function() return engine.pe end},{})
 engine.player=obj('app.PlayerCharacter',{get_GameObject=function() return engine.pgo end,
  get_CharacterEntityHolder=function() return ph end},{})
 local info=obj('info',{get_Valid=function() return true end,get_CharacterValid=function() return true end,
  get_Character=function() return engine.player end},{})
 engine.pm=obj('pm',{isPlayerReady=function() return true end,getControllingPlayerInfo=function() return info end},{})
 sdk={get_managed_singleton=function() return engine.pm end,get_native_singleton=function() return 1 end,
  call_native_func=function() return engine.sc end,find_type_definition=function(n) return n end}
 Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
 ValueType={new=function() local f={};return {set_field=function(_,n,v) f[n]=v end,get_field=function(_,n) return f[n] end} end}
 _G.onimusha_mc={status=function() return {enabled=false} end}
 engine.runtime=factory()
 engine.stock=obj('app.cStockDamageInfoCharacter',{
  get_Attacker=function() return engine.pgo end,get_AttackObj=function() return engine.weapon end},{})
 return engine
end
function engine_state() return engine end
''')
module = lua.execute(source.split('_G.onimusha_enemy_hit={queue=queue}', 1)[0] + '''
return {queue=queue,capture=capture,state=function() return s end,resolve=resolve_player,initialize=initialize}
''')
lua.globals().module = module
lua.execute(r'''
local cases=0
local function passed(n) cases=cases+1;print('PASS '..n) end
local function prepare()
 local e=setup();local s=module.state();s.mode='capture';s.templates={};s.capture_info={};s.captured_ids={};s.errors={};s.pending={};s.events={};s.initialized=true
 local p={get_field=function() return 12 end}
 module.capture({stock=e.stock,runtime=e.runtime,param=p,go=e.ego})
 assert(#s.templates==1 and s.templates[1].runtime~=e.runtime)
 s.selected={1}
 s.mode='trial';s.trial_remaining=1
 return e,s,{active=true,player=e.player,player_go=e.pgo},{id=9,obj=e.enemy,health=e.health,height=1.8}
end
local e,s,b,t=prepare();local tr={}
assert(module.queue(t,b,700,tr)==true and e.queues==1 and e.hp==2000 and tr.outcome=='queued_native')
assert(e.runtime:call('get_Attack')==100 and e.runtime:call('get_FixedAttack')==0)
assert(e.queued_runtime:call('get_FixedAttack')==700)
passed('enqueue once without manual HP mutation or modifying original attack asset')
assert(module.queue(t,b,700,{})==true and e.queues==1)
passed('single-hit trial budget prevents repeated native requests')

e,s,b,t=prepare();s.mode='off';assert(module.queue(t,b,700,{})==false and e.queues==0)
passed('off mode leaves existing adapter route available')
e,s,b,t=prepare();e.fail=true;tr={}
assert(module.queue(t,b,700,tr)==true and e.queues==1 and tr.outcome=='native_unconfirmed')
assert(module.queue(t,b,700,{})==true and e.queues==1 and e.hp==2000)
passed('exception after enqueue never retries or falls back to a second HP write')
e,s,b,t=prepare();e.nilresult=true;tr={};assert(module.queue(t,b,700,tr) and tr.reason=='native_enqueue_returned_nil' and e.queues==1)
passed('native null result is a rejection, not a retry')
e,s,b,t=prepare();e.wrongreceiver=true;tr={};assert(module.queue(t,b,700,tr) and tr.outcome=='native_unconfirmed' and e.queues==1)
passed('unexpected native result cannot trigger another damage route')
for _,fault in ipairs({'scene','player','weapon','enemy','health','distance','dead','inactive','nan'}) do
 e,s,b,t=prepare();tr={}
 if fault=='scene' then e.sc=obj('via.Scene',{}, {})
 elseif fault=='player' then b.player=e.enemy
 elseif fault=='weapon' then e.weaponvalid=false
 elseif fault=='enemy' then e.enemyvalid=false
 elseif fault=='health' then t.health=obj('health',{}, {})
 elseif fault=='distance' then e.distance=50
 elseif fault=='dead' then e.hp=0
 elseif fault=='inactive' then b.active=false end
 assert(module.queue(t,b,fault=='nan' and 0/0 or 700,tr)==true and e.queues==0 and tr.outcome=='rejected',fault)
end
passed('changed scene/player/weapon/target/health, distant/dead targets and invalid requests rejected before native call')
e,s,b,t=prepare();s.mode='capture';s.templates={}
e.stock.call=function(_,n) if n=='get_Attacker' then return e.ego end end
module.capture({stock=e.stock,runtime=e.runtime});assert(#s.templates==0)
passed('enemy attacks cannot become the shared player-hit template')

e,s,b,t=prepare();s.mode='capture'
local p={get_field=function() return 13 end}
module.capture({stock=e.stock,runtime=e.runtime,param=p,go=e.ego})
module.capture({stock=e.stock,runtime=e.runtime,param=p,go=e.ego})
assert(#s.templates==2)
s.selected={1,2};local chosen={}
math.randomseed(823)
for i=1,32 do
 s.mode='trial';s.trial_remaining=1;local result={}
 assert(module.queue(t,b,700,result) and result.outcome=='queued_native')
 chosen[result.native_template]=true
end
assert(chosen[1] and chosen[2] and e.queues==32)
passed('two generic profiles selected at random, duplicate natural hit not captured twice')

e,s,b,t=prepare()
local count=0
sdk.get_tdb_version=function() return 82 end
sdk.to_int64=function(n) return n end
sdk.hook=function() count=count+1 end
sdk.find_type_definition=function(name)
 local td={get_full_name=function() return name end,is_value_type=function() return false end}
 td.get_fields=function() return {{get_name=function() return 'test' end,get_type=function() return td end,
  get_offset_from_base=function() return 16 end}} end
 td.get_methods=function() return {} end
 td.get_method=function(_,sig) return {get_declaring_type=function() return td end,get_num_params=function() return 1 end,
  is_static=function() return false end,get_function=function() return 99 end,
  get_return_type=function() return {get_full_name=function() return 'System.Void' end} end} end
 return td
end
module.initialize();assert(count==4 and s.initialized)
passed('metadata initialization uses fixed SDK field API and installs all hook plans')
print('NATIVE_ENEMY_HIT_REGRESSION_OK '..cases..' groups')
''')
