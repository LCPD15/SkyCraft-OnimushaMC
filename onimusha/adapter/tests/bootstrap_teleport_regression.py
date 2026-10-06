"""Run the actual production tick: saved MC outside target coverage must bootstrap without taking control."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
views=source[source.index("local function finite_camera_number("):source.index("-- Traverse only live object references.")]
counter=source[source.index("local function next_session_counter("):source.index("local state = {")]
positions=source[source.index("local function mcpos("):source.index("local function new_object(")]
failures=source[source.index("local function fail_open("):source.index("local function reload_config(")]
collision=source[source.index("local function collision_counters("):source.index("local function create_direct_box(")]
tick=source[source.index("local function tick()"):source.index('re.on_pre_application_entry("UpdateBehavior"')]
run=lua.execute(r"""
local cfg,state,native,mc,bridge,submitted
local pose_writes,rotation_writes,draw_writes,fov_writes,input_writes,captures
local persist_calls=0
local session_seed=12345
local native_position={x=0,y=65,z=42}
Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
Vector4f={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
Quaternion={new=function(v) return v end}
local function call(obj,name,...) if obj then return obj:call(name,...) end end
local function strictcall(obj,name,...) assert(obj);return obj:call(name,...) end
local function reload_config() end
local function restoration_pending() return false end
local function discover() error('Unexpected discovery during a ready-bound tick') end
local function install_hooks() end
local function scene() return {} end
local function stage_key() return 'stage:20:area:78' end
local function choose_world(key) assert(key==state.world_key);return true end
local function refresh_camera_baseline() return true end
local function apply_events() end
local function probe_block_colliders() end
local function publish_actors() end
local function persist_session() persist_calls=persist_calls+1 end
local function apply_solids() end
local function restore_player_input_seals() end
local function restore_player_visuals() end
local function set_boxes_enabled() end
local function capture_player_visuals() captures=captures+1;state.draw_targets={{obj=state.player_go,original=true}} end
local function seal_player_inputs() input_writes=input_writes+1 end
-- Exact active-camera ownership/readback is independently exercised by its production fixture.
local function prepare_owned_active_camera() return {} end
local function sync_owned_active_camera() end
local function cache_mc_camera_pose(position,rotation,fov,owner,mc)
 state.camera_transform:set_position(Vector4f.new(position.x,position.y,position.z,1),false)
 state.camera_transform:set_rotation(rotation);strictcall(state.camera,'set_FOV',fov)
 sync_owned_active_camera(owner)
end
local function positive_fov(v) return type(v)=='number' and v>0 and v<math.huge end
local function contains(s,p) return type(s)=='string' and string.find(s,p,1,true) end
local function mock_call(values)
 return {call=function(_,name,...)
  if name=='set_DrawSelf' then draw_writes=draw_writes+1;assert((...)==false);return end
  if name=='set_FOV' then fov_writes=fov_writes+1;return end
  return values[name]
 end}
end
local function setup(ack,inside,enabled)
 cfg={runtime_stage='C',diagnostic_only=false,install_control_hooks=true,enabled=enabled,
  units_per_block=1,tile_stride=8192,collision_radius=16,enable_terrain_queries=true,
  enable_health_hook_tests=false,max_pose_jump=8,camera_fov_radians=false}
 state={frame=2,epoch=10,bridge_epoch=10,bridge_initialized=true,active=false,world_key='stage:20:area:78',
  world_id=1,tile={x=8192,z=-24576},teleport_seq=100,health_revision=1,bindings={root_motion=true},
  camera_axis_calibrated=true,camera_forward_sign=-1,host_camera_angles={yaw=180,pitch=0}}
 pose_writes,rotation_writes,draw_writes,fov_writes,input_writes,captures=0,0,0,0,0,0
 persist_calls=0
 submitted=nil
 state.player=mock_call({get_IsEventStart=false})
 state.player_go=mock_call({})
 state.info=mock_call({get_Valid=true,get_CharacterValid=true})
 state.pm=mock_call({isPlayerReady=true,get_IsAutoMove=false,isPlayerDying=false,isPlayerDead=false})
 state.pause=mock_call({get_IsMenuPause=false,get_IsPlayerPause=false})
 state.controller=mock_call({get_IsEventJack=false,get_IsDialogueJack=false})
 state.health=mock_call({get_Health=75,get_MaxHealth=100})
 state.transform={get_position=function() return native_position end,
  set_position=function() pose_writes=pose_writes+1 end,set_rotation=function() rotation_writes=rotation_writes+1 end}
 state.camera_transform={set_position=function() pose_writes=pose_writes+1 end,set_rotation=function() rotation_writes=rotation_writes+1 end}
 state.camera=mock_call({})
 native={connected=true,enabled=enabled,renderer_ready=true,ready=false,host_ready=false,
  collision_epoch=10,mc_pid=100,collision_generation=4,collision_ring_valid=true,
  collision_publish_seq=7,collision_consumed_seq=7,collision_ready=true}
 mc={in_world=true,dead=false,teleport_ack=ack,x=8192,y=65,z=-24576+(inside and 42 or 22),
  eye_x=8192,eye_y=66.62,eye_z=-24576+42,yaw=180,pitch=0,camera_mode=0,camera_distance=4,fov=70}
 bridge={read_mc=function() return mc end,set_camera=function() return true end,status=function() return native end,
  submit_host=function(host)
   submitted=host;native.host_ready=host.ready
   -- Real native active() additionally requires enable/MC world and matching ack.
   native.ready=host.ready and native.enabled and mc.in_world and mc.teleport_ack==host.teleport_seq
   native.not_ready_reason=native.ready and 'ready' or not native.enabled and 'disabled' or 'teleport_ack_mismatch'
   return true
  end,
  publish_collision_tris=function() error('Unexpected fresh query during bootstrap') end}
 onimusha_mc=bridge
end
"""+counter+views+positions+failures+collision+tick+r"""
local function seed_coverage()
 local coverage=assert(collision_context(native));coverage.centre={x=0,y=65,z=42}
 coverage.bounds={min_x=8192-16,max_x=8192+16,min_y=49,max_y=81,min_z=-24576+26,max_z=-24576+58}
 coverage.publish_seq=7;coverage.count=3264;state.collision_coverage=coverage;state.collision_ready=true
end
local function assert_no_takeover()
 assert(pose_writes==0 and rotation_writes==0 and draw_writes==0 and fov_writes==0 and input_writes==0 and captures==0)
 assert(not state.active)
end
return function()
 setup(4294967295,false,false);seed_coverage();tick()
 assert(submitted.ready and submitted.teleport_seq==100 and submitted.z==-24576+42)
 assert(state.gate_snapshot.teleport_pending and state.gate_snapshot.host_bootstrap_ready)
 assert(state.gate_snapshot.host_ready and not state.gate_snapshot.native_ready)
 assert(not state.gate_snapshot.coverage and state.gate_snapshot.native_coverage)
 assert_no_takeover()
 print('PASS before F10, stale saved MC outside target bounds receives ready native target without pose/draw/input writes')
 setup(4294967295,false,true);seed_coverage();tick()
 assert(submitted.ready and not native.ready and state.not_ready_reason=='Minecraft teleport acknowledgment pending')
 assert_no_takeover()
 print('PASS enabled bridge still refuses takeover until the newly requested teleport is acknowledged')
 setup(100,true,true);seed_coverage();tick()
 assert(submitted.ready and native.ready and state.active and not state.gate_snapshot.teleport_pending)
 assert(state.gate_snapshot.host_ready and state.gate_snapshot.native_ready)
 assert(pose_writes==2 and rotation_writes==2 and draw_writes==1 and input_writes==1 and fov_writes==1 and captures==1)
 print('PASS matching acknowledgment inside both bodies/query bounds enables the actual production control writes')
 setup(100,false,true);seed_coverage();tick()
 assert(not submitted.ready and not state.gate_snapshot.host_bootstrap_ready and not state.gate_snapshot.teleport_pending)
 assert(contains(state.not_ready_reason,'Minecraft foot/body/support outside'))
 assert_no_takeover()
 print('PASS matching acknowledgment outside verified bounds cannot use the bootstrap exception')
 for _,guard in ipairs({
  function() state.collision_coverage=nil;state.collision_ready=false end,
  function()
   native.collision_consumed_seq=6;state.collision_pending=state.collision_coverage
   state.collision_pending.queued_frame=state.frame;state.collision_coverage=nil;state.collision_ready=false
  end,
  function() state.pause=mock_call({get_IsMenuPause=true,get_IsPlayerPause=false}) end,
  function() state.controller=mock_call({get_IsEventJack=true,get_IsDialogueJack=false}) end,
  function() state.health=mock_call({get_Health=0,get_MaxHealth=100}) end,
  function() cfg.install_control_hooks=false end,
  function() state.camera_axis_calibrated=false end,
  function() state.bindings.root_motion=false end,
  function() native.collision_ring_valid=false end}) do
  setup(4294967295,false,true);seed_coverage();cfg.enable_terrain_queries=false;guard();tick()
  assert(not submitted.ready);assert_no_takeover()
 end
 print('PASS bootstrap retains terrain completion, ring, menu/scripted, HP, hook, root-motion and camera guards')
 setup(100,false,false);seed_coverage();tick()
 assert(state.previous_native_enabled==false and not state.collision and not state.collision_pending and not state.collision_failure)
 assert(state.teleport_seq==100 and persist_calls==0);assert_no_takeover()
 local retained=state.collision_coverage;native.enabled=true;state.frame=state.frame+1;tick()
 assert(state.teleport_seq==101 and persist_calls==1 and state.enable_resync_frame==state.frame)
 assert(submitted.ready and submitted.teleport_seq==101 and not native.ready and state.collision_coverage==retained)
 assert_no_takeover()
 mc.teleport_ack=101;mc.z=-24576+42;state.frame=state.frame+1;tick()
 assert(state.active and submitted.ready and state.teleport_seq==101 and persist_calls==1)
 print('PASS off-native-walk ignores stale MC pose for refresh; explicit enable reserves one persisted sequence and bootstraps before taking control')
 setup(100,false,true);seed_coverage();state.active=true;state.previous_native_enabled=true;cfg.enable_terrain_queries=false
 tick();assert(state.teleport_seq==100 and persist_calls==0 and not submitted.ready)
 assert_no_takeover()
 assert(state.control_diagnostic.deactivations==1 and contains(state.not_ready_reason,'outside'))
 print('PASS active unverified MC movement fails open without forced resynchronization or a new teleport sequence')
end
""")
run()
print('BOOTSTRAP_TELEPORT_REGRESSION_OK 7 actual-production tick cases; LUA54_COMPLETE_SYNTAX_OK')
