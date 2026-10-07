"""Exercise the real tile-selection path across a verified seamless area boundary."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
s=(Path(__file__).resolve().parents[1]/'onimusha_mc.lua').read_text(encoding='utf-8')
body=s[s.index('local function canonical_world_key('):s.index('local function vec(v)')]
LuaRuntime().execute('''
local state={tile_map={['stage:0:area:13']={index=8,x=57344,z=0},['stage:0:area:14']={index=9,x=65536,z=0}},
world_aliases={['stage:0:area:14']='stage:0:area:13'},world_key='stage:0:area:13',epoch=10,teleport_seq=20,bindings={}}
local cfg={tile_stride=8192};local resets=0
local function fail_open() resets=resets+1 end
local function persist_session() end
local function invalidate_collision_coverage() end
local function clear_boxes() end
json={dump_file=function() end}
''' + body + '''
for i=1,50 do assert(choose_world(i%2==0 and 'stage:0:area:13' or 'stage:0:area:14')) end
assert(resets==0 and state.epoch==10 and state.teleport_seq==20 and state.world_key=='stage:0:area:13')
assert(choose_world('stage:20:area:78'))
assert(resets==1 and state.epoch==11 and state.teleport_seq==21)
state.world_aliases['stage:20:area:78']='stage:0:area:13'
assert(not pcall(choose_world,'stage:20:area:78'))
state.world_aliases['stage:0:area:14']='stage:0:area:99'
assert(not pcall(choose_world,'stage:0:area:14'))
print('PASS verified seamless boundary retains epoch/tile; real stage transitions reset; invalid aliases rejected')
''')
