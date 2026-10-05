"""Execute the adapter's actual hot reload function in Lua 5.4.
Checks that F10's runtime state survives unchanged or unrelated stage-C settings.
"""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
fragment=source[source.index("local function reload_config()"):source.index("local function discover()")]
lua=LuaRuntime(unpack_returned_tuples=True)
run=lua.execute("""
local cfg,next_config,state
local calls,open_calls=0,0
log={info=function() end}
local function read_config() return next_config end
local function fail_open() open_calls=open_calls+1;state.active=false end
"""+fragment+"""
return function(previous,incoming,native_enabled)
 cfg=previous;next_config=incoming;state={frame=1,active=true}
 calls=0;open_calls=0
 onimusha_mc={enabled=native_enabled,set_enabled=function(value) calls=calls+1;onimusha_mc.enabled=value end}
 reload_config()
 return calls,onimusha_mc.enabled,open_calls
end
""")
def config(stage="C",enabled=False,radius=32):
 return {"runtime_stage":stage,"enabled":enabled,"config_reload_frames":120,
         "units_per_block":1,"tile_stride":8192,"collision_radius":radius,"enable_terrain_queries":stage!="A"}
cases=[
 ("unchanged C preserves F10",config(),config(),True,(0,True,0)),
 ("unrelated C tuning preserves F10",config(),config(radius=24),True,(0,True,1)),
 ("C to A disables",config(),config(stage="A"),True,(1,False,1)),
 ("C to B disables",config(),config(stage="B"),True,(1,False,1)),
 ("explicit enabled true applies",config(),config(enabled=True),False,(1,True,1)),
 ("explicit enabled false applies",config(enabled=True),config(),True,(1,False,1)),
 ("B to C applies configured preference",config(stage="B"),config(enabled=True),False,(1,True,1)),
]
for label,previous,incoming,native,expected in cases:
 actual=run(lua.table_from(previous),lua.table_from(incoming),native)
 assert actual==expected,(label,actual,expected)
 print("PASS",label)
print(f"RUNTIME_TOGGLE_REGRESSION_OK {len(cases)} actual-Lua-5.4 cases")
