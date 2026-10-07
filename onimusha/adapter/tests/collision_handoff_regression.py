"""Execute production collision query/export/coverage handoff and fail-open telemetry in Lua 5.4."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
lua.eval("function(s) local f,e=load(s,'onimusha_mc.lua','t');assert(f,e);return true end")(source)
finite=source[source.index("local function finite_camera_number("):source.index("local function native_camera_rotation_from_mc(")]
positions=source[source.index("local function mcpos("):source.index("local function new_object(")]
failures=source[source.index("local function fail_open("):source.index("local function reload_config(")]
collision=source[source.index("local function collision_counters("):source.index("local function create_direct_box(")]
run=lua.execute(r"""
local cfg,state,native,result,query,published,bridge
local writes,publishes
Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end}
Vector4f={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
ValueType={new=function() return {set_field=function(self,key,value) self[key]=value end} end}
local function td(name) return name end
local function typename(obj) return obj.type end
local function pin_managed(obj,expected) assert(obj and obj.type==expected);return obj end
local function attempt(fn) local ok,v=pcall(fn);if ok then return v end end
local function call(obj,name,...) if not obj then return nil end;return obj:call(name,...) end
local function strictcall(obj,name,...) assert(obj);return obj:call(name,...) end
local function triangle_vertices(t) return t end
local function restore_player_input_seals() writes=writes+1 end
local function set_boxes_enabled(enabled) assert(enabled==false);writes=writes+1 end
local function restore_player_visuals() writes=writes+1 end
local function close(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b)) end
local function contains(s,part) return type(s)=='string' and string.find(s,part,1,true) end
sdk={get_native_singleton=function() return {} end,create_instance=function() return query end,
 call_native_func=function() return result end}
local vertices={{x=-1,y=64,z=-1},{x=1,y=64,z=-1},{x=0,y=64,z=1}}
local function setup(count)
 cfg={units_per_block=1,collision_radius=16,collision_triangles_per_frame=1,collision_max_triangles=3}
 state={epoch=10,world_key='stage:20:area:78',tile={x=8192,z=-24576},frame=1,bindings={},active=false}
 native={connected=true,mc_pid=100,collision_epoch=10,collision_ring_valid=true,collision_generation=4,
  collision_publish_seq=7,collision_consumed_seq=7,collision_ready=false}
 writes,publishes,published=0,0,nil
 query={type='via.physics.GetAreaPrimitiveQuery',call=function(self,name,value)
  if name=='set_Area' then self.area=value;return end
  if name=='set_FilterInfo' then return end
  error('Unexpected query call '..name)
 end}
 result={type='via.physics.GetAreaPrimitiveResult',count=count or 2,boxes=0,spheres=0,capsules=0,
  call=function(self,name,index)
   if name=='get_NumTriangles' then return self.count end
   if name=='get_NumBoxes' then return self.boxes end
   if name=='get_NumSpheres' then return self.spheres end
   if name=='get_NumCapsules' then return self.capsules end
   if name=='getTriangleCollidable(System.UInt32)' then return {} end
   if name=='getTriangle(System.UInt32)' then
    if self.bad_read==index then return nil end
    return vertices
   end
   error('Unexpected result call '..name)
  end}
 state.cc={call=function(_,name) assert(name=='get_FilterInfo');return {} end}
 bridge={status=function() return native end,publish_collision_tris=function(region)
  publishes=publishes+1
  if bridge.reject then return false end
  published=region;native.collision_publish_seq=native.collision_publish_seq+1;return true
 end}
end
"""+finite+positions+failures+collision+r"""
local function finish_export()
 for _=1,5 do state.frame=state.frame+1;advance_collision(bridge,native);if not state.collision or state.collision.packing_ticket then return end end
 error('Export did not finish')
end
local function acknowledge()
 native.collision_consumed_seq=native.collision_publish_seq;native.collision_ready=true;reconcile_collision(native)
 assert(state.collision_coverage and state.collision_ready and not state.collision_pending)
end
local function seed_coverage()
 assert(start_collision({}, {x=0,y=65,z=0},native));finish_export();acknowledge()
 return state.collision_coverage
