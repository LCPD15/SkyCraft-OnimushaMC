"""Exercise the production synchronous hit-source hook, including nested/foreign hits."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

base = Path(__file__).resolve().parents[1]
source = (base / "onimusha_mc.lua").read_text(encoding="utf-8-sig")
fixture = (base / "tests/combat_telemetry_regression.py").read_text(encoding="utf-8-sig")
prefix = fixture.split("run=lua.execute(r'''", 1)[1].split("''' + helpers", 1)[0]
helpers = source[source.index("local function combat_diagnostic("):source.index("local function publish_actors(")]
hooks = source[source.index("local function install_hooks("):source.index("local function tick()")]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(prefix + r'''
local raw_td=td
local function type_info(name)
 return {get_full_name=function() return name end,is_a=function(_,n) return n==name end,
 is_value_type=function() return false end,is_by_ref=function() return false end,is_pointer=function() return false end}
end
local apply_name='app.cCharacterApplyDamage.cApplyParam'
local signature='execThirdDamage('..apply_name..')'
td=function(name)
 if name==apply_name then return type_info(name) end
 if name=='app.cCharacterApplyDamage' then
  return {get_method=function(_,n)
   assert(n==signature)
   return {name=n,get_function=function() return 9001 end,is_static=function() return false end,
    get_num_params=function() return 1 end,get_param_types=function() return {type_info(apply_name)} end,
    get_declaring_type=function() return type_info(name) end,get_return_type=function() return type_info('System.Void') end}
  end}
 end
 return raw_td(name)
end
local storage,thread_id,param,stock,damage,entity,attacker,sent
thread={get_hash=function() return thread_id end,get_hook_storage=function() return storage end}
sdk.get_tdb_version=function() return 82 end
sdk.is_managed_object=function(v) return v==77 end
sdk.to_managed_object=function(v) if v==77 then return param end;return v end
local function native_setup()
 setup();storage={};thread_id=1;sent=nil
 state.player.get_address=function() return 89 end
 state.player_go={get_address=function() return 90 end}
 attacker=state.actors.enemy.obj:call('get_GameObject')
 entity={get_field=function(_,n) assert(n=='_DamageInterface');return damage end,
  call=function(_,n) assert(n=='get_OwnerCharacter');return state.player end}
 damage={get_address=function() return 92 end,get_type_definition=function() return type_info('app.cPlayerApplyDamage') end,
  call=function(_,n)
   if n=='get_Valid' then return true end;if n=='get_IsDestroy' then return false end
   if n=='get_OwnerCharacter' then return state.player end;error(n)
  end}
 local holder={call=function(_,n) assert(n=='get_Entity');return entity end}
 state.player.call=function(_,n) assert(n=='get_CharacterEntityHolder');return holder end
 stock={get_type_definition=function() return type_info('app.cStockDamageInfoCharacter') end,
  call=function(_,n) if n=='get_Receiver' then return state.player_go end
   if n=='get_Attacker' then return attacker end;error(n)
  end}
 param={get_type_definition=function() return type_info(apply_name) end,
  get_field=function(_,n) assert(n=='DamageInfo');return stock end}
 bridge.send_hurt=function(value) sent=value;return true end
end
''' + helpers + hooks + r'''
local function start(raw_this,raw_param)
 local prev=storage;storage={}
 assert(callbacks[signature].pre({[2]=raw_this or 92,[3]=raw_param or 77})==nil)
 return {prev=prev,current=storage}
end
local function finish(scope)
 storage=scope.current;assert(callbacks[signature].post(8123)==8123);storage=scope.prev
end
local function hurt(expected)
 assert(callback(nil,-50)==777 and sent.attacker_id==expected and sent.mc_points==1)
 assert(state.health.current==800)
end
native_setup();install_hooks();assert(state.hooks.hurt_source.error==nil)
local a=start();hurt(9);finish(a);hurt(0)
assert(state.hooks.hurt_source.matched_sources==1)
passed('actual HP callback gets same-call generic actor ID; outside scope reverts to unknown')

native_setup();install_hooks();a=start(999);hurt(0);finish(a)
a=start(92,0);hurt(0);finish(a)
passed('foreign damage owner and invalid parameter never borrow another hit source')

native_setup();install_hooks();a=start();local b=start(92,0);hurt(0);finish(b);hurt(9);finish(a)
passed('nested unknown hit masks and then restores the outer same-thread source')

native_setup();install_hooks();a=start();thread_id=2;hurt(0);thread_id=1;hurt(9);finish(a)
passed('another thread cannot observe the synchronous hit source')

native_setup();install_hooks();a=start();state.epoch=11;hurt(0);finish(a)
native_setup();install_hooks();a=start();state.frame=43;hurt(0);finish(a)
passed('changed session or frame invalidates a captured source')

native_setup();install_hooks();stock.call=function(_,n) if n=='get_Receiver' then return attacker end end
a=start();hurt(0);finish(a)
passed('receiver must be the exact current player game object')

native_setup();install_hooks();a=start();state.actors.enemy.id=10;hurt(0);finish(a)
native_setup();install_hooks();attacker={call=function(_,n) return n=='get_Valid' end};a=start();hurt(0);finish(a)
passed('removed/changed actor and unknown attacker never get a nearest-enemy substitute')

native_setup();install_hooks();a=start();bridge.send_hurt=function() return false end
assert(callback(nil,-50)==nil and state.health.current==800);finish(a)
passed('source enrichment does not suppress original damage on failed queue delivery')

native_setup();install_hooks();param.get_field=function() error('borrowed parameter unavailable') end
a=start();hurt(0);finish(a);assert(state.hooks.hurt_source.error)
passed('source read failure leaves original call intact and cleans scope')
print('HURT_SOURCE_REGRESSION_OK '..cases..' production-hook groups')
''')
