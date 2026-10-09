-- SkyCraft Onimusha runtime adapter, MIT. MOD制作：LCPD15/LCPD拉灯
-- OnimushaWotS.exe only; method existence is checked against its live TDB.
local CFG_FILE = "onimusha_mc_config.json"
local defaults = {
    runtime_stage="A", config_reload_frames=120,
    enabled=false, units_per_block=1.0, tile_stride=8192, collision_radius=16,
    collision_triangles_per_frame=1600, collision_max_triangles=95000,
    enemy_host_damage_per_mc_point=100.0, require_native_enemy_damage=true, max_pose_jump=8.0,
    camera_yaw_sign=-1.0, camera_yaw_offset=180.0, camera_pitch_sign=-1.0,
    camera_fov_radians=false, mirror_native_damage_to_mc=true,
    block_collider_resource="mod/onimusha_mc/unit_box.rcol",
    diagnostic_only=true, install_control_hooks=false,
    enable_native_block_colliders=false,
    enable_prefab_block_colliders=false,
    enable_native_section_rendering=false,
    enable_block_collider_tests=false, enable_health_hook_tests=false,
    enable_terrain_queries=false,
}
local function normalize_damage_multiplier(value)
    if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then return 100 end
    return math.floor(math.max(100,math.min(5000,value))+0.5)
end
local function read_config()
    local ok,raw=pcall(json.load_file,CFG_FILE)
    if not ok or type(raw)~="table" then raw={} end
    local result={}
    for k,v in pairs(defaults) do
        if type(raw[k])==type(v) then result[k]=raw[k]
        else result[k]=v end
    end
    result.enemy_host_damage_per_mc_point=normalize_damage_multiplier(result.enemy_host_damage_per_mc_point)
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
    result.enable_prefab_block_colliders=result.runtime_stage=="C" and not result.diagnostic_only and result.enable_prefab_block_colliders
    result.enable_native_section_rendering=result.runtime_stage=="C" and not result.diagnostic_only and result.enable_native_section_rendering
    result.enable_block_collider_tests=result.enable_native_block_colliders and result.enable_block_collider_tests
    -- This Onimusha build uses a verified local -Z camera and an identity XYZ world basis.
    -- Old sign=+1 settings described the former reflected basis; never reuse that override.
    result.camera_yaw_sign=-1.0;result.camera_yaw_offset=180.0;result.camera_pitch_sign=-1.0
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
    -- Written only after the offline world merger has preserved both old area tiles.
    world_aliases=json.load_file("onimusha_mc_world_aliases.json") or {},
    world_key=nil, tile={x=0,z=0}, status="Waiting for native bridge", bindings={},
    collision=nil, collision_count=0, collision_ready=false, last_error=nil,
    blocks={}, solid_backlog={}, collider_probe=nil,
    hooks={},
}
local function save_damage_multiplier(value)
    value=normalize_damage_multiplier(value)
    local ok,err=pcall(function()
        -- Preserve settings edited outside this panel, including unknown keys.
        -- Do not save cfg.enabled: F10 owns its live state independently.
        local saved=json.load_file(CFG_FILE)
        assert(type(saved)=="table","Cannot read configuration; original settings preserved")
        saved.enemy_host_damage_per_mc_point=value
        assert(json.dump_file(CFG_FILE,saved)~=false,"Cannot write damage multiplier")
        local check=json.load_file(CFG_FILE)
        assert(type(check)=="table" and check.enemy_host_damage_per_mc_point==value,"Cannot verify saved damage multiplier")
    end)
    if not ok then state.damage_setting_error=tostring(err);return false end
    cfg.enemy_host_damage_per_mc_point=value;state.damage_setting_error=nil
    return true
end
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
        -- MC forward = (-sin(yaw), -sin(pitch), cos(yaw)); RE and MC share XYZ axes.
        yaw=math.deg(math.atan(-fx,fz))
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
local function finite_camera_number(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function native_camera_rotation_from_mc(yaw,pitch,forward_axis,axis_verified)
    -- Only this Onimusha build's observed local -Z optical axis is supported.
    -- A forward-axis observation alone must not claim another camera basis is calibrated.
    if not axis_verified or forward_axis~=-1 then return nil,"Unverified camera basis; only local -Z is supported" end
    if not finite_camera_number(yaw) or not finite_camera_number(pitch) or math.abs(pitch)>90 then
        return nil,"Invalid Minecraft camera angles"
    end
    return {yaw=180-yaw,pitch=-pitch}
end
local function native_player_yaw_from_mc(yaw)
    if not finite_camera_number(yaw) then return nil,"Invalid Minecraft player yaw" end
    return -yaw -- The hidden native player's local +Z is its forward direction.
end
local function mc_camera_eye(mc)
    if not mc then return nil,"Missing Minecraft camera" end
    for _,name in ipairs({"eye_x","eye_y","eye_z","yaw","pitch"}) do
        if not finite_camera_number(mc[name]) then return nil,"Invalid Minecraft camera "..name end
    end
    if math.abs(mc.pitch)>90 then return nil,"Invalid Minecraft camera pitch" end
    local mode=mc.camera_mode
    if mode~=0 and mode~=1 and mode~=2 then return nil,"Invalid Minecraft camera mode" end
    local distance=mc.camera_distance or 0
    if not finite_camera_number(distance) then return nil,"Invalid Minecraft camera distance" end
    distance=math.max(0,math.min(32,distance))
    local eye={x=mc.eye_x,y=mc.eye_y,z=mc.eye_z,yaw=mc.yaw,pitch=mc.pitch}
    if mode~=0 then
        local yaw,pitch=math.rad(mc.yaw),math.rad(mc.pitch)
        local sign=mode==2 and 1 or -1
        eye.x=eye.x-math.sin(yaw)*math.cos(pitch)*distance*sign
        eye.y=eye.y-math.sin(pitch)*distance*sign
        eye.z=eye.z+math.cos(yaw)*math.cos(pitch)*distance*sign
        if mode==2 then eye.yaw=eye.yaw+180;eye.pitch=-eye.pitch end
    end
    return eye
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
        z=p.z/cfg.units_per_block+state.tile.z }
end
local function repos(x,y,z)
    return Vector3f.new((x-state.tile.x)*cfg.units_per_block,y*cfg.units_per_block,(z-state.tile.z)*cfg.units_per_block)
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
    if _G.onimusha_native_blocks then _G.onimusha_native_blocks.stop() end
    if _G.onimusha_native_sections then _G.onimusha_native_sections.stop() end
    for _,box in pairs(state.blocks) do destroy_box(box) end
    state.blocks={};state.solid_backlog={}
    if state.collider_probe then destroy_box(state.collider_probe);state.collider_probe=nil end
end
local function set_boxes_enabled(enabled)
    if not enabled and _G.onimusha_native_blocks then _G.onimusha_native_blocks.stop() end
    if not enabled and _G.onimusha_native_sections then _G.onimusha_native_sections.stop() end
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
local function owned_camera_value(value,kind)
    if kind=="fov" then
        if not positive_fov(value) then error("Invalid owned camera FOV",0) end
        return value
    end
    local result={}
    for _,axis in ipairs(kind=="rotation" and {"x","y","z","w"} or {"x","y","z"}) do
        if not value or not finite_camera_number(value[axis]) then error("Invalid owned camera "..kind.."."..axis,0) end
        result[axis]=value[axis]
    end
    if kind=="rotation" and result.x^2+result.y^2+result.z^2+result.w^2<0.000001 then
        error("Zero-length owned camera quaternion",0)
    end
    return result
end
local function owned_camera_equal(a,b,kind)
    if kind=="fov" then return math.abs(a-b)<=math.max(0.0001,math.abs(b)*0.00001) end
    local difference,opposite,scale=0,0,1
    for _,axis in ipairs(kind=="rotation" and {"x","y","z","w"} or {"x","y","z"}) do
        difference=math.max(difference,math.abs(a[axis]-b[axis]))
        opposite=math.max(opposite,math.abs(a[axis]+b[axis]));scale=math.max(scale,math.abs(b[axis]))
    end
    if kind=="rotation" then difference=math.min(difference,opposite) end
    return difference<=0.0001+scale*0.000001
end
local function owned_camera_read(record)
    if record.go and strictcall(record.go,"get_Valid")~=true then error("Owned virtual camera GameObject is invalid",0) end
    local value
    if record.field then value=record.obj:get_field(record.field)
    elseif record.kind=="position" then value=record.obj:get_position()
    elseif record.kind=="rotation" then value=record.obj:get_rotation()
    else value=strictcall(record.obj,"get_FOV") end
    return owned_camera_value(value,record.kind)
end
local function owned_camera_write(record,value)
    if record.go and strictcall(record.go,"get_Valid")~=true then error("Owned virtual camera GameObject is invalid",0) end
    if record.field then
        record.obj:set_field(record.field,record.kind=="fov" and value or Vector3f.new(value.x,value.y,value.z))
    elseif record.kind=="position" then
        record.obj:set_position(Vector4f.new(value.x,value.y,value.z,1),false)
    elseif record.kind=="rotation" then
        -- Fixed SDK constructor is glm::quat(w,x,y,z); originals are numeric deep copies.
        record.obj:set_rotation(Quaternion.new(value.w,value.x,value.y,value.z))
    else strictcall(record.obj,"set_FOV",value) end
