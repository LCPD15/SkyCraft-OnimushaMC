-- OnimushaWotS 01.000.001 / TDB82: bounded generic native-hit trial.
-- One ordinary player-hit template for every enemy; no enemy/animation tables.
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
    s.mode='off';s.trial_remaining=0
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
local function decode(args)
    if sdk.is_managed_object(args[2])~=true or sdk.is_managed_object(args[3])~=true then return end
    local damage=exact(sdk.to_managed_object(args[2]),'app.cEnemyApplyDamage')
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
            if typ(sdk.to_managed_object(args[2]))~='app.cEnemyApplyDamage' then return end
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
    -- Off/preparing retains the previously tested direct-HP route. An explicitly
    -- armed native trial consumes a hit even on rejection; never retry or fall
    -- back after enqueue could have run.
    if s.mode~='trial' then return false end
    trace.native_route=true
    if s.trial_remaining<=0 then trace.outcome='rejected';trace.reason='native_trial_budget_exhausted';return true end
    s.trial_remaining=s.trial_remaining-1
    local attempted=false
    local ok,e=pcall(function()
        assert(s.initialized and #s.selected>0,'No prepared generic hit templates')
        local template_index=s.selected[math.random(#s.selected)]
        local template=assert(s.templates[template_index],'Selected hit template missing')
        trace.native_template=template_index
        assert(bridge_state.active and finite(damage) and damage>0 and damage<=100000,'Invalid native hit request')
        local p=resolve_player();assert(template.owner_identity==p.identity,'Template owner/scene changed')
        assert(same(p.player,bridge_state.player) and same(p.go,bridge_state.player_go),'Bridge player mismatch')
        assert(get(template.weapon,'get_Valid')==true,'Template weapon unloaded')
        local go=get(entry.obj,'get_GameObject');assert(get(go,'get_Valid')==true,'Target unloaded')
        local entity=get(get(entry.obj,'get_CharacterEntityHolder'),'get_Entity')
        assert(same(get(entity,'get_OwnerCharacter'),entry.obj),'Target entity changed')
        local target_health=get(get(get(entry.obj,'get_Context'),'get_Chara'),'get_HealthManager')
        assert(same(target_health,entry.health) and get(target_health,'get_Health')>0,'Target health changed/dead')
        local module=exact(entity:get_field('_DamageInterface'),'app.cEnemyApplyDamage')
        assert(get(module,'get_Valid')==true and get(module,'get_IsDestroy')==false,'Target damage module invalid')
        local runtime=clone(template.runtime)
        get(runtime,'set_Attack',0.0);get(runtime,'set_FixedAttack',damage)
        -- Keep the one captured ordinary-hit reaction profile. Native defenses,
        -- guard and armor decide the response; no forced animation/effect IDs.
        local pos=get(go,'get_Transform'):get_position()
        local origin=get(p.go,'get_Transform'):get_position()
        assert(finite(pos.x) and finite(pos.y) and finite(pos.z),'Invalid target position')
        assert((pos.x-origin.x)^2+(pos.y-origin.y)^2+(pos.z-origin.z)^2<=100,'Target outside trial range')
        local height=math.max(0.5,math.min(4,entry.height or 1.8))
        local hitpos=Vector3f.new(pos.x,pos.y+height*0.6,pos.z)
        local dir=nullable(NULLDIR);local av=nullable(NULLVEC);local normal=nullable(NULLVEC)
        local ap=nullable(NULLVEC);local az=nullable(NULLVEC)
        trace.before=get(target_health,'get_Health');trace.requested_damage=damage
        attempted=true
        local stock=get(entity,DIRECT,p.go,template.weapon,runtime,hitpos,dir,av,normal,ap,az,0,nil)
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
        s.mode='trial';s.trial_remaining=0
    end
    return true
end
_G.onimusha_enemy_hit={queue=queue}
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
            elseif c.mode=='trial' then
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
            control_id=s.control_id,trial_remaining=s.trial_remaining})
    end
end
re.on_application_entry('LateUpdateBehavior',function()
    local ok,e=pcall(tick);if not ok then failure('frame',e) end
end)
re.on_script_reset(function() s.mode='off';s.templates={};s.pending={};_G.onimusha_enemy_hit=nil end)
