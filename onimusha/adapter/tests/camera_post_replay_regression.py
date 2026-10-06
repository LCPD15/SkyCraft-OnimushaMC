"""Execute actual outer lateUpdate post hook and camera-only cached replay helpers."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

adapter=Path(__file__).resolve().parents[1]
source=(adapter/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
fixture=(adapter/"tests"/"active_camera_sync_regression.py").read_text(encoding="utf-8-sig")
# Reuse only fixed-SDK-shaped objects from the existing camera ownership fixture.
prefix=fixture.split("run=lua.execute(r'''",1)[1].split("''' + helpers",1)[0]
helpers=source[source.index("local function owned_camera_value("):source.index("local function capture_player_visuals(")]
visual_restore=source[source.index("local function restore_player_visuals("):source.index("local function restoration_pending(")]
release=source[source.index("local function restoration_pending("):source.index("local function invalidate_collision_coverage(")]
replay_and_hooks=source[source.index("local function replay_cached_mc_camera("):source.index("local function combat_diagnostic(")]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
class RawPointer:
    def __init__(self,value): self.value=value
lua.globals().sdk_pointer=RawPointer
run=lua.execute(prefix+helpers+visual_restore+release+r'''
local native,mc,hook,storage
local function setup_replay()
 setup();state.teleport_seq=100;state.camera_observation_frame=43
 state.camera_observation_phase='before_update_behavior';storage={}
 primary.fov=41;state.fov_restore={obj=primary,original=41}
 primary.methods.get_LookAtPosition=function()
  return {x=primary_transform.position.x-1,y=primary_transform.position.y,z=primary_transform.position.z}
 end
 native={enabled=true,connected=true,ready=true,host_ready=true,renderer_ready=true,collision_epoch=10}
 mc={in_world=true,dead=false,teleport_ack=100}
 calls.bridge_reads=0;calls.errors=0
 onimusha_mc.status=function() calls.bridge_reads=calls.bridge_reads+1;return native end
 onimusha_mc.read_mc=function() calls.bridge_reads=calls.bridge_reads+1;return mc end
 local old_td=td
 local m={is_static=function() return false end,get_num_params=function() return 0 end,
  get_return_type=function() return {get_full_name=function() return 'System.Void' end} end,
  get_param_types=function() return {} end,get_function=function() return sdk_pointer(5370779600) end}
 td=function(name)
  if name=='app.CameraManager' then return {get_method=function(_,name) return name=='lateUpdate()' and m or nil end} end
  return old_td(name)
 end
 sdk.to_int64=function(value) assert(type(value)=='userdata');return value.value end
 sdk.to_managed_object=function() error('Raw hook argument must never be wrapped') end
 sdk.hook=function(method,pre,post) assert(method==m);hook={pre=pre,post=post} end
 thread={get_hook_storage=function() return storage end}
 log={error=function(message) assert(message:find('camera replay',1,true));calls.errors=calls.errors+1 end}
end
local function certify()
 local owner=prepare_owned_active_camera()
 cache_mc_camera_pose({x=20,y=3,z=7},{w=0.70710678,x=0,y=0.70710678,z=0},70,owner,mc)
 assert(state.cached_camera_pose and calls.writes==9)
 return owner
end
local function native_overwrite()
 primary.fov=41;primary_transform.position={x=0,y=1,z=5};primary_transform.rotation={w=1,x=0,y=0,z=0}
 virtual.fov=41;transform.position={x=0,y=1,z=5};transform.rotation={w=1,x=0,y=0,z=0}
 param.values={EyePos={x=0,y=1,z=5},LookAtPos={x=0,y=1,z=0},FOV=41}
end
local function native_snapshot()
 native_overwrite();primary.fov=43
end
local function assert_primary_snapshot()
 assert(primary_transform.position.x==0 and primary_transform.position.y==1 and primary_transform.position.z==5,
  'Post failure must restore the native position, not leave the MC half-write')
 assert(primary_transform.rotation.w==1 and primary_transform.rotation.x==0
  and primary_transform.rotation.y==0 and primary_transform.rotation.z==0,
  'Post failure must restore the native quaternion')
 assert(primary.fov==43,'Per-attempt native FOV43 must not be overwritten by initial visual FOV41')
end
local function fail_primary_mc_write(kind,mode)
 local obj=kind=='fov' and primary or primary_transform
 local function is_mc(value)
  return kind=='fov' and value==70 or kind=='position' and value.x==20
   or kind=='rotation' and math.abs(value.y)>0.7
 end
 if kind=='fov' then
  local original=obj.methods.set_FOV
  obj.methods.set_FOV=function(value)
   if not is_mc(value) then return original(value) end
   if mode=='throw_after' then original(value) else calls.writes=calls.writes+1 end
   if mode~='silent' then error('actual primary fov '..mode) end
  end
 else
  local name='set_'..kind;local original=obj[name]
  obj[name]=function(self,value,no_dirty)
   if not is_mc(value) then return original(self,value,no_dirty) end
   if mode=='throw_after' then original(self,value,no_dirty) else calls.writes=calls.writes+1 end
   if mode~='silent' then error('actual primary '..kind..' '..mode) end
  end
 end
end
''' + replay_and_hooks + r'''
local function invoke(address,between)
 storage={};local token={original='retval'}
 assert(hook.pre({[2]=sdk_pointer(address or addr(manager))})==nil)
 if between then between() end
 assert(hook.post(token)==token,'Outer post must preserve exact original retval')
end
return function()
 setup_replay();install_camera_observation_hooks();local owner=certify();native_overwrite()
 local before=calls.writes;invoke()
 assert(calls.writes-before==9 and calls.bridge_reads==2 and calls.errors==0)
 assert(primary.fov==70 and primary_transform.position.x==20 and virtual.fov==70 and transform.position.x==20)
 assert(param.values.EyePos.x==20 and param.values.LookAtPos.x==19 and param.values.FOV==70)
 assert(state.camera_replay_diagnostic.applied==1 and state.active and state.cached_camera_pose.owner==owner)
 passed('actual outer manager post replays exactly primary3 plus owned6 with no whole tick/game update exposed')

 setup_replay();install_camera_observation_hooks();local before=calls.writes;invoke()
 assert(calls.writes==before and calls.bridge_reads==0 and state.camera_replay_diagnostic==nil)
 prepare_owned_active_camera();invoke()
 assert(calls.writes==before and calls.bridge_reads==0 and state.camera_replay_diagnostic.last_reason=='No certified MC camera pose')
 for _,change in ipairs({function() state.active=false end,function() cfg.runtime_stage='A';cfg.diagnostic_only=true end,
   function() cfg.runtime_stage='B' end,function() cfg.install_control_hooks=false end}) do
  setup_replay();install_camera_observation_hooks();certify();change();local writes,reads=calls.writes,calls.reads
  invoke();assert(calls.writes==writes and calls.reads==reads and calls.bridge_reads==0)
 end
 passed('first activation without cache and inactive/A/B/control-disabled callbacks add no gameplay reads or writes')

 for _,change in ipairs({function() state.cached_camera_pose.frame=41 end,
   function() state.cached_camera_pose.epoch=9 end,function() state.cached_camera_pose.teleport_seq=99 end,
   function() state.cached_camera_pose.teleport_ack=99 end,function() state.cached_camera_pose.owner={} end,
   function() state.cached_camera_pose.primary=virtual end,function() state.cached_camera_pose.transform=transform end,
   function() state.cached_camera_pose.manager=operator end,function() state.active_camera_restore.restore_pending=true end}) do
  setup_replay();install_camera_observation_hooks();certify();change();local writes,reads=calls.writes,calls.reads
  invoke();assert(calls.writes==writes and calls.reads==reads and calls.bridge_reads==0)
 end
 setup_replay();install_camera_observation_hooks();certify();local writes,reads=calls.writes,calls.reads
 invoke(999);assert(calls.writes==writes and calls.reads==reads and calls.bridge_reads==0)
 invoke(nil,function() state.epoch=11 end);assert(calls.writes==writes and calls.bridge_reads==0)
 passed('stale frame/session/ack/owner/transform/manager and changed pre-post epoch refuse every replay write')

 for _,change in ipairs({function() native.enabled=false end,function() native.connected=false end,
   function() native.ready=false;native.host_age_ms=501 end,function() native.host_ready=false end,
   function() native.renderer_ready=false end,function() native.collision_epoch=9 end,
   function() mc.teleport_ack=99 end,function() mc.in_world=false end,function() mc.dead=true end,
   function() onimusha_mc=nil end}) do
  setup_replay();install_camera_observation_hooks();certify();change();local writes,reads=calls.writes,calls.reads
  invoke();assert(calls.writes==writes and calls.reads==reads)
 end
 passed('fresh native watchdog/readiness/connection/epoch and live MC ack/alive gate disallow cached poses')

 setup_replay();install_camera_observation_hooks();owner=certify()
 local new_transform=make_transform(910,{x=1,y=1,z=1},{w=1,x=0,y=0,z=0});local replacement=camera(920,new_transform)
 operator.methods.getActiveVirtualCamera=function() return replacement end
 invoke();assert(not state.active and state.cached_camera_pose==nil and not restoration_pending())
 assert(calls.errors==1 and primary.fov==41 and replacement.fov==41 and new_transform.position.x==1)
 assert(state.camera_replay_diagnostic.error:find('identity mismatch',1,true))
 passed('actual owner-chain change fails open and restores only the previous owner without capturing a replacement')

 setup_replay();install_camera_observation_hooks();certify();native_overwrite()
 virtual.fail_fov=true;transform.restore_failures=1;invoke()
 assert(not state.active and state.cached_camera_pose==nil and primary.fov==41 and calls.errors==1)
 assert(restoration_pending() and #state.active_camera_restore.records==1)
 assert(state.active_camera_restore.records[1].name=='virtual_position')
 virtual.fail_fov=false;fail_open('Retry owned recovery');assert(not restoration_pending())
 passed('partial post setter failure preserves original retval and retains only failed exact-owner recovery for retry')

 setup_replay();install_camera_observation_hooks();certify();native_overwrite()
 primary.methods.set_FOV=function(value) calls.writes=calls.writes+1 end
 invoke();assert(not state.active and state.cached_camera_pose==nil and primary.fov==41 and not restoration_pending())
 assert(calls.errors==1 and state.camera_replay_diagnostic.error:find('Primary camera synchronization failed readback: fov',1,true))
 setup_replay();install_camera_observation_hooks();certify();onimusha_mc.status=function() error('readonly bridge failed') end
 invoke();assert(not state.active and state.cached_camera_pose==nil and primary.fov==41 and not restoration_pending())
 passed('primary three-field readback and readonly bridge failures cannot leave takeover/cache active or change post retval')

 setup_replay();owner=prepare_owned_active_camera();local p={x=20,y=3,z=7};local q={w=1,x=0,y=0,z=0}
 cache_mc_camera_pose(p,q,70,owner,mc);p.x=999;q.w=0
 assert(state.cached_camera_pose.position.x==20 and state.cached_camera_pose.rotation.w==1)
 fail_open('F10 off');assert(state.cached_camera_pose==nil and not state.active and primary.fov==41 and not restoration_pending())
 passed('successful certification caches numeric deep copies and actual fail-open clears them before owned restoration')

 for _,mode in ipairs({'silent','throw_before','throw_after'}) do
  setup_replay();install_camera_observation_hooks();certify();native_snapshot()
  fail_primary_mc_write('position',mode);invoke();assert_primary_snapshot()
  assert(not state.active and state.cached_camera_pose==nil and not restoration_pending() and calls.errors==1)
  assert(state.primary_camera_rollback==nil and state.primary_camera_rollback_diagnostic.pending_records==0)
 end
 passed('primary position silent/before-write/after-write failure rolls back native XYZ/quaternion/FOV43')

 for _,kind in ipairs({'rotation','fov'}) do
  for _,mode in ipairs({'silent','throw_before','throw_after'}) do
   setup_replay();install_camera_observation_hooks();certify();native_snapshot()
   fail_primary_mc_write(kind,mode);invoke();assert_primary_snapshot()
   assert(not state.active and not restoration_pending() and calls.errors==1 and state.fov_restore==nil)
  end
 end
 passed('primary rotation and FOV silent/throw failures restore the full post-native snapshot, not only initial FOV')

 for _,kind in ipairs({'EyePos','FOV'}) do
  setup_replay();install_camera_observation_hooks();certify();native_snapshot()
  param.fail_field=kind;invoke();assert_primary_snapshot()
  assert(not state.active and not restoration_pending() and calls.errors==1)
  assert(virtual.fov==41 and transform.position.x==0 and param.values.FOV==41)
 end
 passed('failure after primary3 in either early or late owned6 restores primary3 as well as the original owned6')

 setup_replay();install_camera_observation_hooks();certify();native_snapshot()
 primary_transform.restore_failures=1;fail_primary_mc_write('fov','silent');invoke()
 assert(not state.active and restoration_pending() and state.primary_camera_rollback.restore_pending)
 assert(#state.primary_camera_rollback.records==1 and state.primary_camera_rollback.records[1].name=='primary_position')
 assert(primary_transform.position.x==20 and primary_transform.rotation.w==1 and primary.fov==43)
 assert(state.fov_restore and state.fov_restore.original==41)
 local before=calls.writes;invoke();assert(calls.writes==before,'Inactive post must not recapture or overwrite a pending rollback')
 cfg.runtime_stage='A';cfg.diagnostic_only=true;native.enabled=false;state.epoch=11
 fail_open('Disabled stage A retry');assert_primary_snapshot()
 assert(not restoration_pending() and state.fov_restore==nil and state.primary_camera_rollback==nil)
 passed('failed primary XYZ restore stays pending, and stage-A/disabled/new-epoch retry preserves native FOV43')

 setup_replay();install_camera_observation_hooks();certify();native_snapshot()
 local normal_fov=primary.methods.set_FOV;local prevent_restore=true
 primary.methods.set_FOV=function(value)
  if value==43 and prevent_restore then calls.writes=calls.writes+1;return end
  return normal_fov(value)
 end
 param.fail_field='FOV';invoke()
 assert(not state.active and restoration_pending() and #state.primary_camera_rollback.records==1)
 assert(state.primary_camera_rollback.records[1].name=='primary_fov' and primary.fov==70)
 assert(primary_transform.position.x==0 and primary_transform.rotation.w==1 and state.fov_restore.original==41)
 fail_open('Silent rollback still failing');assert(restoration_pending() and primary.fov==70)
 prevent_restore=false;fail_open('Rollback setter recovered');assert_primary_snapshot()
 assert(not restoration_pending() and state.fov_restore==nil)
 passed('silent FOV rollback failure is retained through retries, never silently cleared or replaced by initial FOV41')

 setup_replay();install_camera_observation_hooks();certify();native_snapshot()
 local original_primary,original_transform=primary,primary_transform
 local replacement_transform=make_transform(1910,{x=100,y=200,z=300},{w=1,x=0,y=0,z=0})
 local replacement=camera(1920,replacement_transform);replacement.fov=55
 primary.methods.set_FOV=function(value)
  calls.writes=calls.writes+1
  if value==70 then state.camera=replacement;state.camera_transform=replacement_transform;error('Owner switched inside setter') end
  original_primary.fov=value
 end
 invoke();assert_primary_snapshot()
 assert(not state.active and not restoration_pending() and replacement.fov==55 and replacement_transform.position.x==100)
 assert(original_transform.position.x==0 and original_primary.fov==43)
 passed('owner replacement during a partial write restores only captured old primary3, never the new camera')

 setup_replay();install_camera_observation_hooks();certify();native_snapshot()
 local original_go=primary.go;local replacement_transform=make_transform(2910,{x=80,y=90,z=100},{w=1,x=0,y=0,z=0})
 primary.methods.set_FOV=function(value)
  calls.writes=calls.writes+1
  if value==70 then original_go.valid=false;error('Original primary GO invalidated') end
  primary.fov=value
 end
 invoke();assert(restoration_pending() and #state.primary_camera_rollback.records==3)
 local writes=calls.writes;fail_open('Invalid owner retry');assert(calls.writes==writes and restoration_pending())
 original_go.valid=true;original_go.methods.get_Transform=function() return replacement_transform end
 fail_open('GO transform replaced');assert(calls.writes==writes and restoration_pending())
 assert(replacement_transform.position.x==80 and replacement_transform.rotation.w==1)
 original_go.methods.get_Transform=function() return primary_transform end
 fail_open('Exact old owner valid again');assert_primary_snapshot();assert(not restoration_pending())
 passed('invalid or changed old GO/transform remains pending without touching replacement owners, then retries exact originals')

 setup_replay();install_camera_observation_hooks();certify();native_snapshot();invoke()
 assert(state.primary_camera_rollback==nil and state.primary_camera_rollback_diagnostic.committed)
 assert(state.primary_camera_rollback_diagnostic.captures==1 and state.fov_restore.original==41)
 native_snapshot();primary_transform.position.x=8;primary.fov=55;invoke()
 assert(state.primary_camera_rollback==nil and state.primary_camera_rollback_diagnostic.captures==2)
 primary_transform.position={x=9,y=2,z=6};primary_transform.rotation={w=1,x=0,y=0,z=0};primary.fov=55
 fail_open('Normal F10 disable after successful replay')
 assert(primary_transform.position.x==9 and primary_transform.rotation.w==1 and primary.fov==41 and not restoration_pending())
 setup_replay();install_camera_observation_hooks();certify();native_snapshot();cfg.runtime_stage='A';cfg.diagnostic_only=true
 local reads,writes=calls.reads,calls.writes;invoke();assert(calls.reads==reads and calls.writes==writes and state.primary_camera_rollback==nil)
 passed('successful post snapshots are discarded per attempt; normal F10 pose semantics and cold disabled-stage no-capture remain unchanged')
 return cases
end
''')
print(f"CAMERA_POST_REPLAY_REGRESSION_OK {run()} actual-production groups; LUA54_COMPLETE_SYNTAX_OK")
