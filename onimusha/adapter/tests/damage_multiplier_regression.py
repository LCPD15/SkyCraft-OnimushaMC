"""Check new defaults and run the actual combat setter/event/hook code at scale100."""
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime

adapter=Path(__file__).resolve().parents[1]
source=(adapter/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
fixture=(adapter/"tests"/"combat_telemetry_regression.py").read_text(encoding="utf-8-sig")
prefix=fixture.split("run=lua.execute(r'''",1)[1].split("''' + helpers",1)[0]
defaults=source[source.index("local defaults = {"):source.index("local function read_config()")]
helpers=source[source.index("local function combat_diagnostic("):source.index("local function publish_actors(")]
events=source[source.index("local function apply_events("):source.index("local function install_hooks(")]
hooks=source[source.index("local function install_hooks("):source.index("local function tick()")]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
for name in ("onimusha_mc_config.json","onimusha_mc_config.stage-A.json","onimusha_mc_config.stage-B.json","onimusha_mc_config.stage-C.json"):
    config=json.loads((adapter.parent/"config"/name).read_text(encoding="utf-8-sig"))
    assert config["enemy_host_damage_per_mc_point"]==100,name
print("PASS all four source default/stage configs set native damage per MC point to100")
run=lua.execute(prefix+defaults+helpers+events+hooks+r'''
local function deliver(list) bridge.drain_events=function() return list end;apply_events(bridge) end
local function setup_scale(value)
 local enemy=setup();cfg.enemy_host_damage_per_mc_point=value or defaults.enemy_host_damage_per_mc_point
 enemy.current=5000;enemy.maximum=5000;return enemy
end
return function()
 assert(defaults.enemy_host_damage_per_mc_point==100 and defaults.mirror_native_damage_to_mc==true)
 local enemy=setup_scale();deliver({{type=1,form_id=9,a=7}})
 assert(enemy.current==4300 and enemy.setters==1 and enemy.checks==1)
 assert(latest('events').host_damage==700 and latest('events').host_damage_scale==100)
 assert(latest('writes').actual_delta==-700 and state.health.current==800 and state.health.setters==0)
 passed('actual seven-point MC hit writes700 native damage once, leaving player HP untouched')

 enemy=setup_scale(10);deliver({{type=1,form_id=9,a=7}});local old=5000-enemy.current
 enemy=setup_scale();deliver({{type=1,form_id=9,a=7}});local new=5000-enemy.current
 assert(old==70 and new==old*10 and new~=old*100 and enemy.setters==1 and enemy.checks==1)
 passed('old explicit scale10 versus new default100 changes damage exactly tenfold with no second multiplier')

 for _,factor in ipairs({100,500,1000,2000,5000}) do
  enemy=setup_scale(factor);enemy.current=90000;enemy.maximum=90000
  deliver({{type=1,form_id=9,a=7}})
  close(enemy.current,90000-7*factor)
  assert(latest('events').damage_multiplier==factor/100 and latest('events').base_host_damage_scale==100)
  assert(not latest('events').damage_capped and enemy.setters==1)
 end
 passed('100/500/1000/2000/5000 presets multiply actual MC damage once;100 preserves previous damage')
 enemy=setup_scale(5000);enemy.current=200000;enemy.maximum=200000
 deliver({{type=1,form_id=9,a=1000}})
 assert(enemy.current==100000 and latest('events').damage_capped and latest('events').host_damage==100000)
 passed('high user multiplier caps at native queue limit instead of rejecting all damage')

 enemy=setup_scale();deliver({{type=1,form_id=9,a=2.255}})
 assert(enemy.current==4775 and enemy.setters==1);close(latest('events').host_damage,225.5)
 assert(latest('writes').actual_delta==-225)
 enemy=setup_scale();deliver({{type=1,form_id=9,a=2.256}})
 assert(enemy.current==4774 and latest('writes').actual_delta==-226)
 passed('fractional MC damage retains existing native nearest-integer rounding around the half-HP boundary')

 enemy=setup_scale();deliver({{type=1,form_id=9,a=0},{type=1,form_id=9,a=-7},{type=1,form_id=123,a=7}})
 assert(enemy.current==5000 and enemy.setters==0 and enemy.checks==0)
 assert(count('enemy_hits','noop')==2 and count('enemy_hits','rejected')==1)
 passed('zero/negative MC damage and unknown actor remain unwritten at the new scale')

 enemy=setup_scale();enemy.current=650;deliver({{type=1,form_id=9,a=7}})
 assert(enemy.current==0 and enemy.setters==1 and enemy.checks==1 and state.health_revision==2)
 assert(latest('events').host_damage==700 and latest('writes').actual_delta==-650)
 enemy=setup_scale();enemy.current=99000;enemy.maximum=99000;deliver({{type=1,form_id=9,a=2000}})
 assert(enemy.current==0 and enemy.setters==1 and enemy.checks==1)
 assert(latest('events').host_damage==100000)
 passed('overkill clamps native HP tozero and calls checkHealthZero once; MC input cap remains1000 before scaling')

 setup_scale(5000)
 deliver({{type=6,weapon=10,a=-0.1,b=-2},{type=6,weapon=10,a=0.1,b=2}})
 assert(state.health.current==800 and state.health.setters==2 and state.health.checks==2)
 assert(state.combat.events[1].integer==-100 and state.combat.events[2].integer==100)
 install_hooks();local sent;bridge.send_hurt=function(value) sent=value;return true end
 assert(callback(nil,-50)==777 and sent);close(sent.mc_points,1)
 assert(state.health.current==800)
 passed('percent damage/healing and native50-of1000 damage to one MC point remain independent of enemy scale')
 return cases
end
''')
print(f"DAMAGE_MULTIPLIER_REGRESSION_OK {run()+1} actual-production/config groups; LUA54_COMPLETE_SYNTAX_OK")
