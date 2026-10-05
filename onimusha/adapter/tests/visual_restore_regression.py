"""Exercise production visual capture/release with actual managed call signatures."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
fragment=source[source.index("local function positive_fov("):source.index("local function reload_config()")]
lua=LuaRuntime(unpack_returned_tuples=True)
run=lua.execute(r"""
local state
local writes=0
local function addr(obj) return obj.id end
local function call(obj,name,...) return obj:call(name,...) end
local function strictcall(obj,name,...) return obj:call(name,...) end
local function elements(value) return value end
local function restore_player_input_seals() end
local function set_boxes_enabled() end
local function managed(id,draw,fov)
 local obj={id=id,draw=draw,fov=fov,valid=true}
 obj.call=function(self,name,...)
  local count=select('#',...)
  if name=='get_Valid' then assert(count==0);return self.valid end
  if name=='get_DrawSelf' then assert(count==0);return self.draw end
  if name=='get_FOV' then assert(count==0);return self.fov end
  if name=='set_DrawSelf' then
   local value=...;assert(count==1 and type(value)=='boolean');writes=writes+1
   if self.fail_draw then error('temporary draw setter failure') end
   self.draw=value;return
  end
  if name=='set_FOV' then
   local value=...;assert(count==1 and type(value)=='number');writes=writes+1
   if self.fail_fov then return end -- Real SDK void setter can fail without throwing.
   self.fov=value;return
  end
  error('Unexposed SDK method '..name)
 end
 return obj
end
local function setup()
 writes=0
 local body=managed('body',true)
 local part=managed('part',false)
 local camera=managed('camera',nil,41)
 local context={call=function(_,name) assert(name=='get_Parts');return {body,part} end}
 state={player_go=body,camera=camera,context=context,hidden=false,active=false}
 return body,part,camera
end
"""+fragment+r"""
return function()
 local body,part,camera=setup()
 body.draw=nil
 local ok,err=pcall(capture_player_visuals)
 assert(not ok and tostring(err):find('DrawSelf must be Boolean',1,true) and writes==0)
 assert(not state.draw_targets and not state.fov_restore)
 print('PASS missing Boolean DrawSelf prevents all visual writes and baseline commit')
 for _,invalid in ipairs({0,-1,0/0,math.huge}) do
  body,part,camera=setup();camera.fov=invalid
  ok,err=pcall(capture_player_visuals)
  assert(not ok and tostring(err):find('finite positive',1,true) and writes==0 and not state.fov_restore)
 end
 print('PASS invalid original FOV prevents takeover')
 body,part,camera=setup();capture_player_visuals()
 assert(#state.draw_targets==2 and state.original_fov==41 and writes==0)
 state.active=true;state.hidden=true;body.draw=false;camera.fov=60
 body.fail_draw=true;camera.fail_fov=true
 state.camera=managed('replacement-camera',nil,75)
 fail_open('test release')
 assert(not state.active and state.hidden and #state.draw_targets==1)
 assert(state.draw_targets[1].obj==body and state.original_fov==41 and state.fov_restore.obj==camera)
 assert(state.visual_restore_diagnostic.pending_draw==1 and state.visual_restore_diagnostic.pending_fov)
 assert(state.visual_restore_diagnostic.fov_error:find('failed readback',1,true))
 assert(restoration_pending())
 body.fail_draw=false;camera.fail_fov=false
 fail_open('retry')
 assert(not restoration_pending() and not state.hidden and #state.draw_targets==0)
 assert(not state.fov_restore and not state.original_fov and body.draw==true and part.draw==false)
 assert(camera.fov==41 and state.camera.fov==75)
 assert(state.visual_restore_diagnostic.draw_writes==1 and state.visual_restore_diagnostic.fov_writes==1)
 local before=writes;fail_open('already restored');assert(writes==before)
 print('PASS draw/FOV failure preserves exact owner and values; retry restores once')
end
""")
run()
print("VISUAL_RESTORE_REGRESSION_OK")
