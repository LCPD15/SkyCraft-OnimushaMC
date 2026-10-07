-- OnimushaWotS 01.000.001 / TDB82: generic native enemy damage.
-- Two player attack assets shared by EVERY enemy, independent of enemy name.
-- The native entity enqueues exactly once. Never add a second HP write afterward.
-- MOD制作：LCPD15/LCPD拉灯
local CONTROL='onimusha_enemy_hit_control.json'
local OUTPUT='onimusha_enemy_hit_status.json'
local APPLY='app.cCharacterApplyDamage.cApplyParam'
local RUNTIME='app.cAttackRuntimeParamPlayer'
local NULLDIR='System.Nullable`1<app.AttackVectorDirections.ATTACK_VEC_DIR>'
local NULLVEC='System.Nullable`1<via.vec3>'
local DIRECT='stockDirectDamage(via.GameObject, via.GameObject, app.cAttackRuntimeParamBase, via.vec3, '..
    NULLDIR..', '..NULLVEC..', '..NULLVEC..', '..NULLVEC..', '..NULLVEC..', app.CharacterDef.PARTS_INDEX, via.GameObject)'
local s={frame=0,mode='off',events={},errors={},metadata={},pending={},hooks={},trial_remaining=0,
    templates={},capture_info={},captured_ids={},selected={}}
-- Matched to the user's natural-hit captures through the current player's
-- owned asset list (IDs 1 and 41). These are asset IDs, never memory addresses.
local PROFILES={
    {id=1,attack=100,rikido=150,armor=75,flags=0},
    {id=41,attack=300,rikido=450,armor=300,flags=81922},
}
local function typ(o) return o and o:get_type_definition():get_full_name() end
local function addr(o) return o and o:get_address() end
local function same(a,b) return a~=nil and b~=nil and addr(a)==addr(b) end
local function get(o,n,...)
    assert(o and o:get_type_definition():get_method(n),'Missing '..tostring(typ(o))..'.'..n)
    return o:call(n,...)