end
return function()
 setup();assert(start_collision({}, {x=0,y=65,z=0},native));assert(not state.collision_ready)
 close(query.area.minpos.y,48-0.002);close(query.area.maxpos.y,88+0.002)
 advance_collision(bridge,native);assert(state.collision and #state.collision.triangles==1 and publishes==0)
 state.frame=state.frame+1;advance_collision(bridge,native)
 assert(publishes==1 and state.collision_pending and not state.collision_ready and not state.collision_coverage)
 reconcile_collision(native);assert(not state.collision_ready)
 acknowledge();assert(state.collision_stats.starts==1 and state.collision_stats.queued==1 and state.collision_stats.consumed==1)
 print('PASS initial coverage requires a fully exported and consumed batch')
 local old=state.collision_coverage
 assert(start_collision({}, {x=9,y=65,z=0},native));assert(state.collision_ready and state.collision_coverage==old)
 state.frame=state.frame+1;advance_collision(bridge,native)
 assert(state.collision and state.collision_coverage==old and state.collision_ready)
 local foot={x=8192,y=65,z=-24576}
 assert(collision_coverage_gate(native,foot,foot))
 finish_export();assert(state.collision_pending and state.collision_coverage==old and state.collision_ready)
 close(old.bounds.min_x,8192-16);close(old.bounds.max_x,8192+16)
 assert(collision_coverage_gate(native,{x=8192-8,y=65,z=-24576},foot))
 assert(collision_coverage_gate(native,foot,foot))
 reconcile_collision(native);assert(state.collision_coverage==old)
 acknowledge();assert(state.collision_coverage~=old and state.collision_coverage.centre.x==9)
 assert(state.collision_stats.starts==2 and state.collision_stats.queued==2 and state.collision_stats.consumed==2)
 print('PASS retained old bounds span multi-frame refresh/queue and switch only on whole-batch acknowledgment')
 setup();seed_coverage()
 local b=state.collision_coverage.bounds
 assert(collision_contains_foot(b,{x=8192+15,y=65,z=-24576}))
 assert(not collision_contains_foot(b,{x=8192+15.001,y=65,z=-24576}))
 assert(not collision_contains_foot(b,{x=8192,y=65,z=-24576-15.001}))
 assert(collision_contains_foot(b,{x=8192,y=60,z=-24576}))
 assert(not collision_contains_foot(b,{x=8192,y=59.999,z=-24576}))
 assert(collision_contains_foot(b,{x=8192,y=86,z=-24576}))
 assert(not collision_contains_foot(b,{x=8192,y=86.001,z=-24576}))
 local outside={x=8192+16,y=65,z=-24576}
 assert(not collision_coverage_gate(native,foot,outside));assert(not collision_coverage_gate(native,outside,foot))
 assert(not collision_refresh_due({x=8,y=65,z=0}));assert(collision_refresh_due({x=8.001,y=65,z=0}))
 assert(not collision_refresh_due({x=0,y=63,z=0}));assert(collision_refresh_due({x=0,y=62.999,z=0}))
 assert(collision_refresh_due({x=0,y=67.001,z=0}))
 assert(not collision_contains_foot(b,{x=0/0,y=65,z=0}))
 assert(published.min_x%8==0 and (published.max_x+1)%8==0)
 assert(published.min_y==48 and published.max_y==87)
 print('PASS whole-cell query bounds gate both feet/body/support and vertical refresh starts before the 12-cell support edge')

 -- The worker ticket is not a publication or an acknowledgement. Readiness stays
 -- on the previous complete cells while an owned numeric copy packs off-thread.
 setup();old=seed_coverage();native.collision_async_supported=true
 bridge.publish_collision_tris=function(region)
  assert(region.async and region.min_x%8==0 and (region.max_x+1)%8==0)
  published=region;native.collision_job_id=31;native.collision_job_state='packing';return 31
 end
 assert(start_collision({}, {x=9,y=65,z=0},native));finish_export()
 assert(state.collision and state.collision.packing_ticket==31 and state.collision.triangles==nil)
 assert(state.collision_coverage==old and not state.collision_pending)
 assert(collision_diagnostic().exporting.packing_ticket==31)
 advance_collision(bridge,native);assert(not state.collision_pending)
 native.collision_job_state='published';native.collision_publish_seq=native.collision_publish_seq+1
 native.collision_job_publish_seq=native.collision_publish_seq
 advance_collision(bridge,native);assert(state.collision_pending and state.collision_coverage==old)
 acknowledge();assert(state.collision_coverage~=old)
 print('PASS background submission preserves old coverage until publication AND final consumer acknowledgement')
 for _,mode in ipairs({'failed','discarded','superseded','timeout'}) do
  setup();old=seed_coverage();native.collision_async_supported=true
  bridge.publish_collision_tris=function(region)
   native.collision_job_id=32;native.collision_job_state='packing';return 32
  end
  assert(start_collision({}, {x=9,y=65,z=0},native));finish_export()
  if mode=='superseded' then native.collision_job_id=33
  elseif mode=='timeout' then state.frame=state.collision.packing_frame+601
  else native.collision_job_state=mode;native.collision_job_error='test rejection' end
  advance_collision(bridge,native)
  assert(not state.collision and not state.collision_pending and state.collision_coverage==old)
 end
 print('PASS rejected, stale and timed-out worker jobs never replace certified terrain')
 setup();cfg.units_per_block=0.25;seed_coverage()
 local scaled_foot=mcpos({x=0,y=65,z=0})
 local allowed,reason=collision_coverage_gate(native,scaled_foot,scaled_foot)
 assert(not allowed and contains(reason,'units_per_block=1'))
 print('PASS unmeasured nondefault native body scale cannot authorize takeover despite a consumed terrain batch')
 for _,mutation in ipairs({
  function() state.epoch=11 end,function() native.collision_epoch=11 end,function() state.world_key='different' end,
  function() cfg.units_per_block=2 end,function() state.tile.x=16384 end,
  function() cfg.collision_radius=32 end,function() state.config_revision=1 end,
  function() native.mc_pid=101 end,function() native.collision_generation=5 end,
  function() native.connected=false end,function() native.collision_ring_valid=false end}) do
  setup();seed_coverage();assert(start_collision({}, {x=9,y=65,z=0},native))
  mutation();reconcile_collision(native)
  assert(not state.collision_ready and not state.collision_coverage and not state.collision and not state.collision_pending)
 end
 print('PASS epoch/world/scale/tile/radius/config and MC reconnect/generation invalidate old and pending coverage')
 setup();old=seed_coverage();assert(start_collision({}, {x=9,y=65,z=0},native));result.bad_read=1
 finish_export();assert(state.collision_coverage==old and state.collision_ready and not state.collision_pending)
 assert(publishes==1 and state.collision_stats.failures==1 and contains(state.collision_failure.reason,'read failed'))
 assert(not start_collision({}, {x=9,y=65,z=0},native));state.frame=state.collision_retry_frame
 result.bad_read=nil;assert(start_collision({}, {x=9,y=65,z=0},native));bridge.reject=true;finish_export()
 assert(state.collision_coverage==old and state.collision_ready and contains(state.collision_failure.reason,'publication rejected'))
 close(state.collision_retry_frame-state.frame,30)
 for _=1,6 do
  state.frame=state.collision_retry_frame;assert(start_collision({}, {x=9,y=65,z=0},native));finish_export()
  assert(state.collision_retry_frame-state.frame<=240 and state.collision_coverage==old)
 end
 close(state.collision_retry_frame-state.frame,240)
 print('PASS failed partial reads/publication retain old valid bounds and retry only after bounded backoff')
 for _,primitive in ipairs({'boxes','spheres','capsules'}) do
  setup();old=seed_coverage();result[primitive]=1
  assert(not start_collision({}, {x=9,y=65,z=0},native))
  assert(state.collision_coverage==old and publishes==1 and contains(state.collision_failure.reason,'Unsupported'))
 end
 setup();result.count=4;assert(not start_collision({}, {x=0,y=65,z=0},native));assert(publishes==0)
 assert(contains(state.collision_failure.reason,'truncation rejected'))
 setup(3);assert(start_collision({}, {x=0,y=65,z=0},native));finish_export();assert(publishes==1);acknowledge()
 setup();assert(start_collision({}, {x=0,y=65,z=0},native));state.collision.max_triangles=1
 finish_export();assert(publishes==0 and contains(state.collision_failure.reason,'before complete exhaustion'))
 print('PASS unsupported query primitives and true truncation reject; exact-budget complete exhaustion succeeds')
 for _,failure in ipairs({'unsupported','transform','nonfinite','no_query'}) do
  setup();assert(start_collision({}, {x=0,y=65,z=0},native))
  if failure=='unsupported' then state.collision.unsupported=1
  elseif failure=='transform' then state.collision.shapes[1].matrix={}
  elseif failure=='nonfinite' then
   state.collision.shapes[1].vertices={{x=math.huge,y=0,z=0},vertices[2],vertices[3]}
  else state.collision.complete_query=false end
  finish_export();assert(publishes==0 and not state.collision_coverage and state.collision_failure)
 end
 setup();result=nil;assert(not start_collision({}, {x=0,y=65,z=0},native));assert(publishes==0)
 print('PASS unsupported/read/transform/non-finite/incomplete or unavailable queries never publish a certified AABB')
 setup();old=seed_coverage();assert(start_collision({}, {x=9,y=65,z=0},native));finish_export()
 state.frame=state.collision_pending.queued_frame+301;reconcile_collision(native)
 assert(state.collision_coverage==old and not state.collision_pending and contains(state.collision_failure.reason,'timed out'))
 close(old.bounds.min_x,8192-16)
 setup();seed_coverage();assert(start_collision({}, {x=9,y=65,z=0},native));finish_export()
 native.collision_publish_seq=native.collision_publish_seq+1;reconcile_collision(native)
 assert(not state.collision_coverage and not state.collision_ready and contains(state.collision_failure.reason,'superseded'))
 setup();seed_coverage();assert(start_collision({}, {x=9,y=65,z=0},native));finish_export()
 native.collision_generation=native.collision_generation+1;native.collision_consumed_seq=native.collision_publish_seq
 reconcile_collision(native);assert(not state.collision_coverage and not state.collision_pending and not state.collision_ready)
 setup();seed_coverage();invalidate_collision_coverage('Lua reinitialization')
 assert(not state.collision_ready and not state.collision_coverage)
 print('PASS ack timeout is bounded, superseded batches revoke coverage, and Lua reinitialization starts unverified')
 setup();state.active=true;state.gate_snapshot={frame=1,menu_pause=false,player_pause=true,
  event_jack=false,dialogue_jack=false,event_start=false,auto_move=true,coverage=true}
 fail_open('Native menu owns control');assert(state.control_diagnostic.deactivations==1 and writes==3)
 assert(state.control_diagnostic.last_deactivation.gate.player_pause and state.control_diagnostic.last_deactivation.gate.auto_move)
 fail_open('Still paused');assert(state.control_diagnostic.deactivations==1 and state.not_ready_reason=='Still paused')
 assert(state.control_diagnostic.last_deactivation.reason=='Native menu owns control')
 assert(state.control_diagnostic.per_reason_counts['Native menu owns control']==1 and not state.control_diagnostic.per_reason_counts['Still paused'])
 for i=1,17 do state.active=true;state.frame=i+1;fail_open('Repeated actual transition') end
 assert(state.control_diagnostic.deactivations==18 and #state.control_diagnostic.transitions==16)
 assert(state.control_diagnostic.transitions[1].frame==3 and state.control_diagnostic.transitions[16].frame==18)
 assert(state.control_diagnostic.per_reason_counts['Repeated actual transition']==17)
 assert(state.control_diagnostic.last_deactivation.epoch==10 and not state.control_diagnostic.last_deactivation.refresh.exporting)
 print('PASS deactivation telemetry records only transitions with distinct pause/scripted gates and a reason/frame')
end
""")
run()
print("COLLISION_HANDOFF_REGRESSION_OK 12 actual-production Lua cases; LUA54_COMPLETE_SYNTAX_OK")
