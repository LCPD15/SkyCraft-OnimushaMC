"""Execute the real config/save/UI callbacks and ensure tuning never releases takeover."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'onimusha_mc.lua').read_text(encoding='utf-8-sig')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.eval('function(s) local f,e=load(s);assert(f,e) end')(source)
config = source[source.index('local CFG_FILE'):source.index('local session =')]
save = source[source.index('local function save_damage_multiplier('):source.index('local function persist_session(')]
reload = source[source.index('local function reload_config('):source.index('local function discover(')]
ui = source[source.index('re.on_draw_ui(function()'):source.index('_G.onimusha_adapter_lifecycle=')]
lua.execute(r'''
local disk={runtime_stage='C',diagnostic_only=false,enabled=false,external_key='preserve'}
local writes,write_fail,read_fail=0,false,false
local function copy(t) local c={};for k,v in pairs(t)do c[k]=v end;return c end
json={load_file=function() if read_fail then error('unreadable')end;return copy(disk)end,
 dump_file=function(_,value) if write_fail then return false end;disk=copy(value);writes=writes+1;return true end}
''' + config + r'''
local state={active=true,epoch=27,frame=1,config_revision=4,collision_ready=true,bindings={}}
local restores,invalidations,toggles=0,0,0
local function fail_open() restores=restores+1;state.active=false end
local function invalidate_collision_coverage() invalidations=invalidations+1;state.collision_ready=false end
log={info=function()end}
_G.onimusha_mc={status=function()return {enabled=true}end,set_enabled=function()toggles=toggles+1 end}
''' + save + reload + r'''
local callback,drag,button
re={on_draw_ui=function(fn)callback=fn end}
imgui={tree_node=function()return true end,tree_pop=function()end,text=function()end,same_line=function()end,
 checkbox=function(_,v)return false,v end,
 drag_float=function(_,value,speed,lo,hi) assert(speed==10 and lo==100 and hi==5000);return drag~=nil,drag or value end,
 button=function(label)return button==label end}
''' + ui + r'''
local cases=0
local function passed(label) cases=cases+1;print('PASS '..label)end
assert(cfg.enemy_host_damage_per_mc_point==100 and read_config().enemy_host_damage_per_mc_point==100)
assert(normalize_damage_multiplier(0/0)==100 and normalize_damage_multiplier(math.huge)==100
 and normalize_damage_multiplier(-math.huge)==100 and normalize_damage_multiplier('5')==100)
disk.enemy_host_damage_per_mc_point=0/0;assert(read_config().enemy_host_damage_per_mc_point==100)
disk.enemy_host_damage_per_mc_point=-10;assert(read_config().enemy_host_damage_per_mc_point==100)
disk.enemy_host_damage_per_mc_point=9000;assert(read_config().enemy_host_damage_per_mc_point==5000)
disk.enemy_host_damage_per_mc_point=nil
passed('old configs preserve100; malformed, non-finite and out-of-range user input is bounded')

button='500##onimusha_damage';callback();button=nil
assert(cfg.enemy_host_damage_per_mc_point==500 and disk.enemy_host_damage_per_mc_point==500 and writes==1)
assert(disk.external_key=='preserve' and disk.enabled==false and state.active and toggles==0)
reload_config();assert(restores==0 and invalidations==0 and state.epoch==27 and state.config_revision==4)
assert(state.collision_ready and read_config().enemy_host_damage_per_mc_point==500)
passed('actual preset callback saves and reloads500 without toggling F10 or invalidating terrain')

drag=750;callback();drag=nil
assert(cfg.enemy_host_damage_per_mc_point==750 and disk.enemy_host_damage_per_mc_point==750)
button='100##onimusha_damage';callback();button=nil
assert(cfg.enemy_host_damage_per_mc_point==100 and disk.enemy_host_damage_per_mc_point==100)
passed('drag and100 restore button persist through the real UI callback')

write_fail=true;drag=2000;callback();drag=nil;write_fail=false
assert(cfg.enemy_host_damage_per_mc_point==100 and disk.enemy_host_damage_per_mc_point==100 and state.damage_setting_error)
local before=writes;read_fail=true;assert(not save_damage_multiplier(1000));read_fail=false
assert(writes==before and cfg.enemy_host_damage_per_mc_point==100 and disk.external_key=='preserve')
assert(save_damage_multiplier(1000) and not state.damage_setting_error)
passed('failed read/write leaves live factor unchanged and reports failure; later save recovers')

disk.enemy_host_damage_per_mc_point=5000;reload_config()
assert(cfg.enemy_host_damage_per_mc_point==5000 and state.active and state.collision_ready)
assert(restores==0 and invalidations==0 and toggles==0 and state.config_revision==4)
passed('external damage-only config update is immediate without session/terrain reset')

disk.collision_radius=32;reload_config()
assert(restores==1 and invalidations==1 and not state.active and state.config_revision==5)
passed('unrelated terrain config changes still follow required restoration path')
print('DAMAGE_UI_REGRESSION_OK '..cases..' groups')
''')