end
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function exact(o,n) assert(typ(o)==n,'Expected '..n);return o end
local function record(event)
    event.frame=s.frame;s.events[#s.events+1]=event
    if #s.events>64 then table.remove(s.events,1) end
end
local function failure(where,e)
    s.errors[#s.errors+1]={frame=s.frame,where=where,error=tostring(e):sub(1,700)}
    if #s.errors>16 then table.remove(s.errors,1) end
    s.ready=false;s.trial_remaining=0
    if s.mode~='enabled' then s.mode='held' end
end
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),
        sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function resolve_player()
    local pm=sdk.get_managed_singleton('app.PlayerManager')
    assert(get(pm,'isPlayerReady',false)==true,'Player not ready')
    local info=get(pm,'getControllingPlayerInfo')
    assert(get(info,'get_Valid')==true and get(info,'get_CharacterValid')==true,'Player unavailable')
    local player=exact(get(info,'get_Character'),'app.PlayerCharacter')
    local go=exact(get(player,'get_GameObject'),'via.GameObject')
    local entity=exact(get(get(player,'get_CharacterEntityHolder'),'get_Entity'),'app.cPlayerCharacterEntity')
    assert(get(go,'get_Valid')==true and same(get(entity,'get_OwnerCharacter'),player),'Player owner mismatch')
    local sc=assert(scene(),'Scene unavailable')
    return {player=player,go=go,entity=entity,scene=sc,
        identity=table.concat({addr(player),addr(go),addr(entity),addr(sc)},':')}
end
local function clone(runtime)
    exact(runtime,RUNTIME)
    local copy=exact(get(runtime,'duplicate()'),RUNTIME)
    assert(not same(copy,runtime),'Native duplicate returned original')
    copy:add_ref() -- Lua-owned wrapper; GC releases our retained reference.
    assert(same(get(copy,'get_OriginData'),get(runtime,'get_OriginData')),'Duplicate lost origin asset')
    return copy
end
local function resolve_profiles(p)
    local supporter=get(p.entity,'get_AttackParamSupporter')
    local asset=assert(supporter:get_field('_AttackParamData'),'Player attack asset unavailable')
    local items=assert(asset:get_field('_AttackParamListItems')):get_elements()
    assert(#items<=2048,'Unexpected attack asset size')
    local found={}
    for _,item in ipairs(items) do
        local id=item:get_field('_ID')
        for i,want in ipairs(PROFILES) do
            if id==want.id then
                assert(not found[i],'Duplicate player attack asset ID')
                local data=exact(item:get_field('_AttackParam'),'app.cAttackParamDataPlayer')
                assert(data:get_field('_Attack')==want.attack and data:get_field('_RikidoAttack')==want.rikido
                    and data:get_field('_ArmorAttack')==want.armor and data:get_field('_PlayerFlagBit')==want.flags
                    and data:get_field('<PercentageDamageType>k__BackingField')==0,
                    'Player attack asset fingerprint changed; game adapter update required')
                found[i]={asset=data,id=id}
            end
        end
    end
    assert(found[1] and found[2],'The two shared player attack assets are not loaded')
    local weapons=get(p.entity,'get_Weapon'):get_field('_WeaponDataList')
    local count=weapons:get_field('_size');assert(count>=0 and count<=64,'Unexpected weapon list size')
    local list=weapons:get_field('_items');local weapon
    for i=0,count-1 do
        local item=list:get_element(i)
        -- The captured attack object is the player's base sword, shared by both
        -- profiles. Resolve it through its live owner, never a retained pointer.
        if item and typ(item:get_field('WeaponGimmick'))=='app.Gm800_000' then
            local go=item:get_field('<WeaponGimmickGameObj>k__BackingField')
            if go and get(go,'get_Valid')==true then weapon=go;break end
        end
    end
    assert(weapon,'Player base sword object unavailable')
    s.profile_info={{id=PROFILES[1].id},{id=PROFILES[2].id}};s.ready=true
    return found,weapon
end
local function create_runtime(asset)
    local runtime=exact(get(asset,'createRuntimeParam()'),RUNTIME)
    runtime:add_ref()
    assert(same(get(runtime,'get_OriginData'),asset),'Runtime factory lost attack origin')
    return runtime
end
local function decode(args)
    if sdk.is_managed_object(args[2])~=true or sdk.is_managed_object(args[3])~=true then return end
    local damage=sdk.to_managed_object(args[2])
    assert(damage and damage:get_type_definition():is_a('app.cEnemyApplyDamage'),'Not an enemy damage module')
    if get(damage,'get_Valid')~=true or get(damage,'get_IsDestroy')~=false then return end
    local owner=get(damage,'get_OwnerCharacter')
    assert(owner and owner:get_type_definition():is_a('app.EnemyCharacter'),'Not an enemy owner')
    local go=get(owner,'get_GameObject')
    assert(get(go,'get_Valid')==true,'Enemy no longer valid')
    local entity=get(get(owner,'get_CharacterEntityHolder'),'get_Entity')
    assert(same(entity:get_field('_DamageInterface'),damage) and same(get(entity,'get_OwnerCharacter'),owner),
        'Enemy module owner changed')
    local param=exact(sdk.to_managed_object(args[3]),APPLY)
    local stock=exact(param:get_field('DamageInfo'),'app.cStockDamageInfoCharacter')
    assert(same(get(stock,'get_Receiver'),go),'Damage receiver mismatch')
    return {damage=damage,owner=owner,go=go,entity=entity,param=param,stock=stock,
        runtime=get(stock,'get_AttackParamData')}
end
local function describe_type(name)
    local t=sdk.find_type_definition(name)
    if not t then return {missing=true} end
    local out={name=name,value_type=t:is_value_type(),fields={},methods={}}
    for _,f in ipairs(t:get_fields() or {}) do
        out.fields[#out.fields+1]={name=f:get_name(),type=f:get_type():get_full_name(),offset=f:get_offset_from_base()}
    end
    for _,m in ipairs(t:get_methods() or {}) do
        if m:get_name():match('Damage') or m:get_name():match('Attack') or m:get_name():match('duplicate')
            or m:get_name():match('Runtime') or m:get_name():match('Rumtime') then
            local p={};for _,pt in ipairs(m:get_param_types() or {}) do p[#p+1]=pt:get_full_name() end
            out.methods[#out.methods+1]={name=m:get_name(),params=p,returns=m:get_return_type():get_full_name(),
                address=sdk.to_int64(m:get_function())}
        end
    end
    return out
end
local function capture(d)
    if s.mode~='capture' or #s.templates>=8 then return end
    local bridge=_G.onimusha_mc
    if not bridge or bridge.status().enabled~=false then return end
    local p=resolve_player()
    if not same(get(d.stock,'get_Attacker'),p.go) or typ(d.runtime)~=RUNTIME then return end
    local uid=d.param:get_field('UniqueID')
    local key=tostring(addr(d.go))..':'..tostring(uid)
    if s.captured_ids[key] then return end
    local weapon=get(d.stock,'get_AttackObj')
    assert(weapon and get(weapon,'get_Valid')==true,'Missing ordinary attack object')
    local copied=clone(d.runtime)
    local index=#s.templates+1
    s.templates[index]={runtime=copied,weapon=weapon,owner_identity=p.identity}
    s.captured_ids[key]=index
    local info={index=index,uid=uid,frame=s.frame,owner=p.identity,runtime=typ(copied),
        attack=get(copied,'get_Attack'),fixed_attack=get(copied,'get_FixedAttack'),
        rikido=get(copied,'get_RikidoAttack'),break_attack=get(copied,'get_BreakAttack'),
        weapon=addr(weapon),origin=typ(get(copied,'get_OriginData')),
        origin_address=addr(get(copied,'get_OriginData')),independent_copy=true}
    s.capture_info[index]=info
    record({kind='template_captured',info=info})
end
local function hook(spec)
    local td=assert(sdk.find_type_definition(spec.type))
    local m=assert(td:get_method(spec.name..'('..APPLY..')'))
    assert(m:get_declaring_type():get_full_name()==spec.type and m:get_num_params()==1
        and not m:is_static() and m:get_return_type():get_full_name()=='System.Void','Wrong hook signature')
    s.hooks[spec.name]={address=sdk.to_int64(m:get_function()),matched=0}
    sdk.hook(m,function(args)
        local storage=thread.get_hook_storage();storage.onimusha_enemy_hit=nil
        if s.mode~='capture' and next(s.pending)==nil then return end
        local ok,e=pcall(function()
            -- A base effect callback also serves the player: check its actual
            -- damage-module type before decode, without treating it as an error.
            if sdk.is_managed_object(args[2])~=true then return end
            if not sdk.to_managed_object(args[2]):get_type_definition():is_a('app.cEnemyApplyDamage') then return end
            local d=decode(args);if not d then return end
            if spec.name=='execFirstDamage' then capture(d) end
            if s.mode=='capture' then
                local index=s.captured_ids[tostring(addr(d.go))..':'..tostring(d.param:get_field('UniqueID'))]
                if index then record({kind='captured_native_stage',index=index,method=spec.name,
                    health_decrease=d.param:get_field('HealthDecrease'),damage=d.param:get_field('Damage'),
                    reaction=d.param:get_field('ReactionType'),rikido_decrease=d.param:get_field('RikidoDecrease')}) end
            end
            local pending=s.pending[addr(d.runtime)]
            if not pending or pending.stock~=addr(d.stock) or pending.target~=addr(d.go) then return end
            s.hooks[spec.name].matched=s.hooks[spec.name].matched+1
            local health=get(get(get(d.owner,'get_Context'),'get_Chara'),'get_HealthManager')
            storage.onimusha_enemy_hit={runtime=addr(d.runtime),stock=addr(d.stock),target=addr(d.go),
                method=spec.name,health=health,frame=s.frame}
            record({kind='native_pre',method=spec.name,hit=pending.hit,
                hp=get(health,'get_Health'),attack=get(d.stock,'get_Attack'),fixed_attack=get(d.stock,'get_FixedDamageAttack')})
        end)
        if not ok then failure('hook '..spec.name,e) end
    end,function(ret)
        local storage=thread.get_hook_storage();local token=storage.onimusha_enemy_hit
        storage.onimusha_enemy_hit=nil
        if token then
            local ok,e=pcall(function()
                local pending=s.pending[token.runtime]
                if pending and pending.stock==token.stock and token.frame==s.frame then
                    record({kind='native_post',method=token.method,hit=pending.hit,hp=get(token.health,'get_Health')})
                    pending.observed=true
                end
            end)
            if not ok then failure('post '..spec.name,e) end
        end
        return ret
    end)
end
local function initialize()
    assert(sdk.get_tdb_version()==82,'Only verified Onimusha TDB82 is supported')
    assert(sdk.find_type_definition(APPLY):is_value_type()==false,'cApplyParam must be a reference')
    for _,name in ipairs({'app.cCharacterApplyDamage','app.cEnemyApplyDamage','app.cCharacterEntityBase',
        'app.cStockDamageInfoBase','app.cStockDamageInfoCharacter','app.cAttackRuntimeParamCharacter',
        'app.cAttackParamDataPlayer','app.cCharacterAttackInfo','app.cCharacterAttackParamSupporter'}) do
        s.metadata[name]=describe_type(name)
    end
    for _,spec in ipairs({
        {type='app.cEnemyApplyDamage',name='execFirstDamage'},
        {type='app.cEnemyApplyDamage',name='execThirdDamage'},
        {type='app.cCharacterApplyDamage',name='applyHitEffect'},
        {type='app.cCharacterApplyDamage',name='applyHitSound'},
    }) do hook(spec) end
    assert(sdk.find_type_definition('app.cCharacterEntityBase'):get_method(DIRECT),'Missing exact native enqueue overload')
    s.initialized=true
end
local function nullable(name)
    local v=ValueType.new(assert(sdk.find_type_definition(name)))
    v:set_field('_HasValue',false)
    assert(v:get_field('_HasValue')==false,'Nullable must be empty')
    return v
end
local function queue(entry,bridge_state,damage,trace)
    -- Production requires this route; an unavailable/off module reports not ready.
    -- The legacy single-hit trial remains diagnostic only. Never retry or add
    -- a direct-health write after enqueue could have run.
    if s.mode~='trial' and s.mode~='enabled' and s.mode~='held' then return false end
    trace.native_route=true
    if s.mode=='held' then trace.outcome='rejected';trace.reason='native_profiles_unavailable';return true end
    if s.mode=='trial' then
        if s.trial_remaining<=0 then trace.outcome='rejected';trace.reason='native_trial_budget_exhausted';return true end
        s.trial_remaining=s.trial_remaining-1
    end
    local attempted=false
    local ok,e=pcall(function()
        assert(s.initialized,'Native damage module not initialized')
        assert(bridge_state.active and finite(damage) and damage>0 and damage<=100000,'Invalid native hit request')
        local p=resolve_player()
        assert(same(p.player,bridge_state.player) and same(p.go,bridge_state.player_go),'Bridge player mismatch')
        local template_index,weapon,runtime
        if s.mode=='enabled' then
            local profiles;profiles,weapon=resolve_profiles(p)
            template_index=math.random(#profiles)
            runtime=create_runtime(profiles[template_index].asset)
            trace.native_profile_id=profiles[template_index].id
        else
            assert(#s.selected>0,'No prepared generic hit templates')
            template_index=s.selected[math.random(#s.selected)]
            local template=assert(s.templates[template_index],'Selected hit template missing')
            assert(template.owner_identity==p.identity,'Template owner/scene changed')
            weapon=template.weapon;runtime=clone(template.runtime)
        end
        trace.native_template=template_index
        assert(get(weapon,'get_Valid')==true,'Template weapon unloaded')
        local go=get(entry.obj,'get_GameObject');assert(get(go,'get_Valid')==true,'Target unloaded')
        local entity=get(get(entry.obj,'get_CharacterEntityHolder'),'get_Entity')
        assert(same(get(entity,'get_OwnerCharacter'),entry.obj),'Target entity changed')
        local target_health=get(get(get(entry.obj,'get_Context'),'get_Chara'),'get_HealthManager')
        assert(same(target_health,entry.health) and get(target_health,'get_Health')>0,'Target health changed/dead')
        local module=assert(entity:get_field('_DamageInterface'))
        assert(module:get_type_definition():is_a('app.cEnemyApplyDamage'),'Not an enemy damage module')
        assert(get(module,'get_Valid')==true and get(module,'get_IsDestroy')==false,'Target damage module invalid')
        get(runtime,'set_Attack',0.0);get(runtime,'set_FixedAttack',damage)
        -- Keep the randomly selected shared reaction profile. Native defenses,
        -- guard and armor decide the response; no forced animation/effect IDs.
        local pos=get(go,'get_Transform'):get_position()
        local origin=get(p.go,'get_Transform'):get_position()
        assert(finite(pos.x) and finite(pos.y) and finite(pos.z),'Invalid target position')
        local height=math.max(0.5,math.min(4,entry.height or 1.8))
        local hitpos=Vector3f.new(pos.x,pos.y+height*0.6,pos.z)
        local distance_sq=(pos.x-origin.x)^2+(pos.y-origin.y)^2+(pos.z-origin.z)^2
        local bounds=entry.bounds_native
        if bounds then
            distance_sq=0
            for _,axis in ipairs({'x','y','z'}) do
                local lo,hi=bounds.min[axis],bounds.max[axis]
                assert(finite(lo) and finite(hi) and hi>=lo and hi-lo<=64
                    and math.abs((lo+hi)*0.5-pos[axis])<=32,'Invalid target damage bounds')
                local closest=math.max(lo,math.min(hi,origin[axis]))
                distance_sq=distance_sq+(closest-origin[axis])^2
            end
            -- Actor roots are not necessarily at the feet (e.g. flying enemies).
            -- Use current native damage bounds for the effect point and range.
            hitpos=Vector3f.new((bounds.min.x+bounds.max.x)*0.5,
                bounds.min.y+(bounds.max.y-bounds.min.y)*0.6,(bounds.min.z+bounds.max.z)*0.5)
        end
        -- Minecraft already resolves reach/projectile impact. Keep the extra
        -- stale-proxy distance guard, but do not apply a melee limit to arrows.
        -- HIT_PROJECTILE=2 / HIT_FIRE=8 in the shared protocol; no enemy rules.
        local flags=trace.flags or 0
        assert(finite(flags) and flags>=0 and flags<=4294967295 and flags==math.floor(flags),'Invalid hit flags')
        local indirect=(flags & 58)~=0 -- projectile 2, fire 8, explosion 16, MC mob 32
        local max_distance=indirect and 128 or 10
        trace.native_distance=math.sqrt(distance_sq);trace.native_range=max_distance
        if distance_sq>max_distance*max_distance then
            trace.outcome='rejected';trace.reason='native_hit_out_of_range';return
        end
        trace.native_hit_position={x=hitpos.x,y=hitpos.y,z=hitpos.z}
        trace.native_bounds_source=bounds and bounds.source or 'movement_capsule'
        local dir=nullable(NULLDIR);local av=nullable(NULLVEC);local normal=nullable(NULLVEC)
        local ap=nullable(NULLVEC);local az=nullable(NULLVEC)
        trace.before=get(target_health,'get_Health');trace.requested_damage=damage
        attempted=true
        local stock=get(entity,DIRECT,p.go,weapon,runtime,hitpos,dir,av,normal,ap,az,0,nil)
        if not stock then trace.outcome='rejected';trace.reason='native_enqueue_returned_nil';return end
        exact(stock,'app.cStockDamageInfoCharacter')
        assert(same(get(stock,'get_Receiver'),go) and same(get(stock,'get_Attacker'),p.go)
            and same(get(stock,'get_AttackParamData'),runtime),'Native returned unexpected hit identity')
        s.sequence=(s.sequence or 0)+1
        s.pending[addr(runtime)]={runtime=runtime,stock=addr(stock),target=addr(go),health=target_health,
            before=trace.before,hit=s.sequence,frame=s.frame,owner=p.identity}
        trace.outcome='queued_native';trace.native_hit=s.sequence
        record({kind='queued',hit=s.sequence,target=entry.id,before=trace.before,requested=damage,
            template=template_index,stock_attack=get(stock,'get_Attack'),stock_fixed_attack=get(stock,'get_FixedDamageAttack')})
    end)
    if not ok then
        trace.outcome=attempted and 'native_unconfirmed' or 'rejected'
        trace.reason=attempted and 'enqueue_result_unknown_no_retry' or 'native_preflight_failed'
        trace.error=tostring(e):sub(1,700);failure('queue',e)
        -- Hold trial routing after failure so subsequent clicks cannot silently
        -- switch back to direct health writes during a controlled live test.
        if s.mode~='enabled' then s.mode='trial';s.trial_remaining=0 end
    end
    return true
end
_G.onimusha_enemy_hit={queue=queue,busy=function()
    return next(s.pending)~=nil or (_G.onimusha_explosion and _G.onimusha_explosion.busy())
end}
local function tick()
    s.frame=s.frame+1
    if s.frame==1 then initialize() end
    if s.frame%30==1 then
        local c=json.load_file(CONTROL) or {}
        if c.mode=='off' then s.mode='off';s.trial_remaining=0 end
        if type(c.id)=='string' and c.id~=s.control_id and s.initialized then
            s.control_id=c.id
            if c.mode=='capture' then
                s.templates={};s.capture_info={};s.captured_ids={};s.selected={};s.mode='capture';s.capture_frame=s.frame
            elseif c.mode=='enabled' then s.mode='enabled';s.ready=false
            elseif c.mode=='trial' then
                s.mode='held' -- missing volatile templates must never reopen direct-HP fallback
                local chosen={}
                for _,index in ipairs(c.templates or {}) do
                    assert(type(index)=='number' and index==math.floor(index) and s.templates[index],'Invalid selected template')
                    chosen[#chosen+1]=index
                end
                assert(#chosen>=1 and #chosen<=2,'Select one or two generic hit templates')
                s.selected=chosen;s.mode='trial';s.trial_remaining=1
            elseif c.mode=='prepared' then s.mode='prepared' end
        end
    end
    if s.mode=='enabled' and s.frame%120==1 then
        local ok,err=pcall(function() resolve_profiles(resolve_player()) end)
        s.ready=ok;s.prepare_error=not ok and tostring(err):sub(1,700) or nil
    end
    if s.mode=='capture' and s.frame-(s.capture_frame or s.frame)>18000 then s.mode='off' end
    for key,p in pairs(s.pending) do
        if s.frame-p.frame>120 then
            local ok,hp=pcall(function() return get(p.health,'get_Health') end)
            record({kind='settled_sample',hit=p.hit,before=p.before,after=ok and hp or nil,observed=p.observed==true})
            s.pending[key]=nil
        end
    end
    if s.frame%60==0 then
        json.dump_file(OUTPUT,{frame=s.frame,mode=s.mode,initialized=s.initialized==true,
            templates=s.capture_info,selected=s.selected,events=s.events,errors=s.errors,metadata=s.metadata,hooks=s.hooks,
            control_id=s.control_id,trial_remaining=s.trial_remaining,ready=s.ready==true,
            profiles=s.profile_info,prepare_error=s.prepare_error})
    end
end
re.on_application_entry('LateUpdateBehavior',function()
    local ok,e=pcall(tick);if not ok then failure('frame',e) end
end)
re.on_script_reset(function() s.mode='off';s.templates={};s.pending={};_G.onimusha_enemy_hit=nil end)

-- BEGIN NATIVE EXPLOSION: TDB82 Gm019_000 oil-barrel sample, 2026-10-07.
-- Separate scope, bundled here so the existing transactional loader owns it.
do
local X={frame=0,ready=false,events={},seen={},shells={},mode='off'}
local BASE='GameDesign/Gimmick/Gm019/Gm019_000/Shell/'
local SHOOT='shootShell(System.Int32, ace.cShellShootingInfoBase, System.Action`1<ace.ShellBase>)'
local function xcall(o,n,...) assert(o and o:get_type_definition():get_method(n),'Missing '..n);return o:call(n,...) end
local function xtyp(o) return o and o:get_type_definition():get_full_name() end
local function xaddr(o) return o and o:get_address() end
local function xfinite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function xrecord(r)
    r.frame=X.frame;X.events[#X.events+1]=r;if #X.events>64 then table.remove(X.events,1) end
end
local function xscene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function xnew(t,ctor,...)
    local o=assert(sdk.create_instance(t),'Allocate '..t);o:add_ref();xcall(o,ctor,...);return o
end
local function xnullable(t,v)
    local n=ValueType.new(assert(sdk.find_type_definition('System.Nullable`1<'..t..'>')))
    n:set_field('_HasValue',v~=nil);if v~=nil then n:set_field('_Value',v) end;return n
end
local function shooting(position)
    local info=xnew('app.cShellShootingInfo','.ctor(ace.user_data.ShellCreatorInfoDataBase.ShellCreatorInfoBase)',X.creator)
    -- Fresh values from the sample; no retained callback, shooting-info or address.
    xcall(info,'set_StartPos',xnullable('via.vec3',position))
    xcall(info,'set_TargetPos',xnullable('via.vec3',position))
    xcall(info,'set_StartRot',xnullable('via.Quaternion',Quaternion.new(0,0,0,1)))
    xcall(info,'set_StartMoveDir',xnullable('via.vec3',Vector3f.new(0,0,0)))
    xcall(info,'set_TransformOwner',X.owner)
    xcall(info,'set_StartTerrainCheckDestroy',true)
    xcall(info,'set_ShellGroupNo',-1);xcall(info,'set_SwitchIndex',-1);xcall(info,'set_HitGroup',0)
    assert(info:get_field('OwnerAttachType')==1,'Expected SHOOT_ONLY, not continuous attachment')
    return info
end
local function prepare(player,epoch)
    assert(sdk.get_tdb_version()==82,'Only Onimusha TDB82')
    local sc=assert(xscene());local go=xcall(player,'get_GameObject')
    assert(xcall(go,'get_Valid')==true,'Invalid owner')
    local key=tostring(xaddr(sc))..':'..tostring(xaddr(go))..':'..tostring(epoch)
    if X.identity==key and X.controller then return true end
    X.ready=false;X.controller=nil;X.identity=nil;X.owner=nil;X.seen={};X.shells={}
    local items=xcall(sc,'findComponents(System.Type)',sdk.find_type_definition('app.Gm019_000'):get_runtime_type()):get_elements()
    local data
    for _,gm in ipairs(items) do
        local mini=gm:get_field('_McGimmickCreateShell')
        local param=mini and mini:get_field('_Param')
        local candidate=param and param:get_field('_ShellInfoData')
        if candidate and xcall(candidate,'get_Path')==BASE..'Gm019_000_ShellCreatorInfo.user' then data=candidate;break end
    end
    if not data then
        data=X.loaded_asset or sdk.create_userdata('ace.user_data.ShellCreatorInfoData',BASE..'Gm019_000_ShellCreatorInfo.user')
        if data then data:add_ref();X.loaded_asset=data end
    end
    assert(data,'Captured oil-barrel asset unavailable')
    local list=data:get_field('_ShellList')
    assert(xcall(list,'get_Path')==BASE..'Gm019_000_ShellList.user','Wrong shell list')
    local creator=xcall(data,'getCreatorInfoWithUniqueID',4)
    assert(creator and xcall(creator,'get_ShellFixedID')==6 and xcall(creator,'get_OwnerAttachType')==1,'Barrel mapping changed')
    local function package_by_id(id)
        -- getShellPackage takes a list INDEX in this build, not the fixed ID.
        local entries=list:get_field('_DataList');local a=entries:get_field('_items')
        for i=0,entries:get_field('_size')-1 do
            local item=a:get_element(i)
            if item:get_field('_FixedID')==id then return item:get_field('_ShellPackage') end
        end
        error('Missing fixed shell ID '..id)
    end
    local package=package_by_id(6)
    assert(package:get_field('_ShellNameHash')==3230905416,'Main shell fingerprint changed')
    assert(xcall(package:get_field('_MainParam'),'get_Path')==BASE..'shl_g019_000_004/shl_g019_000_004_MainParam.user','Wrong main asset')
    -- Native explosion owns RE enemy/gimmick hits. The MC host's self damage is
    -- still computed by MC; both native damaging children exclude their owner.
    for _,id in ipairs({0,1}) do
        local pk=package_by_id(id)
        local entries=pk:get_field('_MainParam'):get_field('_ShellMiniParams')
        local a=entries:get_field('_items');local found=false
        for i=0,entries:get_field('_size')-1 do
            local m=a:get_element(i)
            if xtyp(m)=='app.cShellminiParamColHit' then
                assert(m:get_field('_EnableSelfDamage')==false,'Native self-damage would double MC damage');found=true
            end
        end
        assert(found,'Missing native damaging child')
    end
    data:add_ref();list:add_ref();creator:add_ref();go:add_ref()
    local controller=xnew('ace.cShellCreateController','.ctor()')
    xcall(controller,'setup(via.GameObject)',go)
    xcall(controller,'registerShellList(ace.user_data.ShellList)',list)
    X.owner=go;X.controller=controller;X.creator=creator;X.asset=data;X.list=list
    X.identity=key;X.epoch=epoch
    shooting(Vector3f.new(0,0,0)) -- preflight constructor/setters only; never fires.
    X.ready=true;X.error=nil
    xrecord({kind='prepared',asset=BASE..'Gm019_000_ShellList.user',fixed_id=6,epoch=epoch})
    return true
end
local function refresh(player,epoch)
    if X.mode~='enabled' then return false end
    if X.frame%120~=1 and X.last_player==xaddr(player) and X.last_epoch==epoch then return X.ready end
    X.last_player=xaddr(player);X.last_epoch=epoch
    local ok,err=pcall(prepare,player,epoch)
    if not ok then X.ready=false;X.controller=nil;X.identity=nil;X.error=tostring(err):sub(1,700) end
    return X.ready
end
local function queue(event,bridge_state,position)
    local r={kind='explosion',id=event.form_id,epoch=event.weapon,radius=event.d,
        mc={x=event.a,y=event.b,z=event.c},native={x=position.x,y=position.y,z=position.z},outcome='rejected'}
    local attempted=false
    local ok,err=pcall(function()
        assert(X.mode=='enabled' and X.ready and bridge_state.active,'Explosion route unavailable')
        assert(event.weapon==bridge_state.epoch and event.weapon==X.epoch and event.flags==1,'Stale/legacy explosion')
        assert(xfinite(event.form_id) and event.form_id>0 and event.form_id==math.floor(event.form_id),'Invalid explosion ID')
        assert(xfinite(event.d) and event.d>0 and event.d<=32,'Unsupported explosion radius')
        assert(xfinite(position.x) and xfinite(position.y) and xfinite(position.z),'Nonfinite explosion position')
        local p=bridge_state.transform:get_position()
        assert((position.x-p.x)^2+(position.y-p.y)^2+(position.z-p.z)^2<=128^2,'Explosion too far from active player')
        assert(xaddr(xcall(bridge_state.player,'get_GameObject'))==xaddr(X.owner) and xcall(X.owner,'get_Valid')==true,'Owner changed')
        assert(X.identity==tostring(xaddr(xscene()))..':'..tostring(xaddr(X.owner))..':'..tostring(X.epoch),'Scene changed')
        assert(not X.seen[event.form_id],'Duplicate explosion ID')
        local info=shooting(position)
        -- Mark BEFORE the native call. An ambiguous result must not be retried.
        X.seen[event.form_id]=X.frame;X.last_shot=X.frame;attempted=true
        local shell=xcall(X.controller,SHOOT,6,info,nil)
        assert(shell,'Native shell pool returned no shell')
        local go=xcall(shell,'get_GameObject')
        r.name=xcall(go,'get_Name');r.owner=xaddr(xcall(shell,'get_ShellOwner'))
        local pos=xcall(go,'get_Transform'):get_position();r.spawned={x=pos.x,y=pos.y,z=pos.z}
        r.outcome='spawned';X.busy_until=X.frame+180
        xrecord(r)
    end)
    if not ok then
        r.error=tostring(err):sub(1,700);r.outcome=attempted and 'unknown_no_retry' or 'rejected'
        if attempted then X.ready=false;X.error=r.error;X.busy_until=X.frame+180 end
        xrecord(r)
    end
    return ok
end
_G.onimusha_explosion={refresh=refresh,queue=queue,busy=function() return X.frame<(X.busy_until or 0) end}
local function observe_damage()
    for _,spec in ipairs({{'app.cEnemyApplyDamage','execFirstDamage'}, {'app.cEnemyApplyDamage','execThirdDamage'},
        {'app.cCharacterApplyDamage','applyHitEffect'}, {'app.cCharacterApplyDamage','applyHitSound'}}) do
        local key='onimusha_explosion:'..spec[1]..'.'..spec[2]
        local method=assert(sdk.find_type_definition(spec[1]):get_method(spec[2]..'(app.cCharacterApplyDamage.cApplyParam)'))
        sdk.hook(method,function(args)
            thread.get_hook_storage()[key]=nil
            if not X.owner or X.frame>=(X.busy_until or 0) then return end
            local ok,err=pcall(function()
                if not sdk.is_managed_object(args[3]) then return end
                local param=sdk.to_managed_object(args[3]);local stock=param:get_field('DamageInfo')
                if not stock or xaddr(xcall(stock,'get_Attacker'))~=xaddr(X.owner) then return end
                local attack=xcall(stock,'get_AttackObj')
                local name=attack and xcall(attack,'get_Name')
                if type(name)~='string' or not name:match('^shl_g019_000_') then return end
                local damage=sdk.to_managed_object(args[2]);local owner=xcall(damage,'get_OwnerCharacter')
                local hp=xcall(xcall(xcall(owner,'get_Context'),'get_Chara'),'get_HealthManager')
                local r={kind='native_damage',phase=spec[2],shell=name,target=xcall(xcall(owner,'get_GameObject'),'get_Name'),
                    before=xcall(hp,'get_Health'),health_decrease=param:get_field('HealthDecrease')}
                thread.get_hook_storage()[key]={r=r,hp=hp}
            end)
            if not ok then xrecord({kind='observation_error',error=tostring(err):sub(1,500)}) end
        end,function(ret)
            local t=thread.get_hook_storage()[key];thread.get_hook_storage()[key]=nil
            if t then
                local ok,hp=pcall(xcall,t.hp,'get_Health');t.r.after=ok and hp or nil;xrecord(t.r)
            end
            return ret
        end)
    end
end
re.on_application_entry('LateUpdateBehavior',function()
    X.frame=X.frame+1
    if X.frame==1 then
        local ok,err=pcall(observe_damage);if not ok then xrecord({kind='observation_setup_error',error=tostring(err)}) end
    end
    if X.frame%30==1 then
        local c=json.load_file('onimusha_explosion_control.json') or {}
        X.mode=c.enabled==true and 'enabled' or 'off';if X.mode=='off' then X.ready=false end
        for id,frame in pairs(X.seen) do if X.frame-frame>3600 then X.seen[id]=nil end end
        json.dump_file('onimusha_explosion_status.json',{frame=X.frame,mode=X.mode,ready=X.ready,error=X.error,
            epoch=X.epoch,events=X.events,damage_policy='native enemies/gimmicks; MC player and blocks',radius_policy='stock oil barrel'})
    end
end)
re.on_script_reset(function() X.ready=false;X.mode='off';X.controller=nil;X.owner=nil;_G.onimusha_explosion=nil end)
end
-- END NATIVE EXPLOSION
