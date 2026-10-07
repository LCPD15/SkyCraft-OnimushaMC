-- Read-only, bounded combat asset / collider inspection. Onimusha TDB82 only.
-- The control file can select owned fields/array entries, never arbitrary calls.
-- MOD制作：LCPD15/LCPD拉灯
local CONTROL='onimusha_combat_inventory_control.json'
local OUTPUT='onimusha_combat_inventory_status.json'
local state={frame=0,metadata={}}
local function typ(o) return o and o:get_type_definition():get_full_name() end
local function call(o,n,...)
    assert(o and o:get_type_definition():get_method(n),'Missing getter '..n)
    return o:call(n,...)
end
local function fields(o)
    local result={};local td=o:get_type_definition()
    for _=1,8 do
        if not td then break end
        for _,f in ipairs(td:get_fields() or {}) do
            if not f:is_static() then result[#result+1]=f end
        end
        td=td:get_parent_type()
    end
    return result
end
local function metadata(td)
    local name=td:get_full_name();if state.metadata[name] then return end
    local r={fields={},methods={},parent=td:get_parent_type() and td:get_parent_type():get_full_name()}
    state.metadata[name]=r
    for _,f in ipairs(td:get_fields() or {}) do
        local entry={name=f:get_name(),type=f:get_type():get_full_name(),static=f:is_static()}
        if f:is_static() and td:get_parent_type() and td:get_parent_type():get_full_name()=='System.Enum' then
            local ok,v=pcall(function() return f:get_data(nil) end);if ok then entry.value=v end
        end
        r.fields[#r.fields+1]=entry
    end
    for _,m in ipairs(td:get_methods() or {}) do
        local args={};for _,p in ipairs(m:get_param_types() or {}) do args[#args+1]=p:get_full_name() end
        r.methods[#r.methods+1]={name=m:get_name(),params=args,param_names=m:get_param_names(),returns=m:get_return_type():get_full_name(),
            static=m:is_static(),address=tostring(m:get_function())}
    end
end
local function snapshot(v,depth,visited)
    if v==nil or type(v)=='string' or type(v)=='boolean' then return v end
    if type(v)=='number' then return v==v and math.abs(v)<math.huge and v or nil end
    if type(v)~='userdata' and type(v)~='table' then return nil end
    if not v.get_type_definition then
        if type(v.x)=='number' and type(v.y)=='number' and type(v.z)=='number' then
            return {x=v.x,y=v.y,z=v.z}
        end
        return {unsupported_value=true}
    end
    local td=v:get_type_definition();local name=td:get_full_name()
    metadata(td)
    local r={type=name,address=not td:is_value_type() and v:get_address() or nil}
    if depth<=0 or (r.address and visited[r.address]) then return r end
    if r.address then visited[r.address]=true end
    if name:sub(-2)=='[]' then
        local elements=v:get_elements();r.count=#elements;r.items={}
        for i,e in ipairs(elements) do if i>2048 then r.truncated=true;break end
            r.items[#r.items+1]={index=i-1,value=snapshot(e,depth-1,visited)}
        end
    else
        r.fields={}
        for i,f in ipairs(fields(v)) do
            if i>180 then r.truncated=true;break end
            local ok,val=pcall(function() return snapshot(f:get_data(v),depth-1,visited) end)
            if ok then r.fields[f:get_name()]=val
            else r.fields[f:get_name()]={error=tostring(val):sub(1,180)} end
        end
    end
    return r
end
local function colliders(enemy)
    local entity=call(call(enemy,'get_CharacterEntityHolder'),'get_Entity')
    local components=entity:get_field('<CharacterComponents>k__BackingField')
    local switch=components:get_field('<ColliderSwitcher>k__BackingField')
    local rsc=switch:get_field('_RequestSetCollider')
    local go=call(enemy,'get_GameObject')
    local out={name=call(go,'get_Name'),position=snapshot(call(go,'get_Transform'):get_position(),1,{}),groups={}}
    local count=call(rsc,'getRequestSetGroupsCount')
    assert(count>=0 and count<=16,'Unexpected collider group count')
    for i=0,count-1 do
        local group=call(rsc,'getRequestSetGroups(System.UInt32)',i)
        local item={index=i,id=call(group,'get_Id'),sets={}}
        local sets=call(group,'get_NumRequestSets');assert(sets>=0 and sets<=128,'Unexpected set count')
        for j=0,sets-1 do
            local set={index=j,id=call(group,'getRequestSetIdFromIndex(System.UInt32)',j),colliders={}}
            local n=call(rsc,'getNumCollidablesFromIndex(System.UInt32, System.UInt32)',item.id,j)
            assert(n>=0 and n<=128,'Unexpected collidable count')
            for k=0,n-1 do
                local col=call(rsc,'getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)',item.id,j,k)
                local ud=call(col,'get_UserData')
                local parent=ud and ud:get_type_definition():get_method('get_ParentUserData') and call(ud,'get_ParentUserData')
                set.colliders[#set.colliders+1]={index=k,enabled=call(col,'get_Enabled'),
                    aabb=snapshot(call(col,'get_BoundingAabb'),2,{}),
                    world_shape=snapshot(call(call(col,'get_TransformedShape'),'get_BoundingAabb'),2,{}),
                    userdata=snapshot(ud,1,{}),parent_userdata=snapshot(parent,2,{})}
            end
            item.sets[#item.sets+1]=set
        end
        out.groups[#out.groups+1]=item
    end
    return out
end
local function inspect(c)
    assert(sdk.get_tdb_version()==82,'Only TDB82')
    assert(_G.onimusha_mc and _G.onimusha_mc.status().enabled==false,'Keep takeover disabled')
    local pm=sdk.get_managed_singleton('app.PlayerManager')
    assert(call(pm,'isPlayerReady',false)==true,'Player unavailable')
    local player=call(call(pm,'getControllingPlayerInfo'),'get_Character')
    local entity=call(call(player,'get_CharacterEntityHolder'),'get_Entity')
    local supporter=call(entity,'get_AttackParamSupporter')
    local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
    local enemies=call(scene,'findComponents(System.Type)',sdk.find_type_definition('app.EnemyCharacter'):get_runtime_type()):get_elements()
    local roots={player=player,entity=entity,supporter=supporter,
        asset=supporter:get_field('_AttackParamData'),weapon=call(entity,'get_Weapon')}
    local result={id=c.id,frame=state.frame,queries={},enemy_count=#enemies}
    for i,q in ipairs(c.queries or {}) do
        if i>40 then break end
        local ok,value=pcall(function()
            local o=roots[q.root]
            if q.root=='enemy' then
                local index=tonumber(q.enemy_index) or 1
                assert(index>=1 and index<=#enemies and index==math.floor(index),'Invalid enemy index')
                o=enemies[index]
            end
            if q.root=='component' then
                assert(type(q.type)=='string' and q.type:match('^app%.'),'Only app component types')
                local t=assert(sdk.find_type_definition(q.type),'Missing component type')
                assert(t:is_a('via.Component'),'Not a component type')
                local found=call(scene,'findComponents(System.Type)',t:get_runtime_type()):get_elements()
                if q.list==true then
                    local out={count=#found,items={}}
                    for j,item in ipairs(found) do
                        if j>32 then out.truncated=true;break end
                        local go=call(item,'get_GameObject')
                        out.items[#out.items+1]={index=j,name=call(go,'get_Name'),
                            position=snapshot(call(go,'get_Transform'):get_position(),1,{}),
                            object=snapshot(item,math.max(0,math.min(2,tonumber(q.depth) or 1)),{})}
                    end
                    return out
                end
                local j=tonumber(q.component_index) or 1
                assert(j==math.floor(j) and j>=1 and j<=#found,'Component not present')
                o=found[j]
            end
            assert(o,'Root unavailable')
            if q.colliders==true then assert(q.root=='enemy');return colliders(o) end
            for j,step in ipairs(q.path or {}) do
                assert(j<=12,'Path too deep')
                if type(step.field)=='string' then o=o:get_field(step.field)
                elseif type(step.index)=='number' then
                    assert(step.index>=0 and step.index<=2047 and step.index==math.floor(step.index),'Invalid index')
                    assert(typ(o):sub(-2)=='[]','Index only supported for an actual array')
                    o=o:get_element(step.index)
                else error('Only owned fields / array entries can be inspected') end
                assert(o~=nil,'Null path component')
            end
            return snapshot(o,math.max(0,math.min(4,tonumber(q.depth) or 1)),{})
        end)
        result.queries[#result.queries+1]={query=q,value=ok and value or nil,error=not ok and tostring(value) or nil}
    end
    for i,name in ipairs(c.types or {}) do
        if i>32 then break end
        if type(name)=='string' and (name:match('^app%.') or name:match('^via%.') or name:match('^ace%.')) then
            local td=sdk.find_type_definition(name);if td then metadata(td) end
        end
    end
    result.metadata=state.metadata;result.complete=true
    return result
end
re.on_application_entry('LateUpdateBehavior',function()
    state.frame=state.frame+1;if state.frame%60~=1 then return end
    local c=json.load_file(CONTROL)
    if not c or type(c.id)~='string' or c.id==state.done or c.enabled~=true then return end
    state.done=c.id;state.metadata={}
    local ok,result=pcall(inspect,c)
    json.dump_file(OUTPUT,ok and result or {id=c.id,frame=state.frame,error=tostring(result),complete=false})
end)


-- BEGIN EXPLOSION PROBE: passive observation only, routed by the project loader.
-- All callback returns are preserved. No shell creation, game setters or damage requests.
do
local CONTROL='onimusha_explosion_probe_control.json'
local OUTPUT='onimusha_explosion_probe_status.json'
local e={frame=0,armed=false,events={},errors={},hooks={},targets={},gos={},owners={},shells={},shellgos={},profiles={},sequence=0}
local function attempt(fn) local ok,v=pcall(fn);if ok then return v end end
local function addr(o) return o and o:get_address() end
local function managed(raw)
    if raw and sdk.is_managed_object(raw)==true then return sdk.to_managed_object(raw) end
end
local function get(o,n,...)
    if not o or not o:get_type_definition():get_method(n) then return end
    return o:call(n,...)
end
local function field(o,n) return o and attempt(function() return o:get_field(n) end) end
local function vec(v)
    if not v then return end
    local x,y,z=v.x,v.y,v.z
    if type(x)=='number' and type(y)=='number' and type(z)=='number' and x==x and y==y and z==z
        and math.abs(x)<100000 and math.abs(y)<100000 and math.abs(z)<100000 then
        local out={x=x,y=y,z=z};local w=attempt(function() return v.w end)
        if type(w)=='number' and w==w and math.abs(w)<100000 then out.w=w end
        return out
    end
end
local function gameobject(go)
    if not go or get(go,'get_Valid')~=true then return end
    return {address=addr(go),name=get(go,'get_Name'),position=vec(get(go,'get_Transform'):get_position())}
end
local function snap(v,depth,seen,budget)
    if v==nil or type(v)=='string' or type(v)=='boolean' then return v end
    if type(v)=='number' then return v==v and math.abs(v)<math.huge and v or nil end
    if type(v)~='userdata' and type(v)~='table' then return end
    if not v.get_type_definition then return vec(v) end
    local t=v:get_type_definition();local n=t:get_full_name()
    local a=not t:is_value_type() and addr(v) or nil
    local out={type=n,address=a}
    if n=='via.GameObject' then return gameobject(v) or out end
    local path=attempt(function() return get(v,'get_Path') end)
    if type(path)=='string' then out.path=path end
    if depth<=0 or budget.n<=0 or (a and seen[a]) then return out end
    budget.n=budget.n-1;if a then seen[a]=true end
    if n:sub(-2)=='[]' then
        local items=v:get_elements();out.count=#items;out.items={}
        for i,item in ipairs(items) do
            if i>32 or budget.n<=0 then out.truncated=true;break end
            out.items[#out.items+1]={index=i-1,value=snap(item,depth-1,seen,budget)}
        end
    else
        out.fields={}
        for i,f in ipairs(fields(v)) do
            if i>64 or budget.n<=0 then out.truncated=true;break end
            local ok,value=pcall(function() return snap(f:get_data(v),depth-1,seen,budget) end)
            if ok then out.fields[f:get_name()]=value end
        end
    end
    return out
end
local function inspect(o,depth) return snap(o,depth or 2,{}, {n=160}) end
local function error_record(where,err)
    if #e.errors<20 then e.errors[#e.errors+1]={frame=e.frame,where=where,error=tostring(err):sub(1,500)} end
end
local function record(r)
    if #e.events>=256 then e.armed=false;e.status='event_limit';return end
    e.sequence=e.sequence+1;r.seq=e.sequence;r.frame=e.frame;e.events[#e.events+1]=r
end
local function bridge_off() return _G.onimusha_mc and _G.onimusha_mc.status().enabled==false end
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function valid_target(t)
    return t and e.armed and bridge_off() and get(t.go,'get_Valid')==true
        and addr(get(t.obj,'get_GameObject'))==addr(t.go)
end
local function profile(t)
    if e.profiles[t.key] then return end
    e.profiles[t.key]={object=gameobject(t.go),type=typ(t.obj),
        aaa=inspect(field(t.obj,'_AaaParam'),3),bbb=inspect(field(t.obj,'_BbbParam'),3),
        controller=inspect(field(t.obj,'_ShellCreateController'),6),
        mini_controller=inspect(field(t.mc,'<_ShellCreateController>k__BackingField'),6),
        mini_param=inspect(field(t.mc,'_Param'),3)}
end
local function shell_target(sh)
    if not sh then return end
    return e.shells[addr(sh)] or e.gos[addr(get(sh,'get_ShellOwner'))]
end
local function track_shell(sh,t)
    if not sh or not t or not sh:get_type_definition():is_a('ace.ShellBase') then return end
    e.shells[addr(sh)]=t
    local go=get(sh,'get_GameObject');if go then e.shellgos[addr(go)]=t end
end
local function target_for(kind,o)
    if kind=='controller' or kind=='mini' then return e.owners[addr(o)] end
    if kind=='shell' then return shell_target(o) end
    if kind=='shellmini' then return shell_target(get(o,'get_Shell')) end
    return e.targets[addr(o)]
end
local function refresh_targets()
    local sc=assert(scene(),'No scene')
    if e.scene and addr(sc)~=e.scene then e.armed=false;e.status='scene_changed';return end
    e.scene=addr(sc)
    local targets,gos,owners,list={},{},{},{}
    for _,name in ipairs({'app.Gm019','app.Gm009'}) do
        local t=assert(sdk.find_type_definition(name))
        local components=get(sc,'findComponents(System.Type)',t:get_runtime_type()):get_elements()
        assert(#components<=512,'Unexpected gimmick count')
        for _,o in ipairs(components) do
            local go=get(o,'get_GameObject')
            if get(go,'get_Valid')==true then
                local mc=field(o,'_McGimmickCreateShell');local key=tostring(addr(o))
                local item={obj=o,go=go,mc=mc,key=key};targets[addr(o)]=item;gos[addr(go)]=item
                for _,controller in ipairs({field(o,'_ShellCreateController'),field(mc,'<_ShellCreateController>k__BackingField')}) do
                    if controller then owners[addr(controller)]=item end
                end
                if mc then owners[addr(mc)]=item end
                if #list<128 then
                    local g=gameobject(go);g.type=typ(o);g.state=field(o,'_State');list[#list+1]=g
                end
            end
        end
    end
    e.targets=targets;e.gos=gos;e.owners=owners;e.target_list=list
end
local plans={
    {type='app.Gm019',name='getExplosionShellID',kind='gimmick',params={},returns='System.Int32',id_result=true},
    {type='app.Gm019_000',name='getExplosionShellID',kind='gimmick',params={},returns='System.Int32',id_result=true},
    {type='app.Gm019_001',name='getExplosionShellID',kind='gimmick',params={},returns='System.Int32',id_result=true},
    {type='app.Gm019',name='changeStateEvent',kind='gimmick',params={'app.Gm019.STATE'},returns='System.Void',int_arg=3},
    {type='app.Gm009',name='breakEvent',kind='gimmick',params={'app.cGimmickDamageInfo'},returns='System.Void',object_arg=3},
    {type='app.AppGimmickBase',name='createGmShell',kind='gimmick',params={'System.Int32','app.cShellShootingInfo'},returns='ace.ShellBase',int_arg=3,object_arg=4,shell_result=true},
    {type='app.mcGimmickCreateShell',name='createShell',kind='mini',params={'System.Int32','app.cShellShootingInfo','System.Action`1<ace.ShellBase>'},returns='System.Void',int_arg=3,object_arg=4},
    {type='ace.cShellCreateController',name='shootShell',kind='controller',params={'System.Int32','ace.cShellShootingInfoBase','System.Action`1<ace.ShellBase>'},returns='ace.ShellBase',int_arg=3,object_arg=4,shell_result=true},
    {type='ace.ShellBase',name='setup',kind='shell',params={'via.GameObject','ace.cShellSetupArgs'},returns='System.Void',setup=true,object_arg=4},
    {type='app.AppShell',name='doOnSetUp',kind='shell',params={},returns='System.Void'},
    {type='app.mcShellCallEffect',name='callEffects',kind='shellmini',params={'ace.ShellDef.ShellCallType','System.Boolean'},returns='System.Void',int_arg=3},
    {type='app.mcShellCallChildShell',name='createChildShell',kind='shellmini',params={'ace.cChildShellGenerateParam','ace.cShellminiParamCallChildShellBase','ace.cShellShootingInfoBase','System.Action`1<ace.ShellBase>'},returns='ace.ShellBase',object_arg=3,shell_result=true},
    {type='app.cCharacterApplyDamage',name='execThirdDamage',kind='damage',params={'app.cCharacterApplyDamage.cApplyParam'},returns='System.Void',object_arg=3},
    {type='app.cEnemyApplyDamage',name='execThirdDamage',kind='damage',params={'app.cCharacterApplyDamage.cApplyParam'},returns='System.Void',object_arg=3},
}
local function hook_plan(plan)
    local td=assert(sdk.find_type_definition(plan.type),'Missing type '..plan.type)
    local signature=plan.name..'('..table.concat(plan.params,', ')..')'
    local m=assert(td:get_method(signature),'Missing method '..plan.type..'.'..signature)
    assert(m:get_return_type():get_full_name()==plan.returns and not m:is_static(),'Signature mismatch')
    local key=plan.type..'.'..signature
    local rec={address=tostring(m:get_function()),calls=0,matched=0};e.hooks[key]=rec
    local storage_key='onimusha_explosion:'..key
    sdk.hook(m,function(args)
        thread.get_hook_storage()[storage_key]=nil
        if not e.armed or not bridge_off() then return end
        local ok,err=pcall(function()
            local o=managed(args[2]);if not o then return end
            rec.calls=rec.calls+1
            local target,damage,health
            if plan.kind=='damage' then
                local param=managed(args[3]);if not param or typ(param)~='app.cCharacterApplyDamage.cApplyParam' then return end
                damage=field(param,'DamageInfo');if not damage then return end
                local attacker=get(damage,'get_Attacker');local attackobj=get(damage,'get_AttackObj')
                target=e.gos[addr(attacker)] or e.shellgos[addr(attacker)] or e.gos[addr(attackobj)] or e.shellgos[addr(attackobj)]
                local owner=get(o,'get_OwnerCharacter')
                health=get(get(get(owner,'get_Context'),'get_Chara'),'get_HealthManager')
            elseif plan.setup then target=e.gos[addr(managed(args[3]))] or shell_target(o)
            else target=target_for(plan.kind,o) end
            if not valid_target(target) then return end
            profile(target);rec.matched=rec.matched+1
            if plan.kind=='shell' then track_shell(o,target) end
            local r={kind='pre',method=key,target=target.key,object=gameobject(target.go),object_type=typ(o),state=field(target.obj,'_State')}
            if plan.int_arg then r.int_arg=sdk.to_int64(args[plan.int_arg]) end
            if plan.object_arg then r.argument=inspect(managed(args[plan.object_arg]),3) end
            if damage then r.damage=inspect(damage,2);r.hp=get(health,'get_Health') end
            record(r)
            thread.get_hook_storage()[storage_key]={target=target,object=o,health=health,key=key,seq=r.seq}
        end)
        if not ok then error_record(key,err) end
    end,function(ret)
        local store=thread.get_hook_storage();local token=store[storage_key];store[storage_key]=nil
        if not token then return ret end
        local ok,err=pcall(function()
            if not e.armed then return end
            local r={kind='post',method=key,target=token.target.key,pre_seq=token.seq,state=field(token.target.obj,'_State')}
            if plan.id_result then r.explosion_shell_id=sdk.to_int64(ret);e.explosion_frame=e.explosion_frame or e.frame end
            if plan.shell_result then
                local sh=managed(ret);track_shell(sh,token.target)
                r.shell=inspect(sh,3);r.shell_object=gameobject(get(sh,'get_GameObject'))
            elseif plan.kind=='shell' then
                r.shell=inspect(token.object,3);r.shell_object=gameobject(get(token.object,'get_GameObject'))
            elseif plan.kind=='shellmini' then r.component=inspect(token.object,2) end
            if token.health then r.hp=get(token.health,'get_Health') end
            record(r)
        end)
        if not ok then error_record(key,err) end
        return ret
    end)
    rec.installed=true
end
local function install()
    if e.installed then return end
    assert(sdk.get_tdb_version()==82,'Only TDB82 is supported')
    for _,plan in ipairs(plans) do
        local ok,err=pcall(hook_plan,plan);if not ok then error_record('hook '..plan.type..'.'..plan.name,err) end
    end
    e.installed=true;e.install_ok=#e.errors==0
end
local function tick()
    e.frame=e.frame+1
    if e.frame%30==1 then
        local c=json.load_file(CONTROL) or {}
        if c.enabled~=true then e.armed=false;e.status='disabled'
        elseif type(c.id)=='string' and c.id~=e.id then
            assert(bridge_off(),'Keep F10 off before arming explosion probe')
            e.id=c.id;e.events={};e.errors={};e.profiles={};e.shells={};e.shellgos={};e.sequence=0;e.explosion_frame=nil;e.scene=nil
            install();refresh_targets();e.armed=e.install_ok==true and #e.errors==0;e.arm_frame=e.frame
            e.status=e.armed and 'armed_read_only' or 'hook_setup_failed'
        end
        if e.armed then
            if not bridge_off() then e.armed=false;e.status='takeover_enabled'
            elseif e.frame-e.arm_frame>36000 then e.armed=false;e.status='capture_timeout'
            elseif e.explosion_frame and e.frame-e.explosion_frame>600 then e.armed=false;e.status='capture_complete'
            else refresh_targets() end
        end
        json.dump_file(OUTPUT,{id=e.id,frame=e.frame,armed=e.armed,status=e.status,read_only=true,
            scene=e.scene,targets=e.target_list,hooks=e.hooks,profiles=e.profiles,events=e.events,errors=e.errors})
    end
end
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick);if not ok then e.armed=false;e.status='probe_error';error_record('frame',err) end
end)
re.on_script_reset(function() e.armed=false;e.targets={};e.gos={};e.owners={};e.shells={};e.shellgos={} end)
end
-- END EXPLOSION PROBE
