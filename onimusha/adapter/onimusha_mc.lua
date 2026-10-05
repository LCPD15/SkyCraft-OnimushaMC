-- SkyCraft Onimusha runtime adapter, MIT. MOD制作：LCPD15/LCPD拉灯
-- OnimushaWotS.exe only; method existence is checked against its live TDB.
local CFG_FILE = "onimusha_mc_config.json"
local defaults = {
    runtime_stage="A", config_reload_frames=120,
    enabled=false, units_per_block=1.0, tile_stride=8192, collision_radius=32,
    collision_triangles_per_frame=1600, collision_max_triangles=95000,
    enemy_host_damage_per_mc_point=10.0, max_pose_jump=8.0,
    camera_yaw_sign=1.0, camera_yaw_offset=0.0, camera_pitch_sign=-1.0,
    camera_fov_radians=false, mirror_native_damage_to_mc=true,
    block_collider_resource="mod/onimusha_mc/unit_box.rcol",
    diagnostic_only=true, install_control_hooks=false,
    enable_native_block_colliders=false,
    enable_block_collider_tests=false, enable_health_hook_tests=false,
    enable_terrain_queries=false,
}
local function read_config()
    local ok,raw=pcall(json.load_file,CFG_FILE)
    if not ok or type(raw)~="table" then raw={} end
    local result={}
    for k,v in pairs(defaults) do
        if type(raw[k])==type(v) then result[k]=raw[k]
        else result[k]=v end
    end
    if result.runtime_stage~="B" and result.runtime_stage~="C" then result.runtime_stage="A" end
    result.config_reload_frames=math.max(30,math.floor(result.config_reload_frames))
    if result.units_per_block<=0 then result.units_per_block=defaults.units_per_block end
    result.tile_stride=math.max(1024,result.tile_stride)
    result.collision_radius=math.max(8,math.min(64,result.collision_radius))
    result.diagnostic_only=result.runtime_stage=="A" or result.diagnostic_only
    result.install_control_hooks=result.runtime_stage=="C" and not result.diagnostic_only and result.install_control_hooks
    result.enable_terrain_queries=not result.diagnostic_only and result.enable_terrain_queries
    result.enable_health_hook_tests=result.runtime_stage=="C" and not result.diagnostic_only and result.enable_health_hook_tests
    result.enable_native_block_colliders=result.runtime_stage=="C" and not result.diagnostic_only and result.enable_native_block_colliders
    result.enable_block_collider_tests=result.enable_native_block_colliders and result.enable_block_collider_tests
    return result
end
local cfg = read_config()
local session = json.load_file("onimusha_mc_session.json") or {}
if type(session)~="table" then session={} end
local session_seed=math.max(1,math.floor(os.time()%2147483647))
local function next_session_counter(value)
    if type(value)~="number" or value<0 or value>=4294967294 or value~=math.floor(value) then return session_seed end
    return value+1
end
local state = {
    active=false, frame=0, epoch=next_session_counter(session.epoch),
    teleport_seq=next_session_counter(session.teleport_seq), health_revision=1,
    health_bypass=0, health_remainder=0, actor_seq=0, actors={},
    tile_map=json.load_file("onimusha_mc_worlds.json") or {},
    world_key=nil, tile={x=0,z=0}, status="Waiting for native bridge", bindings={},
    collision=nil, collision_count=0, collision_ready=false, last_error=nil,
    blocks={}, solid_backlog={}, collider_probe=nil,
    hooks={},
}
local function persist_session()
    json.dump_file("onimusha_mc_session.json",{epoch=state.epoch,teleport_seq=state.teleport_seq})
    local saved=json.load_file("onimusha_mc_session.json")
    if type(saved)~="table" or saved.epoch~=state.epoch or saved.teleport_seq~=state.teleport_seq then
        error("Cannot persist bridge session counters; takeover held off",0)
    end
end
-- Reserve a distinct epoch even for a reset in the same second and the same PID.
persist_session()
local cache = {}
local function attempt(fn)
    local ok,result=pcall(fn)
    if ok then return result end
    return nil
end
local function required(fn,label)
    local ok,result=pcall(fn)
    if not ok then error(label .. ": " .. tostring(result),0) end
    return result
end
local function td(name)
    if cache[name] == nil then cache[name]=sdk.find_type_definition(name) or false end
    return cache[name] or nil
end
local function typename(obj)
    return attempt(function() return obj:get_type_definition():get_full_name() end) or ""
end
local function pin_managed(obj,expected)
    if not obj or typename(obj)~=expected then error("Unexpected managed type; expected "..expected,0) end
    -- New refcount-zero objects are ephemeral in this REFramework build. add_ref
    -- promotes the wrapper once; Lua GC releases it when our last reference goes.
    required(function() obj:add_ref() end,"Retain "..expected)
    return obj
end
local function addr(obj)
    return attempt(function() return obj:get_address() end) or tostring(obj)
end
local function same(a,b) return a and b and addr(a)==addr(b) end
local function method(obj,name)
    return obj and attempt(function() return obj:get_type_definition():get_method(name) end)
end
local function call(obj,name,...)
    local args={...}
    if not method(obj,name) then return nil end
    return attempt(function() return obj:call(name,table.unpack(args)) end)
end
local function strictcall(obj,name,...)
    local args={...}
    if not method(obj,name) then error("Missing " .. typename(obj) .. "." .. name,0) end
    return required(function() return obj:call(name,table.unpack(args)) end,name)
