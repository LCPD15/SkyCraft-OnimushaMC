"""Run the production reset callback and restoration helpers after a stage-C to A downgrade."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / "onimusha_mc.lua").read_text(encoding="utf-8-sig")
helpers = source[source.index("local function capture_player_input_seals()"):source.index("local function reload_config()")]
reset = source[source.index("re.on_script_reset(function()"):source.index('log.info("[OnimushaMC] adapter loaded;')]
lua = LuaRuntime(unpack_returned_tuples=True)
run = lua.execute(r"""
local state, reset_callback
local cfg = {runtime_stage='A', diagnostic_only=true}
local input_writes, fov_writes, draw_writes, box_calls, clear_calls, bridge_calls
local function addr(obj) return obj.id end
local function call(obj,name,...) return obj:call(name,...) end
local function strictcall(obj,name,...) return obj:call(name,...) end
local function set_boxes_enabled(value) assert(value==false);box_calls=box_calls+1 end
local function clear_boxes() clear_calls=clear_calls+1 end
re={on_script_reset=function(callback) reset_callback=callback end}
onimusha_mc={set_enabled=function() bridge_calls=bridge_calls+1 end}
local function setup(pending_input,pending_fov,permanent_failure)
 input_writes,fov_writes,draw_writes,box_calls,clear_calls,bridge_calls=0,0,0,0,0,0
 state={active=false,hidden=false,draw_targets={},blocks={}}
 local input={value=true,set_field=function(self,key,value)
  assert(key=='_SealAll' and value==false);input_writes=input_writes+1
  if not permanent_failure then self.value=value end
 end}
 local field={get_data=function(_,obj) return obj.value end}
 if pending_input then
  state.input_seals={attempted=true,restore_pending=true,inputs=1,keys=0,arrays={},
   records={{obj=input,field=field,name='_SealAll',original=false}}}
 end
 local camera={fov=60,call=function(self,name,...)
  if name=='get_FOV' then assert(select('#',...)==0);return self.fov end
  if name=='set_FOV' then
   assert(select('#',...)==1);local value=...;assert(value==41);fov_writes=fov_writes+1
   if not permanent_failure then self.fov=value end
   return
  end
  if name=='set_DrawSelf' then draw_writes=draw_writes+1;error('No draw mutation is owned') end
  error('Unexpected visual call '..name)
 end}
 if pending_fov then state.fov_restore={obj=camera,original=41};state.original_fov=41 end
 -- Restoration must target the retained owner, not an unrelated replacement camera.
 state.camera={fov=75}
 return input,camera
end
""" + helpers + reset + r"""
return function()
 setup(false,false,false);reset_callback()
 assert(input_writes==0 and fov_writes==0 and draw_writes==0 and box_calls==0 and clear_calls==0 and bridge_calls==0)
 print('PASS cold stage A reset performs no managed or bridge writes')
 local input,camera=setup(true,false,false);reset_callback()
 assert(input.value==false and not state.input_seals and input_writes==1 and fov_writes==0)
 assert(not restoration_pending() and box_calls==1 and clear_calls==1 and bridge_calls==0)
 print('PASS downgraded stage A reset restores input-only pending owner')
 input,camera=setup(false,true,false);reset_callback()
 assert(camera.fov==41 and state.camera.fov==75 and not state.fov_restore and not state.original_fov)
 assert(fov_writes==1 and input_writes==0 and draw_writes==0 and not restoration_pending())
 print('PASS downgraded stage A reset restores FOV-only pending owner with drawing already restored')
 input,camera=setup(true,true,false);reset_callback()
 assert(input.value==false and camera.fov==41 and state.camera.fov==75 and not restoration_pending())
 assert(input_writes==1 and fov_writes==1 and draw_writes==0 and bridge_calls==0)
 print('PASS downgraded stage A reset restores combined pending input and FOV')
 input,camera=setup(true,true,true);reset_callback()
 assert(input.value==true and camera.fov==60 and state.input_seals.restore_pending and state.fov_restore.obj==camera)
 assert(restoration_pending() and not state.active and input_writes==1 and fov_writes==1)
 assert(state.input_seal_diagnostic.pending_records==1 and state.visual_restore_diagnostic.pending_fov)
 print('PASS permanently failing setters remain pending after the reset attempt; success is not claimed')
end
""")
run()
print("RESET_RESTORE_REGRESSION_OK 5 actual-Lua-5.4 cases")
