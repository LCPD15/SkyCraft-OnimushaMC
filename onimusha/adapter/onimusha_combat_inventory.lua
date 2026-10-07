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
        r.methods[#r.methods+1]={name=m:get_name(),params=args,returns=m:get_return_type():get_full_name()}
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
        if type(name)=='string' and (name:match('^app%.') or name:match('^via%.')) then
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
