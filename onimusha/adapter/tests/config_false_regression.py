"""Execute the adapter's actual config loader in Lua 5.4, including false values.
Run with Python and the local Lupa dependency on PYTHONPATH.
"""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / "onimusha_mc.lua").read_text(encoding="utf-8-sig")
fragment = source[source.index('local CFG_FILE ='):source.index('local cfg = read_config()')]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('json={load_file=function() return test_config end}')
read_config = lua.execute(fragment + '\nreturn read_config')

cases = [
    ({}, {"runtime_stage":"A", "diagnostic_only":True, "mirror_native_damage_to_mc":True}),
    ({"runtime_stage":"B", "diagnostic_only":False, "enable_terrain_queries":True},
     {"runtime_stage":"B", "diagnostic_only":False, "enable_terrain_queries":True, "install_control_hooks":False}),
    ({"runtime_stage":"B", "diagnostic_only":False, "install_control_hooks":True, "enable_native_block_colliders":True,
      "enable_block_collider_tests":True, "enable_health_hook_tests":True},
     {"install_control_hooks":False, "enable_native_block_colliders":False, "enable_block_collider_tests":False,
      "enable_health_hook_tests":False}),
    ({"runtime_stage":"C", "diagnostic_only":False, "install_control_hooks":True, "mirror_native_damage_to_mc":False,
      "enable_native_block_colliders":False, "enable_block_collider_tests":False, "enable_health_hook_tests":False},
     {"runtime_stage":"C", "diagnostic_only":False, "install_control_hooks":True, "mirror_native_damage_to_mc":False,
      "enable_native_block_colliders":False, "enable_block_collider_tests":False, "enable_health_hook_tests":False}),
    ({"runtime_stage":"C", "diagnostic_only":False, "install_control_hooks":False, "enable_terrain_queries":False},
     {"diagnostic_only":False, "install_control_hooks":False, "enable_terrain_queries":False}),
    ({"runtime_stage":"C", "diagnostic_only":"false"}, {"diagnostic_only":True}),
    ({"runtime_stage":"INVALID", "diagnostic_only":False, "install_control_hooks":True},
     {"runtime_stage":"A", "diagnostic_only":True, "install_control_hooks":False}),
]
for index,(raw,expected) in enumerate(cases,1):
    lua.globals().test_config = lua.table_from(raw)
    actual = read_config()
    for key,value in expected.items():
        assert actual[key] == value, (index,key,actual[key],value)
print(f"CONFIG_FALSE_REGRESSION_OK {len(cases)} actual-Lua-5.4 cases")
