"""Run production passive camera evidence code against fixed-SDK shaped objects."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
fragment=source[source.index("local function projection_vector("):source.index("local function combat_diagnostic(")]
run=lua.execute(r'''
local cfg,state,calls,primary,manager,operator,virtual,param,definition
local cases=0
local function passed(label) cases=cases+1;print('PASS '..label) end
local function finite_camera_number(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function addr(obj) return obj:get_address() end
local function td(name) assert(name=='ace.CameraDef.TARGET');calls.types=calls.types+1;return definition end
local function method(obj,name) return obj and obj:get_type_definition():get_method(name) end
local function matrix(seed)
 local columns={}
 for i=0,3 do columns[i]={x=seed+i*4,y=seed+i*4+1,z=seed+i*4+2,w=seed+i*4+3} end
 return setmetatable({}, {__index=function(_,key)
  assert(type(key)=='number' and key>=0 and key<4 and key==math.floor(key),'SDK matrix uses 0..3 columns')
  return columns[key]
 end})
end
local function object(id,methods,fields)
 local obj={methods=methods,fields=fields or {}}
 function obj:get_address() return id end
 function obj:get_type_definition() return {get_method=function(_,name) return self.methods[name] and {} or nil end} end
 function obj:call(name,...)
  calls.getters=calls.getters+1
  assert(self.methods[name],'Unexposed managed method '..name)
  return self.methods[name](...)
 end
 function obj:get_field(name)
  calls.fields=calls.fields+1;assert(self.fields[name]~=nil,'Unexposed field '..name);return self.fields[name]
 end
 return obj
end
local function setup()
 cfg={runtime_stage='C',diagnostic_only=false,install_control_hooks=true}
 state={frame=30,epoch=12,active=false}
 calls={getters=0,fields=0,types=0,singletons=0,qualified=0}
 primary=object(100,{get_LookAtPosition=function() return {x=0,y=1,z=-5} end,
  get_ViewMatrix=function() return matrix(1) end,get_ViewProjMatrix=function() return matrix(21) end})
 virtual=object(200,{get_EyePos=function() return {x=0,y=1,z=0} end,
  get_Forward=function() return {x=0,y=0,z=-1} end,get_Target=function() return 7 end})
 param=object(300,{}, {EyePos={x=0,y=1,z=0},LookAtPos={x=0,y=1,z=-5},FOV=41})
 operator=object(400,{getActiveVirtualCamera=function() return virtual end,getActiveCameraParam=function() return param end})
 local function qualified(target) assert(target==7,'TARGET must come from actual virtual camera and enum');calls.qualified=calls.qualified+1 end
 manager=object(500,{get_InGameCamera=function() return operator end,
  getCameraComponent=function(target) qualified(target);return primary end,
  getCameraComponentViewMatrix=function(target) qualified(target);return matrix(1) end,
  getCameraComponentProjectionMatrix=function(target) qualified(target);return matrix(31) end,
  getActiveCameraViewMatrix=function(target) qualified(target);return matrix(101) end})
 definition={get_fields=function() return {
  {is_static=function() return false end,is_literal=function() return false end},
  {is_static=function() return true end,is_literal=function() return true end,
   get_name=function() return 'ACTUAL_TARGET' end,get_data=function(_,owner) assert(owner==nil);return 7 end},
 } end}
 state.camera=primary;state.camera_transform={get_position=function() return {x=0,y=1,z=0} end}
 sdk={get_managed_singleton=function(name)
  assert(name=='app.CameraManager');calls.singletons=calls.singletons+1;return manager
 end}
 -- No fixture setter, sdk allocator, sdk hook or update method is exposed.
end
''' + fragment + r'''
return function()
 setup();cfg.runtime_stage='A';cfg.diagnostic_only=true
 observe_camera_projection('before_update_behavior',30)
 observe_camera_projection('before_tick',30);observe_camera_projection('after_tick',30)
 assert(calls.getters==0 and calls.fields==0 and calls.types==0 and calls.singletons==0)
 assert(state.camera_projection_diagnostic==nil and state.camera_projection_error==nil)
 passed('stage A resolves no extra object and performs no new getter/field reads')

 setup();observe_camera_projection('before_tick',31)
 cfg.install_control_hooks=false;observe_camera_projection('before_tick',30)
 cfg.install_control_hooks=true;cfg.runtime_stage='B';observe_camera_projection('before_tick',30)
 assert(calls.getters==0 and calls.fields==0 and state.camera_projection_diagnostic==nil)
 passed('sampling cadence, stage B and disabled control-hook configuration stay inert')

 setup();observe_camera_projection('before_tick',30)
 local d=state.camera_projection_diagnostic;local s=d.samples[1].phases.before_tick
 assert(#s.primary_view==16 and s.primary_view[1]==1 and s.primary_view[16]==16)
 assert(#s.errors==0 and s.target==7 and s.target_verified and s.target_name=='ACTUAL_TARGET')
 assert(d.target_enum[1].value==7 and calls.qualified==4 and calls.types==1)
 assert(s.primary_component_view_difference==0 and s.primary_active_view_difference==100)
 assert(s.primary_virtual_eye_distance==0 and s.param_fov==41)
 assert(s.primary_address=='100' and s.virtual_address=='200' and s.component_address=='100')
 passed('real zero-based matrix columns and reflected TARGET literal drive only verified getters')

 state.active=true;state.camera_transform.get_position=function() return {x=3,y=1,z=0} end
 primary.methods.get_ViewMatrix=function() return matrix(11) end
 observe_camera_projection('after_tick',30)
 local after=d.samples[1].phases.after_tick
 assert(after.primary_view_change==10 and after.active_view_change==0 and after.primary_virtual_eye_distance==3)
 assert(after.primary_active_view_difference==90 and after.active and calls.types==1)
 passed('same-frame samples distinguish changed primary from unchanged active virtual camera')

 setup();primary.methods.get_ViewMatrix=function() local m=matrix(1);m[2].y=0/0;return m end
 primary.methods.get_ViewProjMatrix=function() error('native getter temporarily unavailable') end
 param.fields.FOV=math.huge
 observe_camera_projection('after_tick',30)
 s=state.camera_projection_diagnostic.samples[1].phases.after_tick
 assert(s.primary_view==nil and s.primary_view_projection==nil and s.param_fov==nil)
 assert(#s.errors==3 and s.primary_active_view_difference==nil and state.camera_projection_error==nil)
 assert(state.active==false)
 passed('NaN and actual getter exceptions produce diagnostics without fake matrices or control effects')

 setup();definition.get_fields=function() error('enum metadata unavailable') end
 observe_camera_projection('before_tick',30)
 s=state.camera_projection_diagnostic.samples[1].phases.before_tick
 assert(not s.target_verified and s.target==7 and calls.qualified==0 and #s.errors==1)
 assert(s.active_view==nil and state.camera_projection_diagnostic.target_enum==false)
 passed('unverified TARGET never falls back to zero or calls enum-dependent camera methods')

 setup()
 for frame=30,600,30 do
  observe_camera_projection('before_update_behavior',frame)
  observe_camera_projection('before_tick',frame);observe_camera_projection('after_tick',frame)
 end
 d=state.camera_projection_diagnostic
 assert(#d.samples==16 and d.samples[1].frame==150 and d.samples[16].frame==600)
 assert(calls.types==1 and state.camera_projection_error==nil)
 assert(d.samples[16].phases.before_update_behavior and d.samples[16].phases.before_tick and d.samples[16].phases.after_tick)
 passed('sixteen frame groups retain three bounded phases and cache reflected enum metadata')
 return cases
end
''')
print(f"Camera projection regression: {run()} groups passed")
