-- Optional read-only natural-hit probe. OnimushaWotS 01.000.001 / TDB82 only.
-- No setters, allocations, native action requests, skipped calls or changed returns.
-- Default disarmed. A new control-file arm_id is required for every capture.
-- MOD制作：LCPD15/LCPD拉灯
local CONTROL="onimusha_guard_probe_control.json"
local OUTPUT="onimusha_guard_probe_status.json"
local APPLY="app.cCharacterApplyDamage.cApplyParam"
local state={frame=0,armed=false,status="Disarmed",events={},hooks={},sequence=0,
    stable_frames=0,seen_arm_id="",generation=0,stacks={},errors={},metadata={}}
local profiles={guard={
    {key="stock",type="app.cPlayerApplyDamage",name="doApplyStockDamage",returns="System.Void"},
    {key="guard_test",type="app.cCharacterApplyDamage",name="isEnableGuardDamage",returns="System.Boolean"},
    {key="guard_reaction",type="app.cCharacterApplyDamage",name="applyGuardDamageReaction",returns="System.Void"},
    {key="hit_sound",type="app.cCharacterApplyDamage",name="applyHitSound",returns="System.Void"},
},flow={
    {key="first",type="app.cCharacterApplyDamage",name="execFirstDamage",returns="System.Void"},
    {key="second",type="app.cCharacterApplyDamage",name="execSecondDamage",returns="System.Void"},
    {key="third",type="app.cCharacterApplyDamage",name="execThirdDamage",returns="System.Void"},
    {key="enemy_first",type="app.cEnemyApplyDamage",name="execFirstDamage",returns="System.Void"},
    {key="enemy_reaction",type="app.cEnemyApplyDamage",name="applyDamageReaction",returns="System.Void"},
    {key="effect",type="app.cCharacterApplyDamage",name="applyHitEffect",returns="System.Void"},
}}
local function attempt(fn) local ok,v=pcall(fn);if ok then return v end end
local function address(o) return o and o:get_address() end
local function same(a,b) return a~=nil and b~=nil and address(a)==address(b) end
local function typename(o) return o and o:get_type_definition():get_full_name() end
local function get(o,name,...)
    assert(o,"Missing owner for "..name)
    assert(o:get_type_definition():get_method(name),"Missing getter "..name)
    return o:call(name,...)
end
local function exact(o,name) assert(typename(o)==name,"Expected "..name);return o end
local function scalar(v)
    if type(v)=="boolean" or type(v)=="string" then return v end
    if type(v)=="number" and v==v and v>-math.huge and v<math.huge then return v end
end
local function vec(v)
    if not v then return nil end
    local x,y,z=scalar(v.x),scalar(v.y),scalar(v.z)
    if type(x)=="number" and type(y)=="number" and type(z)=="number" then return {x=x,y=y,z=z} end
