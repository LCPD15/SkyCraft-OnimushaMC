"""Exercise actual production combat functions/hooks; observation must not alter damage or skip rules."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
helpers=source[source.index("local function combat_diagnostic("):source.index("local function publish_actors(")]
events=source[source.index("local function apply_events("):source.index("local function install_hooks(")]
hooks=source[source.index("local function install_hooks("):source.index("local function tick()")]
run=lua.execute(r'''
local cfg,state,callbacks,bridge
local cases=0
local function passed(label) cases=cases+1;print('PASS '..label) end
local function close(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b)) end
local function attempt(fn) local ok,value=pcall(fn);if ok then return value end end
local function addr(obj) return obj:get_address() end
local function typename(obj) return attempt(function() return obj:get_type_definition():get_full_name() end) or '' end
local function health(current,maximum)
 local obj={current=current,maximum=maximum,setters=0,checks=0,getters=0,calls={}}
 obj.get_address=function() return 1234 end
 obj.get_type_definition=function() return {get_full_name=function() return 'app.cHealthManager' end} end
 obj.call=function(self,name,...)
  local argc=select('#',...);self.calls[#self.calls+1]=name
  if name=='get_Health' then
   assert(argc==0);self.getters=self.getters+1
   if self.setters>0 and self.fail_readback then error('getter unavailable after mutation') end
   if self.setters>0 and self.bad_readback then return 0/0 end
   return self.current
  end
  if name=='get_MaxHealth' then assert(argc==0);return self.maximum end
  if name=='setHealth' then
   assert(argc==1 and type((...))=='number');self.setters=self.setters+1
   if self.fail_setter then error('real setter failure') end
   if self.silent_setter then return end
   self.current=...;return
  end
  if name=='checkHealthZero' then assert(argc==0);self.checks=self.checks+1;return end
  error('Unexposed managed SDK method '..name)
 end
 return obj
end
local function strictcall(obj,name,...) assert(obj);return obj:call(name,...) end
local function call(obj,name,...)
 if not obj then return nil end
 local ok,result=pcall(obj.call,obj,name,...);if ok then return result end
end
local function same(a,b) return a==b end
local function td(type_name)
 return {get_method=function(_,name)
  return {get_function=function() return 4660 end,get_num_params=function() return 0 end,name=name,type_name=type_name}
 end}
end
sdk={PreHookResult={SKIP_ORIGINAL=777},to_managed_object=function(value) return value end,
 to_int64=function(value) return value end,
 hook=function(method,pre,post) callbacks[method.name]={pre=pre,post=post} end}
local function setup()
 cfg={enemy_host_damage_per_mc_point=10,mirror_native_damage_to_mc=true}
 state={active=true,frame=42,epoch=10,health_revision=1,health_bypass=0,health_remainder=0,
  hooks={},bindings={},player={},health=health(800,1000),actors={}}
 local go={get_address=function() return 4321 end,call=function(_,name)
  if name=='get_Valid' then return true end
  if name=='get_DrawSelf' then return false end
  error('Unexposed GameObject method '..name)
 end}
 local enemy={get_address=function() return 5678 end,call=function(_,name)
  assert(name=='get_GameObject');return go
 end}
 state.actors.enemy={id=9,health=health(80,100),obj=enemy,name='verified enemy',position={x=1,y=2,z=3},width=1,height=2}
 callbacks={}
 bridge={drain_events=function() return {} end,send_hurt=function(_) return true end}
 onimusha_mc=bridge
 return state.actors.enemy.health
end
local function latest(list) local values=state.combat[list];return values[#values] end
local function count(group,name) return (state.combat.counters[group] or {})[name] or 0 end
local function callback(name,value,obj)
 return callbacks[name or 'addHealth(System.Int32, System.Boolean)'].pre({[2]=obj or state.health,[3]=value})
end
''' + helpers + events + hooks + r'''
local function deliver(event_list)
 bridge.drain_events=function() return event_list end;apply_events(bridge)
end
return function()
 local enemy=setup()
 deliver({{type=1,form_id=9,a=2.25,weapon=1,flags=0}})
 assert(enemy.current==58 and enemy.setters==1 and enemy.checks==1 and state.health_revision==2)
 local event=latest('events');local write=latest('writes')
 assert(event.outcome=='applied' and event.target_id==9 and event.target_name=='verified enemy')
 assert(event.before==80 and event.requested==58 and event.after==58 and event.host_damage==22.5)
 assert(event.target_position.x==1 and event.target_width==1 and event.target_height==2)
 assert(event.target_health_type=='app.cHealthManager' and event.target_health_address=='1234')
 assert(event.target_object_address=='5678' and event.target_gameobject_address=='4321')
 assert(event.target_valid==true and event.target_draw_self==false)
 assert(write.role=='enemy' and write.before==80 and write.actual_delta==-22)
 assert(count('enemy_hits','received')==1 and count('enemy_hits','accepted')==1 and count('enemy_hits','applied')==1)
 passed('EV1 retains original scaled damage/rounding, target identity and actual getter readback')

 enemy=setup();enemy.current=5
 deliver({{type=1,form_id=9,a=2000},{type=1,form_id=9,a=1}})
 assert(enemy.current==0 and enemy.setters==2 and enemy.checks==2 and state.health_revision==3)
 assert(state.combat.events[1].host_damage==10000 and latest('events').outcome=='noop')
 assert(count('enemy_hits','applied')==1 and count('enemy_hits','noop')==1)
 passed('EV1 clipping and unchanged-at-zero setter calls retain original behavior')

 enemy=setup()
 deliver({{type=1,form_id=123,a=7},{type=1,form_id=9,a=0},{type=1,form_id=9,a=-5}})
 assert(enemy.current==80 and enemy.setters==0 and enemy.checks==0 and state.health_revision==1)
 assert(state.combat.events[1].reason=='unknown_actor' and count('enemy_hits','rejected')==1)
 assert(count('enemy_hits','accepted')==2 and count('enemy_hits','noop')==2)
 passed('unknown target and zero/negative MC damage remain unwritten with distinct reasons')

 setup()
 deliver({{type=6,weapon=10,a=-0.0123,b=-0.246,form_id=0,flags=1}})
 assert(state.health.current==788 and state.health.setters==1);close(state.health_remainder,-0.3)
 event=latest('events');assert(event.integer==-12 and event.protocol_weapon==10 and event.event_epoch==10)
 close(event.fraction,-0.0123);close(event.mc_points,-0.246);close(event.remainder_after,-0.3)
 deliver({{type=6,weapon=10,a=-0.0005,b=-0.01},{type=6,weapon=10,a=-0.0005,b=-0.01}})
 assert(state.health.current==787 and state.health.setters==2 and state.health.checks==2)
 close(state.health_remainder,-0.3)
 assert(state.combat.events[2].outcome=='noop' and state.combat.events[2].reason=='rounded_to_zero')
 passed('EV6 percentage and fractional remainder preserve original ceiling/floor and zero-write rules')

 setup();state.health.current=995
 deliver({{type=6,weapon=10,a=0.012,b=0.24,flags=2},{type=6,weapon=10,a=0,b=0}})
 assert(state.health.current==1000 and state.health.setters==1 and state.health.checks==1)
 assert(state.combat.events[1].requested==1000 and state.combat.events[1].after==1000)
 assert(latest('events').outcome=='noop' and state.health_revision==2)
 passed('healing clamps to original max and a zero fraction does not add a setter call')

 enemy=setup();state.active=false
 deliver({{type=1,form_id=9,a=7},{type=6,weapon=10,a=-0.2}})
 assert(count('enemy_hits','rejected')==1 and count('health_changes','rejected')==1)
 assert(state.combat.events[1].reason=='inactive' and state.combat.events[2].reason=='inactive')
 state.active=true;deliver({{type=6,weapon=9,a=-0.2},{type=6,weapon=10,a=2}})
 assert(state.combat.events[3].reason=='stale_epoch' and state.combat.events[4].reason=='invalid_fraction')
 state.health.maximum=nil;deliver({{type=6,weapon=10,a=-0.2}})
 assert(latest('events').reason=='health_max_unavailable' and type(latest('events').reason)=='string')
 state.health.maximum=0;deliver({{type=6,weapon=10,a=-0.2}})
 assert(latest('events').reason=='health_max_unavailable')
 assert(state.health.current==800 and enemy.current==80 and state.health.setters==0 and enemy.setters==0)
 passed('inactive/stale/invalid/missing max retain discarded/no-write rules and string reasons')

 setup();state.health.fail_readback=true
 deliver({{type=6,weapon=10,a=-0.1,b=-2}})
 assert(state.health.current==700 and state.health.setters==1 and state.health.checks==1)
 assert(state.health_revision==2 and state.health_bypass==0)
 event=latest('events');assert(event.outcome=='unconfirmed' and event.write_completed and event.after==nil)
 assert(event.readback_error:find('getter unavailable',1,true) and count('writes','readback_failed')==1)
 assert(count('health_changes','accepted')==1 and count('health_changes','applied')==0)
 passed('post-write getter failure is diagnostic only and never retries or throws a new gameplay error')

 setup();state.health.bad_readback=true
 deliver({{type=6,weapon=10,a=-0.1}})
 assert(state.health.current==700 and state.health_revision==2 and state.health_bypass==0)
 assert(latest('events').outcome=='unconfirmed' and latest('writes').readback_error=='Native HP readback is not finite')
 passed('non-finite getter result is bounded diagnostic data and preserves successful original mutation')

 setup();state.health.silent_setter=true
 deliver({{type=6,weapon=10,a=-0.1}})
 assert(state.health.current==800 and state.health.setters==1 and state.health.checks==1 and state.health_revision==2)
 event=latest('events');assert(event.outcome=='unconfirmed' and event.reason=='readback_mismatch')
 assert(event.before==800 and event.requested==700 and event.after==800 and event.readback_matches==false)
 assert(count('health_changes','accepted')==1 and count('health_changes','applied')==0)
 passed('a silent no-op setter reports mismatch without inventing damage or adding a retry')

 setup();state.health.fail_setter=true
 local ok,err=pcall(deliver,{{type=6,weapon=10,a=-0.1}})
 assert(not ok and tostring(err):find('real setter failure',1,true))
 assert(state.health.current==800 and state.health.setters==1 and state.health.checks==0)
 assert(state.health_revision==1 and state.health_bypass==0 and latest('events').reason=='health_write_failed')
 assert(latest('writes').reason=='setter_failed' and count('health_changes','rejected')==1)
 passed('existing setter error still propagates with bypass/revision/error rules preserved')

 setup();local sends=0;local last
 bridge.send_hurt=function(value) sends=sends+1;last=value;return true end
 install_hooks();local result=callback(nil,-50)
 assert(result==777 and sends==1 and last.kind==0 and last.flags==4 and last.attacker_id==0)
 close(last.mc_points,1)
 local incoming=latest('incoming');assert(incoming.outcome=='accepted' and incoming.before==800 and incoming.maximum==1000)
 assert(state.hooks['addHealth(System.Int32, System.Boolean)'].queued_hurts==1 and state.health.setters==0)
 result=callback('set_Health(System.Int32)',750)
 assert(result==777 and sends==2 and state.hooks['set_Health(System.Int32)'].queued_hurts==1)
 assert(count('incoming','accepted')==2 and state.health.current==800)
 passed('both actual production health hook callbacks retain accepted queue and SKIP_ORIGINAL rules')

 for _,kind in ipairs({'bridge_rejected','bridge_unavailable','inactive','health_bypass','mirroring_disabled'}) do
  setup();sends=0;bridge.send_hurt=function() sends=sends+1;return false end
  if kind=='bridge_unavailable' then onimusha_mc={} end
  if kind=='inactive' then state.active=false end
  if kind=='health_bypass' then state.health_bypass=1 end
  if kind=='mirroring_disabled' then cfg.mirror_native_damage_to_mc=false end
  install_hooks();result=callback(nil,-50)
  assert(result==nil and latest('incoming').reason==kind and count('incoming','rejected')==1)
  assert(state.health.setters==0 and state.health.current==800)
  assert(sends==(kind=='bridge_rejected' and 1 or 0))
  assert(state.hooks['addHealth(System.Int32, System.Boolean)'].queued_hurts==0)
 end
 setup();install_hooks();callback(nil,0);callback(nil,50);callback(nil,-50,health(400,1000))
 assert(state.combat==nil and state.hooks['addHealth(System.Int32, System.Boolean)'].queued_hurts==0)
 passed('hook failures/inactive/bypass/disabled and zero/heal/nonplayer calls retain original fail-open paths')

 setup();install_hooks()
 for i=1,40 do
  state.frame=i;deliver({{type=1,form_id=9,a=1}});callback(nil,-1)
 end
 assert(#state.combat.events==16 and #state.combat.writes==16 and #state.combat.incoming==16)
 assert(state.combat.events[1].frame==25 and state.combat.writes[1].frame==25 and state.combat.incoming[1].frame==25)
 assert(count('enemy_hits','received')==40 and count('writes','received')==40 and count('incoming','received')==40)
 passed('three real production telemetry lists retain only latest 16 without capping truthful counters')
 setup()
 _G.onimusha_enemy_hit={queue=function(entry,owner,damage,trace)
  assert(entry.id==9 and owner==state and damage==7*cfg.enemy_host_damage_per_mc_point)
  trace.outcome='queued_native';return true
 end}
 deliver({{type=1,form_id=9,a=7}})
 assert(latest('events').outcome=='queued_native' and state.actors.enemy.health.setters==0)
 _G.onimusha_enemy_hit.queue=function(_,_,_,trace) trace.outcome='native_unconfirmed';return true end
 deliver({{type=1,form_id=9,a=7}})
 assert(state.actors.enemy.health.setters==0)
 _G.onimusha_enemy_hit=nil
 cfg.require_native_enemy_damage=true
 local before=enemy.current;local setters=enemy.setters
 deliver({{type=1,form_id=9,a=7}})
 assert(enemy.current==before and enemy.setters==setters and latest('events').reason=='native_enemy_damage_not_ready')
 _G.onimusha_enemy_hit={queue=function() return false end}
 deliver({{type=1,form_id=9,a=7}})
 assert(enemy.current==before and enemy.setters==setters and latest('events').reason=='native_enemy_damage_not_ready')
 cfg.require_native_enemy_damage=false;_G.onimusha_enemy_hit=nil
 passed('missing/off native module cannot silently fall back to direct HP in production mode')
 passed('optional native queue owns both success and ambiguous failure without direct HP fallback')
 return cases
end
''')
count=run()
assert count==15
print(f"COMBAT_TELEMETRY_REGRESSION_OK {count} actual-production cases; LUA54_COMPLETE_SYNTAX_OK")