end
local function restore_owned_active_camera()
    local ledger=state.active_camera_restore
    if not ledger then return end
    local remaining,errors,restored={},{},0
    for _,record in ipairs(ledger.records) do
        if record.attempted then
            local ok,err=pcall(function()
                if not owned_camera_equal(owned_camera_read(record),record.original,record.kind) then
                    owned_camera_write(record,record.original)
                    if not owned_camera_equal(owned_camera_read(record),record.original,record.kind) then
                        error("Owned camera restore failed readback: "..record.name,0)
                    end
                end
            end)
            if ok then restored=restored+1
            else remaining[#remaining+1]=record;if #errors<6 then errors[#errors+1]=record.name..": "..tostring(err):sub(1,256) end end
        end
    end
    ledger.records=remaining;ledger.restore_pending=#remaining>0
    if #remaining==0 then state.active_camera_restore=nil end
    local diagnostic=state.camera_sync_diagnostic or {}
    state.camera_sync_diagnostic=diagnostic
    diagnostic.restored_records=restored;diagnostic.pending_records=#remaining;diagnostic.restore_errors=errors
    diagnostic.applied=false
end
local function primary_rollback_owner(ledger)
    if strictcall(ledger.go,"get_Valid")~=true
        or not same(strictcall(ledger.primary,"get_GameObject"),ledger.go)
        or not same(strictcall(ledger.go,"get_Transform"),ledger.transform) then
        error("Primary camera rollback owner became invalid or changed",0)
    end
end
local function capture_primary_camera_rollback(pose,owner)
    if state.primary_camera_rollback then error("Primary camera rollback remains pending",0) end
    if not state.active or cfg.runtime_stage~="C" or cfg.diagnostic_only or not cfg.install_control_hooks
        or not pose or owner~=state.active_camera_restore or pose.owner~=owner
        or not same(pose.primary,state.camera) or not same(pose.transform,state.camera_transform) then
        error("Unowned primary camera rollback capture refused",0)
    end
    local ledger={primary=pose.primary,transform=pose.transform,
        go=strictcall(pose.primary,"get_GameObject"),frame=state.frame,epoch=state.epoch,records={}}
    primary_rollback_owner(ledger)
    ledger.records={{name="primary_position",obj=ledger.transform,kind="position",go=ledger.go},
        {name="primary_rotation",obj=ledger.transform,kind="rotation",go=ledger.go},
        {name="primary_fov",obj=ledger.primary,kind="fov",go=ledger.go}}
    for _,record in ipairs(ledger.records) do record.original=owned_camera_read(record) end
    -- A post-native snapshot belongs only to this attempt. Never retain successful
    -- frame poses as a long-term release position, and never capture after a write.
    ledger.primary:add_ref();ledger.transform:add_ref();ledger.go:add_ref()
    state.primary_camera_rollback=ledger
    local diagnostic=state.primary_camera_rollback_diagnostic or {captures=0}
    state.primary_camera_rollback_diagnostic=diagnostic
    diagnostic.captures=diagnostic.captures+1;diagnostic.frame=state.frame
    diagnostic.pending_records=0;diagnostic.committed=false;diagnostic.errors={}
    return ledger
end
local function restore_primary_camera_rollback()
    local ledger=state.primary_camera_rollback
    if not ledger then return end
    local remaining,errors,restored={},{},0
    for _,record in ipairs(ledger.records) do
        if record.attempted then
            local ok,err=pcall(function()
                primary_rollback_owner(ledger)
                if not owned_camera_equal(owned_camera_read(record),record.original,record.kind) then
                    owned_camera_write(record,record.original)
                    if not owned_camera_equal(owned_camera_read(record),record.original,record.kind) then
                        error("Primary camera rollback failed readback: "..record.name,0)
                    end
                end
            end)
            if ok then restored=restored+1
            else remaining[#remaining+1]=record;errors[#errors+1]=record.name..": "..tostring(err):sub(1,256) end
        end
    end
    ledger.records=remaining;ledger.restore_pending=#remaining>0
    if #remaining==0 then
        -- This snapshot restores the same primary's post-native FOV. The older
        -- initial FOV must not overwrite it, including after a partial retry.
        if state.fov_restore and same(state.fov_restore.obj,ledger.primary) then
            state.fov_restore=nil;state.original_fov=nil
            if state.visual_restore_diagnostic then state.visual_restore_diagnostic.pending_fov=false end
        end
        state.primary_camera_rollback=nil
    end
    local diagnostic=state.primary_camera_rollback_diagnostic or {}
    state.primary_camera_rollback_diagnostic=diagnostic
    diagnostic.restored_records=restored;diagnostic.pending_records=#remaining;diagnostic.errors=errors
    diagnostic.committed=false
end
local function prepare_owned_active_camera()
    if cfg.runtime_stage~="C" or cfg.diagnostic_only or not cfg.install_control_hooks then return nil end
    local manager=sdk.get_managed_singleton("app.CameraManager")
    local operator=strictcall(manager,"get_InGameCamera")
    local virtual=strictcall(operator,"getActiveVirtualCamera")
    local target=strictcall(virtual,"get_Target")
    local target_name
    if not state.camera_sync_target_enum then
        local definition=td("ace.CameraDef.TARGET")
        if not definition then error("Active camera TARGET metadata unresolved",0) end
        local values={}
        for _,field in ipairs(definition:get_fields() or {}) do
            if field:is_static() and field:is_literal() and field:get_name()~="MAX" then
                local value=field:get_data(nil)
                if finite_camera_number(value) and value==math.floor(value) then
                    values[#values+1]={name=field:get_name(),value=value}
                    if #values>=16 then break end
                end
            end
        end
        if #values==0 then error("Active camera TARGET literals unreadable",0) end
        state.camera_sync_target_enum=values
    end
    for _,entry in ipairs(state.camera_sync_target_enum) do if entry.value==target then target_name=entry.name;break end end
    if not target_name then error("Active camera TARGET is not a verified literal",0) end
    local component=strictcall(manager,"getCameraComponent",target)
    local controller=strictcall(manager,"getActiveCamera",target)
    local current=strictcall(controller,"getCurrentParam")
    if not same(component,state.camera) or same(virtual,state.camera)
        or not same(strictcall(controller,"get_Camera"),virtual)
        or not same(strictcall(operator,"getActiveCameraParam"),current) then
        error("Active camera/component/controller identity mismatch",0)
    end
    if typename(current)~="ace.cCameraParam" or same(current,state.camera) or same(current,virtual)
        or same(current,state.camera_transform) then error("Unexpected active camera parameter owner",0) end
    local go=strictcall(virtual,"get_GameObject")
    if strictcall(go,"get_Valid")~=true then error("Active virtual camera GameObject is invalid",0) end
    local transform=strictcall(go,"get_Transform")
    if not transform or same(transform,state.camera_transform) then error("Active virtual camera transform aliases primary",0) end
    local diagnostic=state.camera_sync_diagnostic or {}
    state.camera_sync_diagnostic=diagnostic
    diagnostic.target=target;diagnostic.target_name=target_name
    diagnostic.controller_address=tostring(addr(controller));diagnostic.virtual_address=tostring(addr(virtual))
    diagnostic.param_address=tostring(addr(current));diagnostic.component_address=tostring(addr(component))
    local ledger=state.active_camera_restore
    if ledger then
        if ledger.restore_pending then error("Owned active camera restoration remains pending",0) end
        if ledger.target~=target or not same(ledger.virtual,virtual) or not same(ledger.controller,controller)
            or not same(ledger.param,current) or not same(ledger.transform,transform) or not same(ledger.primary,state.camera)
            or not same(ledger.go,go) then
            diagnostic.owner_changed=true
            error("Active camera owner changed; restoring previous exact owners before recapture",0)
        end
        ledger.manager=manager;ledger.operator=operator
        return ledger
    end
    ledger={target=target,virtual=virtual,controller=controller,param=current,transform=transform,go=go,
        manager=manager,operator=operator,
        primary=state.camera,records={}}
    local specs={{name="virtual_position",obj=transform,kind="position"},
        {name="virtual_rotation",obj=transform,kind="rotation"},{name="virtual_fov",obj=virtual,kind="fov"},
        {name="param_eye",obj=current,kind="position",field="EyePos"},
        {name="param_look_at",obj=current,kind="position",field="LookAtPos"},
        {name="param_fov",obj=current,kind="fov",field="FOV"}}
    local seen={}
    for _,record in ipairs(specs) do
        record.go=go
        if record.field then
            local field=current:get_type_definition():get_field(record.field)
            local expected=record.kind=="fov" and "System.Single" or "via.vec3"
            if not field or field:get_type():get_full_name()~=expected or type(current.set_field)~="function" then
                error("Missing typed managed camera field/setter "..record.field,0)
            end
        end
        record.original=owned_camera_read(record)
        local identity=addr(record.obj)
        if not seen[identity] then record.obj:add_ref();seen[identity]=true end
        ledger.records[#ledger.records+1]=record
    end
    state.active_camera_restore=ledger;diagnostic.captured=true;diagnostic.pending_records=0;diagnostic.owner_changed=false
    return ledger
end
local function sync_owned_active_camera(ledger)
    if not state.active or cfg.runtime_stage~="C" or cfg.diagnostic_only or not ledger then return false end
    if ledger~=state.active_camera_restore or ledger.restore_pending then error("Unowned active camera write refused",0) end
    local position=owned_camera_value(state.camera_transform:get_position(),"position")
    local rotation=owned_camera_value(state.camera_transform:get_rotation(),"rotation")
    local look=owned_camera_value(strictcall(state.camera,"get_LookAtPosition"),"position")
    local fov=owned_camera_value(strictcall(state.camera,"get_FOV"),"fov")
    local desired={virtual_position=position,virtual_rotation=rotation,virtual_fov=fov,
        param_eye=position,param_look_at=look,param_fov=fov}
    local diagnostic=state.camera_sync_diagnostic
    diagnostic.applied=false;diagnostic.checked_records=0
    for _,record in ipairs(ledger.records) do
        record.attempted=true
        owned_camera_write(record,desired[record.name])
        if not owned_camera_equal(owned_camera_read(record),desired[record.name],record.kind) then
            error("Active camera synchronization failed readback: "..record.name,0)
        end
        diagnostic.checked_records=diagnostic.checked_records+1
    end
    diagnostic.applied=true;diagnostic.frame=state.frame
    -- Matrix-cache differences are observed separately, never an immediate failure gate.
    return true
end
local function apply_mc_camera_pose(pose,ledger,rollback)
    if not state.active or cfg.runtime_stage~="C" or cfg.diagnostic_only or not cfg.install_control_hooks then return false end
    if not pose or ledger~=state.active_camera_restore or pose.owner~=ledger or ledger.restore_pending
        or not same(pose.primary,state.camera) or not same(pose.transform,state.camera_transform) then
        error("Unowned cached primary camera write refused",0)
    end
    local values={position=owned_camera_value(pose.position,"position"),
        rotation=owned_camera_value(pose.rotation,"rotation"),fov=owned_camera_value(pose.fov,"fov")}
    local records={{obj=state.camera_transform,kind="position"},{obj=state.camera_transform,kind="rotation"},
        {obj=state.camera,kind="fov"}}
    if rollback then
        if rollback~=state.primary_camera_rollback or not same(rollback.primary,pose.primary)
            or not same(rollback.transform,pose.transform) or #rollback.records~=3 then
            error("Unowned primary camera rollback transaction refused",0)
        end
        records=rollback.records
    end
    for _,record in ipairs(records) do
        local value=values[record.kind]
        if rollback then record.attempted=true end
        owned_camera_write(record,value)
        if not owned_camera_equal(owned_camera_read(record),value,record.kind) then
            error("Primary camera synchronization failed readback: "..record.kind,0)
        end
    end
    if not sync_owned_active_camera(ledger) then error("Owned active camera synchronization unavailable",0) end
    return true
end
local function cache_mc_camera_pose(position,rotation,fov,ledger,mc)
    local pose={position=owned_camera_value(position,"position"),rotation=owned_camera_value(rotation,"rotation"),
        fov=owned_camera_value(fov,"fov"),owner=ledger,primary=state.camera,transform=state.camera_transform,
        manager=ledger.manager,frame=state.frame,epoch=state.epoch,teleport_seq=state.teleport_seq,
        teleport_ack=mc.teleport_ack}
    if not apply_mc_camera_pose(pose,ledger) then error("Certified MC camera pose could not be applied",0) end
    -- Commit only after all nine writes and their existing/direct readbacks succeed.
    state.cached_camera_pose=pose
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
    if state.fov_restore and not (state.primary_camera_rollback
        and same(state.fov_restore.obj,state.primary_camera_rollback.primary)) then
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
local function restore_camera_dither()
    local record=state.dither_restore
    if not record then return end
    local ok,err=pcall(function()
        if record.obj:get_field('_IsDestroy')==true then return end
        strictcall(record.obj,'setEnable(System.Boolean, System.Single, via.curve.EaseType)',record.original,0.0,0)
        assert(record.obj:get_field('_Enable')==record.original,'Camera dither restore readback failed')
    end)
    local diagnostic=state.hooks and state.hooks.camera_dither
    if ok then state.dither_restore=nil
    elseif diagnostic then diagnostic.restore_error=tostring(err) end
    if diagnostic then diagnostic.pending_restore=state.dither_restore~=nil end
end
local function restoration_pending()
    return (state.input_seals and state.input_seals.restore_pending) or state.hidden or state.fov_restore~=nil
        or state.active_camera_restore~=nil or state.primary_camera_rollback~=nil or state.dither_restore~=nil
end
local function fail_open(reason)
    state.cached_camera_pose=nil
    if state.active then
        local diagnostic=state.control_diagnostic or {deactivations=0,transitions={},per_reason_counts={}}
        diagnostic.deactivations=diagnostic.deactivations+1
        diagnostic.per_reason_counts[reason]=(diagnostic.per_reason_counts[reason] or 0)+1
        diagnostic.last_deactivation={reason=reason,frame=state.frame,epoch=state.epoch,gate=state.gate_snapshot,
            refresh={exporting=state.collision~=nil,pending=state.collision_pending~=nil,
                active_seq=state.collision_coverage and state.collision_coverage.publish_seq,
                pending_seq=state.collision_pending and state.collision_pending.publish_seq}}
        diagnostic.transitions[#diagnostic.transitions+1]=diagnostic.last_deactivation
        if #diagnostic.transitions>16 then table.remove(diagnostic.transitions,1) end
        state.control_diagnostic=diagnostic
    end
    state.not_ready_reason=reason
    state.active=false; state.status=reason
    restore_player_input_seals()
    set_boxes_enabled(false)
    restore_player_visuals()
    restore_camera_dither()
    if state.active_camera_restore then restore_owned_active_camera() end
    if state.primary_camera_rollback then restore_primary_camera_rollback() end
end
local function invalidate_collision_coverage(reason)
    state.collision=nil;state.collision_pending=nil;state.collision_coverage=nil
    state.collision_ready=false;state.collision_centre=nil;state.collision_count=0
    state.collision_retry_frame=0;state.collision_failures=0
    state.collision_invalidation=reason
end
local function reload_config()
    if state.frame%cfg.config_reload_frames~=1 then return end
    local next_cfg=read_config()
    local changed,requires_restore=false,false
    for k,v in pairs(next_cfg) do
        if cfg[k]~=v then
            changed=true
            if k~="enemy_host_damage_per_mc_point" then requires_restore=true end
        end
    end
    if not changed then return end
    -- Damage-only tuning must not release input/camera or invalidate terrain.
    if not requires_restore then cfg=next_cfg;state.damage_setting_error=nil;return end
    local previous=cfg
    fail_open("Configuration changed; native player control restored")
    cfg=next_cfg
    state.config_revision=(state.config_revision or 0)+1
    invalidate_collision_coverage("Configuration changed")
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
        state.live_snapshot=nil;invalidate_collision_coverage("Native player unavailable")
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
        state.health_remainder=0;invalidate_collision_coverage("Native player changed")
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
local function canonical_world_key(key)
    local target=type(state.world_aliases)=="table" and state.world_aliases[key]
    if target==nil then return key end
    -- Only verified continuous areas of the same stage may share coordinates.
    local stage=type(key)=="string" and key:match("^stage:(%d+):area:%d+$")
    local target_stage=type(target)=="string" and target:match("^stage:(%d+):area:%d+$")
    if not stage or stage~=target_stage or not state.tile_map[target]
        or (state.world_aliases[target] and state.world_aliases[target]~=target) then
        error("Invalid/unmigrated continuous-area alias: "..tostring(key),0)
    end
    return target
end
local function choose_world(key)
    if not key then fail_open("Stage identity unresolved; block persistence held safely");return false end
    state.observed_area_key=key
    key=canonical_world_key(key)
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
    invalidate_collision_coverage("Stage changed");state.actors={}
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
local function collision_counters()
    if not state.collision_stats then state.collision_stats={starts=0,queued=0,consumed=0,failures=0} end
    return state.collision_stats
end
local function collision_context(native)
    if not native or not native.connected or type(native.mc_pid)~="number" or native.mc_pid<=0
        or type(native.collision_generation)~="number" or native.collision_epoch~=state.epoch
        or native.collision_ring_valid~=true then return nil end
    return {epoch=state.epoch,world=state.world_key,units=cfg.units_per_block,
        tile_x=state.tile.x,tile_z=state.tile.z,radius=cfg.collision_radius,
        config_revision=state.config_revision or 0,mc_pid=native.mc_pid,generation=native.collision_generation}
end
local function collision_same_context(record,native)
    local current=collision_context(native)
    if not record or not current then return false end
    for key,value in pairs(current) do if record[key]~=value then return false end end
    return true
end
local function collision_failure(reason)
    local stats=collision_counters();stats.failures=stats.failures+1
    state.collision_failures=math.min(5,(state.collision_failures or 0)+1)
    state.collision_retry_frame=state.frame+math.min(240,15*2^(state.collision_failures-1))
    state.collision_failure={reason=reason,frame=state.frame,retry_frame=state.collision_retry_frame}
    state.collision=nil;state.collision_pending=nil
    -- A failed refresh never replaces or revokes a still-current, verified old region.
end
local function collision_resample_distance()
    return math.min(12,cfg.collision_radius*0.5)*cfg.units_per_block
end
local function collision_vertical_resample_distance()
    -- The startup/support probe extends 12 blocks below the feet. At radius 16,
    -- refresh after 2 blocks vertically, before exhausting its narrow lower margin.
    return math.min(math.min(12,cfg.collision_radius*0.5),math.max(0,(cfg.collision_radius-12)*0.5))*cfg.units_per_block
end
local function collision_refresh_due(p)
    local coverage=state.collision_coverage
    if not coverage then return true end
    local horizontal=collision_resample_distance();local vertical=collision_vertical_resample_distance()
    return math.abs(p.x-coverage.centre.x)>horizontal or math.abs(p.z-coverage.centre.z)>horizontal
        or math.abs(p.y-coverage.centre.y)>vertical
end
local function collision_contains_foot(bounds,p)
    if not p or not finite_camera_number(p.x) or not finite_camera_number(p.y) or not finite_camera_number(p.z) then return false end
    -- Conservative standing MC body plus one-block X/Z travel margin and the real
    -- 12-cell downward support probe. Use the actual query AABB, never pack padding.
    return p.x-1>=bounds.min_x and p.x+1<=bounds.max_x
        and p.z-1>=bounds.min_z and p.z+1<=bounds.max_z
        and math.floor(p.y)-12>=bounds.min_y and p.y+2<=bounds.max_y
end
local function collision_native_coverage_gate(native,native_foot)
    local coverage=state.collision_coverage
    if not collision_same_context(coverage,native) then return false,"No current consumed terrain coverage" end
    -- Current live body coverage was verified at one RE metre per MC block only.
    -- Other unit scales need measured native CC dimensions before takeover is safe.
    if cfg.units_per_block~=1 then return false,"Native body coverage is verified only at units_per_block=1" end
    if not native.collision_ready then return false,"Native terrain batch is not ready" end
    if not collision_contains_foot(coverage.bounds,native_foot) then return false,"Native foot/body/support outside verified query" end
    return true
end
local function collision_coverage_gate(native,native_foot,mc)
    local covered,reason=collision_native_coverage_gate(native,native_foot)
    if not covered then return false,reason end
    local coverage=state.collision_coverage
    if not collision_contains_foot(coverage.bounds,mc) then return false,"Minecraft foot/body/support outside verified query" end
    return true
end
local function reconcile_collision(native)
    if not collision_context(native) then
        if state.collision_coverage or state.collision or state.collision_pending then
            invalidate_collision_coverage("Minecraft disconnected or terrain ring invalid")
        end
        return
    end
    for _,record in ipairs({state.collision_coverage or false,state.collision or false,state.collision_pending or false}) do
        if record and not collision_same_context(record,native) then invalidate_collision_coverage("Terrain epoch/config/connection changed");return end
    end
    local pending=state.collision_pending
    if pending then
        if native.collision_publish_seq~=pending.publish_seq then
            invalidate_collision_coverage("Terrain batch superseded");collision_failure("Terrain batch superseded");return
        end
        if type(native.collision_consumed_seq)=="number" and native.collision_consumed_seq>=pending.publish_seq then
            state.collision_coverage=pending;state.collision_pending=nil;state.collision_ready=true
            state.collision_centre=pending.centre;state.collision_count=pending.count
            state.collision_failures=0;state.collision_retry_frame=0
            collision_counters().consumed=collision_counters().consumed+1
        elseif state.frame-pending.queued_frame>300 then collision_failure("Terrain consumption acknowledgment timed out") end
    end
    state.collision_ready=state.collision_coverage~=nil
end
local function start_collision(s,p,native)
    if state.collision or state.collision_pending or state.frame<(state.collision_retry_frame or 0) then return false end
    local job=collision_context(native)
    if not job then return false end
    job.shapes={};job.triangles={};job.centre={x=p.x,y=p.y,z=p.z}
    job.shape_index=1;job.triangle_index=0;job.unsupported=0;job.started_frame=state.frame
    local mapped=mcpos(p);local r=job.radius
    -- COL_REGION replaces an entire 8-block cell. Query every replaced cell,
    -- including edge cells, so unqueried padding cannot erase cached ground.
    job.bounds={min_x=math.floor((mapped.x-r)/8)*8,min_y=math.floor((mapped.y-r)/8)*8,min_z=math.floor((mapped.z-r)/8)*8,
        max_x=math.ceil((mapped.x+r)/8)*8,max_y=math.ceil((mapped.y+r)/8)*8,max_z=math.ceil((mapped.z+r)/8)*8}
    local b=job.bounds;local halo=0.002
    job.query_aabb={min_x=(b.min_x-job.tile_x-halo)*job.units,min_y=(b.min_y-halo)*job.units,min_z=(b.min_z-job.tile_z-halo)*job.units,
        max_x=(b.max_x-job.tile_x+halo)*job.units,max_y=(b.max_y+halo)*job.units,max_z=(b.max_z-job.tile_z+halo)*job.units}
    job.max_triangles=cfg.collision_max_triangles
    collision_counters().starts=collision_counters().starts+1
    local query_ok,query_error=pcall(function()
        local system=sdk.get_native_singleton("via.physics.System")
        local query=state.area_query
        if query and typename(query)~="via.physics.GetAreaPrimitiveQuery" then query=nil;state.area_query=nil end
        if not query then query=sdk.create_instance("via.physics.GetAreaPrimitiveQuery") end
        if not query then query=sdk.create_instance("via.physics.GetAreaPrimitiveQuery",true) end
        if not query or not system then error("Native area query allocation unavailable") end
        query=pin_managed(query,"via.physics.GetAreaPrimitiveQuery")
        local box=ValueType.new(td("via.AABB"));local q=job.query_aabb
        box:set_field("minpos",Vector3f.new(q.min_x,q.min_y,q.min_z))
        box:set_field("maxpos",Vector3f.new(q.max_x,q.max_y,q.max_z))
        strictcall(query,"set_Area",box)
        local filter=call(state.cc,"get_FilterInfo")
        if not filter then error("Player CharacterController collision filter unavailable") end
        strictcall(query,"set_FilterInfo",filter)
        local function query_scene()
            return pin_managed(sdk.call_native_func(system,td("via.physics.System"),"getAreaPrimitive",query),
                "via.physics.GetAreaPrimitiveResult")
        end
        local blocks=_G.onimusha_native_blocks
        local result=blocks and blocks.query_terrain and blocks.query_terrain(query_scene) or query_scene()
        local count=strictcall(result,"get_NumTriangles")
        local counts={boxes=strictcall(result,"get_NumBoxes"),spheres=strictcall(result,"get_NumSpheres"),capsules=strictcall(result,"get_NumCapsules")}
        state.query_diagnostic={allocated=true,triangles=count,boxes=counts.boxes,spheres=counts.spheres,capsules=counts.capsules,
            query_type=typename(query),result_type=typename(result),retained=true,bounds=job.query_aabb}
        if type(count)~="number" or count~=math.floor(count) or count<=0 then error("Native area query returned no complete triangle set") end
        if count>job.max_triangles then error("Native area query exceeds triangle budget; truncation rejected") end
        for name,n in pairs(counts) do
            if type(n)~="number" or n~=0 then error("Unsupported native area query primitive: "..name.."="..tostring(n)) end
        end
        state.area_query=query
        state.ground_collidable=call(result,"getTriangleCollidable(System.UInt32)",0)
        job.shapes[1]={shape=result,count=count,world_space=true,accessor="getTriangle(System.UInt32)"}
        job.complete_query=true
        state.bindings.collision="via.physics.System.getAreaPrimitive(player CharacterController filter)"
    end)
    if not query_ok then
        state.query_diagnostic=state.query_diagnostic or {};state.query_diagnostic.error=tostring(query_error)
        -- Scene traversal/fallback cannot prove an AABB contains every collider;
        -- do not certify its skipped, clamped or unsupported shapes as complete.
        collision_failure("Incomplete terrain query: "..tostring(query_error));return false
    end
    state.collision=job
    return true
end
local function accept_collision_publication(job,after,before)
    if not collision_same_context(job,after) or type(after.collision_publish_seq)~="number"
        or after.collision_publish_seq==before or after.collision_publish_seq<=0 then
        invalidate_collision_coverage("Terrain publication context/sequence invalid");collision_failure("Terrain publication context/sequence invalid");return
    end
    job.publish_seq=after.collision_publish_seq;job.queued_frame=state.frame
    job.shapes=nil;job.triangles=nil
    -- All replacement cells were completely queried. Old certified cells remain
    -- valid while the consumer drains the batch; no intersection shrink is needed.
    state.collision_pending=job;state.collision=nil
    collision_counters().queued=collision_counters().queued+1
    reconcile_collision(after)
end
local function advance_collision(bridge,native)
    local job=state.collision
    if not job then return end
    if not collision_same_context(job,native) then invalidate_collision_coverage("Terrain export context changed");return end
    if job.packing_ticket then
        local after=bridge.status()
        if after.collision_job_id~=job.packing_ticket then collision_failure("Terrain packing ticket superseded");return end
        if after.collision_job_state=="packing" then
            if state.frame-job.packing_frame>600 then collision_failure("Background terrain packing timed out") end
            return
        end
        if after.collision_job_state~="published" then
            collision_failure("Background terrain packing failed: "..tostring(after.collision_job_error));return
        end
        if after.collision_job_publish_seq~=after.collision_publish_seq then collision_failure("Background terrain publication superseded");return end
        accept_collision_publication(job,after,job.before_publish_seq);return
    end
    local budget=cfg.collision_triangles_per_frame
    while budget>0 and job.shape_index<=#job.shapes do
        local item=job.shapes[job.shape_index]
        if job.triangle_index>=item.count then job.shape_index=job.shape_index+1;job.triangle_index=0
        else
            if #job.triangles>=job.max_triangles then collision_failure("Terrain triangle budget reached before complete exhaustion");return end
            local vs=item.vertices or triangle_vertices(call(item.shape,item.accessor or "getTriangleArray(System.UInt32)",job.triangle_index))
            if not vs or #vs~=3 then collision_failure("Terrain triangle read failed; incomplete export rejected");return end
            local out={flags=0};local letters={"a","b","c"}
            for i,v in ipairs(vs) do
                if item.matrix then
                    local transformed=attempt(function() return item.matrix*Vector4f.new(v.x,v.y,v.z,1) end)
                    if not transformed then collision_failure("Terrain transform failed; incomplete export rejected");return end
                    v=transformed
                end
                if not finite_camera_number(v.x) or not finite_camera_number(v.y) or not finite_camera_number(v.z) then
                    collision_failure("Non-finite terrain vertex; incomplete export rejected");return
                end
                -- Job coordinates are immutable throughout the multi-frame export.
                out[letters[i].."x"]=v.x/job.units+job.tile_x
                out[letters[i].."y"]=v.y/job.units
                out[letters[i].."z"]=v.z/job.units+job.tile_z
            end
            job.triangles[#job.triangles+1]=out
            job.triangle_index=job.triangle_index+1;budget=budget-1
        end
    end
    -- A budget boundary after the final triangle is complete, not truncation.
    while job.shape_index<=#job.shapes and job.triangle_index>=job.shapes[job.shape_index].count do
        job.shape_index=job.shape_index+1;job.triangle_index=0
    end
    if job.shape_index<=#job.shapes then return end
    if not job.complete_query or job.unsupported~=0 or #job.triangles==0 then
        collision_failure("Incomplete or unsupported terrain export rejected");return
    end
    local bounds=job.bounds
    local region={epoch=job.epoch,min_x=math.floor(bounds.min_x),min_y=math.floor(bounds.min_y),min_z=math.floor(bounds.min_z),
        max_x=bounds.max_x-1,max_y=bounds.max_y-1,max_z=bounds.max_z-1,triangles=job.triangles,
        async=native.collision_async_supported==true}
    local before=native.collision_publish_seq
    local ok,accepted=pcall(bridge.publish_collision_tris,region)
    if region.async then
        if not ok or type(accepted)~="number" or accepted<=0 then collision_failure("Background terrain submission rejected");return end
        job.packing_ticket=accepted;job.packing_frame=state.frame;job.before_publish_seq=before
        job.count=#job.triangles;job.shapes=nil;job.triangles=nil;return
    end
    if not ok or accepted~=true then collision_failure("Complete terrain batch publication rejected");return end
    local after=bridge.status()
    job.count=#job.triangles;accept_collision_publication(job,after,before)
end
local function collision_diagnostic()
    local job=state.collision
    return {counters=state.collision_stats,coverage=state.collision_coverage,pending=state.collision_pending,
        exporting=job and {epoch=job.epoch,world=job.world,mc_pid=job.mc_pid,generation=job.generation,
            started_frame=job.started_frame,triangles=job.triangles and #job.triangles or job.count,shape_index=job.shape_index,
            packing_ticket=job.packing_ticket,packing_frame=job.packing_frame,
            triangle_index=job.triangle_index,bounds=job.bounds,query_aabb=job.query_aabb},
        last_failure=state.collision_failure,retry_frame=state.collision_retry_frame,
        invalidation=state.collision_invalidation}
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
-- Passive camera/UI evidence only. No reflection write, game update call or hook
-- belongs here. Flatten the SDK's real Matrix4x4f columns [0,4), not guessed fields.
local function projection_vector(value)
    if not value then error("Missing vector",0) end
    local result={}
    for _,axis in ipairs({"x","y","z"}) do
        if not finite_camera_number(value[axis]) then error("Non-finite vector "..axis,0) end
        result[axis]=value[axis]
    end
    return result
end
local function projection_matrix(value)
    if not value then error("Missing Matrix4x4f",0) end
    local result={}
    for column=0,3 do
        local v=value[column]
        if not v then error("Missing Matrix4x4f column "..column,0) end
        for _,axis in ipairs({"x","y","z","w"}) do
            if not finite_camera_number(v[axis]) then error("Non-finite Matrix4x4f element",0) end
            result[#result+1]=v[axis]
        end
    end
    return result
end
local function projection_difference(a,b)
    if not a or not b or #a~=16 or #b~=16 then return nil end
    local difference=0
    for i=1,16 do difference=math.max(difference,math.abs(a[i]-b[i])) end
    return difference
end
local function sample_camera_projection(phase,frame)
    -- Stage A must not even resolve these extra objects or access these getters.
    if cfg.runtime_stage~="C" or cfg.diagnostic_only or not cfg.install_control_hooks or frame%30~=0 then return end
    local diagnostic=state.camera_projection_diagnostic
    if not diagnostic then diagnostic={samples={}};state.camera_projection_diagnostic=diagnostic end
    local group=diagnostic.samples[#diagnostic.samples]
    if not group or group.frame~=frame or group.epoch~=state.epoch then
        group={frame=frame,epoch=state.epoch,phases={}}
        diagnostic.samples[#diagnostic.samples+1]=group
        if #diagnostic.samples>16 then table.remove(diagnostic.samples,1) end
    end
    state.camera_observation_seq=(state.camera_observation_seq or 0)+1
    local sample={active=state.active,errors={},seq=state.camera_observation_seq}
    group.phases[phase]=sample
    local function observe(label,fn)
        local ok,value=pcall(fn)
        if ok and value~=nil then return value end
        if #sample.errors<12 then sample.errors[#sample.errors+1]={field=label,
            error=ok and "Unavailable getter/object" or tostring(value):sub(1,256)} end
    end
    local function getter(obj,name,...)
        if not obj or not method(obj,name) then error("Unresolved getter "..name,0) end
        return obj:call(name,...)
    end
    local function matrix(obj,name,...)
        local args={...}
        return observe(name,function() return projection_matrix(getter(obj,name,table.unpack(args))) end)
    end
    local function vector(label,fn)
        return observe(label,function() return projection_vector(fn()) end)
    end
    local primary=state.camera
    sample.primary_address=primary and tostring(addr(primary)) or nil
    sample.primary_position=vector("primary_position",function() return state.camera_transform:get_position() end)
    sample.primary_look_at=vector("primary_look_at",function() return getter(primary,"get_LookAtPosition") end)
    sample.primary_view=matrix(primary,"get_ViewMatrix")
    sample.primary_view_projection=matrix(primary,"get_ViewProjMatrix")
    local manager=observe("camera_manager",function() return sdk.get_managed_singleton("app.CameraManager") end)
    local operator=observe("in_game_camera",function() return getter(manager,"get_InGameCamera") end)
    local virtual=observe("active_virtual",function() return getter(operator,"getActiveVirtualCamera") end)
    sample.virtual_address=virtual and tostring(addr(virtual)) or nil
    sample.virtual_eye=vector("virtual_eye",function() return getter(virtual,"get_EyePos") end)
    sample.virtual_forward=vector("virtual_forward",function() return getter(virtual,"get_Forward") end)
    local param=observe("active_param",function() return getter(operator,"getActiveCameraParam") end)
    sample.param_eye=vector("param_eye",function() return param:get_field("EyePos") end)
    sample.param_look_at=vector("param_look_at",function() return param:get_field("LookAtPos") end)
    sample.param_fov=observe("param_fov",function()
        local value=param:get_field("FOV");if not finite_camera_number(value) then error("Non-finite FOV",0) end
        return value
    end)
    if diagnostic.target_enum==nil then
        diagnostic.target_enum=observe("target_enum",function()
            local definition=td("ace.CameraDef.TARGET")
            if not definition then error("Missing ace.CameraDef.TARGET",0) end
            local values={}
            for _,field in ipairs(definition:get_fields() or {}) do
                if field:is_static() and field:is_literal() then
                    local value=field:get_data(nil)
                    if finite_camera_number(value) and value==math.floor(value) then
                        values[#values+1]={name=field:get_name(),value=value}
                        if #values>=16 then break end
                    end
                end
            end
            if #values==0 then error("No readable TARGET enum literals",0) end
            return values
        end) or false
    end
    local target=observe("active_target",function() return getter(virtual,"get_Target") end)
    local target_verified=false
    if finite_camera_number(target) and target==math.floor(target) and diagnostic.target_enum then
        for _,entry in ipairs(diagnostic.target_enum) do
            if entry.value==target then target_verified=true;sample.target_name=entry.name;break end
        end
    end
    sample.target=target;sample.target_verified=target_verified
    -- Do not guess TARGET=0 or call an enum-dependent getter without an actual literal match.
    if target_verified then
        local component=observe("target_component",function() return getter(manager,"getCameraComponent",target) end)
        sample.component_address=component and tostring(addr(component)) or nil
        sample.component_view=matrix(manager,"getCameraComponentViewMatrix",target)
        sample.component_projection=matrix(manager,"getCameraComponentProjectionMatrix",target)
        sample.active_view=matrix(manager,"getActiveCameraViewMatrix",target)
        sample.primary_component_view_difference=projection_difference(sample.primary_view,sample.component_view)
        sample.primary_active_view_difference=projection_difference(sample.primary_view,sample.active_view)
    end
    if sample.primary_position and sample.virtual_eye then
        local a,b=sample.primary_position,sample.virtual_eye
        sample.primary_virtual_eye_distance=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
    end
    if phase=="after_tick" and group.phases.before_tick then
        local before=group.phases.before_tick
        sample.primary_view_change=projection_difference(sample.primary_view,before.primary_view)
        sample.active_view_change=projection_difference(sample.active_view,before.active_view)
    end
end
local function observe_camera_projection(phase,frame)
    -- Diagnostics cannot add fail_open transitions or alter the takeover gates.
    local ok,err=pcall(sample_camera_projection,phase,frame)
    if not ok then state.camera_projection_error=tostring(err):sub(1,512) end
end
local function replay_cached_mc_camera(manager_address)
    local diagnostic=state.camera_replay_diagnostic or {calls=0,applied=0,rejected=0}
    state.camera_replay_diagnostic=diagnostic;diagnostic.calls=diagnostic.calls+1
    diagnostic.frame=state.frame;diagnostic.epoch=state.epoch
    local function refuse(reason)
        diagnostic.rejected=diagnostic.rejected+1;diagnostic.last_reason=reason
        return false
    end
    if not state.active or cfg.runtime_stage~="C" or cfg.diagnostic_only or not cfg.install_control_hooks then
        return refuse("Inactive camera replay")
    end
    local pose=state.cached_camera_pose
    if not pose then return refuse("No certified MC camera pose") end
    diagnostic.cached_frame=pose.frame;diagnostic.teleport_seq=pose.teleport_seq
    if pose.frame~=state.frame or pose.epoch~=state.epoch or pose.teleport_seq~=state.teleport_seq
        or pose.teleport_ack~=state.teleport_seq then return refuse("Stale cached MC camera session") end
    local ledger=state.active_camera_restore
    if not ledger or pose.owner~=ledger or ledger.restore_pending or not same(pose.primary,state.camera)
        or not same(pose.transform,state.camera_transform) or not same(pose.manager,ledger.manager)
        or manager_address~=addr(pose.manager) then return refuse("Cached MC camera owner mismatch") end
    if state.primary_camera_rollback then return refuse("Primary camera rollback remains pending") end
    local bridge=_G.onimusha_mc
    if not bridge or type(bridge.status)~="function" or type(bridge.read_mc)~="function" then
        return refuse("Camera replay bridge unavailable")
    end
    -- This runs only after the outer manager lateUpdate has returned. Inner
    -- reflection hooks never traverse its camera list or call these bridge APIs.
    local native,mc=bridge.status(),bridge.read_mc()
    if not native or native.enabled~=true or native.connected~=true or native.ready~=true
        or native.host_ready~=true or native.renderer_ready~=true or native.collision_epoch~=state.epoch
        or not mc or mc.in_world~=true or mc.dead or mc.teleport_ack~=state.teleport_seq then
        return refuse("Latest native/MC camera replay gate closed")
    end
    local confirmed=prepare_owned_active_camera()
    if confirmed~=ledger or not same(confirmed.manager,pose.manager) then error("Camera replay cannot capture a new owner",0) end
    local rollback=capture_primary_camera_rollback(pose,confirmed)
    if not apply_mc_camera_pose(pose,confirmed,rollback) then error("Camera replay application refused",0) end
    state.primary_camera_rollback=nil
    state.primary_camera_rollback_diagnostic.committed=true
    diagnostic.applied=diagnostic.applied+1;diagnostic.last_reason=nil;diagnostic.error=nil
    diagnostic.primary_checked_records=3;diagnostic.owned_checked_records=state.camera_sync_diagnostic.checked_records
    return true
end
local function camera_hook_sample(record,phase,stamp)
    local previous=record.sample_frames[phase]
    if previous and previous.frame==stamp.frame and previous.epoch==stamp.epoch then return end
    record.sample_frames[phase]={frame=stamp.frame,epoch=stamp.epoch}
    state.camera_observation_seq=(state.camera_observation_seq or 0)+1
    local sample={method=record.method,label=record.label,phase=phase,frame=stamp.frame,lua_frame=state.frame,
        epoch=stamp.epoch,seq=state.camera_observation_seq,application_phase=state.camera_observation_phase,
        active=state.active,target=stamp.owner.target,errors={}}
    -- These are leaf component reads only. Never traverse CameraManager from an
    -- inner reflection hook: its outer caller may hold _LockCameraList.
    local function observe(label,fn)
        local ok,value=pcall(fn)
        if ok then return value end
        sample.errors[#sample.errors+1]={field=label,error=tostring(value):sub(1,256)}
    end
    sample.fov=observe("primary_fov",function() return owned_camera_value(strictcall(state.camera,"get_FOV"),"fov") end)
    sample.position=observe("primary_position",function() return owned_camera_value(state.camera_transform:get_position(),"position") end)
    sample.forward=observe("primary_forward",function()
        local q=owned_camera_value(state.camera_transform:get_rotation(),"rotation")
        return {x=-2*(q.x*q.z+q.w*q.y),y=-2*(q.y*q.z-q.w*q.x),z=-(1-2*(q.x*q.x+q.y*q.y))}
    end)
    sample.param_fov=observe("current_param_fov",function() return owned_camera_value(stamp.owner.param:get_field("FOV"),"fov") end)
    local samples=state.camera_hooks.samples
    samples[#samples+1]=sample;if #samples>64 then table.remove(samples,1) end
    record["sampled_"..phase]=(record["sampled_"..phase] or 0)+1
end
local function install_camera_observation_hooks()
    if cfg.runtime_stage~="C" or cfg.diagnostic_only or not cfg.install_control_hooks
        or state.camera_hooks_attempted then return end
    state.camera_hooks_attempted=true
    state.camera_hooks={methods={},samples={}}
    local specs={
        {label="manager_late",owner="app.CameraManager",name="lateUpdate()",params={},returns="System.Void",match="manager",post=true},
        {label="reflect_component",owner="ace.CameraManagerBase",name="reflectGameCameraToCameraComponent(via.Camera, ace.CameraControllerBase)",
            params={"via.Camera","ace.CameraControllerBase"},returns="System.Void",match="component",post=true},
        {label="screen_active",owner="app.cInGameCameraOperator",name="convertWorldPos2ScreenPosActiveCamera(via.vec3)",
            params={"via.vec3"},returns="via.vec2",match="operator"},
        {label="screen_depth_active",owner="app.cInGameCameraOperator",name="convertWorldPos2ScreenPosDepthActiveCamera(via.vec3)",
            params={"via.vec3"},returns="via.vec3",match="operator"},
        {label="screen_world",owner="ace.CameraManagerBase",name="convertWorldPos2ScreenPos(via.vec3, System.Nullable`1<via.Size>, ace.CameraDef.TARGET)",
            params={"via.vec3","System.Nullable`1<via.Size>","ace.CameraDef.TARGET"},returns="via.vec2",match="target"},
        {label="screen_projected_world",owner="ace.CameraManagerBase",name="convertWorldPos2ProjectedScreenPos(via.vec3, System.Nullable`1<via.Size>, ace.CameraDef.TARGET)",
            params={"via.vec3","System.Nullable`1<via.Size>","ace.CameraDef.TARGET"},returns="via.vec2",match="target"},
        {label="manager_update",owner="app.CameraManager",name="update()",params={},returns="System.Void",match="manager",post=true},
        {label="manager_render_pre",owner="app.CameraManager",name="preproccessOfUpdateRenderCamera()",params={},returns="System.Void",match="manager",post=true},
    }
    local addresses={}
    for _,spec in ipairs(specs) do
        local record={label=spec.label,method=spec.name,type=spec.owner,attempted=false,
            observed_calls=0,post_calls=0,owned_sample_calls=0,sample_frames={}}
        state.camera_hooks.methods[spec.label]=record
        local ok,err=pcall(function()
            local definition=td(spec.owner)
            local m=definition and definition:get_method(spec.name)
            if not m or m:is_static() or m:get_num_params()~=#spec.params
                or m:get_return_type():get_full_name()~=spec.returns then error("Camera observation signature mismatch",0) end
            local params=m:get_param_types() or {}
            for i,expected in ipairs(spec.params) do
                if not params[i] or params[i]:get_full_name()~=expected then error("Camera observation parameter mismatch",0) end
            end
            -- Fixed SDK get_function returns void*. Convert its pointer value;
            -- a metadata method without an implementation must never be hooked.
            local fn=m:get_function()
            if fn==nil then error("Missing camera observation function address",0) end
            local numeric_address=sdk.to_int64(fn)
            if not finite_camera_number(numeric_address) or numeric_address<=0
                or numeric_address~=math.floor(numeric_address) then
                error("Invalid camera observation function address",0)
            end
            local address=tostring(numeric_address);record.address=address
            if addresses[address] then error("Duplicate hook function address: "..addresses[address],0) end
            addresses[address]=spec.label
            local key="onimusha_mc_camera_observation_"..spec.label
            local replay_key="onimusha_mc_camera_replay_"..spec.label
            record.attempted=true
            sdk.hook(m,function(args)
                record.observed_calls=record.observed_calls+1
                local pre_ok,pre_err=pcall(function()
                    local storage=thread.get_hook_storage();storage[key]=false
                    storage[replay_key]=false
                    if spec.label=="manager_late" and state.active and cfg.runtime_stage=="C"
                        and not cfg.diagnostic_only and cfg.install_control_hooks and state.active_camera_restore then
                        local self_address=sdk.to_int64(args[2])
                        if self_address==addr(state.active_camera_restore.manager) then
                            storage[replay_key]={address=self_address,frame=state.frame,epoch=state.epoch,
                                teleport_seq=state.teleport_seq}
                        end
                    end
                    local frame=state.camera_observation_frame or state.frame+1
                    if not state.active or cfg.runtime_stage~="C" or cfg.diagnostic_only
                        or not cfg.install_control_hooks or frame%30~=0 then return end
                    local owner=state.active_camera_restore
                    if not owner or owner.restore_pending then return end
                    -- Struct-return ABI argument placement is not certified.
                    -- Compare raw pointer numbers with verified owners only:
                    -- a shifted slot refuses the sample without dereferencing it.
                    local self_address=sdk.to_int64(args[2])
                    local matched=spec.match=="operator" and self_address==addr(owner.operator)
                        or spec.match~="operator" and self_address==addr(owner.manager)
                    if matched and spec.match=="component" then
                        matched=sdk.to_int64(args[3])==addr(owner.primary)
                            and sdk.to_int64(args[4])==addr(owner.controller)
                    elseif matched and spec.match=="target" then matched=sdk.to_int64(args[5])==owner.target end
                    if not matched then return end
                    record.owned_sample_calls=record.owned_sample_calls+1
                    local stamp={owner=owner,frame=frame,lua_frame=state.frame,epoch=state.epoch}
                    storage[key]=stamp;camera_hook_sample(record,"pre",stamp)
                end)
                if not pre_ok then record.callback_error=tostring(pre_err):sub(1,512) end
                -- Observation never returns SKIP_ORIGINAL or invokes the game method.
            end,function(retval)
                record.post_calls=record.post_calls+1
                local post_ok,post_err=pcall(function()
                    local storage=thread.get_hook_storage();local stamp=storage[key];storage[key]=nil
                    local replay_stamp=storage[replay_key];storage[replay_key]=nil
                    if spec.post and type(stamp)=="table" and state.active and cfg.runtime_stage=="C"
                        and not cfg.diagnostic_only and cfg.install_control_hooks and stamp.epoch==state.epoch
                        and stamp.lua_frame==state.frame and stamp.owner==state.active_camera_restore then
                        camera_hook_sample(record,"post",stamp)
                    end
                    if spec.label=="manager_late" and type(replay_stamp)=="table" and replay_stamp.frame==state.frame
                        and replay_stamp.epoch==state.epoch and replay_stamp.teleport_seq==state.teleport_seq then
                        replay_cached_mc_camera(replay_stamp.address)
                    end
                end)
                if not post_ok then
                    record.callback_error=tostring(post_err):sub(1,512)
                    if spec.label=="manager_late" and state.active then
                        local diagnostic=state.camera_replay_diagnostic or {};state.camera_replay_diagnostic=diagnostic
                        diagnostic.error=record.callback_error
                        local restore_ok,restore_err=pcall(fail_open,"Camera replay error: "..record.callback_error)
                        if not restore_ok then diagnostic.restore_error=tostring(restore_err):sub(1,512) end
                        log.error("[OnimushaMC] camera replay: "..record.callback_error)
                    end
                end
                return retval
            end)
        end)
        if not ok then record.install_error=tostring(err):sub(1,512) end
    end
end
local function combat_diagnostic()
    if not state.combat then
        state.combat={counters={},reason_counts={},events={},writes={},incoming={}}
    end
    return state.combat
end
local function combat_count(group,outcome,reason)
    local diagnostic=combat_diagnostic()
    local counters=diagnostic.counters[group] or {}
    diagnostic.counters[group]=counters;counters[outcome]=(counters[outcome] or 0)+1
    if reason then
        local reasons=diagnostic.reason_counts[group] or {}
        diagnostic.reason_counts[group]=reasons;reasons[reason]=(reasons[reason] or 0)+1
    end
end
local function combat_record(list,record)
    record.frame=state.frame;record.epoch=state.epoch
    local records=combat_diagnostic()[list]
    records[#records+1]=record
    if #records>16 then table.remove(records,1) end
    return record
end
local function reject_combat_event(record,reason)
    record.outcome="rejected";record.reason=reason
    combat_count(record.group,"rejected",reason)
end
local function resolve_player_death_action(player)
    -- Resolve against the current player's loaded actions, never fixed category/index
    -- values: those vary with the equipped native fighting style.
    local controller=assert(strictcall(player,'get_BaseActionController'),'Missing base action controller')
    local list=assert(controller:get_field('_ActionList'),'Missing loaded player actions')
    local count=list:get_field('_size')
    assert(type(count)=='number' and count>=1 and count<=32,'Invalid action category count')
    local groups=assert(list:get_field('_items'))
    local current=strictcall(player,'get_BaseCurrentAction')
    local style=current and attempt(function() return current:get_field('_Style') end)
    local selected,best=nil,-1
    for category=0,count-1 do
        local group=groups:get_element(category)
        if group then
            local actions=group:get_elements()
            assert(#actions<=2048,'Invalid loaded action count')
            for i,action in ipairs(actions) do
                if action and typename(action):match('%.cDie$')
                    and action:get_type_definition():is_a('app.PlayerCommonAction.cDieBase')
                    and same(action:get_field('_OwnerCharacter'),player) then
                    local score=style~=nil and action:get_field('_Style')==style and 2 or
                        (typename(action)=='app.PlayerBasicDamageAction.cDie' and 1 or 0)
                    if score>best then
                        best=score;selected={category=category,index=i-1,type=typename(action)}
                    end
                end
            end
        end
    end
    assert(selected,'No loaded native player death action')
    local id=ValueType.new(assert(td('ace.ACTION_ID')))
    id:set_field('_Category',selected.category);id:set_field('_Index',selected.index)
    -- Resolve and validate the constructed ID before requesting a transition.
    local check=strictcall(player,'getActionFromID_Base(ace.ACTION_ID)',id)
    assert(check and typename(check)==selected.type and same(check:get_field('_OwnerCharacter'),player),
        'Death action ID/owner mismatch')
    return id,selected
end
local function process_death_handoff(bridge,current,dying,menu,scripted)
    local pending=state.death_pending
    if not pending then return end
    state.death_diagnostic=pending
    if pending.player~=addr(state.player) or pending.health~=addr(state.health) or pending.epoch~=state.epoch then
        pending.outcome='cancelled_owner_changed';state.death_pending=nil;return
    end
    if type(current)~='number' then return end
    if current>0 then
        pending.outcome='native_revived';state.death_pending=nil;state.health_remainder=0;return
    end
    -- Unseal inputs and release camera/draw/physics before requesting the native
    -- animation. An inactive bridge alone cannot finish an asynchronous MC death.
    fail_open('Native death owns control');bridge.set_enabled(false)
    if restoration_pending() or menu or scripted then pending.outcome='waiting_for_restore';return end
    local entity=strictcall(strictcall(state.player,'get_CharacterEntityHolder'),'get_Entity')
    local die=strictcall(entity,'get_DieSupporter')
    local action=strictcall(state.player,'get_BaseCurrentAction')
    local native_action=action and action:get_type_definition():is_a('app.PlayerCommonAction.cDieBase')
    if dying or native_action or strictcall(die,'get_IsRequested') or strictcall(die,'get_IsRequestRevive') then
        pending.outcome='native_flow_observed';pending.observed_frame=state.frame;return
    end
    if pending.attempted then return end -- No duplicate request, including ambiguous SDK errors.
    local id,selection=resolve_player_death_action(state.player)
    local normal=assert(td('app.CharacterDeadType.TYPE'):get_field('NORMAL')):get_data(nil)
    local damage=assert(td('app.CharacterDef.ACTION_REQUEST_CATEGORY'):get_field('DAMAGE')):get_data(nil)
    assert(normal==0 and damage==4,'Unsupported Onimusha death enum values')
    pending.action=selection;pending.attempted=true;pending.request_frame=state.frame
    local ok,err=pcall(function()
        if strictcall(entity,'get_DeadType')==-1 then
            -- Explicit nil argument: generic strictcall's unpack drops trailing nil.
            die:call('reqForceDie(app.CharacterDeadType.TYPE, via.GameObject)',normal,nil)
        end
        pending.accepted=strictcall(state.player,
            'requestBaseAction(ace.ACTION_ID, app.CharacterDef.ACTION_REQUEST_CATEGORY)',id,damage)
        assert(pending.accepted==true,'Native death action request was rejected')
    end)
    pending.outcome=ok and 'requested_native_death' or 'request_failed'
    if not ok then pending.error=tostring(err);error(err,0) end
end
local function set_native_health(health,delta,event_record)
    local current=strictcall(health,"get_Health")
    local maximum=strictcall(health,"get_MaxHealth")
    local new=math.max(0,math.min(maximum,math.floor(current+delta+0.5)))
    local write=combat_record("writes",{role=event_record and event_record.role or "unspecified",
        target_id=event_record and event_record.target_id, event_type=event_record and event_record.type,
        protocol_weapon=event_record and event_record.protocol_weapon,before=current,maximum=maximum,
        requested=new,delta=delta,outcome="attempted"})
    combat_count("writes","received")
    state.health_bypass=state.health_bypass+1
    local ok,err=pcall(function()
        strictcall(health,"setHealth",new)
        strictcall(health,"checkHealthZero")
    end)
    state.health_bypass=state.health_bypass-1
    -- Only observe the already-verified getter. A failed readback never adds a
    -- health mutation or changes the existing setter/error/skip behavior.
    local read_ok,after=pcall(function() return strictcall(health,"get_Health") end)
    if read_ok and type(after)=="number" and after==after and after>-math.huge and after<math.huge then
        write.after=after;write.actual_delta=after-current;write.readback_matches=after==new
    else
        write.readback_error=read_ok and "Native HP readback is not finite" or tostring(after):sub(1,1024)
        combat_count("writes","readback_failed")
    end
    write.completed=ok
    if not ok then
        write.outcome="rejected";write.reason="setter_failed";write.error=tostring(err):sub(1,1024)
        combat_count("writes","rejected","setter_failed")
        error(err,0)
    end
    state.health_revision=state.health_revision+1
    combat_count("writes","accepted")
    if write.readback_matches then
        write.outcome=write.actual_delta==0 and "noop" or "applied"
        combat_count("writes",write.outcome,write.outcome=="noop" and "clamped_or_unchanged" or nil)
        if current>0 and write.after==0 and same(health,state.health) and state.player then
            -- The original damage reaction ran before MC armour settled the HP.
            -- setHealth/checkHealthZero notify HP listeners, but do not select a
            -- player death animation: otherwise MediumDamage can stay stuck forever.
            state.death_pending={player=addr(state.player),health=addr(health),epoch=state.epoch,
                lethal_frame=state.frame,outcome='queued'}
        end
    else
        write.outcome="unconfirmed";write.reason=write.readback_error and "readback_failed" or "readback_mismatch"
        combat_count("writes","unconfirmed",write.reason)
    end
    return write
end
local function apply_combat_write(record,health,delta)
    local ok,write=pcall(set_native_health,health,delta,record)
    if not ok then
        reject_combat_event(record,"health_write_failed");record.error=tostring(write):sub(1,1024)
        error(write,0)
    end
    record.before=write.before;record.maximum=write.maximum;record.requested=write.requested
    record.after=write.after;record.actual_delta=write.actual_delta;record.write_completed=write.completed
    record.readback_error=write.readback_error;record.readback_matches=write.readback_matches
    record.outcome=write.outcome;record.reason=write.reason
    combat_count(record.group,record.outcome,record.reason)
end
local function valid_enemy_aabb(box,origin)
    if not box then return end
    local lo,hi=box.minpos,box.maxpos
    if not lo or not hi then return end
    for _,axis in ipairs({'x','y','z'}) do
        local a,b=lo[axis],hi[axis]
        if type(a)~='number' or type(b)~='number' or a~=a or b~=b or math.abs(a)>100000
            or math.abs(b)>100000 or b<a or b-a>64 then return end
        if math.abs((a+b)*0.5-origin[axis])>32 then return end
    end
    return {min={x=lo.x,y=lo.y,z=lo.z},max={x=hi.x,y=hi.y,z=hi.z}}
end
local function enemy_damage_bounds(enemy,origin)
    -- TYPE_DAMAGE=0 is reflected from this game's enum. Never infer damage
    -- colliders from monster names, mesh filenames, or attack-volume sizes.
    return attempt(function()
        local entity=call(call(enemy,'get_CharacterEntityHolder'),'get_Entity')
        local components=entity:get_field('<CharacterComponents>k__BackingField')
        local switch=components:get_field('<ColliderSwitcher>k__BackingField')
        local rsc=switch:get_field('_RequestSetCollider')
        local group=call(switch,'getGroupFromType(app.ColliderSwitcher.COLLIDER_TYPE)',0)
        local group_id=call(group,'get_Id');local count=call(group,'get_NumRequestSets')
        if not count or count<0 or count>128 then return end
        local bounds,parts,total=nil,{},0
        for j=0,count-1 do
            if call(switch,'isRequestSetActiveFromIndex(app.ColliderSwitcher.COLLIDER_TYPE, System.UInt32)',0,j)==true then
                local n=call(rsc,'getNumCollidablesFromIndex(System.UInt32, System.UInt32)',group_id,j) or 0
                if n<0 or n>64 or total+n>128 then return end
                total=total+n
                for k=0,n-1 do
                    local col=call(rsc,'getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)',group_id,j,k)
                    if call(col,'get_Enabled')==true then
                        local box=valid_enemy_aabb(call(col,'get_BoundingAabb'),origin)
                        if box then
                            local ud=call(col,'get_UserData');local parent=call(ud,'get_ParentUserData') or ud
                            local part=attempt(function() return parent:get_field('_PartsIndex') end)
                            parts[#parts+1]={min=box.min,max=box.max,part=part}
                            if not bounds then bounds={min={x=box.min.x,y=box.min.y,z=box.min.z},max={x=box.max.x,y=box.max.y,z=box.max.z}}
                            else for _,axis in ipairs({'x','y','z'}) do
                                bounds.min[axis]=math.min(bounds.min[axis],box.min[axis])
                                bounds.max[axis]=math.max(bounds.max[axis],box.max[axis])
                            end end
                        end
                    end
                end
            end
        end
        if bounds then bounds.parts=parts;bounds.source='active_damage_colliders';return bounds end
    end)
end
local function publish_actors(s,bridge)
    local actors,live={},{}
    local candidates=scene_components(s,"app.EnemyCharacter")
    local diagnostic={found=#candidates,valid_go=0,context_resolved=0,health_resolved=0,alive=0,damage_bounds=0,fallback_bounds=0,bounds_samples={}}
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
                    local bounds=dx*dx+dy*dy+dz*dz<=32*32*cfg.units_per_block*cfg.units_per_block and enemy_damage_bounds(enemy,p) or nil
                    if bounds then
                        local w=math.max(bounds.max.x-bounds.min.x,bounds.max.z-bounds.min.z)/cfg.units_per_block
                        local h=(bounds.max.y-bounds.min.y)/cfg.units_per_block
                        if w>0.02 and h>0.02 then
                            width=math.min(64,w);height=math.min(64,h)
                            m=mcpos({x=(bounds.min.x+bounds.max.x)*0.5,y=bounds.min.y,z=(bounds.min.z+bounds.max.z)*0.5})
                            entry.bounds_native=bounds;diagnostic.damage_bounds=diagnostic.damage_bounds+1
                        else bounds=nil end
                    end
                    if not bounds then diagnostic.fallback_bounds=diagnostic.fallback_bounds+1 end
                    local name=tostring(call(go,"get_Name") or "Onimusha enemy")
                    entry.name=name;entry.position={x=m.x,y=m.y,z=m.z};entry.width=width;entry.height=height
                    if #diagnostic.bounds_samples<32 then diagnostic.bounds_samples[#diagnostic.bounds_samples+1]={id=id,name=name,
                        x=m.x,y=m.y,z=m.z,width=width,height=height,source=bounds and bounds.source or 'movement_capsule'} end
                    actors[#actors+1]={id=id,flags=1,x=m.x,y=m.y,z=m.z,yaw=0,width=width,height=height,
                        health_frac=current/maximum,level=1,name=name}
                    if #actors>=96 then break end
                end
            end
        end
    end
    state.actors=live;bridge.publish_actors(actors);state.actor_count=#actors;state.enemy_diagnostic=diagnostic
end
local function apply_events(bridge)
    for _,event in ipairs(bridge.drain_events() or {}) do
        if event.type==3 and _G.onimusha_explosion
            and finite_camera_number(event.a) and finite_camera_number(event.b) and finite_camera_number(event.c) then
            _G.onimusha_explosion.queue(event,state,repos(event.a,event.b,event.c))
        end
        local trace
        if event.type==1 or event.type==6 then
            trace=combat_record("events",{type=event.type,group=event.type==6 and "health_changes" or "enemy_hits",
                role=event.type==6 and "player" or "enemy",target_id=event.form_id,active=state.active,
                protocol_weapon=event.weapon,flags=event.flags,a=event.a,b=event.b,outcome="received"})
            if event.type==6 then
                trace.fraction=event.a;trace.mc_points=event.b;trace.event_epoch=event.weapon
                trace.remainder_before=state.health_remainder
            end
            combat_count(trace.group,"received")
        end
        if state.active and event.type==6 and event.weapon==state.epoch then
            local maximum=call(state.health,"get_MaxHealth")
            trace.maximum=maximum;trace.fraction=event.a;trace.mc_points=event.b;trace.event_epoch=event.weapon
            trace.remainder_before=state.health_remainder
            if maximum and maximum>0 and type(event.a)=="number" and math.abs(event.a)<=1 then
                combat_count(trace.group,"accepted")
                local amount=event.a*maximum+state.health_remainder
                local integer=amount<0 and math.ceil(amount) or math.floor(amount)
                state.health_remainder=amount-integer
                trace.amount=amount;trace.integer=integer;trace.remainder_after=state.health_remainder
                if integer~=0 then apply_combat_write(trace,state.health,integer)
                else trace.outcome="noop";trace.reason="rounded_to_zero";combat_count(trace.group,"noop",trace.reason) end
            else
                reject_combat_event(trace,(not maximum or maximum<=0) and "health_max_unavailable" or "invalid_fraction")
            end
        elseif state.active and event.type==1 then
            local matched=false
            for _,entry in pairs(state.actors) do
                if entry.id==event.form_id then
                    matched=true;combat_count(trace.group,"accepted")
                    trace.target_name=entry.name;trace.target_position=entry.position
                    trace.target_width=entry.width;trace.target_height=entry.height
                    -- Observe the exact proxy owner without changing actor eligibility.
                    -- Loaded/hidden enemies can otherwise look like a successful visible hit.
                    local target_go=call(entry.obj,"get_GameObject")
                    trace.target_object_address=attempt(function() return tostring(addr(entry.obj)) end)
                    trace.target_health_address=attempt(function() return tostring(addr(entry.health)) end)
                    trace.target_gameobject_address=attempt(function() return tostring(addr(target_go)) end)
                    trace.target_health_type=typename(entry.health)
                    trace.target_valid=call(target_go,"get_Valid")
                    trace.target_draw_self=call(target_go,"get_DrawSelf")
                    local scale=cfg.enemy_host_damage_per_mc_point
                    local requested=math.max(0,math.min(1000,event.a or 0))*scale
                    -- Keep the verified native queue's per-hit bound at high multipliers.
                    local damage=math.min(100000,requested)
                    trace.mc_damage=event.a;trace.base_host_damage_scale=100
                    trace.damage_multiplier=scale/100;trace.host_damage_scale=scale;trace.host_damage=damage
                    trace.damage_capped=requested>damage
                    if damage>0 then
                        local native_hit=_G.onimusha_enemy_hit
                        if native_hit and type(native_hit.queue)=="function" and native_hit.queue(entry,state,damage,trace) then
                            -- A native request owns its settlement, including ambiguous
                            -- failures. Never add a second direct-health write.
                            combat_count(trace.group,trace.outcome,trace.reason)
                        elseif cfg.require_native_enemy_damage then
                            reject_combat_event(trace,"native_enemy_damage_not_ready")
                        else apply_combat_write(trace,entry.health,-damage) end
                    else trace.outcome="noop";trace.reason="zero_damage";combat_count(trace.group,"noop",trace.reason) end
                    break
                end
            end
            if not matched then reject_combat_event(trace,"unknown_actor") end
        elseif trace then
            if not state.active then reject_combat_event(trace,"inactive")
            else trace.event_epoch=event.weapon;reject_combat_event(trace,"stale_epoch") end
        end
    end
end
local function install_hooks()
    if cfg.runtime_stage=="C" then install_camera_observation_hooks() end
    if state.control_hooks_attempted then return end
    state.control_hooks_attempted=true
    -- Camera-distance dither only. Death/stealth/material transparency keep their own logic.
    local dither=td('app.mcCamSys_DitherDepth')
    local dither_method=dither and dither:get_method('onLateUpdateEnd')
    if dither_method then
        -- TDB82 requestDisable feeds its request Boolean directly into setEnable;
        -- observed requests did not disable dither. Scope the verified enable setter
        -- around its real consumer instead, then restore before leaving the hook.
        state.hooks.camera_dither={attempted=true,calls=0,suppressed=0,
            method='onLateUpdateEnd/scoped setEnable',address=tostring(dither_method:get_function())}
        sdk.hook(dither_method,function(args)
            local r=state.hooks.camera_dither;r.calls=r.calls+1
            if not state.active then return end
            local ok,err=pcall(function()
                local obj=assert(sdk.to_managed_object(args[2]))
                assert(typename(obj)=='app.mcCamSys_DitherDepth','Unexpected camera dither owner')
                assert(not state.dither_restore,'Previous camera dither restore still pending')
                -- get_IsEnable also reports an unfinished ease transition. setEnable(0s)
                -- starts that transition; onLateUpdateEnd consumes it later in this call.
                -- Only _Enable is the setter's actual Boolean, and the baseline to restore.
                local original=obj:get_field('_Enable')
                assert(type(original)=='boolean','Invalid camera dither baseline')
                state.dither_restore={obj=obj,original=original}
                strictcall(obj,'setEnable(System.Boolean, System.Single, via.curve.EaseType)',false,0.0,0)
                assert(obj:get_field('_Enable')==false,'Camera dither disable readback failed')
                r.last_request_frame=state.frame;r.error=nil
            end)
            if not ok then r.error=tostring(err) end
        end,function(retval)
            local record=state.dither_restore
            if record then
                local r=state.hooks.camera_dither
                local ok,err=pcall(function()
                    r.enabled_during_consumer=strictcall(record.obj,'get_IsEnable')
                    local param=record.obj:get_field('_CurrentParam')
                    r.near_alpha=param and param:get_field('NearAlpha')
                    r.far_alpha=param and param:get_field('FarAlpha')
                    if r.enabled_during_consumer==false then r.suppressed=r.suppressed+1 end
                end)
                if not ok then r.error=tostring(err) end
                restore_camera_dither()
                if state.dither_restore then fail_open('Camera dither restore pending') end
            end
            return retval
        end)
    end
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
    -- In TDB82 execThirdDamage encloses the real HP mutation (natural capture
    -- combat-flow-user-confirmed-04). Keep only scalar source identities for
    -- that synchronous call; never borrow cApplyParam/stock across frames.
    local hit_contexts={}
    local source_record={method="execThirdDamage",attempted=false,calls=0,owned_calls=0,matched_sources=0}
    state.hooks.hurt_source=source_record
    local function current_hit_source()
        if not thread or not thread.get_hash then return nil end
        local stack=hit_contexts[tostring(thread.get_hash())]
        local hit=stack and stack[#stack]
        if not hit or hit.frame~=state.frame or hit.epoch~=state.epoch or not state.active
            or hit.player~=addr(state.player) or hit.health~=addr(state.health) then return nil end
        for _,actor in pairs(state.actors or {}) do
            local go=call(actor.obj,"get_GameObject")
            if actor.id==hit.actor and addr(actor.obj)==hit.character and go
                and call(go,"get_Valid")==true and addr(go)==hit.gameobject then return hit end
        end
        return nil
    end
    local source_ok,source_error=pcall(function()
        assert(sdk.get_tdb_version and sdk.get_tdb_version()==82 and thread and thread.get_hook_storage,
            "Synchronous hit source requires TDB82 and hook storage")
        local apply_name="app.cCharacterApplyDamage.cApplyParam"
        local param_type=assert(td(apply_name))
        assert(not param_type:is_value_type() and not param_type:is_by_ref() and not param_type:is_pointer())
        local source_method=assert(td("app.cCharacterApplyDamage"):get_method("execThirdDamage("..apply_name..")"))
        assert(not source_method:is_static() and source_method:get_num_params()==1
            and source_method:get_param_types()[1]:get_full_name()==apply_name
            and source_method:get_declaring_type():get_full_name()=="app.cCharacterApplyDamage"
            and source_method:get_return_type():get_full_name()=="System.Void")
        source_record.attempted=true;source_record.address=tostring(source_method:get_function())
        sdk.hook(source_method,function(args)
            source_record.calls=source_record.calls+1
            local storage=thread.get_hook_storage();storage.onimusha_mc_hit_source=nil
            if not state.active or not state.player or not state.health then return end
            local ok,err=pcall(function()
                local holder=call(state.player,"get_CharacterEntityHolder")
                local entity=call(holder,"get_Entity")
                if not entity or not same(call(entity,"get_OwnerCharacter"),state.player) then return end
                local damage=entity:get_field("_DamageInterface")
                if not damage or sdk.to_int64(args[2])~=addr(damage) then return end
                if typename(damage)~="app.cPlayerApplyDamage" or call(damage,"get_Valid")~=true
                    or call(damage,"get_IsDestroy")~=false or not same(call(damage,"get_OwnerCharacter"),state.player) then return end
                local key=tostring(thread.get_hash());local stack=hit_contexts[key] or {}
                assert(#stack<16,"Unexpected native damage recursion")
                -- Push even an unresolved inner hit, masking the outer source.
                local token={frame=state.frame,epoch=state.epoch,player=addr(state.player),health=addr(state.health)}
                stack[#stack+1]=token;hit_contexts[key]=stack
                storage.onimusha_mc_hit_source={key=key,token=token}
                source_record.owned_calls=source_record.owned_calls+1
                if sdk.is_managed_object(args[3])~=true then return end
                local param=sdk.to_managed_object(args[3])
                if not param or not param:get_type_definition():is_a(apply_name) then return end
                local stock=param:get_field("DamageInfo")
                if not stock or not stock:get_type_definition():is_a("app.cStockDamageInfoCharacter")
                    or not same(call(stock,"get_Receiver"),state.player_go) then return end
                local attacker=call(stock,"get_Attacker")
                if not attacker or call(attacker,"get_Valid")~=true then return end
                for _,actor in pairs(state.actors or {}) do
                    if same(call(actor.obj,"get_GameObject"),attacker) then
                        token.actor=actor.id;token.character=addr(actor.obj);token.gameobject=addr(attacker)
                        source_record.matched_sources=source_record.matched_sources+1
                        return
                    end
                end
            end)
            if not ok then source_record.error=tostring(err):sub(1,400) end
            -- Direction metadata only: never suppress native damage stages.
        end,function(retval)
            local storage=thread.get_hook_storage();local saved=storage.onimusha_mc_hit_source
            storage.onimusha_mc_hit_source=nil
            if saved then
                local stack=hit_contexts[saved.key]
                if stack and stack[#stack]==saved.token then
                    table.remove(stack);if #stack==0 then hit_contexts[saved.key]=nil end
                else hit_contexts[saved.key]=nil;source_record.error="Unbalanced native hit context" end
            end
            return retval
        end)
    end)
    if not source_ok then source_record.error=tostring(source_error):sub(1,400) end
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
                local incoming
                if delta<0 then
                    incoming=combat_record("incoming",{method=name,before=current,maximum=maximum,delta=delta,
                        mc_points=-delta/maximum*20,active=state.active,health_bypass=state.health_bypass,outcome="received"})
                    combat_count("incoming","received")
                end
                if not state.active or state.health_bypass>0 or not cfg.mirror_native_damage_to_mc then
                    if incoming then
                        incoming.outcome="rejected";incoming.reason=not state.active and "inactive"
                            or state.health_bypass>0 and "health_bypass" or "mirroring_disabled"
                        combat_count("incoming","rejected",incoming.reason)
                    end
                    return
                end
                local bridge=_G.onimusha_mc
                if not bridge or not bridge.send_hurt then
                    if incoming then incoming.outcome="rejected";incoming.reason="bridge_unavailable";
                        combat_count("incoming","rejected",incoming.reason) end
                    return
                end
                if delta<0 then
                    combat_count("incoming","attempted")
                    local hit=current_hit_source()
                    local attacker_id=hit and hit.actor or 0
                    incoming.attacker_id=attacker_id;incoming.source_verified=hit~=nil
                    local accepted=bridge.send_hurt({kind=0,mc_points=-delta/maximum*20,attacker_id=attacker_id,flags=4})
                    incoming.accepted=not not accepted;incoming.outcome=accepted and "accepted" or "rejected"
                    incoming.reason=not accepted and "bridge_rejected" or nil
                    combat_count("incoming",incoming.outcome,incoming.reason)
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
    local menu_pause=call(state.pause,"get_IsMenuPause")
    local player_pause=call(state.pause,"get_IsPlayerPause")
    local event_jack=call(state.controller,"get_IsEventJack")
    local dialogue_jack=call(state.controller,"get_IsDialogueJack")
    local event_start=call(state.player,"get_IsEventStart")
    local auto_move=call(state.pm,"get_IsAutoMove")
    local menu=menu_pause or player_pause
    local scripted=event_jack or dialogue_jack or event_start or auto_move
    local dying=call(state.pm,"isPlayerDying") or call(state.pm,"isPlayerDead")
    local p=state.transform:get_position();local m=mcpos(p)
    if math.abs(p.x/cfg.units_per_block)>=cfg.tile_stride/2-128
        or math.abs(p.z/cfg.units_per_block)>=cfg.tile_stride/2-128 then
        fail_open("Stage extent exceeds isolated Minecraft tile; recalibrate tile_stride")
        bridge.submit_host({ready=false});return
    end
    local current,maximum=call(state.health,"get_Health"),call(state.health,"get_MaxHealth")
    local valid_hp=type(current)=="number" and type(maximum)=="number" and maximum>0
    if cfg.runtime_stage=="C" then process_death_handoff(bridge,current,dying,menu,scripted) end
    if state.bridge_epoch~=state.epoch then
        bridge.submit_host({ready=false,world_id=state.world_id,epoch=state.epoch,
            teleport_seq=state.teleport_seq,x=m.x,y=m.y,z=m.z,yaw=host_angles.yaw,pitch=host_angles.pitch,
            health_current=current or 0,health_max=maximum or 0,units_per_block=cfg.units_per_block})
        state.bridge_epoch=state.epoch
    end
    local native=bridge.status();local mc
    if type(bridge.read_render_mc)=='function' then mc=bridge.read_render_mc() else mc=bridge.read_mc()end
    if state.previous_native_enabled==false and native.enabled and not state.active then
        -- A deliberate off->on takeover starts at the current native pose. Never
        -- resync an active/out-of-bounds MC move to conceal missing terrain.
        state.teleport_seq=next_session_counter(state.teleport_seq)
        persist_session();state.enable_resync_frame=state.frame
    end
    state.previous_native_enabled=native.enabled==true
    reconcile_collision(native)
    local covered,coverage_reason=collision_coverage_gate(native,m,mc)
    local mc_position
    if mc and finite_camera_number(mc.x) and finite_camera_number(mc.y) and finite_camera_number(mc.z) then
        mc_position=repos(mc.x,mc.y,mc.z)
    end
    local prospective=mc_position and mc.in_world and mc.teleport_ack==state.teleport_seq
        and (state.active or native.enabled)
    local coverage=state.collision_coverage
    local refresh_due=collision_refresh_due(p) or (prospective and collision_refresh_due(mc_position))
        or (coverage and (not collision_contains_foot(coverage.bounds,m)
            or prospective and not collision_contains_foot(coverage.bounds,mc)))
    if cfg.enable_terrain_queries and refresh_due then start_collision(s,state.active and mc_position or p,native) end
    advance_collision(bridge,native)
    native=bridge.status()
    covered,coverage_reason=collision_coverage_gate(native,m,mc)
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
    local camera_basis_verified=state.camera_axis_calibrated and state.camera_forward_sign==-1
    local control_bindings_ready=cfg.install_control_hooks and not menu and not scripted and not dying and valid_hp
        and current>0 and state.bindings.root_motion and camera_basis_verified
    local teleport_pending=not mc or mc.teleport_ack~=state.teleport_seq
    local native_covered,native_coverage_reason=collision_native_coverage_gate(native,m)
    -- The saved MC pose may be outside this newly queried stage. Publish a ready
    -- native target so MC can bootstrap-teleport; native's ack gate still forbids
    -- takeover. Once ack matches, both current native and prospective MC bodies
    -- must be inside consumed coverage before any native pose/draw/input write.
    local host_pose_covered=covered
    if teleport_pending then host_pose_covered=native_covered end
    local host_bootstrap_ready=control_bindings_ready and host_pose_covered
    local can_control=control_bindings_ready and covered
    -- HP getters are authoritative even before the first hit in a safe area.
    -- Damage hooks fail open to native damage if an MC mitigation event cannot
    -- be queued; observed hook counters remain separate runtime evidence.
    bridge.set_camera({binding_ready=state.camera_transform~=nil,valid=false})
    local explosions_ready=_G.onimusha_explosion and _G.onimusha_explosion.refresh(state.player,state.epoch)
    bridge.submit_host({ready=host_bootstrap_ready,menu=menu or false,loading=not call(state.pm,"isPlayerReady",false),
        flags=explosions_ready and 128 or 0,
        x=m.x,y=m.y,z=m.z,yaw=host_angles.yaw,pitch=host_angles.pitch,world_id=state.world_id,epoch=state.epoch,teleport_seq=state.teleport_seq,
        health_current=current or 0,health_max=maximum or 0,health_revision=state.health_revision,
        units_per_block=cfg.units_per_block})
    local alive=mc and mc.in_world and not mc.dead
    local after_submit=bridge.status()
    state.gate_snapshot={frame=state.frame,epoch=state.epoch,native_foot={x=m.x,y=m.y,z=m.z},
        mc_foot=mc and {x=mc.x,y=mc.y,z=mc.z},coverage=covered,coverage_reason=coverage_reason,
        native_coverage=native_covered,native_coverage_reason=native_coverage_reason,
        teleport_pending=teleport_pending,host_bootstrap_ready=host_bootstrap_ready,enable_resync_frame=state.enable_resync_frame,
        menu_pause=menu_pause,player_pause=player_pause,event_jack=event_jack,dialogue_jack=dialogue_jack,
        event_start=event_start,auto_move=auto_move,dying=dying,valid_hp=valid_hp,health_current=current,health_max=maximum,
        enabled=native.enabled,connected=native.connected,renderer_ready=native.renderer_ready,
        mc_alive=alive,teleport_ack=mc and mc.teleport_ack,teleport_seq=state.teleport_seq,
        camera_basis_verified=camera_basis_verified,root_motion=state.bindings.root_motion,
        host_ready=after_submit.host_ready,native_ready=after_submit.ready,native_not_ready_reason=after_submit.not_ready_reason,
        host_age_ms=after_submit.host_age_ms,mc_heartbeat_age_ms=after_submit.mc_heartbeat_age_ms,
        collision_generation=native.collision_generation,
        collision_publish_seq=native.collision_publish_seq,collision_consumed_seq=native.collision_consumed_seq}
    if not native.enabled or not native.renderer_ready or not can_control or not alive or not native.connected
        or mc.teleport_ack~=state.teleport_seq or not after_submit.ready then
        fail_open(not native.enabled and "Bridge disabled" or not native.connected and "Minecraft disconnected" or
            not native.renderer_ready and "Native renderer not ready" or
            not camera_basis_verified and "Unverified camera basis; only local -Z is supported" or
            menu and "Native menu owns control" or scripted and "Scripted scene owns control" or
            dying and "Native death owns control" or not valid_hp and "Native HP unavailable" or
            current<=0 and "Native HP depleted" or not alive and "Waiting for Minecraft world" or
            not cfg.install_control_hooks and "Native control hooks disabled" or
            not state.bindings.root_motion and "Root motion binding not ready" or
            teleport_pending and not native_covered and native_coverage_reason or
            teleport_pending and "Minecraft teleport acknowledgment pending" or
            not covered and coverage_reason or
            mc.teleport_ack~=state.teleport_seq and "Minecraft teleport acknowledgment pending" or
            after_submit.not_ready_reason or "Native host readiness gate closed")
        return
    end
    local eye,eye_error=mc_camera_eye(mc)
    if not eye then error(eye_error,0) end
    local camera_rotation,rotation_error=native_camera_rotation_from_mc(eye.yaw,eye.pitch,
        state.camera_forward_sign,state.camera_axis_calibrated)
    if not camera_rotation then error(rotation_error,0) end
    local player_yaw,player_error=native_player_yaw_from_mc(mc.yaw)
    if not player_yaw then error(player_error,0) end
    local active_camera_owner=prepare_owned_active_camera()
    if not state.active then
        capture_player_visuals()
    end
    state.active=true;state.not_ready_reason=nil;state.status="Minecraft controls player; native HP authoritative"
    set_boxes_enabled(true)
    seal_player_inputs()
    local np=repos(mc.x,mc.y,mc.z)
    local delta=math.sqrt((np.x-p.x)^2+(np.y-p.y)^2+(np.z-p.z)^2)
    if delta>cfg.max_pose_jump*cfg.units_per_block and mc.teleport_ack~=state.teleport_seq then
        fail_open("Rejected stale/unacknowledged MC teleport");return
    end
    state.transform:set_position(Vector4f.new(np.x,np.y,np.z,1),false)
    state.transform:set_rotation(Quaternion.new(Vector3f.new(0,math.rad(player_yaw),0)))
    if state.physics then call(state.physics,"doWarp") end
    state.hidden=true
    for _,item in ipairs(state.draw_targets) do strictcall(item.obj,"set_DrawSelf",false) end
    local ep=repos(eye.x,eye.y,eye.z)
    local camera_quaternion=Quaternion.new(Vector3f.new(math.rad(camera_rotation.pitch),math.rad(camera_rotation.yaw),0))
    local target_fov=cfg.camera_fov_radians and math.rad(mc.fov) or mc.fov
    if not positive_fov(target_fov) then error("MC FOV must be a finite positive number",0) end
    cache_mc_camera_pose(ep,camera_quaternion,target_fov,active_camera_owner,mc)
    if state.frame%6==0 then publish_actors(s,bridge) end
    -- MC block collision is authoritative for the MC player. Native enemy colliders require
    -- verified RequestSetCollider registration; pending updates remain visible diagnostics.
    -- Leave native's update queue intact until a verified collider sink is available.
    apply_solids(bridge)
    local blocks=_G.onimusha_native_blocks
    if blocks then
        if cfg.enable_prefab_block_colliders then
            blocks.update({bridge=bridge,units=cfg.units_per_block,scene=addr(s),epoch=state.epoch,world_id=state.world_id,
                mc_pid=native.mc_pid,generation=native.collision_generation,x=mc.x,y=mc.y,z=mc.z,
                folder=strictcall(strictcall(state.player,"get_GameObject"),"get_Folder"),to_native=repos})
        else blocks.stop() end
    end
    local sections=_G.onimusha_native_sections
    if sections then
        if cfg.enable_native_section_rendering then
            sections.update({bridge=bridge,units=cfg.units_per_block,scene=addr(s),epoch=state.epoch,world_id=state.world_id,
                render_frame=mc.frame,
                mc_pid=native.mc_pid,generation=native.collision_generation,x=mc.x,y=mc.y,z=mc.z,
                folder=strictcall(strictcall(state.player,"get_GameObject"),"get_Folder"),to_native=repos})
        else sections.stop() end
    end
end
re.on_pre_application_entry("UpdateBehavior",function()
    state.camera_observation_phase="before_update_behavior"
    state.camera_observation_frame=state.frame+1
    observe_camera_projection("before_update_behavior",state.camera_observation_frame)
    if state.active and state.input then
        local ok,err=pcall(seal_player_inputs)
        if not ok then fail_open("Input seal error: "..tostring(err)) end
    end
end)
re.on_application_entry("LateUpdateBehavior",function()
    state.frame=state.frame+1
    state.camera_observation_phase="late_before_tick"
    state.camera_observation_frame=state.frame
    observe_camera_projection("before_tick",state.camera_observation_frame)
    local ok,err=pcall(tick)
    if not ok then
        fail_open("Adapter error: "..tostring(err))
        if state.last_error~=tostring(err) then log.error("[OnimushaMC] "..tostring(err));state.last_error=tostring(err) end
        if not cfg.diagnostic_only and _G.onimusha_mc then _G.onimusha_mc.submit_host({ready=false}) end
    end
    state.camera_observation_phase="late_after_tick"
    state.camera_observation_frame=state.frame
    observe_camera_projection("after_tick",state.camera_observation_frame)
    if state.frame%300==0 then
        json.dump_file("onimusha_mc_status.json",{status=state.status,active=state.active,bindings=state.bindings,
            runtime_stage=cfg.runtime_stage,diagnostic_only=cfg.diagnostic_only,
            enemy_host_damage_per_mc_point=cfg.enemy_host_damage_per_mc_point,damage_setting_error=state.damage_setting_error,
            death_handoff=state.death_diagnostic or state.death_pending,
            control_hooks_enabled=cfg.install_control_hooks,terrain_queries_enabled=cfg.enable_terrain_queries,
            native_block_colliders_enabled=cfg.enable_native_block_colliders,
            health_hook_tests_enabled=cfg.enable_health_hook_tests,
            world=state.world_key or state.observed_world_key,observed_area=state.observed_area_key,
            epoch=state.epoch,collision_count=state.collision_count,
            collision_refresh=collision_diagnostic(),not_ready_reason=state.not_ready_reason,
            control_transitions=state.control_diagnostic,control_gate=state.gate_snapshot,
            collision_unsupported=state.collision_unsupported,actor_count=state.actor_count,
            enemy_diagnostic=state.enemy_diagnostic,
            pending_native_block_colliders=state.pending_native_block_colliders,query=state.query_diagnostic,
            block_colliders=state.collider_diagnostic,native_block_count=state.native_block_count,
            prefab_blocks=_G.onimusha_native_blocks and _G.onimusha_native_blocks.status(),
            native_sections=_G.onimusha_native_sections and _G.onimusha_native_sections.status(),
            collider_ray=state.collider_ray_diagnostic,
            camera_axis=state.camera_axis_diagnostic,
            camera_projection=state.camera_projection_diagnostic,camera_projection_error=state.camera_projection_error,
            camera_sync=state.camera_sync_diagnostic,
            camera_hooks=state.camera_hooks,
            camera_replay=state.camera_replay_diagnostic,
            primary_camera_rollback=state.primary_camera_rollback_diagnostic,
            host_camera=state.host_camera_diagnostic,
            input_seals=state.input_seal_diagnostic,
            visual_restore=state.visual_restore_diagnostic,
            hooks=state.hooks,health_hook_test=state.health_hook_test,
            combat=state.combat,health_revision=state.health_revision,health_remainder=state.health_remainder,
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
        if imgui.tree_node("Damage / 伤害设置") then
            local edited,multiplier=imgui.drag_float("Attack damage multiplier / 对敌伤害倍率",cfg.enemy_host_damage_per_mc_point,10,100,5000)
            if edited then save_damage_multiplier(multiplier) end
            for _,preset in ipairs({100,500,1000,2000,5000}) do
                if preset~=100 then imgui.same_line() end
                if imgui.button(tostring(preset).."##onimusha_damage") then save_damage_multiplier(preset) end
            end
            imgui.text(string.format("Current / 当前: %d (%.1fx previous damage / 原伤害)",cfg.enemy_host_damage_per_mc_point,cfg.enemy_host_damage_per_mc_point/100))
            imgui.text("100 = previous damage / 100为原伤害；500为原伤害5倍")
            imgui.text("Immediate + auto-save / 即时生效并自动保存")
            imgui.text("MC attacks, projectiles and mobs / MC近战、弹射物和生物攻击")
            imgui.text("Player damage taken and native TNT unchanged / 不影响玩家承伤和原生TNT")
            imgui.text("Maximum native damage per hit: 100000 / 单次原生伤害上限100000")
            if state.damage_setting_error then imgui.text("Save failed / 保存失败: "..state.damage_setting_error) end
            imgui.tree_pop()
        end
        imgui.text("Native collision triangles: "..tostring(state.collision_count))
        imgui.text("Enemies exported: "..tostring(state.actor_count or 0))
        imgui.text("Native block colliders: "..tostring(state.native_block_count or 0))
        imgui.text(state.bindings.block_colliders and "Native registration raycast verified" or
            "Native registration pending / check status report")
        imgui.tree_pop()
    end
end)
_G.onimusha_adapter_lifecycle={ready_for_reload=function()
    return not state.active and not restoration_pending() and not state.hidden
        and (state.health_bypass or 0)==0
        and (not _G.onimusha_native_blocks or not _G.onimusha_native_blocks.busy())
        and (not _G.onimusha_native_sections or not _G.onimusha_native_sections.busy())
end}
re.on_script_reset(function()
    if not cfg.diagnostic_only or restoration_pending() or state.hidden or state.collider_probe or next(state.blocks) then
        fail_open("Script reset");clear_boxes()
    end
    if not cfg.diagnostic_only and _G.onimusha_mc then _G.onimusha_mc.set_enabled(false) end
    _G.onimusha_adapter_lifecycle=nil
end)
log.info("[OnimushaMC] adapter loaded; TDB "..tostring(sdk.get_tdb_version()).."; stage "..cfg.runtime_stage)