end
local function error_record(where,err)
    state.errors[#state.errors+1]={frame=state.frame,where=where,error=tostring(err):sub(1,400)}
    if #state.errors>16 then table.remove(state.errors,1) end
end
local function disarm(reason)
    state.armed=false;state.status=reason;state.generation=state.generation+1
end
local function bridge_off()
    local bridge=_G.onimusha_mc
    if not bridge or type(bridge.status)~="function" then return false end
    local n=bridge.status()
    -- host_ready certifies MC takeover (terrain/menu/root-motion), not whether a
    -- native combat callback is safe to observe. Resolve the real player below.
    return n and n.enabled==false
end
local function current_scene()
    local sm=sdk.get_native_singleton("via.SceneManager")
    assert(sm,"No scene manager")
    return assert(sdk.call_native_func(sm,sdk.find_type_definition("via.SceneManager"),"get_CurrentScene"),"No scene")
end
local function resolve_owner()
    assert(bridge_off(),"Keep F10 off in a playable scene")
    local pm=sdk.get_managed_singleton("app.PlayerManager")
    local info=get(pm,"getControllingPlayerInfo")
    assert(get(info,"get_Valid")==true and get(info,"get_CharacterValid")==true
        and get(pm,"isPlayerReady",false)==true,"Player is not ready")
    local player=exact(get(info,"get_Character"),"app.PlayerCharacter")
    local go=exact(get(player,"get_GameObject"),"via.GameObject")
    assert(get(go,"get_Valid")==true,"Invalid player game object")
    local entity=exact(get(get(player,"get_CharacterEntityHolder"),"get_Entity"),"app.cPlayerCharacterEntity")
    assert(same(get(entity,"get_OwnerCharacter"),player),"Entity owner mismatch")
    local damage=exact(entity:get_field("_DamageInterface"),"app.cPlayerApplyDamage")
    local guard=exact(get(entity,"get_PlayerGuardController"),"app.cPlayerGuardController")
    for _,module in ipairs({damage,guard}) do
        assert(get(module,"get_Valid")==true and get(module,"get_IsDestroy")==false
            and same(get(module,"get_OwnerCharacter"),player),"Module owner invalid")
    end
    assert(same(get(damage,"get__PlayerEntity"),entity)
        and same(get(guard,"get_CharacterEntity"),entity),"Module entity mismatch")
    local health=exact(get(get(get(info,"get_Context"),"get_Chara"),"get_HealthManager"),"app.cHealthManager")
    assert(get(health,"get_Health")>0,"Player has no health")
    local scene=current_scene()
    local owner={info=info,player=player,go=go,entity=entity,damage=damage,guard=guard,health=health,scene=scene}
    local ids={}
    for _,key in ipairs({"info","player","go","entity","damage","guard","health","scene"}) do ids[#ids+1]=tostring(address(owner[key])) end
    owner.identity=table.concat(ids,":")
    return owner
end
local function owner_still_valid(o)
    -- Called only after raw-this matched; cached references never replace owner checks.
    return o and state.owner==o and state.owner_frame==state.frame and bridge_off()
        and get(o.go,"get_Valid")==true and get(o.damage,"get_Valid")==true
        and get(o.damage,"get_IsDestroy")==false and get(o.guard,"get_Valid")==true
        and same(get(o.damage,"get_OwnerCharacter"),o.player)
        and same(get(o.entity,"get_OwnerCharacter"),o.player)
        and same(get(get(o.player,"get_CharacterEntityHolder"),"get_Entity"),o.entity)
        and same(o.entity:get_field("_DamageInterface"),o.damage)
end
local function optional_get(o,name)
    return attempt(function() return get(o,name) end)
end
local function position(go)
    if not go or optional_get(go,"get_Valid")~=true then return nil end
    local transform=get(go,"get_Transform")
    return transform and vec(transform:get_position())
end
local function refresh_targets(player_owner)
    local targets={[address(player_owner.damage)]=player_owner}
    player_owner.role="player"
    if state.profile=="flow" then
        local et=sdk.find_type_definition("app.EnemyCharacter")
        local list=get(player_owner.scene,"findComponents(System.Type)",et:get_runtime_type())
        local items=list and list:get_elements() or {}
        for index,enemy in ipairs(items) do
            if index>256 then break end
            local ok,o=pcall(function()
                assert(enemy:get_type_definition():is_a("app.EnemyCharacter"),"Not an enemy")
                local go=exact(get(enemy,"get_GameObject"),"via.GameObject")
                assert(get(go,"get_Valid")==true,"Enemy object invalid")
                local p,origin=position(go),position(player_owner.go)
                assert(p and origin and (p.x-origin.x)^2+(p.y-origin.y)^2+(p.z-origin.z)^2<64^2,"Distant enemy")
                local entity=get(get(enemy,"get_CharacterEntityHolder"),"get_Entity")
                assert(entity:get_type_definition():is_a("app.cEnemyCharacterEntity")
                    and same(get(entity,"get_OwnerCharacter"),enemy),"Enemy entity mismatch")
                local damage=exact(entity:get_field("_DamageInterface"),"app.cEnemyApplyDamage")
                assert(get(damage,"get_Valid")==true and get(damage,"get_IsDestroy")==false
                    and same(get(damage,"get_OwnerCharacter"),enemy),"Enemy damage owner mismatch")
                local health=exact(get(get(get(enemy,"get_Context"),"get_Chara"),"get_HealthManager"),"app.cHealthManager")
                assert(get(health,"get_Health")>0,"Dead enemy")
                return {player=enemy,go=go,entity=entity,damage=damage,health=health,
                    scene=player_owner.scene,role="enemy",name=optional_get(go,"get_Name"),
                    identity=table.concat({tostring(address(enemy)),tostring(address(entity)),
                        tostring(address(damage)),tostring(address(health)),tostring(address(player_owner.scene))},":")}
            end)
            if ok then targets[address(o.damage)]=o end
        end
    end
    state.targets=targets
end
local function target_valid(o)
    if not o then return false end
    if o.role~="enemy" then return owner_still_valid(o) end
    return state.owner and state.owner_frame==state.frame and bridge_off()
        and state.targets and state.targets[address(o.damage)]==o
        and same(current_scene(),o.scene) and get(o.go,"get_Valid")==true
        and get(o.damage,"get_Valid")==true and get(o.damage,"get_IsDestroy")==false
        and same(get(o.damage,"get_OwnerCharacter"),o.player)
        and same(get(o.entity,"get_OwnerCharacter"),o.player)
        and same(get(get(o.player,"get_CharacterEntityHolder"),"get_Entity"),o.entity)
        and same(o.entity:get_field("_DamageInterface"),o.damage)
end
local function reference_param(raw)
    if not state.metadata.param_reference or sdk.to_int64(raw)==0 then return nil end
    -- The conversion alone is a cast in the fixed SDK; validate before using it.
    if sdk.is_managed_object(raw)~=true then return nil end
    local p=sdk.to_managed_object(raw)
    if not p or not p:get_type_definition():is_a(APPLY) then return nil end
    return p
end
local function read_stock_info(param)
    local field=state.stock_info_field
    if not field then return nil end
    local stock=field:get_data(param)
    if not stock or not stock:get_type_definition():is_a("app.cStockDamageInfoCharacter") then return nil end
    local result={type=typename(stock),address=address(stock),scalars={},vectors={},game_objects={}}
    -- Only reflected primitive/vector/GameObject fields of this same-call stock
    -- record. No arbitrary getter traversal or retention of pooled hit objects.
    local scan=stock:get_type_definition();local count=0
    for _=1,6 do
        if not scan then break end
        for _,f in ipairs(scan:get_fields() or {}) do
            if count<80 and not f:is_static() then
                count=count+1
                local name,ft=f:get_name(),f:get_type():get_full_name()
                if ft=="System.Boolean" or ft=="System.Int32" or ft=="System.UInt32" or ft=="System.Single" or ft=="System.Double" then
                    result.scalars[name]=scalar(f:get_data(stock))
                elseif ft=="via.vec3" then result.vectors[name]=vec(f:get_data(stock))
                elseif ft=="via.GameObject" then
                    local go=f:get_data(stock)
                    if go and typename(go)=="via.GameObject" and get(go,"get_Valid")==true then
                        result.game_objects[name]={address=address(go),position=position(go)}
                    end
                elseif ft=="app.cAttackRuntimeParamBase" then
                    local runtime=f:get_data(stock)
                    if runtime and runtime:get_type_definition():is_a(ft) then
                        local rt=runtime:get_type_definition()
                        result.attack_param={type=rt:get_full_name(),address=address(runtime),fields={}}
                        for _=1,4 do
                            if not rt then break end
                            for _,rf in ipairs(rt:get_fields() or {}) do
                                if #result.attack_param.fields<100 and not rf:is_static() then
                                    local rft=rf:get_type():get_full_name()
                                    local entry={name=rf:get_name(),type=rft}
                                    if rft=="System.Boolean" or rft=="System.Int32" or rft=="System.UInt32"
                                        or rft=="System.Single" or rft=="System.Double" then
                                        entry.value=scalar(rf:get_data(runtime))
                                    end
                                    result.attack_param.fields[#result.attack_param.fields+1]=entry
                                end
                            end
                            rt=rt:get_parent_type()
                        end
                    end
                end
            end
        end
        scan=scan:get_parent_type()
    end
    return result
end
local function snapshot(o,param_raw)
    local result={hp=scalar(get(o.health,"get_Health")),max_hp=scalar(get(o.health,"get_MaxHealth")),
        guard=scalar(optional_get(o.guard,"get_IsGuard")),player_position=position(o.go),
        role=o.role or "player",name=o.name,game_object=address(o.go)}
    local arg=optional_get(o.player,"get_ArgumentData")
    result.input_guard=scalar(optional_get(optional_get(arg,"get_Input"),"get_IsGuard"))
    local controller=optional_get(o.info,"get_Controller")
    local input_entity=optional_get(optional_get(controller,"get_MainControllerEntityHolder"),"get_Entity")
    result.command_guard=scalar(optional_get(optional_get(input_entity,"get_CommandResult"),"get_IsGuard"))
    local param=reference_param(param_raw)
    result.param_decoded=param~=nil
    if not param then return result end
    result.param_type=typename(param);result.param_scalars={}
    result.stock_info=read_stock_info(param)
    for _,f in ipairs(state.param_fields or {}) do
        local v=attempt(function() return f:get_data(param) end)
        result.param_scalars[f:get_name()]=scalar(v)
    end
    local battle=optional_get(o.entity,"get_BattleComponent")
    local info=optional_get(battle,"get_DamageInfo")
    local info_param=optional_get(info,"get_ApplyParam")
    result.battle_param_matches=same(info_param,param)==true
    if not result.battle_param_matches then return result end
    result.battle_info_type=typename(info)
    local attacker=optional_get(info,"get_Attacker")
    local attack_obj=optional_get(info,"get_AttackObj")
    result.attacker_address=address(attacker);result.attack_object_address=address(attack_obj)
    result.attacker_position=position(attacker)
    for _,name in ipairs({"HitPosition","AttackVector","VectorToAttacker","AttackerAxisZ"}) do
        result[name]=vec(optional_get(info,"get_"..name))
    end
    for _,name in ipairs({"Damage","HealthDecrease","RikidoDecrease","DamageActionType"}) do
        result[name]=scalar(optional_get(info,"get_"..name))
    end
    local attr=optional_get(info,"get_AttrBit")
    result.attribute_1=scalar(optional_get(attr,"get_Attribute_1_Unique"))
    result.attribute_2=scalar(optional_get(attr,"get_Attribute_2"))
    return result -- no managed object or borrowed parameter is retained
end
local function append(event)
    if #state.events>=256 then disarm("Capture full (256 events)");return end
    state.events[#state.events+1]=event
end
local function install_hooks()
    if state.installed then return end
    assert(not state.install_attempted,"Partial hook install; Reset Scripts is required")
    assert(sdk.get_tdb_version()==82,"Wrong TDB version")
    local param_type=assert(sdk.find_type_definition(APPLY),"Missing cApplyParam")
    state.metadata.param_reference=param_type:is_value_type()==false
        and param_type:is_by_ref()==false and param_type:is_pointer()==false
    state.metadata.param_type=param_type:get_full_name();state.metadata.param_fields={};state.param_fields={}
    local scan=param_type
    for _=1,6 do
        if not scan then break end
        for _,f in ipairs(scan:get_fields() or {}) do
            if #state.metadata.param_fields<80 and not f:is_static() then
                local ft=f:get_type();local name=ft:get_full_name()
                state.metadata.param_fields[#state.metadata.param_fields+1]={name=f:get_name(),type=name}
                if f:get_name()=="DamageInfo" and name=="app.cStockDamageInfoCharacter"
                    and ft:is_value_type()==false and ft:is_by_ref()==false and ft:is_pointer()==false then
                    state.stock_info_field=f
                end
                if name=="System.Boolean" or name=="System.Int32" or name=="System.UInt32"
                    or name=="System.Single" or name=="System.Double" then state.param_fields[#state.param_fields+1]=f end
            end
        end
        scan=scan:get_parent_type()
    end
    local plans,addresses={},{}
    for _,spec in ipairs(assert(profiles[state.profile or "guard"])) do
        local definition=assert(sdk.find_type_definition(spec.type),"Missing "..spec.type)
        local signature=spec.name.."("..APPLY..")"
        local m=assert(definition:get_method(signature),"Missing "..signature)
        assert(not m:is_static() and m:get_num_params()==1 and m:get_param_types()[1]:get_full_name()==APPLY
            and m:get_return_type():get_full_name()==spec.returns
            and m:get_declaring_type():get_full_name()==spec.type,"Hook signature mismatch: "..signature)
        local fn=assert(m:get_function(),"Missing hook implementation")
        local a=sdk.to_int64(fn)
        assert(a>0 and a==math.floor(a) and not addresses[a],"Duplicate/invalid hook address")
        addresses[a]=true
        plans[#plans+1]={method=m,spec=spec,address=a,signature=signature}
    end
    state.install_attempted=true
    for _,plan in ipairs(plans) do
        local spec=plan.spec
        local record={calls=0,owned_calls=0,post_calls=0,address=plan.address,signature=plan.signature}
        state.hooks[spec.key]=record
        local storage_key="onimusha_guard_probe_"..spec.key
        sdk.hook(plan.method,function(args)
            record.calls=record.calls+1
            local ok,err=pcall(function()
                local storage=thread.get_hook_storage();storage[storage_key]=nil
                if not state.armed then return end
                local raw_owner=sdk.to_int64(args[2])
                local o=state.targets and state.targets[raw_owner]
                if not o then return end
                if not target_valid(o) then disarm("Owner/control changed during capture");return end
                local tid=tostring(thread.get_hash())
                local stack=state.stacks[tid] or {};state.stacks[tid]=stack
                assert(#stack<16,"Unexpected hook recursion")
                state.sequence=state.sequence+1
                local param_address=sdk.to_int64(args[3])
                local parent=stack[#stack]
                local token={id=state.sequence,thread=tid,param_address=param_address,frame=state.frame,
                    generation=state.generation,identity=o.identity,method=spec.key,owner=raw_owner}
                if parent and parent.frame==state.frame and parent.generation==state.generation
                    and parent.owner==raw_owner and parent.param_address==param_address then token.parent=parent.id end
                storage[storage_key]=token;stack[#stack+1]=token
                record.owned_calls=record.owned_calls+1
                local event={id=token.id,parent=token.parent,phase="pre",method=spec.key,frame=state.frame,
                    thread=tid,param_address=param_address,owner=address(o.damage),role=o.role,generation=state.generation}
                event.sample=snapshot(o,args[3]);append(event)
            end)
            if not ok then error_record(spec.key.." pre",err);disarm("Probe read failed; original call preserved") end
            -- Always call the original. Never return SKIP_ORIGINAL.
        end,function(retval)
            record.post_calls=record.post_calls+1
            local token
            local ok,err=pcall(function()
                local storage=thread.get_hook_storage();token=storage[storage_key];storage[storage_key]=nil
                if not token then return end
                local stack=state.stacks[token.thread]
                assert(stack and stack[#stack]==token,"Mismatched hook stack")
                table.remove(stack);if #stack==0 then state.stacks[token.thread]=nil end
                local o=state.targets and state.targets[token.owner]
                if not state.armed or token.generation~=state.generation or not o
                    or token.identity~=o.identity or not target_valid(o) then return end
                local event={id=token.id,parent=token.parent,phase="post",method=spec.key,frame=state.frame,
                    thread=token.thread,param_address=token.param_address,owner=token.owner,role=o.role,
                    hp=scalar(get(o.health,"get_Health"))}
                if state.profile=="flow" then event.sample=snapshot(o,sdk.to_ptr(token.param_address)) end
                if spec.returns=="System.Boolean" then event.guard_result=(sdk.to_int64(retval)&0xff)~=0 end
                append(event)
            end)
            if not ok then
                if token then state.stacks[token.thread]=nil end
                error_record(spec.key.." post",err);disarm("Probe post read failed; original return preserved")
            end
            return retval
        end)
    end
    state.installed=true
end
local function read_control()
    local control=attempt(function() return json.load_file(CONTROL) end)
    if type(control)~="table" or control.enabled~=true then
        state.pending_arm_id=nil;if state.armed then disarm("Capture disabled") end;return
    end
    local id=control.arm_id
    if type(id)=="string" and #id>0 and #id<=80 and id~=state.seen_arm_id then
        local profile=control.profile or "guard"
        if not profiles[profile] then state.status="Unknown probe profile";return end
        if state.installed and state.profile~=profile then state.status="Profile changed; Reset Scripts required";return end
        state.profile=profile;state.pending_arm_id=id
    end
end
local function collect_combat_metadata()
    if sdk.get_tdb_version()~=82 then return end
    local roots={"app.cStockDamageInfoCharacter","app.cCharacterApplyDamage.cApplyParam","app.HitInfo",
        "app.cCharacterEntityBase","app.cCharacterStockDamage","app.cCharacterApplyDamage",
        "app.cCharacterApplyDamageAfter","app.cPlayerApplyDamage","app.EnemyCharacter",
        "app.cEnemyCharacterEntity","app.cEnemyApplyDamage","app.CharacterDamageAttribute",
        "app.cAttackRuntimeParamPlayer","app.cAttackRuntimeParamCharacter","app.cAttackRuntimeParamBase",
        "app.cAttackParamDataCharacter","app.cAttackParamDataBase","app.cAttackerDetailInfo",
        "app.BattleInfo.cDamageInfoBase","app.cCharacterApplyDamage.cHitEffectParam",
        "System.Nullable`1<app.AttackVectorDirections.ATTACK_VEC_DIR>",
        "app.AttackVectorDirections.ATTACK_VEC_DIR","app.cAttackParamDataCommon.CALCULATION_TYPE"}
    local report={tdb=82,types={}}
    local function describe(t)
        if not t then return end
        local name=t:get_full_name()
        if report.types[name] then return end
        local entry={name=name,value_type=t:is_value_type(),fields={},methods={}}
        report.types[name]=entry
        local parent=t:get_parent_type();entry.parent=parent and parent:get_full_name()
        for _,f in ipairs(t:get_fields() or {}) do
            if #entry.fields<200 then
                local field={name=f:get_name(),type=f:get_type():get_full_name(),static=f:is_static()}
                if field.static then field.value=scalar(attempt(function() return f:get_data(nil) end)) end
                entry.fields[#entry.fields+1]=field
            end
        end
        for _,m in ipairs(t:get_methods() or {}) do
            if #entry.methods<200 or m:get_name()=="stockDirectDamage" then
                local params={};for _,p in ipairs(m:get_param_types() or {}) do params[#params+1]=p:get_full_name() end
                local method={name=m:get_name(),params=params,returns=m:get_return_type():get_full_name(),static=m:is_static()}
                method.param_names=attempt(function() return m:get_param_names() end)
                if method.name=="stockDirectDamage" or method.name=="duplicate" or method.name=="createRuntimeParam"
                    or method.name=="createDuplicateParam" then
                    method.address=attempt(function() return sdk.to_int64(m:get_function()) end)
                end
                entry.methods[#entry.methods+1]=method
            end
        end
    end
    for _,name in ipairs(roots) do
        local t=sdk.find_type_definition(name)
        if t then
            for _=1,3 do if not t then break end;describe(t);t=t:get_parent_type() end
        else report.types[name]={missing=true} end
    end
    json.dump_file("onimusha_combat_types.json",report)
end
local function frame_tick()
    state.frame=state.frame+1
    if state.frame==1 then
        local ok,err=pcall(collect_combat_metadata)
        if not ok then error_record("metadata",err) end
    end
    if state.frame%30==1 then read_control() end
    if state.armed or state.pending_arm_id then
        local ok,o=pcall(resolve_owner)
        if not ok then
            state.owner=nil;state.stable_frames=0
            if state.armed then disarm("Capture stopped: "..tostring(o)) else state.status=tostring(o):sub(1,240) end
        else
            local unchanged=state.owner and o.identity==state.owner.identity
            if state.armed and not unchanged then disarm("Scene/player owner changed") end
            state.stable_frames=unchanged and state.stable_frames+1 or 1
            state.owner=o;state.owner_frame=state.frame
            if state.profile=="flow" and (not unchanged or state.frame%30==0 or not state.targets) then
                refresh_targets(o)
            else
                state.targets=state.targets or {};o.role="player";state.targets[address(o.damage)]=o
            end
            if state.pending_arm_id and state.stable_frames>=30 and not state.armed then
                local id=state.pending_arm_id;state.pending_arm_id=nil;state.seen_arm_id=id
                install_hooks()
                state.events={};state.errors={};state.generation=state.generation+1
                state.armed=true;state.started_at=os.time();state.status="Armed: "..state.profile..", F10 off"
            end
        end
    end
    if state.armed and os.time()-state.started_at>300 then disarm("Capture timed out (5 minutes)") end
    if state.frame%120==0 then
        json.dump_file(OUTPUT,{schema=1,tdb=sdk.get_tdb_version(),frame=state.frame,armed=state.armed,
            status=state.status,arm_id=state.seen_arm_id,pending_arm_id=state.pending_arm_id,
            owner=state.owner and state.owner.identity,stable_frames=state.stable_frames,
            hooks=state.hooks,metadata=state.metadata,events=state.events,errors=state.errors,
            installed=state.installed==true,read_only=true,profile=state.profile})
    end
end
re.on_application_entry("LateUpdateBehavior",function()
    local ok,err=pcall(frame_tick)
    if not ok then error_record("frame",err);disarm("Probe stopped: "..tostring(err):sub(1,200)) end
end)
re.on_script_reset(function() disarm("Script reset");state.owner=nil;state.stacks={} end)
re.on_draw_ui(function()
    if imgui.tree_node("Onimusha natural guard probe (read only)") then
        imgui.text(state.status);imgui.text("Samples: "..#state.events.." / 256. F10 must remain off.")
        imgui.tree_pop()
    end
end)
