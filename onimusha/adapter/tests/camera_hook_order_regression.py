"""Run production passive hooks with exact fixed-SDK metadata and nested hook storage."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
class RawPointer:
    """Lupa exposes this as userdata, like fixed-SDK void* hook slots."""
    def __init__(self, value): self.value=value
lua.globals().sdk_pointer=RawPointer
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
values=source[source.index("local function owned_camera_value("):source.index("local function owned_camera_equal(")]
hooks=source[source.index("local function camera_hook_sample("):source.index("local function combat_diagnostic(")]
replay=source[source.index("local function replay_cached_mc_camera("):source.index("local function camera_hook_sample(")]
application_callbacks=source[source.index('re.on_pre_application_entry("UpdateBehavior"'):source.index('re.on_draw_ui(')]
run=lua.execute(r'''
local cfg,state,calls,callbacks,definitions,methods,storage,owner
local cases=0
local function passed(label) cases=cases+1;print('PASS '..label) end
local function finite_camera_number(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function positive_fov(v) return finite_camera_number(v) and v>0 end
local function addr(obj) return obj:get_address() end
local function same(a,b) return a and b and addr(a)==addr(b) end
local function method(obj,name) return obj and obj:get_type_definition():get_method(name) end
local function strictcall(obj,name,...) assert(method(obj,name),'Unexposed leaf getter '..name);return obj:call(name,...) end
local function typeinfo(name) return {get_full_name=function() return name end} end
local function identity(id) return {get_address=function() return id end} end
local function pointer(value) return sdk_pointer(value) end
local function td(name) calls.metadata=calls.metadata+1;return definitions[name] end
local signatures={
 {'manager_late','app.CameraManager','lateUpdate()',{},'System.Void'},
 {'reflect_component','ace.CameraManagerBase','reflectGameCameraToCameraComponent(via.Camera, ace.CameraControllerBase)',{'via.Camera','ace.CameraControllerBase'},'System.Void'},
 {'screen_active','app.cInGameCameraOperator','convertWorldPos2ScreenPosActiveCamera(via.vec3)',{'via.vec3'},'via.vec2'},
 {'screen_depth_active','app.cInGameCameraOperator','convertWorldPos2ScreenPosDepthActiveCamera(via.vec3)',{'via.vec3'},'via.vec3'},
 {'screen_world','ace.CameraManagerBase','convertWorldPos2ScreenPos(via.vec3, System.Nullable`1<via.Size>, ace.CameraDef.TARGET)',{'via.vec3','System.Nullable`1<via.Size>','ace.CameraDef.TARGET'},'via.vec2'},
 {'screen_projected_world','ace.CameraManagerBase','convertWorldPos2ProjectedScreenPos(via.vec3, System.Nullable`1<via.Size>, ace.CameraDef.TARGET)',{'via.vec3','System.Nullable`1<via.Size>','ace.CameraDef.TARGET'},'via.vec2'},
 {'manager_update','app.CameraManager','update()',{},'System.Void'},
 {'manager_render_pre','app.CameraManager','preproccessOfUpdateRenderCamera()',{},'System.Void'},
}
local function setup()
 cfg={runtime_stage='C',diagnostic_only=false,install_control_hooks=true}
 state={frame=29,epoch=10,active=true,camera_observation_phase='before_update_behavior'}
 calls={metadata=0,installed=0,leaf_reads=0,conversions=0};callbacks={};definitions={};methods={};storage={}
 owner={manager=identity(100),operator=identity(200),controller=identity(300),primary=identity(400),virtual=identity(500),target=7}
 owner.param={get_field=function(_,name) assert(name=='FOV');calls.leaf_reads=calls.leaf_reads+1;return 41 end}
 state.active_camera_restore=owner;state.camera=owner.primary
 state.camera.get_type_definition=function() return {get_method=function(_,name) return name=='get_FOV' and {} or nil end} end
 state.camera.call=function(_,name) assert(name=='get_FOV');calls.leaf_reads=calls.leaf_reads+1;return 70 end
 state.camera_transform={get_position=function() calls.leaf_reads=calls.leaf_reads+1;return {x=1,y=2,z=3} end,
  get_rotation=function() calls.leaf_reads=calls.leaf_reads+1;return {x=0,y=0,z=0,w=1} end}
 for i,spec in ipairs(signatures) do
  local m={label=spec[1],address=1000+i,params=spec[4],returns=spec[5],static=false}
  function m:get_function() if self.address==nil then return nil end;return pointer(self.address) end
  function m:is_static() return self.static end
  function m:get_num_params() return #self.params end
  function m:get_return_type() return typeinfo(self.returns) end
  function m:get_param_types() local result={};for _,name in ipairs(self.params) do result[#result+1]=typeinfo(name) end;return result end
  local definition=definitions[spec[2]]
  if not definition then definition={entries={},get_method=function(self,name) return self.entries[name] end};definitions[spec[2]]=definition end
  definition.entries[spec[3]]=m;methods[spec[1]]=m
 end
 sdk={to_managed_object=function(v) calls.conversions=calls.conversions+1;error('Unsafe managed argument conversion is forbidden') end,
  to_int64=function(v) assert(type(v)=='userdata','Fixed SDK to_int64 expects void*');return v.value end,PreHookResult={SKIP_ORIGINAL=999},
  hook=function(m,pre,post) calls.installed=calls.installed+1;callbacks[m.label]={pre=pre,post=post} end}
 -- Intentionally expose no manager getters, matrix getters, game setter or allocator.
thread={get_hook_storage=function() return storage end}
end
local function args(label)
 if label=='reflect_component' then return {[2]=pointer(addr(owner.manager)),[3]=pointer(addr(owner.primary)),[4]=pointer(addr(owner.controller))} end
 if label=='screen_active' or label=='screen_depth_active' then return {[2]=pointer(addr(owner.operator))} end
 if label=='screen_world' or label=='screen_projected_world' then return {[2]=pointer(addr(owner.manager)),[5]=pointer(owner.target)} end
 return {[2]=pointer(addr(owner.manager))}
end
local function invoke(label,a)
 local old=storage;storage={};local token={retval='original'}
 assert(callbacks[label].pre(a or args(label))==nil,'Observer must not SKIP_ORIGINAL')
 assert(callbacks[label].post(token)==token,'Observer must return exact original retval')
 storage=old
end
''' + values + replay + hooks + r'''
local applications,marker_samples={},{ }
re={on_pre_application_entry=function(name,fn) assert(name=='UpdateBehavior');applications.pre=fn end,
 on_application_entry=function(name,fn) assert(name=='LateUpdateBehavior');applications.post=fn end}
local function observe_camera_projection(phase,frame)
 marker_samples[#marker_samples+1]={phase=phase,frame=frame,marker=state.camera_observation_phase,marker_frame=state.camera_observation_frame}
end
local function tick() assert(state.camera_observation_phase=='late_before_tick' and state.camera_observation_frame==state.frame) end
local function fail_open(reason) error('Unexpected callback failure '..tostring(reason)) end
''' + application_callbacks + r'''
return function()
 setup();install_camera_observation_hooks()
 assert(calls.installed==8 and calls.leaf_reads==0 and calls.conversions==0)
 install_camera_observation_hooks();assert(calls.installed==8)
 for label,m in pairs(state.camera_hooks.methods) do assert(m.attempted and m.observed_calls==0 and not m.install_error) end
 passed('exact eight instance signatures install once; attempts are distinct from natural dispatch counts')

 state.active=false
 for _,spec in ipairs(signatures) do invoke(spec[1]) end
 assert(calls.leaf_reads==0 and calls.conversions==0 and #state.camera_hooks.samples==0)
 for _,record in pairs(state.camera_hooks.methods) do assert(record.observed_calls==1 and record.post_calls==1) end
 state.active=true;state.frame=30
 for _,spec in ipairs(signatures) do invoke(spec[1]) end
 assert(calls.leaf_reads==0 and calls.conversions==0 and #state.camera_hooks.samples==0)
 passed('inactive and non-sampling invocations only count and preserve original execution/retval')

 state.frame=29
 for _,spec in ipairs(signatures) do invoke(spec[1]) end
 assert(#state.camera_hooks.samples==12 and calls.leaf_reads==48)
 for i,sample in ipairs(state.camera_hooks.samples) do
  assert(sample.seq==i and sample.frame==30 and sample.lua_frame==29 and sample.target==7)
  assert(sample.application_phase=='before_update_behavior' and sample.fov==70 and sample.param_fov==41)
  assert(sample.forward.x==0 and sample.forward.y==0 and sample.forward.z==-1 and #sample.errors==0)
 end
 passed('sampled natural order records leaf pose/FOV only; projection hooks have pre samples only')

 local before=calls.leaf_reads
 for i=1,100 do for _,spec in ipairs(signatures) do invoke(spec[1]) end end
 assert(#state.camera_hooks.samples==12 and calls.leaf_reads==before)
 for _,record in pairs(state.camera_hooks.methods) do assert(record.observed_calls==103 and record.post_calls==103 and record.sampled_pre==1) end
 passed('per-hook phase cadence bounds getter cost while raw dispatch counters remain truthful')

 setup();install_camera_observation_hooks()
 invoke('manager_late',{[2]=pointer(999)})
 invoke('reflect_component',{[2]=pointer(addr(owner.manager)),[3]=pointer(addr(owner.primary)),[4]=pointer(999)})
 invoke('screen_active',{[2]=pointer(999)})
 invoke('screen_world',{[2]=pointer(addr(owner.manager)),[5]=pointer(8)})
 assert(#state.camera_hooks.samples==0 and calls.leaf_reads==0)
 passed('actual this/component/controller/TARGET identities refuse unrelated observation reads')

 setup();install_camera_observation_hooks();local token={}
 local outer_storage={};storage=outer_storage
 assert(callbacks.manager_late.pre(args('manager_late'))==nil)
 assert(callbacks.reflect_component.pre(args('reflect_component'))==nil)
 assert(callbacks.reflect_component.post(token)==token)
 assert(callbacks.manager_late.post(token)==token)
 assert(#state.camera_hooks.samples==4)
 assert(state.camera_hooks.samples[1].label=='manager_late' and state.camera_hooks.samples[2].label=='reflect_component')
 assert(state.camera_hooks.samples[3].phase=='post' and state.camera_hooks.samples[4].label=='manager_late')
 setup();install_camera_observation_hooks();callbacks.manager_late.pre(args('manager_late'))
 state.epoch=11;assert(callbacks.manager_late.post(token)==token and #state.camera_hooks.samples==1)
 passed('independent fixed-thread storage keys preserve nested pairing and reject stale epoch posts')

 setup();install_camera_observation_hooks()
 for frame=29,599,30 do state.frame=frame;for _,spec in ipairs(signatures) do invoke(spec[1]) end end
 assert(#state.camera_hooks.samples==64 and state.camera_hooks.samples[1].seq==177 and state.camera_hooks.samples[64].seq==240)
 for _,record in pairs(state.camera_hooks.methods) do assert(record.observed_calls==20 and record.sampled_pre==20) end
 passed('total observation ring remains 64 without truncating cumulative dispatch counts')

 setup();methods.manager_late.static=true;methods.reflect_component.returns='via.vec3'
 methods.screen_active.params={'via.vec2'};definitions['app.cInGameCameraOperator'].entries[signatures[4][3]]=nil
 install_camera_observation_hooks();assert(calls.installed==4)
 for _,label in ipairs({'manager_late','reflect_component','screen_active','screen_depth_active'}) do
  assert(not state.camera_hooks.methods[label].attempted and state.camera_hooks.methods[label].install_error)
 end
 setup();methods.screen_projected_world.address=methods.manager_late.address
 install_camera_observation_hooks();assert(calls.installed==7)
 assert(not state.camera_hooks.methods.screen_projected_world.attempted and state.camera_hooks.methods.screen_projected_world.install_error:find('Duplicate',1,true))
 passed('static/return/parameter/missing method and duplicate thunk checks reject installation visibly')

 setup();methods.manager_late.address=nil;methods.reflect_component.address=0
 methods.screen_active.address=-1;methods.screen_depth_active.address=math.huge
 install_camera_observation_hooks();assert(calls.installed==4)
 for _,label in ipairs({'manager_late','reflect_component','screen_active','screen_depth_active'}) do
  assert(not state.camera_hooks.methods[label].attempted and state.camera_hooks.methods[label].install_error)
 end
 setup();install_camera_observation_hooks()
 -- A hidden struct return slot may shift this/target. Never wrap or dereference it.
 invoke('screen_active',{[2]=pointer(901),[3]=pointer(addr(owner.operator))})
 invoke('screen_depth_active',{[2]=pointer(902),[3]=pointer(addr(owner.operator))})
 invoke('screen_world',{[2]=pointer(903),[3]=pointer(addr(owner.manager)),[6]=pointer(owner.target)})
 assert(#state.camera_hooks.samples==0 and calls.leaf_reads==0 and calls.conversions==0)
 assert(state.camera_hooks.methods.screen_active.observed_calls==1 and not state.camera_hooks.methods.screen_active.callback_error)
 passed('real void* shaped null/zero/invalid functions and shifted struct-return slots refuse safely without managed dereference')

 for _,stage in ipairs({'A','B'}) do
  setup();cfg.runtime_stage=stage;cfg.diagnostic_only=stage=='A';install_camera_observation_hooks()
  assert(calls.installed==0 and calls.metadata==0 and calls.leaf_reads==0 and state.camera_hooks==nil)
 end
 setup();cfg.install_control_hooks=false;install_camera_observation_hooks();assert(calls.installed==0 and calls.metadata==0)
 setup();install_camera_observation_hooks();cfg.runtime_stage='A';cfg.diagnostic_only=true;invoke('manager_late')
 assert(calls.leaf_reads==0 and calls.conversions==0 and #state.camera_hooks.samples==0)
 passed('cold A/B install no hooks/read metadata and hot downgrade performs no camera observation reads')

 setup();install_camera_observation_hooks();state.camera.call=function() error('leaf read unavailable') end
 invoke('manager_late');assert(#state.camera_hooks.samples==2)
 assert(#state.camera_hooks.samples[1].errors==1 and not state.camera_hooks.methods.manager_late.callback_error)
 thread.get_hook_storage=function() error('SDK thread storage unavailable') end
 invoke('reflect_component');assert(state.camera_hooks.methods.reflect_component.callback_error and #state.camera_hooks.samples==2)
 passed('leaf/storage failures are visible bounded diagnostics and never alter pre/post return semantics')

 setup();install_camera_observation_hooks();marker_samples={}
 applications.pre();invoke('manager_update')
 assert(state.frame==29 and state.camera_hooks.samples[1].frame==30 and state.camera_hooks.samples[1].application_phase=='before_update_behavior')
 applications.post();invoke('screen_active');invoke('manager_late')
 assert(state.frame==30 and #state.camera_hooks.samples==5 and #marker_samples==3)
 for _,sample in ipairs(marker_samples) do assert(sample.frame==30 and sample.marker_frame==30) end
 assert(marker_samples[1].marker=='before_update_behavior' and marker_samples[2].marker=='late_before_tick' and marker_samples[3].marker=='late_after_tick')
 for i=3,5 do assert(state.camera_hooks.samples[i].frame==30 and state.camera_hooks.samples[i].application_phase=='late_after_tick') end
 passed('production application callbacks share one logical sampling frame before update, before tick and after tick')
 return cases
end
''')
print(f"CAMERA_HOOK_ORDER_REGRESSION_OK {run()} actual-production groups; LUA54_COMPLETE_SYNTAX_OK")
