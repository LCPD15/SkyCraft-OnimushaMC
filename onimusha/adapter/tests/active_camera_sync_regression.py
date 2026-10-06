"""Execute production six-write camera ownership, synchronization and release code."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
helpers=source[source.index("local function owned_camera_value("):source.index("local function capture_player_visuals(")]
release=source[source.index("local function restoration_pending("):source.index("local function invalidate_collision_coverage(")]
reset=source[source.index("re.on_script_reset(function()"):source.index('log.info("[OnimushaMC] adapter loaded;')]
run=lua.execute(r'''
local cfg,state,manager,operator,virtual,controller,param,transform,primary,primary_transform,enum,calls
local cases=0
local reset_callback
local function passed(label) cases=cases+1;print('PASS '..label) end
local function finite_camera_number(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function positive_fov(v) return finite_camera_number(v) and v>0 end
local function copy(v) if type(v)~='table' then return v end;local result={};for k,x in pairs(v) do result[k]=x end;return result end
Vector3f={new=function(x,y,z) assert(type(x)=='number' and type(y)=='number' and type(z)=='number');return {x=x,y=y,z=z} end}
Vector4f={new=function(x,y,z,w) assert(w==1);return {x=x,y=y,z=z,w=w} end}
Quaternion={new=function(w,x,y,z) assert(type(w)=='number' and type(x)=='number' and type(y)=='number' and type(z)=='number');return {w=w,x=x,y=y,z=z} end}
local function td(name) assert(name=='ace.CameraDef.TARGET');calls.reads=calls.reads+1;return enum end
local function addr(obj) return obj:get_address() end
local function same(a,b) return a and b and addr(a)==addr(b) end
local function typename(obj) return obj and obj:get_type_definition():get_full_name() or '' end
local function method(obj,name) return obj and obj:get_type_definition():get_method(name) end
local function strictcall(obj,name,...)
 assert(obj and method(obj,name),'Missing real managed method '..name);return obj:call(name,...)
end
local function object(id,type_name,methods,field_types,values)
 local obj={methods=methods or {},values=values or {},field_types=field_types or {},pins=0}
 function obj:get_address() return id end
 function obj:get_type_definition()
  return {get_full_name=function() return type_name end,
   get_method=function(_,name) return self.methods[name] and {} or nil end,
   get_field=function(_,name)
    local ftype=self.field_types[name]
    if ftype then return {get_type=function() return {get_full_name=function() return ftype end} end} end
   end}
 end
 function obj:call(name,...)
  calls.reads=calls.reads+1;assert(self.methods[name],'Unexposed managed method '..name)
  return self.methods[name](...)
 end
 function obj:get_field(name)
  calls.reads=calls.reads+1;assert(self.field_types[name]);return self.values[name]
 end
 function obj:set_field(name,value)
  assert(self.field_types[name]);calls.writes=calls.writes+1
  if self.field_types[name]=='via.vec3' then assert(value.w==nil,'Managed via.vec3 must use Vector3f') end
  if self.fail_field==name then error('actual managed field setter failure') end
  if not self.silent_field then self.values[name]=copy(value) end
 end
 function obj:add_ref() self.pins=self.pins+1 end
 return obj
end
local function make_transform(id,position,rotation)
 local obj=object(id,'via.Transform');obj.position=copy(position);obj.rotation=copy(rotation)
 function obj:get_position() calls.reads=calls.reads+1;return self.position end
 function obj:get_rotation() calls.reads=calls.reads+1;return self.rotation end
 function obj:set_position(value,no_dirty)
  assert(no_dirty==false and value.w==1);calls.writes=calls.writes+1
  if self.restore_failures and value.x==0 then self.restore_failures=self.restore_failures-1;if self.restore_failures>=0 then error('actual transform restore failure') end end
  self.position={x=value.x,y=value.y,z=value.z}
 end
 function obj:set_rotation(value)
  calls.writes=calls.writes+1;self.rotation=copy(value)
  if self.negate_quaternion then for k,v in pairs(self.rotation) do self.rotation[k]=-v end end
 end
 return obj
end
local function camera(id,tr)
 local obj=object(id,'ace.VirtualCamera');obj.fov=41
 local go=object(id+1,'via.GameObject',{get_Transform=function() return tr end})
 go.valid=true;go.methods.get_Valid=function() return go.valid end;obj.go=go
 obj.methods={get_Target=function() return 7 end,get_GameObject=function() return go end,
  get_FOV=function() return obj.fov end,
  set_FOV=function(value)
   calls.writes=calls.writes+1
   if obj.fail_fov then error('actual FOV setter failure') end
   obj.fov=value
  end}
 return obj
end
local function setup()
 calls={reads=0,writes=0};cfg={runtime_stage='C',diagnostic_only=false,install_control_hooks=true}
 state={active=true,frame=42,epoch=10,hooks={},bindings={},blocks={},hidden=false}
 transform=make_transform(101,{x=0,y=1,z=5},{w=1,x=0,y=0,z=0});virtual=camera(200,transform)
 primary_transform=make_transform(301,{x=10,y=2,z=-3},{w=0.70710678,x=0,y=0.70710678,z=0})
 primary=camera(400,primary_transform);primary.fov=70
 primary.methods.get_LookAtPosition=function() return {x=9,y=2,z=-3} end
 param=object(500,'ace.cCameraParam',{}, {EyePos='via.vec3',LookAtPos='via.vec3',FOV='System.Single'},
  {EyePos={x=0,y=1,z=5},LookAtPos={x=0,y=1,z=0},FOV=41})
 controller=object(600,'app.GameCameraController',{get_Camera=function() return virtual end,getCurrentParam=function() return param end})
 operator=object(700,'app.cInGameCameraOperator',{getActiveVirtualCamera=function() return virtual end,getActiveCameraParam=function() return param end})
 manager=object(800,'app.CameraManager',{get_InGameCamera=function() return operator end,
  getCameraComponent=function(target) assert(target==7);return primary end,
  getActiveCamera=function(target) assert(target==7);return controller end})
 enum={get_fields=function() return {
  {is_static=function() return true end,is_literal=function() return true end,get_name=function() return 'ACTUAL_TARGET' end,
   get_data=function(_,owner) assert(owner==nil);return 7 end},
  {is_static=function() return true end,is_literal=function() return true end,get_name=function() return 'MAX' end,
   get_data=function(_,owner) assert(owner==nil);return 8 end},
 } end}
 sdk={get_managed_singleton=function(name) assert(name=='app.CameraManager');calls.reads=calls.reads+1;return manager end}
 state.camera=primary;state.camera_transform=primary_transform
 _G.onimusha_mc={set_enabled=function(value) assert(value==false) end}
end
local function restore_player_input_seals() end
local function restore_player_visuals() end
local function set_boxes_enabled() end
local function clear_boxes() end
re={on_script_reset=function(fn) reset_callback=fn end}
''' + helpers + release + reset + r'''
return function()
 setup();local owner=prepare_owned_active_camera()
 assert(#owner.records==6 and transform.pins==1 and virtual.pins==1 and param.pins==1 and calls.writes==0)
 assert(sync_owned_active_camera(owner) and calls.writes==6)
 assert(transform.position.x==10 and virtual.fov==70 and param.values.EyePos.x==10 and param.values.LookAtPos.x==9 and param.values.FOV==70)
 assert(state.camera_sync_diagnostic.checked_records==6 and state.camera_sync_diagnostic.applied)
 fail_open('Disabled')
 assert(not state.active and not restoration_pending() and calls.writes==12)
 assert(transform.position.x==0 and transform.rotation.w==1 and virtual.fov==41 and param.values.EyePos.x==0 and param.values.LookAtPos.z==0 and param.values.FOV==41)
 assert(state.camera_sync_diagnostic.restored_records==6 and state.camera_sync_diagnostic.pending_records==0)
 passed('production six-item capture/sync/readback and actual F10 fail-open restore exact owners')

 for _,break_identity in ipairs({
  function() manager.methods.getCameraComponent=function() return virtual end end,
  function() operator.methods.getActiveVirtualCamera=function() return primary end end,
  function() controller.methods.get_Camera=function() return primary end end,
  function() operator.methods.getActiveCameraParam=function() return object(999,'ace.cCameraParam') end end,
  function() virtual.methods.get_Target=function() return 8 end end,
  function() param.field_types.EyePos='via.vec4' end,
  function() virtual.go.valid=false end,
 }) do
  setup();break_identity();local ok=pcall(prepare_owned_active_camera)
  assert(not ok and calls.writes==0 and state.active_camera_restore==nil)
 end
 passed('unknown/MAX target, primary alias, inconsistent controller/param or wrong field type refuse all new writes')

 setup();state.active=false;cfg.runtime_stage='A';cfg.diagnostic_only=true
 assert(prepare_owned_active_camera()==nil and not sync_owned_active_camera(nil));reset_callback()
 assert(calls.reads==0 and calls.writes==0 and not restoration_pending())
 setup();state.active=false;owner=prepare_owned_active_camera();local writes=calls.writes
 assert(not sync_owned_active_camera(owner) and calls.writes==writes)
 fail_open('Inactive capture');assert(calls.writes==0 and state.active_camera_restore==nil)
 passed('cold stage A reads/writes nothing new and an unsealed inactive capture restores without writes')

 setup();owner=prepare_owned_active_camera();virtual.fail_fov=true;transform.restore_failures=1
 local ok=pcall(sync_owned_active_camera,owner);assert(not ok and transform.position.x==10)
 fail_open('Actual partial setter failure')
 assert(state.active_camera_restore and state.active_camera_restore.restore_pending and restoration_pending())
 assert(#state.active_camera_restore.records==1 and state.active_camera_restore.records[1].name=='virtual_position')
 assert(transform.rotation.w==1 and param.values.FOV==41 and state.camera_sync_diagnostic.pending_records==1)
 assert(not pcall(prepare_owned_active_camera))
 fail_open('Retry');assert(not restoration_pending() and transform.position.x==0)
 passed('partial write failure releases only successful restore records and retains failed original for retry')

 setup();owner=prepare_owned_active_camera();assert(sync_owned_active_camera(owner))
 local old_transform,old_virtual,old_param=transform,virtual,param
 transform=make_transform(901,{x=50,y=3,z=0},{w=1,x=0,y=0,z=0});virtual=camera(902,transform)
 param=object(905,'ace.cCameraParam',{}, {EyePos='via.vec3',LookAtPos='via.vec3',FOV='System.Single'},
  {EyePos={x=50,y=3,z=0},LookAtPos={x=50,y=3,z=-1},FOV=41})
 local prior=calls.writes;local changed,err=pcall(prepare_owned_active_camera)
 assert(not changed and err:find('owner changed',1,true) and calls.writes==prior)
 fail_open('Owner changed')
 assert(old_transform.position.x==0 and old_virtual.fov==41 and old_param.values.FOV==41)
 assert(transform.position.x==50 and virtual.fov==41 and param.values.EyePos.x==50 and not restoration_pending())
 owner=prepare_owned_active_camera();state.active=true;assert(sync_owned_active_camera(owner))
 assert(transform.position.x==10 and owner.param==param and owner.virtual==virtual)
 passed('changed owner causes no new write until exact old owner restores and next capture succeeds')

 setup();owner=prepare_owned_active_camera();param.silent_field=true
 ok=pcall(sync_owned_active_camera,owner);assert(not ok and not state.camera_sync_diagnostic.applied)
 assert(state.camera_sync_diagnostic.checked_records==3)
 param.silent_field=false;fail_open('Silent field write rejected');assert(not restoration_pending())
 setup();transform.negate_quaternion=true;owner=prepare_owned_active_camera()
 assert(sync_owned_active_camera(owner));fail_open('Equivalent quaternion')
 assert(not restoration_pending() and math.abs(transform.rotation.w)==1)
 passed('real six-field readback rejects silent no-op and accepts q/-q equivalent rotation')

 setup();local original=param.values.EyePos;owner=prepare_owned_active_camera()
 original.x=999;transform.position.x=888
 assert(owner.records[1].original.x==0 and owner.records[4].original.x==0)
 assert(sync_owned_active_camera(owner));cfg.runtime_stage='A';cfg.diagnostic_only=true;state.active=false
 reset_callback();assert(not restoration_pending() and transform.position.x==0 and param.values.EyePos.x==0)
 passed('original vectors are numeric deep copies and downgraded stage-A reset restores an owned ledger')

 setup();owner=prepare_owned_active_camera();assert(sync_owned_active_camera(owner))
 -- No manager view-matrix/update/reflect methods are exposed; cached matrix lag is not a mutation guard.
 assert(state.camera_sync_diagnostic.checked_records==6);fail_open('Release');local final=calls.writes
 fail_open('Repeated release');assert(calls.writes==final)
 passed('matrix refresh is diagnostic only and confirmed release is idempotent without engine update calls')

 setup();owner=prepare_owned_active_camera();assert(sync_owned_active_camera(owner))
 virtual.go.valid=false;local before=calls.writes;fail_open('Destroyed owner')
 assert(calls.writes==before and restoration_pending() and #state.active_camera_restore.records==6)
 assert(state.camera_sync_diagnostic.pending_records==6)
 virtual.go.valid=true;fail_open('Actual owner valid again');assert(not restoration_pending())
 passed('pinned references do not substitute for actual GameObject validity during restoration')
 return cases
end
''')
print(f"ACTIVE_CAMERA_SYNC_REGRESSION_OK {run()} actual-production groups; LUA54_COMPLETE_SYNTAX_OK")