end
local function fields(obj)
    local result,scan={},attempt(function() return obj:get_type_definition() end)
    for _=1,8 do
        if not scan then break end
        for _,f in ipairs(scan:get_fields() or {}) do
            if not f:is_static() then result[#result+1]=f end
        end
        scan=scan:get_parent_type()
    end
    return result
end
local function elements(a)
    return attempt(function() return a:get_elements() end) or {}
end
local function camera_angles_from_look(position,look,previous_yaw)
    local function finite(value)
        return type(value)=="number" and value==value and value>-math.huge and value<math.huge
    end
    if not position or not look then return nil,"Missing camera position/look-at" end
    for _,point in ipairs({position,look}) do
        if not finite(point.x) or not finite(point.y) or not finite(point.z) then
            return nil,"Non-finite camera position/look-at"
        end
    end
    local dx,dy,dz=look.x-position.x,look.y-position.y,look.z-position.z
    if not finite(dx) or not finite(dy) or not finite(dz) then return nil,"Non-finite camera direction" end
    local scale=math.max(math.abs(dx),math.abs(dy),math.abs(dz))
    if scale<0.000001 then return nil,"Zero-length camera direction" end
    local sx,sy,sz=dx/scale,dy/scale,dz/scale
    local length=math.sqrt(sx*sx+sy*sy+sz*sz)
    local fx,fy,fz=sx/length,sy/length,sz/length
    local yaw
    if math.sqrt(fx*fx+fz*fz)<0.00000001 then
        if not finite(previous_yaw) then return nil,"Vertical camera direction has no verified yaw" end
        yaw=previous_yaw
    else
        -- MC forward = (-sin(yaw), -sin(pitch), cos(yaw)); MC z = -RE z.
        yaw=math.deg(math.atan(-fx,-fz))
    end
    local pitch=-math.deg(math.asin(math.max(-1,math.min(1,fy))))
    return {yaw=yaw,pitch=pitch}
end
local function refresh_camera_baseline()
    -- Our active camera writes must never become a new native teleport baseline.
    if state.active then return state.host_camera_angles~=nil end
    local position=attempt(function() return state.camera_transform:get_position() end)
    local look=call(state.camera,"get_LookAtPosition")
    local previous=state.host_camera_angles and state.host_camera_angles.yaw
    local ok,angles,err=pcall(camera_angles_from_look,position,look,previous)
    if not ok then err=angles;angles=nil end
    state.host_camera_angles=angles
    state.host_camera_diagnostic={valid=angles~=nil,yaw=angles and angles.yaw,
        pitch=angles and angles.pitch,error=err,frame=state.frame}
    return angles~=nil
end
-- Traverse only live object references. No speculative getters, offsets or memory writes.
local function find_live(root,wanted,maxdepth)
    local queue,seen={{obj=root,path="root",depth=0}},{}
    local head=1
    while head<=#queue and head<=1500 do
        local item=queue[head]; head=head+1
        local obj=item.obj
        if obj and not seen[addr(obj)] then
            seen[addr(obj)]=true
            local name=typename(obj)
            if wanted[name] then return obj,item.path end
            if item.depth<(maxdepth or 6) then
                if name:find("%[%]$") then
                    for i,v in ipairs(elements(obj)) do
                        if i>16 then break end
                        if type(v)=="userdata" then queue[#queue+1]={obj=v,path=item.path.."["..i.."]",depth=item.depth+1} end
                    end
                elseif name:match("^app%.") or name:match("^ace%.") then
                    for _,f in ipairs(fields(obj)) do
                        local ft=f:get_type():get_full_name()
                        if not ft:match("^System%.") and not ft:find("user_data",1,true)
                            and not ft:find("Resource",1,true) and not ft:find("Catalog",1,true)
                            and not ft:find("Delegate",1,true) and not ft:find("SafeEvent",1,true) then
                            local v=attempt(function() return f:get_data(obj) end)
                            if type(v)=="userdata" then queue[#queue+1]={obj=v,path=item.path.."."..f:get_name(),depth=item.depth+1} end
                        end
                    end
                end
            end
        end
    end
end
local function scene()
    local sm=sdk.get_native_singleton("via.SceneManager")
    if not sm or not td("via.SceneManager") then return nil end
    return attempt(function() return sdk.call_native_func(sm,td("via.SceneManager"),"get_CurrentScene") end)
end
local function scene_components(s,name)
    if not s or not td(name) then return {} end
    local result=call(s,"findComponents(System.Type)",td(name):get_runtime_type())
    return elements(result)
end
local function mcpos(p)
    return { x=p.x/cfg.units_per_block+state.tile.x, y=p.y/cfg.units_per_block,
        z=-p.z/cfg.units_per_block+state.tile.z }
end
local function repos(x,y,z)
    return Vector3f.new((x-state.tile.x)*cfg.units_per_block,y*cfg.units_per_block,-(z-state.tile.z)*cfg.units_per_block)
end
local function new_object(name)
    local object=attempt(function() return sdk.create_instance(name) end)
    if not object then object=attempt(function() return sdk.create_instance(name,true) end) end
    if not object then error("Native allocation failed: "..name,0) end
    return object
end
local function destroy_box(box)
    if not box then return end
    call(box.collider,"disable")
    if box.component and box.group_id and box.set_id then
        call(box.component,"unregisterRequestSet(System.UInt32, System.UInt32)",box.group_id,box.set_id)
    end
    if box.go then
        attempt(function() td("via.GameObject"):get_method("destroy(via.GameObject)"):call(nil,box.go) end)
    end
end
local function clear_boxes()
    for _,box in pairs(state.blocks) do destroy_box(box) end
    state.blocks={};state.solid_backlog={}
    if state.collider_probe then destroy_box(state.collider_probe);state.collider_probe=nil end
end
local function set_boxes_enabled(enabled)
    if state.boxes_enabled==enabled then return end
    for _,box in pairs(state.blocks) do
        if box.component then
            call(box.component,"set_DisableLayerBits",enabled and 0 or -1)
        elseif box.collider then call(box.collider,enabled and "enable" or "disable") end
    end
    state.boxes_enabled=enabled
end
local function capture_player_input_seals()
    if state.input_seals then
        if state.input_seals.restore_pending then error("Input restoration remains pending",0) end
        return state.input_seals
    end
    local ledger={records={},seen={},inputs=0,keys=0,attempted=false,arrays={}}
    local function array_size(array,label,limit)
        if not array or not typename(array):find("%[%]$") then
            error("Unexpected managed array type for "..label..": "..typename(array),0)
        end
        -- The deployed SDK exposes SystemArray get_size/get_element with zero-based
        -- indices. get_elements returns a C++ vector, not a guaranteed Lua table.
        local count=required(function() return array:get_size() end,"Read array size "..label)
        if type(count)~="number" or count~=math.floor(count) or count<0 or count>limit then
            error("Unexpected managed array size for "..label..": "..tostring(count),0)
        end
        return count
    end
    local function remember(obj,name,is_key)
        if not obj then error("Missing player input object for "..name,0) end
        local identity=tostring(addr(obj))..":"..name
        if ledger.seen[identity] then return end
        local field
        for _,candidate in ipairs(fields(obj)) do
            if candidate:get_name()==name and candidate:get_type():get_full_name()=="System.Boolean" then
                field=candidate;break
            end
        end
        if not field then error("Missing reflected Boolean "..typename(obj).."."..name,0) end
        local value=required(function() return field:get_data(obj) end,"Read input seal "..name)
        if type(value)~="boolean" then error("Non-Boolean input seal "..name,0) end
        local setter=required(function() return obj.set_field end,"Check managed input field setter")
        if type(setter)~="function" then error("Missing callable REManagedObject.set_field for "..name,0) end
        required(function() obj:add_ref() end,"Retain input seal owner")
        ledger.seen[identity]=true
        ledger.records[#ledger.records+1]={obj=obj,field=field,original=value,name=name}
        if is_key then ledger.keys=ledger.keys+1 else ledger.inputs=ledger.inputs+1 end
    end
    local ok,err=pcall(function()
        for _,name in ipairs({"_PlayerInput","_PadPlayerInput","_MkbPlayerInput"}) do
            local array=required(function() return state.input:get_field(name) end,"Read player input array "..name)
            local count=array_size(array,name,16)
            ledger.arrays[name]=count
            for index=0,count-1 do
                local obj=required(function() return array:get_element(index) end,"Read player input "..name.."["..index.."]")
                remember(obj,"_SealAll",false)
                local key_array=required(function() return obj:get_field("_Keys") end,"Read input keys")
                local key_count=array_size(key_array,name.."["..index.."]._Keys",512)
                for key_index=0,key_count-1 do
                    local key=required(function() return key_array:get_element(key_index) end,"Read input key ["..key_index.."]")
                    remember(key,"_IsSealed",true)
                end
            end
        end
        if ledger.inputs==0 or ledger.keys==0 then error("No reflected player input/key owners",0) end
    end)
    state.input_seal_diagnostic={captured=ok,inputs=ledger.inputs,keys=ledger.keys,arrays=ledger.arrays,
        error=not ok and tostring(err) or nil,sealed=false}
    if not ok then error("Input seal capture failed before sealing: "..tostring(err),0) end
    state.input_seals=ledger
    return ledger
end
local function seal_player_inputs()
    local ledger=capture_player_input_seals()
    if not method(state.input,"sealAllPlayer") then error("Missing GameInputManager.sealAllPlayer",0) end
    -- Record the attempted call before invoking it, so a partial failure can be restored.
    ledger.attempted=true
    strictcall(state.input,"sealAllPlayer")
    state.input_seal_diagnostic.sealed=true
end
local function restore_player_input_seals()
    local ledger=state.input_seals
    if not ledger then return end
    local restored,errors,remaining=0,{},{}
    if ledger.attempted then
        for _,record in ipairs(ledger.records) do
            local ok,err=pcall(function()
                local current=record.field:get_data(record.obj)
                if type(current)~="boolean" then error("Input seal owner became invalid") end
                if current~=record.original then
                    -- This SDK exposes writes on REManagedObject, not REField.
                    record.obj:set_field(record.name,record.original)
                    if record.field:get_data(record.obj)~=record.original then error("Input seal write failed readback") end
                    restored=restored+1
                end
            end)
            if not ok then
                remaining[#remaining+1]=record
                if #errors<3 then errors[#errors+1]=record.name..": "..tostring(err) end
            end
        end
    end
    ledger.records=remaining;ledger.restore_pending=#remaining>0
    if #remaining==0 then state.input_seals=nil end
    state.input_seal_diagnostic={captured=true,inputs=ledger.inputs,keys=ledger.keys,arrays=ledger.arrays,
        sealed=false,restore_writes=restored,pending_records=#remaining,errors=errors}
end
local function positive_fov(value)
    return type(value)=="number" and value==value and value>0 and value<math.huge
end
local function capture_player_visuals()
    local fov=strictcall(state.camera,"get_FOV")
    if not positive_fov(fov) then error("Native FOV must be a finite positive number before takeover",0) end
    local targets,seen={},{}
    local gos={state.player_go}
    for _,part in ipairs(elements(call(state.context,"get_Parts"))) do gos[#gos+1]=part end
    for _,go in ipairs(gos) do
        if go and not seen[addr(go)] then
            if strictcall(go,"get_Valid")~=true then error("Native draw target is not valid",0) end
            local original=strictcall(go,"get_DrawSelf")
            if type(original)~="boolean" then error("Native DrawSelf must be Boolean before takeover",0) end
            seen[addr(go)]=true;targets[#targets+1]={obj=go,original=original}
        end
    end
    if #targets==0 then error("No validated native draw targets",0) end
    -- Commit only after every original value has been validated, before any write.
    state.draw_targets=targets;state.original_fov=fov
    state.fov_restore={obj=state.camera,original=fov}
end
local function restore_player_visuals()
    local remaining,errors={},{}
    local draw_writes,restored_draw,fov_writes=0,0,0
    if state.hidden then
        for _,item in ipairs(state.draw_targets or {}) do
            local ok,err=pcall(function()
                if strictcall(item.obj,"get_Valid")~=true then error("Draw target became invalid") end
                local current=strictcall(item.obj,"get_DrawSelf")
                if type(current)~="boolean" then error("Draw target getter is not Boolean") end
                if current~=item.original then
                    strictcall(item.obj,"set_DrawSelf",item.original)
                    if strictcall(item.obj,"get_DrawSelf")~=item.original then error("Draw restore failed readback") end
                    draw_writes=draw_writes+1
                end
            end)
            if ok then restored_draw=restored_draw+1
            else
                remaining[#remaining+1]=item
                if #errors<3 then errors[#errors+1]=tostring(err) end
            end
        end
    end
    state.draw_targets=remaining;state.hidden=#remaining>0
    local fov_error
    if state.fov_restore then
        local record=state.fov_restore
        local ok,err=pcall(function()
            if not positive_fov(record.original) then error("Invalid saved native FOV") end
            if strictcall(record.obj,"get_FOV")~=record.original then
                strictcall(record.obj,"set_FOV",record.original)
                local after=strictcall(record.obj,"get_FOV")
                if not positive_fov(after) or math.abs(after-record.original)>record.original*0.00001 then
                    error("FOV restore failed readback")
                end
                fov_writes=1
            end
        end)
        if ok then state.fov_restore=nil;state.original_fov=nil else fov_error=tostring(err) end
    end
    state.visual_restore_diagnostic={pending_draw=#remaining,pending_fov=state.fov_restore~=nil,
        draw_writes=draw_writes,restored_draw=restored_draw,fov_writes=fov_writes,errors=errors,fov_error=fov_error}
end
local function restoration_pending()
    return (state.input_seals and state.input_seals.restore_pending) or state.hidden or state.fov_restore~=nil
end
local function fail_open(reason)
    state.active=false; state.status=reason
    restore_player_input_seals()
    set_boxes_enabled(false)
    restore_player_visuals()
end
local function reload_config()
    if state.frame%cfg.config_reload_frames~=1 then return end
    local next_cfg=read_config()
    local changed=false
    for k,v in pairs(next_cfg) do if cfg[k]~=v then changed=true;break end end
    if not changed then return end
    local previous=cfg
    fail_open("Configuration changed; native player control restored")
    cfg=next_cfg
    if previous.units_per_block~=cfg.units_per_block or previous.tile_stride~=cfg.tile_stride then
        state.world_key=nil;state.collision=nil;state.collision_ready=false
    elseif previous.enable_terrain_queries and not cfg.enable_terrain_queries then
        state.collision=nil;state.collision_ready=false
    end
    local bridge=_G.onimusha_mc
    -- A cold stage-A run never mutates the bridge. A deliberate downgrade releases
    -- an earlier test's takeover, rather than leaving its last pose/render active.
    if bridge and (previous.runtime_stage~=cfg.runtime_stage or previous.enabled~=cfg.enabled) then
        bridge.set_enabled(cfg.runtime_stage=="C" and cfg.enabled)
        state.bridge_initialized=true
    end
    state.last_error=nil
    log.info("[OnimushaMC] hot config: stage "..cfg.runtime_stage.."; diagnostic_only="..tostring(cfg.diagnostic_only))
end
local function discover()
    local function unavailable(reason)
        fail_open(reason)
        state.player,state.info,state.health,state.transform,state.context=nil,nil,nil,nil,nil
        state.controller,state.physics,state.cc=nil,nil,nil
        state.live_snapshot=nil;state.collision=nil;state.collision_ready=false
        state.host_camera_angles=nil
        return false
    end
    local pm=sdk.get_managed_singleton("app.PlayerManager")
    local info=call(pm,"getControllingPlayerInfo")
    if not info then return unavailable("No playable character (menu/loading)") end
    if call(info,"get_Valid")~=true or call(info,"get_CharacterValid")~=true
        or call(pm,"isPlayerReady",false)~=true then
        return unavailable("Player is not fully initialized; native binding calls deferred")
    end
    local player,ppath=call(info,"get_Character"),"PlayerManager.getControllingPlayerInfo().get_Character()"
    local context=call(info,"get_Context") or call(player,"get_Context")
    local chara=call(context,"get_Chara")
    local health,hpath=call(chara,"get_HealthManager"),"PlayerInfo.get_Context().get_Chara().get_HealthManager()"
    if not player or not health then
        return unavailable("Unresolved player/health reference; run read-only probe")
    end
    local go=call(player,"get_GameObject")
    local transform=go and call(go,"get_Transform")
    local camera=sdk.get_primary_camera()
    local camera_go=call(camera,"get_GameObject")
    local camera_transform=camera_go and call(camera_go,"get_Transform")
    local controller=call(info,"get_Controller")
    if not go or not transform or not camera or not camera_transform or not controller then
        return unavailable("Unresolved player/camera/controller binding")
    end
    if state.player and not same(state.player,player) then
        fail_open("Player changed"); state.teleport_seq=state.teleport_seq+1
        persist_session()
        state.health_remainder=0;state.collision_ready=false;state.collision=nil
        state.host_camera_angles=nil
    end
    state.pm, state.info, state.player, state.player_go, state.transform=pm,info,player,go,transform
    state.health,state.controller,state.camera,state.camera_transform=health,controller,camera,camera_transform
    state.context=context
    state.cc=call(go,"getComponent(System.Type)",td("via.physics.CharacterController"):get_runtime_type())
    state.input=sdk.get_managed_singleton("app.GameInputManager")
    state.pause=sdk.get_managed_singleton("app.PauseManager")
    state.physics=attempt(function() return player:get_field("CharacterPhysics") end)
    state.bindings.player=ppath;state.bindings.health=hpath;state.bindings.camera=typename(camera)
    if not state.active and not state.camera_axis_calibrated then
        local look=call(camera,"get_LookAtPosition")
        local cp=camera_transform:get_position()
        local q=camera_transform:get_rotation()
        if look and q then
            local dx,dy,dz=look.x-cp.x,look.y-cp.y,look.z-cp.z
            local length=math.sqrt(dx*dx+dy*dy+dz*dz)
            local fx,fy,fz=2*(q.x*q.z+q.w*q.y),2*(q.y*q.z-q.w*q.x),1-2*(q.x*q.x+q.y*q.y)
            local dot=length>0.01 and (fx*dx+fy*dy+fz*dz)/length or 0
            if math.abs(dot)>0.9 then
                state.camera_forward_sign=dot>0 and 1 or -1
                state.camera_axis_calibrated=true
                state.bindings.camera_forward_axis=state.camera_forward_sign>0 and "+Z (live look-at/rotation)" or "-Z (live look-at/rotation)"
            end
            state.camera_axis_diagnostic={dot=dot,position={x=cp.x,y=cp.y,z=cp.z},
                rotation={x=q.x,y=q.y,z=q.z,w=q.w},look_at={x=look.x,y=look.y,z=look.z}}
        end
    end
    for _,check in ipairs({{go,"get_DrawSelf"},{go,"set_DrawSelf"},{health,"get_Health"},
        {health,"get_MaxHealth"},{health,"setHealth"},{health,"checkHealthZero"},
        {state.input,"sealAllPlayer"},{camera,"get_FOV"},{camera,"set_FOV"},
        {controller,"get_IsEventJack"},{controller,"get_IsDialogueJack"}}) do
        if not method(check[1],check[2]) then fail_open("Missing required method "..check[2]);return false end
    end
    state.live_snapshot={health_current=call(health,"get_Health"),health_max=call(health,"get_MaxHealth"),
        camera_fov=call(camera,"get_FOV"),frame=state.frame}
    return true
end
local function stage_key(s)
    local identity=call(state.context,"get_Info")
    local stage=call(identity,"get_StageID")
    local area=call(identity,"get_AreaID")
    if type(stage)=="number" and stage>=0 and type(area)=="number" and area>=0 then
        state.bindings.stage="PlayerInfo.get_Context().get_Info().get_StageID()/get_AreaID()"
        return "stage:"..tostring(stage)..":area:"..tostring(area)
    end
    -- A stable stage key is required to prevent same-coordinate cross-stage block leakage.
    -- Exact candidate fields are selected only if reflection proves they exist and are populated.
    for _,name in ipairs({"app.EnvironmentManager","app.StageManager","app.cStageSceneManager","app.cAreaSceneManager","app.SceneManager"}) do
        local manager=sdk.get_managed_singleton(name)
        if manager then
            local stage_manager=find_live(manager,{["app.cStageSceneManager"]=true},4)
            for _,candidate in ipairs({stage_manager or manager,manager}) do
                for _,f in ipairs(fields(candidate)) do
                    local fn=f:get_name()
                    if fn:match("[Ss]tage[Ii][Dd]") or fn:match("[Aa]rea[Ii][Dd]") then
                        local v=attempt(function() return f:get_data(candidate) end)
                        if type(v)=="number" or type(v)=="string" then return typename(candidate)..":"..fn..":"..tostring(v) end
                    end
                end
            end
        end
    end
    -- Scene names are containers rather than verified stage IDs and are not used as fallback.
    return nil
end
local function choose_world(key)
    if not key then fail_open("Stage identity unresolved; block persistence held safely");return false end
    if key==state.world_key then return true end
    fail_open("Stage transition")
    state.host_camera_angles=nil
    if not state.tile_map[key] then
        local count=0;for _ in pairs(state.tile_map) do count=count+1 end
        state.tile_map[key]={index=count+1,x=(count%16)*cfg.tile_stride,z=math.floor(count/16)*cfg.tile_stride}
        json.dump_file("onimusha_mc_worlds.json",state.tile_map)
    end
    state.tile=state.tile_map[key];state.world_key=key
    state.world_id=state.tile.index;state.epoch=state.epoch+1
    state.teleport_seq=state.teleport_seq+1;state.health_remainder=0
    persist_session()
    state.collision=nil;state.collision_ready=false;state.actors={}
    clear_boxes();state.bindings.block_colliders=false;state.collider_probe_failed=false;state.collider_mode=nil
    return true
end
local function vec(v)
    if not v then return nil end
    return attempt(function()
        if type(v.x)~="number" or type(v.y)~="number" or type(v.z)~="number" then return nil end
        return Vector3f.new(v.x,v.y,v.z)
    end)
end
local function triangle_vertices(t)
    if not t then return nil end
    local result={}
    local typeinfo=attempt(function() return t:get_type_definition() end)
    if typeinfo then
        for _,f in ipairs(typeinfo:get_fields() or {}) do
            if f:get_type():get_full_name()=="via.vec3" then
                local v=vec(attempt(function() return f:get_data(t) end))
                if v then result[#result+1]=v end
            end
        end
    end
    if #result==3 then return result end
    -- ValueType layout is not guessed from byte offsets. Unsupported values stop export.
    return nil
end
local function close_aabb(box,centre,radius)
    if not box then return false end
    local vs={}
    local bt=attempt(function() return box:get_type_definition() end)
    if bt then
        for _,f in ipairs(bt:get_fields() or {}) do
            if f:get_type():get_full_name()=="via.vec3" then vs[#vs+1]=vec(attempt(function() return f:get_data(box) end)) end
        end
    end
    if #vs~=2 or not vs[1] or not vs[2] then return false end
    return vs[1].x<=centre.x+radius and vs[2].x>=centre.x-radius
        and vs[1].z<=centre.z+radius and vs[2].z>=centre.z-radius
        and vs[1].y<=centre.y+radius and vs[2].y>=centre.y-radius
end
local function start_collision(s,p)
    local job={shapes={},triangles={},seen={},centre=p,shape_index=1,triangle_index=0,unsupported=0}
    -- Native world-space query: query setters change only our temporary query object.
    -- AABB and Triangle field names are verified in this game's live TDB 82.
    local query_ok,query_error=pcall(function()
        local system=sdk.get_native_singleton("via.physics.System")
        local query=state.area_query
        if query and typename(query)~="via.physics.GetAreaPrimitiveQuery" then query=nil;state.area_query=nil end
        if not query then query=sdk.create_instance("via.physics.GetAreaPrimitiveQuery") end
        if not query then query=sdk.create_instance("via.physics.GetAreaPrimitiveQuery",true) end
        if not query or not system then error("Native area query allocation unavailable") end
        query=pin_managed(query,"via.physics.GetAreaPrimitiveQuery")
        local box=ValueType.new(td("via.AABB"))
        local r=cfg.collision_radius*cfg.units_per_block
        box:set_field("minpos",Vector3f.new(p.x-r,p.y-r,p.z-r))
        box:set_field("maxpos",Vector3f.new(p.x+r,p.y+r,p.z+r))
        strictcall(query,"set_Area",box)
        local filter=call(state.cc,"get_FilterInfo")
        if not filter then error("Player CharacterController collision filter unavailable") end
        strictcall(query,"set_FilterInfo",filter)
        local result=pin_managed(sdk.call_native_func(system,td("via.physics.System"),"getAreaPrimitive",query),
            "via.physics.GetAreaPrimitiveResult")
        local count=strictcall(result,"get_NumTriangles")
        if not count or count==0 then error("Native area query returned zero triangles") end
        state.area_query=query
        state.ground_collidable=call(result,"getTriangleCollidable(System.UInt32)",0)
        job.shapes[1]={shape=result,count=count,world_space=true,accessor="getTriangle(System.UInt32)"}
        state.bindings.collision="via.physics.System.getAreaPrimitive(player CharacterController filter)"
        state.query_diagnostic={allocated=true,triangles=count,boxes=call(result,"get_NumBoxes"),
            spheres=call(result,"get_NumSpheres"),capsules=call(result,"get_NumCapsules"),
            query_type=typename(query),result_type=typename(result),retained=true}
    end)
    if query_ok then state.collision=job;state.collision_ready=false;return end
    state.query_diagnostic={error=tostring(query_error)}
    local function collect_shape(shape,depth)
        if not shape or depth>8 or job.seen[addr(shape)] then return end
        job.seen[addr(shape)]=true
        if method(shape,"getTriangleArray(System.UInt32)") then
            local n=call(shape,"getTriangleArrayCount")
            if n and n>0 then job.shapes[#job.shapes+1]={shape=shape,count=n,matrix=call(shape,"get_TransformMatrix")} end
        elseif method(shape,"getInstances(System.UInt32)") then
            local n=call(shape,"getInstancesCount") or 0
            for i=0,math.min(n,4096)-1 do
                local item=call(shape,"getInstances(System.UInt32)",i)
                local child
                for _,f in ipairs(fields(item)) do
                    if f:get_type():get_full_name()=="via.physics.Shape" then child=attempt(function() return f:get_data(item) end);break end
                end
                collect_shape(child,depth+1)
            end
        elseif method(shape,"get_Triangle") then
            local vertices=triangle_vertices(call(shape,"get_Triangle"))
            if vertices then job.shapes[#job.shapes+1]={vertices=vertices,count=1} else job.unsupported=job.unsupported+1 end
        else job.unsupported=job.unsupported+1 end
    end
    for _,type_name in ipairs({"via.physics.Colliders","via.physics.ColliderSet"}) do
        for _,component in ipairs(scene_components(s,type_name)) do
            if close_aabb(call(component,"get_BoundingAabb"),p,cfg.collision_radius*cfg.units_per_block) then
                local n=call(component,"getCollidersCount") or call(component,"get_CollidersCount") or 0
                for i=0,math.min(n,4096)-1 do
                    local collider=call(component,"getCollider(System.UInt32)",i)
                    if collider and call(collider,"get_Enabled")~=false then
                        collect_shape(call(collider,"get_TransformedShape") or call(collider,"get_Shape"),0)
                    end
                end
            end
        end
    end
    state.collision=job;state.collision_ready=false
end
local function advance_collision(bridge)
    local job=state.collision
    if not job then return end
    local budget=cfg.collision_triangles_per_frame
    while budget>0 and job.shape_index<=#job.shapes and #job.triangles<cfg.collision_max_triangles do
        local item=job.shapes[job.shape_index]
        if job.triangle_index>=item.count then job.shape_index=job.shape_index+1;job.triangle_index=0
        else
            local vs=item.vertices or triangle_vertices(call(item.shape,item.accessor or "getTriangleArray(System.UInt32)",job.triangle_index))
            if vs then
                -- Z reflection reverses handedness; swap B/C to retain surface winding.
                local out={flags=0};local letters={"a","c","b"}
                for i,v in ipairs(vs) do
                    if item.matrix then
                        local transformed=attempt(function() return item.matrix*Vector4f.new(v.x,v.y,v.z,1) end)
                        if transformed then v=transformed end
                    end
                    local m=mcpos(v);out[letters[i].."x"]=m.x;out[letters[i].."y"]=m.y;out[letters[i].."z"]=m.z
                end
                job.triangles[#job.triangles+1]=out
            else job.unsupported=job.unsupported+1 end
            job.triangle_index=job.triangle_index+1;budget=budget-1
        end
    end
    if job.shape_index>#job.shapes or #job.triangles>=cfg.collision_max_triangles then
        local p=mcpos(job.centre);local r=cfg.collision_radius
        local region={epoch=state.epoch,min_x=math.floor(p.x-r),min_y=math.floor(p.y-r),min_z=math.floor(p.z-r),
            max_x=math.ceil(p.x+r),max_y=math.ceil(p.y+r),max_z=math.ceil(p.z+r),triangles=job.triangles}
        if #job.triangles>0 then
            state.collision_ready=bridge.publish_collision_tris(region)==true;state.collision_centre=job.centre
            state.collision_count=#job.triangles
        else state.status="No verified native collision triangles; control remains off" end
        state.collision=nil;state.collision_unsupported=job.unsupported
    end
end
local function create_direct_box(position,name)
    local box={}
    local ok,err=pcall(function()
        box.go=td("via.GameObject"):get_method("create(System.String)"):call(nil,name)
        if not box.go then error("GameObject.create returned nil") end
        strictcall(box.go,"set_DrawSelf",false)
        local transform=strictcall(box.go,"get_Transform")
        transform:set_position(Vector4f.new(position.x,position.y,position.z,1),false)
        box.shape=new_object("via.physics.BoxShape")
        local obb=ValueType.new(td("via.OBB"))
        local extent=Vector3f.new(cfg.units_per_block/2,cfg.units_per_block/2,cfg.units_per_block/2)
        obb:set_field("coord",Matrix4x4f.new(Vector4f.new(1,0,0,0),Vector4f.new(0,1,0,0),
            Vector4f.new(0,0,1,0),Vector4f.new(0,0,0,1)))
        obb:set_field("extent",extent)
        strictcall(box.shape,"set_Box",obb)
        box.collider=new_object("via.physics.Collider")
        strictcall(box.collider,"set_GameObject",box.go)
        strictcall(box.collider,"set_Shape",box.shape)
        local original=call(state.ground_collidable,"get_FilterInfo")
        local own=strictcall(box.collider,"get_FilterInfo")
        if not original or not own then error("Static ground collision filter unavailable") end
        for _,field in ipairs({"Layer","Group","SubGroup","IgnoreSubGroup","MaskBits"}) do
            local value=strictcall(original,"get_"..field)
            strictcall(own,"set_"..field,value)
        end
        local resource=call(state.ground_collidable,"get_CollisionFilterResource")
        if resource then strictcall(box.collider,"set_CollisionFilterResource",resource) end
        strictcall(box.collider,"set_UpdateShape",true)
        strictcall(box.collider,"enable")
    end)
    if not ok then destroy_box(box);error(tostring(err),0) end
    return box
end
local function copy_ground_filter(collider)
    local original=call(state.ground_collidable,"get_FilterInfo")
    local own=call(collider,"get_FilterInfo")
    if not original or not own then error("Static ground collision filter unavailable") end
    for _,field in ipairs({"Layer","Group","SubGroup","IgnoreSubGroup","MaskBits"}) do
        strictcall(own,"set_"..field,strictcall(original,"get_"..field))
    end
end
local function create_resource_box(position,name)
    local box={mode="requestset",position=position,start_frame=state.frame}
    local ok,err=pcall(function()
        if not state.unit_box_holder then
            local resource=sdk.create_resource("via.physics.RequestSetColliderResource",cfg.block_collider_resource)
            if not resource then error("Unit box RCOL resource unavailable: "..cfg.block_collider_resource) end
            state.unit_box_holder=resource:create_holder("via.physics.RequestSetColliderResourceHolder")
            if not state.unit_box_holder then error("Unit box RCOL holder unavailable") end
        end
        box.go=td("via.GameObject"):get_method("create(System.String)"):call(nil,name)
        if not box.go then error("GameObject.create returned nil") end
        strictcall(box.go,"set_DrawSelf",false)
        local transform=strictcall(box.go,"get_Transform")
        transform:set_position(Vector4f.new(position.x,position.y,position.z,1),false)
        if cfg.units_per_block~=1 then strictcall(transform,"set_Scale",Vector3f.new(cfg.units_per_block,cfg.units_per_block,cfg.units_per_block)) end
        box.component=strictcall(box.go,"createComponent(System.Type)",td("via.physics.RequestSetCollider"):get_runtime_type())
        strictcall(box.component,"setRequestSetGroupsCount(System.UInt32)",1)
        box.group=strictcall(box.component,"getRequestSetGroups(System.UInt32)",0)
        if not box.group then error("New RequestSetCollider group unavailable") end
        strictcall(box.group,"set_Resource",state.unit_box_holder)
    end)
    if not ok then destroy_box(box);error(tostring(err),0) end
    return box
end
local function finish_resource_box(box)
    if box.collider then return true end
    if not call(box.group,"get_Initialized") then
        if state.frame-box.start_frame>300 then error("Unit box request set resource did not initialize") end
        return false
    end
    if not box.set_id then
        box.group_id=strictcall(box.group,"get_Id")
        local count=strictcall(box.group,"get_NumRequestSets")
        if count<1 then error("Unit box RCOL has no request set") end
        box.set_id=strictcall(box.group,"getRequestSetIdFromIndex(System.UInt32)",0)
        strictcall(box.component,"registerRequestSet(System.UInt32, System.UInt32)",box.group_id,box.set_id)
    end
    strictcall(box.component,"updatePose(System.UInt32, System.UInt32)",box.group_id,box.set_id)
    box.collider=call(box.component,"getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)",0,0,0)
    if box.collider then copy_ground_filter(box.collider);return true end
    if state.frame-box.start_frame>300 then error("Registered request set has no Collidable") end
    return false
end
local function create_box(position,name)
    if state.collider_mode=="requestset" then return create_resource_box(position,name) end
    return create_direct_box(position,name)
end
local function probe_block_colliders()
    if cfg.diagnostic_only or not cfg.enable_block_collider_tests then return end
    if state.bindings.block_colliders or state.collider_probe_failed or not state.ground_collidable then return end
    if not state.collider_probe then
        local ok,result=pcall(function()
            local p=state.transform:get_position()
            -- Stay in the loaded scene's physical bounds; a far-away test could
            -- be culled even when registration is valid. Four metres above the
            -- player avoids contact with the normally controlled character.
            local at=Vector3f.new(p.x,p.y+4*cfg.units_per_block,p.z)
            local box=create_box(at,"OnimushaMC_registration_probe")
            box.position=at;box.start_frame=state.frame;return box
        end)
        if not ok then state.collider_probe_failed=true;state.collider_diagnostic={registered=false,error=tostring(result)};return end
        state.collider_probe=result;return
    end
    local box=state.collider_probe
    if state.frame-box.start_frame<6 then return end
    local ok,result=pcall(function()
        if box.mode=="requestset" and not finish_resource_box(box) then return nil end
        local query=new_object("via.physics.CastRayQuery")
        local filter=strictcall(state.cc,"get_FilterInfo")
        strictcall(query,"copyFilterInfo",filter)
        strictcall(query,"enableAllHits")
        strictcall(query,"enableNearSort")
        local p=box.position
        strictcall(query,"setRay(via.vec3, via.vec3, System.Single)",Vector3f.new(p.x,p.y+2*cfg.units_per_block,p.z),
            Vector3f.new(0,-1,0),4*cfg.units_per_block)
        local result=sdk.call_native_func(sdk.get_native_singleton("via.physics.System"),td("via.physics.System"),"castRay",query)
        local count=strictcall(result,"get_NumContactPoints")
        state.collider_ray_diagnostic={contacts=count,ray_distance=call(query,"get_RayDistance"),
            position={x=p.x,y=p.y,z=p.z},ready=call(box.collider,"get_Ready"),
            layer=call(call(box.collider,"get_FilterInfo"),"get_Layer")}
        for i=0,count-1 do
            if same(call(result,"getContactCollidable(System.UInt32)",i),box.collider) then return true end
        end
        return false
    end)
    if result==true then
        state.bindings.block_colliders="Collider.set_GameObject/set_Shape/enable; native castRay identity verified"
        if box.mode=="requestset" then state.bindings.block_colliders="RequestSetCollider.registerRequestSet; native castRay identity verified" end
        state.collider_diagnostic={registered=true,mode=box.mode or "direct",ready=call(box.collider,"get_Ready")}
        destroy_box(box);state.collider_probe=nil
    elseif not ok or state.frame-box.start_frame>=(box.mode=="requestset" and 360 or 120) then
        state.collider_probe_failed=box.mode=="requestset";state.collider_diagnostic={registered=false,mode=box.mode or "direct",
            error=not ok and tostring(result) or "Native castRay did not hit new collider within 120 frames"}
        destroy_box(box);state.collider_probe=nil
        if not state.collider_probe_failed then state.collider_mode="requestset" end
    end
end
local function apply_solids(bridge)
    if not cfg.enable_native_block_colliders or not state.bindings.block_colliders then return end
    for _,update in ipairs(bridge.drain_solids() or {}) do state.solid_backlog[#state.solid_backlog+1]=update end
    for _=1,math.min(24,#state.solid_backlog) do
        local update=table.remove(state.solid_backlog,1)
        local key=update.x..":"..update.y..":"..update.z
        if not update.solid then destroy_box(state.blocks[key]);state.blocks[key]=nil
        elseif not state.blocks[key] then
            local ok,box=pcall(create_box,repos(update.x+0.5,update.y+0.5,update.z+0.5),"OnimushaMC_block_"..key)
            if ok then state.blocks[key]=box else
                table.insert(state.solid_backlog,1,update);state.collider_diagnostic={registered=false,error=tostring(box)}
                state.bindings.block_colliders=false;state.collider_probe_failed=true;break
            end
        end
    end
    local count=0;for _ in pairs(state.blocks) do count=count+1 end
    state.native_block_count=count;state.pending_native_block_colliders=#state.solid_backlog
    for _,box in pairs(state.blocks) do
        if box.mode=="requestset" and not box.collider then
            local ok,err=pcall(finish_resource_box,box)
            if not ok then state.collider_diagnostic={registered=false,error=tostring(err)};
                state.bindings.block_colliders=false;state.collider_probe_failed=true;break end
        end
    end
end
local function set_native_health(health,delta)
    local current=strictcall(health,"get_Health")
    local maximum=strictcall(health,"get_MaxHealth")
    local new=math.max(0,math.min(maximum,math.floor(current+delta+0.5)))
    state.health_bypass=state.health_bypass+1
    local ok,err=pcall(function()
        strictcall(health,"setHealth",new)
        strictcall(health,"checkHealthZero")
    end)
    state.health_bypass=state.health_bypass-1
    if not ok then error(err,0) end
    state.health_revision=state.health_revision+1
end
local function publish_actors(s,bridge)
    local actors,live={},{}
    local candidates=scene_components(s,"app.EnemyCharacter")
    local diagnostic={found=#candidates,valid_go=0,context_resolved=0,health_resolved=0,alive=0}
    local origin=state.transform:get_position()
    for _,enemy in ipairs(candidates) do
        local go=call(enemy,"get_GameObject")
        local tr=call(go,"get_Transform")
        if go and tr and call(go,"get_Valid")~=false then
            diagnostic.valid_go=diagnostic.valid_go+1
            local p=tr:get_position();local dx,dy,dz=p.x-origin.x,p.y-origin.y,p.z-origin.z
            if dx*dx+dy*dy+dz*dz<128*128*cfg.units_per_block*cfg.units_per_block then
                local context=call(enemy,"get_Context")
                local chara=call(context,"get_Chara")
                local h=call(chara,"get_HealthManager")
                if context then diagnostic.context_resolved=diagnostic.context_resolved+1 end
                if h then diagnostic.health_resolved=diagnostic.health_resolved+1 end
                local current,maximum=call(h,"get_Health"),call(h,"get_MaxHealth")
                if not diagnostic.sample then diagnostic.sample={enemy_type=typename(enemy),context_type=typename(context),
                    chara_type=typename(chara),health_type=typename(h),current=current,maximum=maximum} end
                if current and maximum and maximum>0 and current>0 then
                    diagnostic.alive=diagnostic.alive+1
                    local id=state.actors[addr(enemy)] and state.actors[addr(enemy)].id
                    if not id then state.actor_seq=state.actor_seq+1;id=state.actor_seq end
                    local entry={id=id,obj=enemy,health=h};live[addr(enemy)]=entry
                    local m=mcpos(p)
                    local cc=call(go,"getComponent(System.Type)",td("via.physics.CharacterController"):get_runtime_type())
                    local width=(call(cc,"get_Radius") or 0.45)*2/cfg.units_per_block
                    local height=(call(cc,"get_Height") or 1.8)/cfg.units_per_block
                    actors[#actors+1]={id=id,flags=1,x=m.x,y=m.y,z=m.z,yaw=0,width=width,height=height,
                        health_frac=current/maximum,level=1,name=tostring(call(go,"get_Name") or "Onimusha enemy")}
                    if #actors>=96 then break end
                end
            end
        end
    end
    state.actors=live;bridge.publish_actors(actors);state.actor_count=#actors;state.enemy_diagnostic=diagnostic
end
local function apply_events(bridge)
    for _,event in ipairs(bridge.drain_events() or {}) do
        if state.active and event.type==6 and event.weapon==state.epoch then
            local maximum=call(state.health,"get_MaxHealth")
            if maximum and maximum>0 and type(event.a)=="number" and math.abs(event.a)<=1 then
                local amount=event.a*maximum+state.health_remainder
                local integer=amount<0 and math.ceil(amount) or math.floor(amount)
                state.health_remainder=amount-integer
                if integer~=0 then set_native_health(state.health,integer) end
            end
        elseif state.active and event.type==1 then
            for _,entry in pairs(state.actors) do
                if entry.id==event.form_id then
                    local damage=math.max(0,math.min(1000,event.a or 0))*cfg.enemy_host_damage_per_mc_point
                    if damage>0 then set_native_health(entry.health,-damage) end
                    break
                end
            end
        end
    end
end
local function install_hooks()
    if state.control_hooks_attempted then return end
    state.control_hooks_attempted=true
    local base=td("app.CharacterBase")
    local motion=base and base:get_method("evMotionRootApply(via.vec3, via.Quaternion)")
    if motion then
        state.hooks.root_motion={method="evMotionRootApply",address=tostring(motion:get_function()),attempted=true,
            observed_calls=0,observed_player_calls=0}
        sdk.hook(motion,function(args)
            state.hooks.root_motion.observed_calls=state.hooks.root_motion.observed_calls+1
            if same(sdk.to_managed_object(args[2]),state.player) then
                state.hooks.root_motion.observed_player_calls=state.hooks.root_motion.observed_player_calls+1
                state.bindings.root_motion=true
                if state.active then return sdk.PreHookResult.SKIP_ORIGINAL end
            end
        end,function(retval) return retval end)
        state.bindings.root_motion_attempted=true
    end
    local hp=td("app.cHealthManager")
    state.hooks.setHealth={method="setHealth",attempted=false,
        reason="Current REFramework failed to hook this method's JIT thunk in the first live test; commit calls remain available"}
    for _,name in ipairs({"addHealth(System.Int32, System.Boolean)","set_Health(System.Int32)"}) do
        local m=hp and hp:get_method(name)
        if m then
            local record={method=name,address=tostring(m:get_function()),attempted=true,
                observed_calls=0,observed_player_calls=0,observed_negative_player_calls=0,queued_hurts=0}
            state.hooks[name]=record
            sdk.hook(m,function(args)
                record.observed_calls=record.observed_calls+1
                if same(sdk.to_managed_object(args[2]),state.health) then
                    record.observed_player_calls=record.observed_player_calls+1
                    state.bindings.health_hook=true
                end
                if not same(sdk.to_managed_object(args[2]),state.health) then return end
                local value=sdk.to_int64(args[3]) & 0xFFFFFFFF
                if value>=0x80000000 then value=value-0x100000000 end
                local current,maximum=call(state.health,"get_Health"),call(state.health,"get_MaxHealth")
                if not current or not maximum or maximum<=0 then return end
                local delta=name:sub(1,9)=="addHealth" and value or value-current
                if delta<0 and state.health_bypass==0 then
                    record.observed_negative_player_calls=record.observed_negative_player_calls+1
                end
                if not state.active or state.health_bypass>0 or not cfg.mirror_native_damage_to_mc then return end
                local bridge=_G.onimusha_mc
                if not bridge or not bridge.send_hurt then return end
                if delta<0 then
                    local accepted=bridge.send_hurt({kind=0,mc_points=-delta/maximum*20,attacker_id=0,flags=4})
                    if accepted then record.queued_hurts=record.queued_hurts+1;return sdk.PreHookResult.SKIP_ORIGINAL end
                end
            end,function(retval) return retval end)
            state.bindings.health_hooks_attempted=true
        end
    end
end
local function tick()
    reload_config()
    if not state.active and restoration_pending() then
        fail_open("Retrying owned native input/draw/FOV restoration")
        if restoration_pending() then
            if not cfg.diagnostic_only and _G.onimusha_mc then _G.onimusha_mc.submit_host({ready=false}) end
            return
        end
    end
    if cfg.diagnostic_only then
        if state.frame%60==1 or not state.player then
            if discover() then
                state.observed_world_key=stage_key(scene())
                state.status="Stage A: read-only player/HP/stage/camera diagnostics"
            end
        end
        state.bindings.diagnostic_only=true
        return
    end
    state.bindings.diagnostic_only=false
    local bridge=_G.onimusha_mc
    if not bridge then fail_open("Native OnimushaMC bridge not loaded");return end
    if not state.bridge_initialized then bridge.set_enabled(cfg.runtime_stage=="C" and cfg.enabled);state.bridge_initialized=true end
    if state.frame%30==1 or not state.player then if not discover() then bridge.submit_host({ready=false});return end end
    if call(state.info,"get_Valid")~=true or call(state.info,"get_CharacterValid")~=true
        or call(state.pm,"isPlayerReady",false)~=true then
        discover();bridge.submit_host({ready=false});return
    end
    -- No hooks are installed until a fully initialized live player is established.
    if cfg.install_control_hooks then install_hooks() end
    if cfg.enable_health_hook_tests and cfg.install_control_hooks and not state.health_hook_tested then
        local before=strictcall(state.health,"get_Health")
        strictcall(state.health,"addHealth(System.Int32, System.Boolean)",0,false)
        local after=strictcall(state.health,"get_Health")
        state.health_hook_tested=true
        state.health_hook_test={before=before,after=after,delta=0,
            callback_observed=state.bindings.health_hook or false}
        if before~=after then error("Zero-delta health verification changed native HP") end
    end
    local s=scene()
    if not choose_world(stage_key(s)) then bridge.submit_host({ready=false});return end
    if not refresh_camera_baseline() then
        fail_open("Native camera direction unresolved; takeover held safely")
        bridge.submit_host({ready=false});return
    end
    local host_angles=state.host_camera_angles
    -- Commit the final MC health event before a dead MC frame relinquishes control.
    -- Otherwise a fatal MC hit could be discarded before native HP reaches zero.
    if cfg.runtime_stage=="C" then apply_events(bridge) end
    local menu=call(state.pause,"get_IsMenuPause") or call(state.pause,"get_IsPlayerPause")
    local scripted=call(state.controller,"get_IsEventJack") or call(state.controller,"get_IsDialogueJack")
        or call(state.player,"get_IsEventStart") or call(state.pm,"get_IsAutoMove")
    local dying=call(state.pm,"isPlayerDying") or call(state.pm,"isPlayerDead")
    local p=state.transform:get_position();local m=mcpos(p)
    if math.abs(p.x/cfg.units_per_block)>=cfg.tile_stride/2-128
        or math.abs(p.z/cfg.units_per_block)>=cfg.tile_stride/2-128 then
        fail_open("Stage extent exceeds isolated Minecraft tile; recalibrate tile_stride")
        bridge.submit_host({ready=false});return
    end
    local current,maximum=call(state.health,"get_Health"),call(state.health,"get_MaxHealth")
    local valid_hp=type(current)=="number" and type(maximum)=="number" and maximum>0
    if state.bridge_epoch~=state.epoch then
        bridge.submit_host({ready=false,world_id=state.world_id,epoch=state.epoch,
            teleport_seq=state.teleport_seq,x=m.x,y=m.y,z=m.z,yaw=host_angles.yaw,pitch=host_angles.pitch,
            health_current=current or 0,health_max=maximum or 0,units_per_block=cfg.units_per_block})
        state.bridge_epoch=state.epoch
    end
    if cfg.enable_terrain_queries and not state.collision and (not state.collision_ready or not state.collision_centre
        or math.abs(p.x-state.collision_centre.x)>12*cfg.units_per_block
        or math.abs(p.z-state.collision_centre.z)>12*cfg.units_per_block) then start_collision(s,p) end
    advance_collision(bridge)
    probe_block_colliders()
    if state.frame%60==0 then publish_actors(s,bridge) end
    if cfg.runtime_stage=="B" then
        bridge.set_camera({binding_ready=state.camera_transform~=nil,valid=false})
        bridge.submit_host({ready=false,menu=menu or false,loading=false,
            x=m.x,y=m.y,z=m.z,yaw=host_angles.yaw,pitch=host_angles.pitch,world_id=state.world_id,epoch=state.epoch,teleport_seq=state.teleport_seq,
            health_current=current or 0,health_max=maximum or 0,health_revision=state.health_revision,
            units_per_block=cfg.units_per_block})
        state.status=state.collision_ready and "Stage B: terrain exported; native player retains control" or
            "Stage B: querying terrain; native player retains control"
        return
    end
    local native=bridge.status()
    local can_control=cfg.install_control_hooks and not menu and not scripted and not dying and valid_hp
        and current>0 and state.collision_ready and state.bindings.root_motion
    -- HP getters are authoritative even before the first hit in a safe area.
    -- Damage hooks fail open to native damage if an MC mitigation event cannot
    -- be queued; observed hook counters remain separate runtime evidence.
    local mc=bridge.read_mc()
    bridge.set_camera({binding_ready=state.camera_transform~=nil,valid=false})
    bridge.submit_host({ready=can_control,menu=menu or false,loading=not call(state.pm,"isPlayerReady",false),
        x=m.x,y=m.y,z=m.z,yaw=host_angles.yaw,pitch=host_angles.pitch,world_id=state.world_id,epoch=state.epoch,teleport_seq=state.teleport_seq,
        health_current=current or 0,health_max=maximum or 0,health_revision=state.health_revision,
        units_per_block=cfg.units_per_block})
    local alive=mc and mc.in_world and not mc.dead
    local after_submit=bridge.status()
    if not native.enabled or not native.renderer_ready or not can_control or not alive or not native.connected
        or mc.teleport_ack~=state.teleport_seq or not after_submit.ready then
        fail_open(menu and "Native menu owns control" or scripted and "Scripted scene owns control" or
            dying and "Native death owns control" or not alive and "Waiting for Minecraft world" or state.status)
        return
    end
    if not state.active then
        capture_player_visuals()
    end
    state.active=true;state.status="Minecraft controls player; native HP authoritative"
    set_boxes_enabled(true)
    seal_player_inputs()
    local np=repos(mc.x,mc.y,mc.z)
    local delta=math.sqrt((np.x-p.x)^2+(np.y-p.y)^2+(np.z-p.z)^2)
    if delta>cfg.max_pose_jump*cfg.units_per_block and mc.teleport_ack~=state.teleport_seq then
        fail_open("Rejected stale/unacknowledged MC teleport");return
    end
    state.transform:set_position(Vector4f.new(np.x,np.y,np.z,1),false)
    state.transform:set_rotation(Quaternion.new(Vector3f.new(0,math.rad(180+mc.yaw),0)))
    if state.physics then call(state.physics,"doWarp") end
    state.hidden=true
    for _,item in ipairs(state.draw_targets) do strictcall(item.obj,"set_DrawSelf",false) end
    local cyaw,cpitch=mc.yaw,mc.pitch
    if mc.camera_mode==2 then cyaw=cyaw+180;cpitch=-cpitch end
    local ex,ey,ez=mc.eye_x,mc.eye_y,mc.eye_z
    if mc.camera_mode~=0 then
        local yaw,pitch=math.rad(mc.yaw),math.rad(mc.pitch)
        local distance=math.max(0,math.min(32,mc.camera_distance or 0))
        local sign=mc.camera_mode==2 and 1 or -1
        ex=ex-math.sin(yaw)*math.cos(pitch)*distance*sign
        ey=ey-math.sin(pitch)*distance*sign
        ez=ez+math.cos(yaw)*math.cos(pitch)*distance*sign
    end
    local ep=repos(ex,ey,ez)
    state.camera_transform:set_position(Vector4f.new(ep.x,ep.y,ep.z,1),false)
    local yaw_offset=state.camera_forward_sign==1 and 180 or cfg.camera_yaw_offset
    local pitch_sign=state.camera_axis_calibrated and state.camera_forward_sign or cfg.camera_pitch_sign
    state.camera_transform:set_rotation(Quaternion.new(Vector3f.new(math.rad(cpitch*pitch_sign),
        math.rad(cyaw*cfg.camera_yaw_sign+yaw_offset),0)))
    local target_fov=cfg.camera_fov_radians and math.rad(mc.fov) or mc.fov
    if not positive_fov(target_fov) then error("MC FOV must be a finite positive number",0) end
    strictcall(state.camera,"set_FOV",target_fov)
    if state.frame%6==0 then publish_actors(s,bridge) end
    -- MC block collision is authoritative for the MC player. Native enemy colliders require
    -- verified RequestSetCollider registration; pending updates remain visible diagnostics.
    -- Leave native's update queue intact until a verified collider sink is available.
    apply_solids(bridge)
end
re.on_pre_application_entry("UpdateBehavior",function()
    if state.active and state.input then
        local ok,err=pcall(seal_player_inputs)
        if not ok then fail_open("Input seal error: "..tostring(err)) end
    end
end)
re.on_application_entry("LateUpdateBehavior",function()
    state.frame=state.frame+1
    local ok,err=pcall(tick)
    if not ok then
        fail_open("Adapter error: "..tostring(err))
        if state.last_error~=tostring(err) then log.error("[OnimushaMC] "..tostring(err));state.last_error=tostring(err) end
        if not cfg.diagnostic_only and _G.onimusha_mc then _G.onimusha_mc.submit_host({ready=false}) end
    end
    if state.frame%300==0 then
        json.dump_file("onimusha_mc_status.json",{status=state.status,active=state.active,bindings=state.bindings,
            runtime_stage=cfg.runtime_stage,diagnostic_only=cfg.diagnostic_only,
            control_hooks_enabled=cfg.install_control_hooks,terrain_queries_enabled=cfg.enable_terrain_queries,
            native_block_colliders_enabled=cfg.enable_native_block_colliders,
            health_hook_tests_enabled=cfg.enable_health_hook_tests,
            world=state.world_key or state.observed_world_key,epoch=state.epoch,collision_count=state.collision_count,
            collision_unsupported=state.collision_unsupported,actor_count=state.actor_count,
            enemy_diagnostic=state.enemy_diagnostic,
            pending_native_block_colliders=state.pending_native_block_colliders,query=state.query_diagnostic,
            block_colliders=state.collider_diagnostic,native_block_count=state.native_block_count,
            collider_ray=state.collider_ray_diagnostic,
            camera_axis=state.camera_axis_diagnostic,
            host_camera=state.host_camera_diagnostic,
            input_seals=state.input_seal_diagnostic,
            visual_restore=state.visual_restore_diagnostic,
            hooks=state.hooks,health_hook_test=state.health_hook_test,
            health_current=state.live_snapshot and state.live_snapshot.health_current,
            health_max=state.live_snapshot and state.live_snapshot.health_max,
            camera_fov=state.live_snapshot and state.live_snapshot.camera_fov,
            live_snapshot_frame=state.live_snapshot and state.live_snapshot.frame,
            native=_G.onimusha_mc and _G.onimusha_mc.status()})
    end
end)
re.on_draw_ui(function()
    if imgui.tree_node("Onimusha MC / 鬼武者 MC") then
        local native=_G.onimusha_mc and _G.onimusha_mc.status()
        local changed,value=false,false
        if cfg.runtime_stage~="C" or cfg.diagnostic_only then imgui.text("Stage "..cfg.runtime_stage..": takeover unavailable")
        else changed,value=imgui.checkbox("Enable bridge (F10)",native and native.enabled or false) end
        if changed then
            cfg.enabled=value;json.dump_file(CFG_FILE,cfg)
            if _G.onimusha_mc then _G.onimusha_mc.set_enabled(value) end
            if not value then fail_open("Disabled") end
        end
        imgui.text(state.status)
        imgui.text("Native collision triangles: "..tostring(state.collision_count))
        imgui.text("Enemies exported: "..tostring(state.actor_count or 0))
        imgui.text("Native block colliders: "..tostring(state.native_block_count or 0))
        imgui.text(state.bindings.block_colliders and "Native registration raycast verified" or
            "Native registration pending / check status report")
        imgui.tree_pop()
    end
end)
re.on_script_reset(function()
    if not cfg.diagnostic_only or state.hidden or state.collider_probe or next(state.blocks) then
        fail_open("Script reset");clear_boxes()
    end
    if not cfg.diagnostic_only and _G.onimusha_mc then _G.onimusha_mc.set_enabled(false) end
end)
log.info("[OnimushaMC] adapter loaded; TDB "..tostring(sdk.get_tdb_version()).."; stage "..cfg.runtime_stage)
