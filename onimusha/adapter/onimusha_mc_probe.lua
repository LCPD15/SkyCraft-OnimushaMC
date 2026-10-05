-- SkyCraft Onimusha binding probe. Read-only: no hooks, setters, game state writes.
-- Install only this file first. Reports resolve below reframework/data/.
if _G.onimusha_mc then return end -- The adapter provides compact runtime diagnostics once the DLL is loaded.
local PREFIX = "onimusha_mc_probe_"
local discovered_types = {}
local types = {
    "app.PlayerManager", "app.Player", "app.PlayerCharacter", "app.CharacterBase",
    "app.cPlayerManageInfo", "app.cGameContextHolder", "app.cPlayerCharacterEntity", "app.CharacterBase.cComponents",
    "app.PlayerController", "app.CharacterControllerBase", "app.PlayerCommand", "app.PlayerKey",
    "app.PlayerBattleComponent", "app.BattleComponent", "app.cHealthManager",
    "app.cPlayerContextParam", "app.cCharacterContextParam", "app.cPlayerGameInput",
    "app.cPlayerCommandController", "app.cPlayerInputStateSupporter", "app.cPlayerMotionRootTransStopper",
    "app.cPlayerApplyDamage", "app.cCharacterApplyDamage", "app.cCharacterApplyDamageAfter",
    "app.cCharacterPhysics", "app.cCharacterDynamics", "app.EnemyManager", "app.EnemyCharacter",
    "app.EnemyBattleComponent", "app.ApplyDamage", "app.PlayerApplyDamage", "app.EnemyApplyDamage",
    "app.GameInputManager", "app.CameraManager", "app.PlayerCameraControllerBase",
    "app.CameraController", "ace.CameraManagerBase", "app.AppRaycastManager", "ace.RaycastManagerBase",
    "via.SceneManager", "via.Scene", "via.GameObject", "via.Transform", "via.render.Mesh",
    "via.render.Camera", "via.motion.Motion", "via.physics.System", "via.physics.CharacterController",
    "via.physics.Colliders", "via.physics.Collider", "via.physics.Collidable", "via.physics.BoxShape",
    "via.physics.Shape", "via.physics.CastRayQuery", "via.physics.CastRayResult", "via.physics.FilterInfo",
    "via.physics.CastRayResult.Result", "via.physics.CollidableBase", "via.physics.ColliderSet",
    "via.physics.StaticCompoundShape", "via.physics.MeshShape", "via.physics.TriangleShape",
    "via.physics.GetAreaPrimitiveQuery", "via.physics.GetAreaPrimitiveResult", "via.physics.ContactPoint",
    "via.physics.ColliderSet", "via.physics.CollidableBase", "via.physics.RequestSetCollider",
    "via.physics.BoxShape", "via.Camera", "via.Folder", "via.SceneManager", "app.SceneManager", "app.StageManager",
    "app.cStageSceneManager", "app.cAreaSceneManager", "app.cSMSceneManager", "app.cSubSceneControllerManager",
    "app.cStageManager", "app.SceneManager", "app.AppLoadManager", "app.LoadManager",
    "app.EnvironmentManager", "app.SceneDef", "app.StageGridDefinitionRegisterer",
    "via.Triangle", "via.AABB", "via.OBB", "via.physics.GetAreaPrimitiveResult.Result",
    "via.physics.StaticCompoundShape.Instance", "via.physics.RequestSetCollider.Shape",
    "via.physics.RequestSetCollider.RequestSetGroup", "via.physics.RequestSetCollider.Group",
    "app.cCommonContextParam", "app.cContextIDInfo", "app.cGameContextParamCore",
    "app.cStageSceneManager.cStageSceneInfo", "via.physics.CharacterColliderBankResourceHolder",
    "app.CharacterReadyUpdate", "app.CharacterAfter", "app.PauseManager", "app.GUIManager",
}
local function attempt(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end
local function type_name(t)
    if not t then return "nil" end
    return attempt(function() return t:get_full_name() end) or tostring(t)
end
local function describe_type(td)
    if not td then return { missing = true } end
    local result = { name = type_name(td), fields = {}, methods = {} }
    local parent = attempt(function() return td:get_parent_type() end)
    if parent then result.parent = type_name(parent) end
    if parent and not discovered_types[type_name(parent)] then
        discovered_types[type_name(parent)] = { name=type_name(parent), pending=true }
        discovered_types[type_name(parent)] = describe_type(parent)
    end
    for _, f in ipairs(attempt(function() return td:get_fields() end) or {}) do
        result.fields[#result.fields + 1] = {
            name = attempt(function() return f:get_name() end),
            type = type_name(attempt(function() return f:get_type() end)),
            static = attempt(function() return f:is_static() end),
            offset = attempt(function() return f:get_offset_from_base() end),
        }
    end
    for _, m in ipairs(attempt(function() return td:get_methods() end) or {}) do
        local params = {}
        for _, p in ipairs(attempt(function() return m:get_param_types() end) or {}) do
            params[#params + 1] = type_name(p)
        end
        result.methods[#result.methods + 1] = {
            name = attempt(function() return m:get_name() end), params = params,
            param_names = attempt(function() return m:get_param_names() end),
            returns = type_name(attempt(function() return m:get_return_type() end)),
            static = attempt(function() return m:is_static() end),
        }
    end
    return result
end
local function describe_value(value, depth, seen)
    if value == nil then return { null = true } end
    local kind = type(value)
    if kind == "boolean" or kind == "string" or kind == "number" then return value end
    if kind ~= "userdata" then return tostring(value) end
    local td = attempt(function() return value:get_type_definition() end)
    if not td then
        local v = attempt(function() return { x=value.x, y=value.y, z=value.z, w=value.w } end)
        return v or tostring(value)
    end
    local name, address = type_name(td), tostring(attempt(function() return value:get_address() end) or value)
    if not discovered_types[name] then discovered_types[name] = describe_type(td) end
    local result = { type = name, address = address }
    if name == "System.String" then result.value = tostring(value); return result end
    if depth <= 0 or seen[address] then return result end
    seen[address] = true
    if attempt(function() return td:is_array() end) then
        result.elements = {}
        local elements = attempt(function() return value:get_elements() end) or {}
        for i = 1, math.min(#elements, 12) do
            result.elements[i] = describe_value(elements[i], depth - 1, seen)
        end
        result.length = #elements
        return result
    end
    result.fields = {}
    local scan, inherited = td, 0
    while scan and inherited < 5 do
        for _, f in ipairs(attempt(function() return scan:get_fields() end) or {}) do
            local static = attempt(function() return f:is_static() end)
            local fname = attempt(function() return f:get_name() end)
            if fname and not static then
                local fieldvalue = attempt(function() return f:get_data(value) end)
                result.fields[fname] = describe_value(fieldvalue, depth - 1, seen)
            end
        end
        scan = attempt(function() return scan:get_parent_type() end)
        inherited = inherited + 1
    end
    -- Narrow allow-list of parameterless read accessors; no setters or action methods.
    result.getters = {}
    local allowed = {
        get_Player=true, get_PlayerCharacter=true, get_MainPlayer=true, get_Character=true,
        get_PlayerContext=true, get_Context=true, get_HealthManager=true,
        get_BattleComponent=true, get_Current=true, get_CurrentHP=true, get_MaxHP=true,
        get_Hp=true, get_MaxHp=true, get_Health=true, get_MaxHealth=true,
        get_GameObject=true, get_Transform=true, get_CurrentScene=true,
        get_Name=true, get_Position=true, get_Rotation=true,
        getControllingPlayerInfo=true, getControllingPlayer=true,
        get_FOV=true, get_AspectRatio=true, get_IsMenuPause=true, get_IsPlayerPause=true,
        get_Common=true, get_Chara=true, get_Info=true, get_StageID=true, get_AreaID=true,
    }
    local method_scan, getter_seen = td, {}
    for _ = 1, 5 do
        if not method_scan then break end
        for _, m in ipairs(attempt(function() return method_scan:get_methods() end) or {}) do
            local mn = attempt(function() return m:get_name() end)
            if allowed[mn] and not getter_seen[mn] and attempt(function() return m:get_num_params() end) == 0
                and not attempt(function() return m:is_static() end) then
                getter_seen[mn] = true
                result.getters[mn] = describe_value(attempt(function() return m:call(value) end), depth - 1, seen)
            end
        end
        method_scan = attempt(function() return method_scan:get_parent_type() end)
    end
    return result
end
local function save(name, value)
    local ok, err = pcall(json.dump_file, PREFIX .. name .. ".json", value)
    if not ok then log.error("[OnimushaMC probe] write failed: " .. tostring(err)) end
end
local frame, dumped, snapshots = 0, false, 0
re.on_frame(function()
    if _G.onimusha_mc then return end
    frame = frame + 1
    if not dumped and frame >= 120 then
        local report = { schema=1, tdb_version=attempt(sdk.get_tdb_version), types={} }
        for _, name in ipairs(types) do
            report.types[name] = describe_type(attempt(function() return sdk.find_type_definition(name) end))
        end
        save("types", report)
        dumped = true
        log.info("[OnimushaMC probe] type metadata saved (read-only)")
    end
end)
re.on_application_entry("UpdateBehavior", function()
    if _G.onimusha_mc then return end
    if not dumped or frame % 300 ~= 0 then return end
    snapshots = snapshots + 1
    local report = { frame=frame, tdb_version=attempt(sdk.get_tdb_version), singletons={} }
    for _, name in ipairs({ "app.PlayerManager", "app.EnemyManager", "app.CameraManager", "app.EnvironmentManager",
        "app.GameInputManager", "app.PauseManager", "app.GUIManager" }) do
        report.singletons[name] = describe_value(attempt(function() return sdk.get_managed_singleton(name) end), 3, {})
    end
    report.camera = describe_value(attempt(sdk.get_primary_camera), 2, {})
    local camera=attempt(sdk.get_primary_camera)
    local ct=attempt(function() return camera:call("get_GameObject"):call("get_Transform") end)
    report.camera_pose={position=describe_value(attempt(function() return ct:get_position() end),1,{}),
        rotation=describe_value(attempt(function() return ct:get_rotation() end),1,{}),
        look_at=describe_value(attempt(function() return camera:call("get_LookAtPosition") end),1,{})}
    local pm = attempt(function() return sdk.get_managed_singleton("app.PlayerManager") end)
    report.live_player = describe_value(attempt(function() return pm:call("getControllingPlayerInfo") end), 5, {})
    local info=attempt(function() return pm:call("getControllingPlayerInfo") end)
    local context=attempt(function() return info:call("get_Context") end)
    report.player_context=describe_value(context,2,{})
    report.player_chara_context=describe_value(attempt(function() return context:call("get_Chara") end),4,{})
    report.player_common_context=describe_value(attempt(function() return context:call("get_Common") end),3,{})
    report.player_context_id=describe_value(attempt(function() return context:call("get_Info") end),2,{})
    report.discovered_types = discovered_types
    save("snapshot", report)
    if snapshots <= 30 then save("snapshot_" .. tostring(snapshots), report) end
    if snapshots <= 3 or snapshots % 12 == 0 then
        log.info("[OnimushaMC probe] runtime snapshot " .. tostring(snapshots) .. " saved")
    end
end)
log.info("[OnimushaMC probe] loaded; read-only metadata and bounded runtime snapshots")
