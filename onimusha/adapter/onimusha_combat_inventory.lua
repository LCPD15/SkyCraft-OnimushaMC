-- Bounded combat inspection and explicitly requested isolated native-object probe.
-- Onimusha TDB82 only. The inventory/explosion observation scopes are read-only.
-- The control file can select owned fields/array entries, never arbitrary calls.
-- MOD制作：LCPD15/LCPD拉灯
local CONTROL='onimusha_combat_inventory_control.json'
local OUTPUT='onimusha_combat_inventory_status.json'
local state={frame=0,metadata={}}

-- Natural soul-absorption observation. No command injection, reward writes,
-- skipped calls, or replay of a success notification. Owner is resolved afresh.
do
    local control='onimusha_soul_probe_control.json'
    local output='onimusha_soul_probe_status.json'
    local q={frame=0,armed=false,events={},counts={},metadata={},errors={}}
    local function scalar(v)
        if type(v)=='boolean' or type(v)=='string' then return v end
        if type(v)=='number' and v==v and math.abs(v)<math.huge then return v end
    end
    local function describe(t)
        local n=t:get_full_name();if q.metadata[n] then return end
        local r={fields={},methods={}};q.metadata[n]=r
        for _,f in ipairs(t:get_fields() or {})do
            local v={name=f:get_name(),type=f:get_type():get_full_name(),static=f:is_static()}
            if f:is_static() and t:get_parent_type() and t:get_parent_type():get_full_name()=='System.Enum' then
                local ok,value=pcall(f.get_data,f,nil);if ok then v.value=scalar(value)end
            end
            r.fields[#r.fields+1]=v
        end
        for _,m in ipairs(t:get_methods() or {})do
            local p={};for _,a in ipairs(m:get_param_types() or {})do p[#p+1]=a:get_full_name()end
            r.methods[#r.methods+1]={name=m:get_name(),params=p,returns=m:get_return_type():get_full_name()}
        end
    end
    local function values(o)
        local t=o:get_type_definition();describe(t);local r={}
        for _,f in ipairs(t:get_fields() or {})do
            if not f:is_static() then
                local name=f:get_type():get_full_name()
                local parent=f:get_type():get_parent_type()
                if name=='System.Boolean' or name=='System.Int32' or name=='System.UInt32' or name=='System.Single'
                    or (parent and parent:get_full_name()=='System.Enum') then r[f:get_name()]=scalar(f:get_data(o))end
            end
        end
        return r
    end
    local function event(kind,data)
        q.events[#q.events+1]={frame=q.frame,time=os.clock(),kind=kind,data=data}
        if #q.events>256 then table.remove(q.events,1)end
    end
    local function resolve()
        assert(sdk.get_tdb_version()==82,'Only TDB82')
        assert(_G.onimusha_mc and not _G.onimusha_mc.status().enabled,'Keep F10 off')
        local pm=assert(sdk.get_managed_singleton('app.PlayerManager'))
        assert(pm:call('isPlayerReady',false),'Player not ready')
        local info=pm:call('getControllingPlayerInfo')
        assert(info:call('get_Valid') and info:call('get_CharacterValid'),'Invalid player')
        local p=info:call('get_Character');local go=p:call('get_GameObject')
        assert(go:call('get_Valid'),'Invalid player object')
        local e=p:call('get_CharacterEntityHolder'):call('get_Entity')
        local o=e:call('get_SoulAbsorption')
        assert(o and o:get_type_definition():get_full_name()=='app.cPlayerSoulAbsorptionSupporter','Unexpected soul owner')
        assert(o:get_field('_PlayerCharacterEntity'):get_address()==e:get_address(),'Soul owner mismatch')
        return o
    end
    local function install()
        local t=assert(sdk.find_type_definition('app.cPlayerSoulAbsorptionSupporter'));describe(t)
        local specs={
            {'updateCommand',{'app.cPlayerCommandResult'},'System.Void'},
            {'requestSoulAbsorptionAction',{'System.Boolean'},'System.Void'},
            {'requestAbsorption',{},'System.Boolean'},
            {'updateBeforeAction',{},'System.Void'},
            {'updateAfterAction',{},'System.Void'},
            {'lateUpdate',{},'System.Void'},
            {'executeSoulAbsorptionSuccess',{'app.SoulBase'},'System.Void'},
            {'addSoulAbsorption',{'app.SoulDef.ID_Fixed','System.Int32','System.Boolean'},'System.Void'},
        }
        local seen={}
        for _,spec in ipairs(specs)do
            local name=spec[1];local m=assert(t:get_method(name),'Missing soul method '..name)
            assert(not m:is_static() and m:get_num_params()==#spec[2] and m:get_return_type():get_full_name()==spec[3],'Soul signature mismatch')
            for i,a in ipairs(m:get_param_types() or {})do assert(a:get_full_name()==spec[2][i],'Soul parameter mismatch')end
            local ptr=sdk.to_int64(m:get_function());assert(ptr and ptr>0 and not seen[ptr],'Invalid/duplicate soul hook')
            seen[ptr]=true
            sdk.hook(m,function(args)
                if not q.armed or not q.owner or sdk.to_int64(args[2])~=q.owner then return end
                local ok,err=pcall(function()
                    local o=resolve();assert(o:get_address()==q.owner,'Soul owner changed')
                    q.counts[name]=(q.counts[name] or 0)+1
                    local r={before=values(o)}
                    if name=='updateCommand' then
                        local cmd=sdk.to_managed_object(args[3]);assert(cmd and cmd:get_type_definition():get_full_name()==spec[2][1],'Unexpected command type')
                        r.command=values(cmd)
                        -- Preserve transitions, not hundreds of identical idle frames.
                        local key=tostring(r.before._IsCommandAbsorb)..':'..tostring(r.before._IsAbsorption)
                        for _,k in ipairs({'_IsSoulAbsorption','_SoulAbsorption','_IsCommandAbsorb'})do key=key..':'..tostring(r.command[k])end
                        if q.command_key==key then return end;q.command_key=key
                    elseif name=='requestSoulAbsorptionAction' then
                        r.argument=sdk.to_int64(args[3])~=0
                        if q.action_argument==r.argument then return end;q.action_argument=r.argument
                    elseif name=='executeSoulAbsorptionSuccess' then
                        local soul=sdk.to_managed_object(args[3]);assert(soul and soul:get_type_definition():is_a('app.SoulBase'),'Unexpected soul')
                        r.soul=values(soul);r.address=soul:get_address()
                    elseif name=='addSoulAbsorption' then
                        r.soul_type=sdk.to_int64(args[3]);r.amount=sdk.to_int64(args[4]);r.flag=sdk.to_int64(args[5])~=0
                    elseif q.counts[name]>8 then return end
                    event(name,r)
                end)
                if not ok then q.armed=false;q.error=tostring(err)end
            end,function(ret)return ret end)
        end
        for _,n in ipairs({'app.SoulDef.ID_Fixed','app.SoulDef.SOUL_SIZE','app.SoulDef.SoulAbsorptionType_Fixed','app.cPlayerCommandResult'})do
            local td=sdk.find_type_definition(n);if td then describe(td)end
        end
        q.installed=true
    end
    re.on_application_entry('LateUpdateBehavior',function()
        q.frame=q.frame+1
        if q.frame%30==1 then
            local c=json.load_file(control)
            if not c or c.enabled~=true then q.armed=false
            elseif c.id~=q.id then
                q.id=c.id;q.error=nil;q.owner=nil;q.events={};q.counts={};q.command_key=nil;q.action_argument=nil
                local ok,err=pcall(function()local o=resolve();q.owner=o:get_address();if not q.installed then install()end;q.armed=true end)
                if not ok then q.armed=false;q.error=tostring(err)end
            end
        end
        if q.armed then
            local ok,err=pcall(function()
                local o=resolve();assert(o:get_address()==q.owner,'Soul owner changed')
                local v=values(o);local k=tostring(v._IsCommandAbsorb)..':'..tostring(v._IsAbsorption)..':'..tostring(v._AbsorptionType)
                if k~=q.state_key then q.state_key=k;event('state',v)end
                q.current=v
            end)
            if not ok then q.armed=false;q.error=tostring(err)end
        end
        if q.id and q.frame%60==0 then json.dump_file(output,q)end
    end)
    re.on_script_reset(function()q.armed=false;q.owner=nil end)
end
local function typ(o) return o and o:get_type_definition():get_full_name() end
local function call(o,n,...)
    assert(o and o:get_type_definition():get_method(n),'Missing getter '..n)
    local ok,result=pcall(o.call,o,n,...)
    if not ok then error(typ(o)..'.'..n..': '..tostring(result),0) end
    return result
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
local function engine_inspect(c,scene,player)
    local out={id=c.id,frame=state.frame,scene=snapshot(scene,0,{}),components={},errors={}}
    local origin=call(call(player,'get_GameObject'),'get_Transform'):get_position()
    local function read(o,name,...)
        local ok,v=pcall(call,o,name,...)
        if not ok then return {unavailable=tostring(v):sub(1,160)} end
        local r=snapshot(v,(v and (type(v)=='userdata' or type(v)=='table') and v.get_type_definition and v:get_type_definition():is_value_type()) and 2 or 0,{})
        if v and (type(v)=='userdata' or type(v)=='table') and v.get_type_definition then
            if v:get_type_definition():get_method('get_ResourcePath') then
                local yes,path=pcall(call,v,'get_ResourcePath');if yes then r.resource_path=path end
            end
        end
        return r
    end
    local function describe_go(go)
        local folder=call(go,'get_Folder')
        local r={object=snapshot(go,0,{}),name=call(go,'get_Name'),valid=call(go,'get_Valid'),update=read(go,'get_Update'),draw=read(go,'get_Draw'),
            position=snapshot(call(go,'get_Transform'):get_position(),0,{}),folder=snapshot(folder,0,{})}
        if folder then
            r.folder.name=read(folder,'get_Name');r.folder.path=read(folder,'get_Path')
            r.folder.active=read(folder,'get_Active');r.folder.ready=read(folder,'get_Ready')
        end
        r.components={}
        for i,v in ipairs(call(go,'get_Components'):get_elements()) do
            if i>40 then break end;r.components[#r.components+1]=snapshot(v,0,{})
        end
        return r
    end
    local function owner(o) return describe_go(call(o,'get_GameObject')) end
    local function details(o,getters)
        if not o then return end
        local r={object=snapshot(o,0,{}),getters={}}
        for _,n in ipairs(getters) do r.getters[n]=read(o,n) end
        return r
    end
    local function collider(o)
        return {object=snapshot(o,0,{}),ready=read(o,'get_Ready'),enabled=read(o,'get_Enabled'),filter_resource=read(o,'get_CollisionFilterResource'),shape=read(o,'get_Shape'),
            filter=details(call(o,'get_FilterInfo'),{'get_Layer','get_Group','get_SubGroup','get_IgnoreSubGroup','get_MaskBits'}),owner=read(o,'get_GameObject'),bounds=read(o,'get_BoundingAabb')}
    end
    out.player=owner(player)
    local pc=call(call(player,'get_GameObject'),'getComponent(System.Type)',sdk.find_type_definition('via.physics.CharacterController'):get_runtime_type())
    local floor=pc and call(pc,'get_FloorGameObject')
    if floor then
        out.floor=describe_go(floor);out.floor.physics={}
        for _,o in ipairs(call(floor,'get_Components'):get_elements()) do
            if o:get_type_definition():is_a('via.physics.Colliders') then
                local n=call(o,'getCollidersCount');local item={object=snapshot(o,0,{}),count=n,colliders={}};out.floor.physics[#out.floor.physics+1]=item
                for j=0,math.min(n,4)-1 do item.colliders[#item.colliders+1]=collider(call(o,'getCollider(System.UInt32)',j)) end
            end
        end
    end
    local plans={
        {'via.physics.ColliderSet',{'get_Ready','get_Static','get_Resource','get_CollidersCount'}},
        {'via.physics.RequestSetCollider',{'get_NumRequestSetGroups','get_NumRegisteredRequestSetIds','get_NumExecuteWorkers'}},
        {'via.render.Mesh',{'getMesh','get_Material','get_MeshReady','get_MaterialReady','get_Enabled','get_StaticMesh','get_DrawShadowCast','get_RenderOutputID'}},
        {'via.physics.Colliders',{'get_Ready','get_Static','get_Enabled','getCollidersCount','get_BoundingAabb'}},
        {'via.dynamics.RigidBodySet',{'get_Ready','get_Enabled','get_Resource'}},
        {'via.navigation.AIMapEffector',{'getEffectType','getShapeType','get_MapName','getMapNamesCount','get_Enabled','get_Fixed','get_AddEdge','get_Affected','get_ResourceAttributeBits','get_ExtraLinkConnected','get_Shape'}}, {'via.navigation.AIMap',{}},
        {'via.render.Light',{}}, {'via.physics.CharacterController',{'get_FilterInfo','get_FilterResource','get_Height','get_Radius','get_Ground'}}}
    for _,plan in ipairs(plans) do
        local name=plan[1];local result={type=name,items={}};out.components[#out.components+1]=result
        coroutine.yield()
        local ok,err=pcall(function()
            local t=assert(sdk.find_type_definition(name),'Type unavailable');metadata(t)
            local found=call(scene,'findComponents(System.Type)',t:get_runtime_type()):get_elements()
            result.count=#found;local nearby={}
            for i,o in ipairs(found) do
                if i%64==0 then coroutine.yield() end
                if i>16384 then result.scan_truncated=true;break end
                local go=call(o,'get_GameObject')
                if go and call(go,'get_Valid') and (c.active~=true or call(go,'get_Update') or call(go,'get_Draw'))
                    and (name~='via.render.Mesh' or c.static_mesh~=true or call(o,'get_StaticMesh')) then
                    local p=call(go,'get_Transform'):get_position()
                    nearby[#nearby+1]={o=o,d=(p.x-origin.x)^2+(p.y-origin.y)^2+(p.z-origin.z)^2}
                end
            end
            table.sort(nearby,function(a,b) return a.d<b.d end)
            for i,item in ipairs(nearby) do
                if i>6 then break end
                local o=item.o;local r={object=snapshot(o,name:find('navigation',1,true) and 1 or 0,{}),distance=math.sqrt(item.d),owner=owner(o),getters={}}
                result.items[#result.items+1]=r
                for _,getter in ipairs(plan[2]) do r.getters[getter]=read(o,getter) end
                if name=='via.physics.ColliderSet' and r.getters.get_Ready==true and r.getters.get_CollidersCount>0 then
                    r.collider=collider(call(o,'getCollider(System.UInt32)',0))
                elseif name=='via.physics.Colliders' then
                    r.colliders={};local num=call(o,'getCollidersCount');assert(num<=1024)
                    for j=0,math.min(num,4)-1 do r.colliders[#r.colliders+1]=collider(call(o,'getCollider(System.UInt32)',j)) end
                elseif name=='via.navigation.AIMapEffector' then
                    r.shape=details(call(o,'get_Shape'),{'get_Shape','get_BoundingOBB','get_BoundingOBBType'})
                    r.map_names={};local num=call(o,'getMapNamesCount');assert(num<=64)
                    for j=0,num-1 do r.map_names[#r.map_names+1]=call(o,'getMapNames(System.UInt32)',j) end
                elseif name=='via.physics.RequestSetCollider' then
                    r.groups={};local count=call(o,'getRequestSetGroupsCount');assert(count<=32)
                    for index=0,count-1 do
                        if index>=4 then break end
                        local g=call(o,'getRequestSetGroups(System.UInt32)',index)
                        local row={index=index,id=call(g,'get_Id'),initialized=call(g,'get_Initialized'),resource=read(g,'get_Resource'),sets={}}
                        r.groups[#r.groups+1]=row
                        if row.initialized then
                            local num=call(g,'get_NumRequestSets');assert(num<=512);row.count=num
                            for j=0,math.min(num,2)-1 do
                                local id=call(g,'getRequestSetIdFromIndex(System.UInt32)',j)
                                row.sets[#row.sets+1]={index=j,id=id,registered=call(o,'isRegisteredRequestSet(System.UInt32, System.UInt32)',row.id,id)}
                            end
                        end
                    end
                end
            end
        end)
        if not ok then result.error=tostring(err):sub(1,240) end
    end
    for i,name in ipairs(c.types or {}) do
        if i>32 then break end
        local t=sdk.find_type_definition(name);if t then metadata(t) else out.errors[#out.errors+1]='Missing type '..name end
    end
    out.metadata=state.metadata;out.complete=true;return out
end
local function inspect(c)
    assert(sdk.get_tdb_version()==82,'Only TDB82')
    assert(_G.onimusha_mc and _G.onimusha_mc.status().enabled==false,'Keep takeover disabled')
    local pm=sdk.get_managed_singleton('app.PlayerManager')
    assert(call(pm,'isPlayerReady',false)==true,'Player unavailable')
    local player=call(call(pm,'getControllingPlayerInfo'),'get_Character')
    if c.engine==true then
        local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
        return engine_inspect(c,scene,player)
    end
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
    state.frame=state.frame+1
    if state.engine_job then
        local job=state.engine_job
        local safe,reason=pcall(function()
            assert(_G.onimusha_mc and _G.onimusha_mc.status().enabled==false,'Takeover enabled during probe')
            local pm=sdk.get_managed_singleton('app.PlayerManager')
            assert(call(pm,'isPlayerReady',false)==true,'Player unavailable during probe')
            local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
            assert(scene and scene:get_address()==job.scene,'Scene changed during probe')
        end)
        if not safe then
            state.engine_job=nil;json.dump_file(OUTPUT,{id=job.id,error=tostring(reason),complete=false});return
        end
        local ok,result=coroutine.resume(job.co)
        if not ok or coroutine.status(job.co)=='dead' then
            state.engine_job=nil
            json.dump_file(OUTPUT,ok and result or {id=job.id,error=tostring(result),complete=false})
        end
        return
    end
    if state.frame%60~=1 then return end
    local c=json.load_file(CONTROL)
    if not c or type(c.id)~='string' or c.id==state.done or c.enabled~=true then return end
    state.done=c.id;state.metadata={}
    if c.engine==true then
        local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
        if not scene then json.dump_file(OUTPUT,{id=c.id,error='No scene',complete=false});return end
        state.engine_job={id=c.id,scene=scene:get_address(),co=coroutine.create(function() return inspect(c) end)}
        json.dump_file(OUTPUT,{id=c.id,status='scanning',complete=false});return
    end
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

-- BEGIN NATIVE OBJECT PROBE: explicit single-object experiment, TDB82 only.
-- Navigation creation/hasEffectNodes are quarantined after the 2026-10-07 crash.
-- Resource and holder ownership follows REFramework's REResource API.
-- No gameplay object is edited; no physics allocator/global setting is enabled.
do
local CONTROL='onimusha_native_object_probe_control.json'
local OUTPUT='onimusha_native_object_probe_status.json'
local q={frame=0,phase='idle',retired={}}
local function scene_now()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function report()
    local r={id=q.id,frame=q.frame,phase=q.phase,error=q.error,position=q.position,
        scene=q.scene_address,object_name=q.name,ground=q.ground,ready=q.ready,destroyed=q.destroyed,
        collision=q.collision,action=q.action,asset_id=q.asset_id,pending_id=q.pending_id,model_loader=q.model_loader and q.model_loader:get_address(),motion=q.motion,motion_updates=q.motion_updates,
        material_probe=q.material_probe,transform_probe=q.transform_probe,material_isolation=q.material_isolation,
        replay_scale=q.replay_scale,flash_probe=q.flash_probe}
    if q.mesh_holder and sdk.is_managed_object then
        local h=q.mesh_holder
        r.holder={address=h:get_address(),managed=sdk.is_managed_object(h),factory=q.action=='render_userdata' and 'engine_userdata' or 'create_holder_global'}
        if r.holder.managed then
            r.holder.references=h:get_reference_count();r.holder.resource=h:read_qword(0x10)
            r.holder.path=call(h,'get_ResourcePath')
        end
    end
    if q.prefab then r.prefab_ready=call(q.prefab,'get_Ready') end
    if q.go and call(q.go,'get_Valid') then
        r.owner={address=q.go:get_address(),valid=true,draw=call(q.go,'get_Draw'),update=call(q.go,'get_Update'),
            folder=call(call(q.go,'get_Folder'),'get_Path')}
        if q.mesh then
            r.mesh={ready=call(q.mesh,'get_MeshReady'),material_ready=call(q.mesh,'get_MaterialReady'),
                enabled=call(q.mesh,'get_Enabled'),materials=call(q.mesh,'get_MaterialNum'),
                output=call(q.mesh,'get_RenderOutputID'),shadow=call(q.mesh,'get_DrawShadowCast'),
                bounds=snapshot(call(q.mesh,'get_WorldAABB'),2,{})}
        end
    end
    json.dump_file(OUTPUT,r)
end
local function cleanup(reason)
    if q.peer_go then
        if call(q.peer_go,'get_Valid')then
            call(q.peer_mesh,'set_Enabled',false);call(q.peer_go,'set_DrawSelf',false)
            sdk.find_type_definition('via.GameObject'):get_method('destroy(via.GameObject)'):call(nil,q.peer_go)
        end
        q.retired[#q.retired+1]={frame=q.frame,go=q.peer_go,mesh=q.peer_mesh,model_loader=q.model_loader,mesh_holder=q.mesh_holder,material_holder=q.material_holder}
        q.peer_go=nil;q.peer_mesh=nil
    end
    if q.go then
        if call(q.go,'get_Valid') then
            if q.colliders then call(q.colliders,'set_Enabled',false) end
            if q.mesh then call(q.mesh,'set_Enabled',false) end
            call(q.go,'set_DrawSelf',false)
            sdk.find_type_definition('via.GameObject'):get_method('destroy(via.GameObject)'):call(nil,q.go)
        end
        -- Keep wrappers until engine deferred destruction has completed.
        q.retired[#q.retired+1]={frame=q.frame,go=q.go,mesh=q.mesh,colliders=q.colliders,collider=q.collider,
            prefab=q.prefab,loader=q.loader,model_loader=q.model_loader,mesh_holder=q.mesh_holder,material_holder=q.material_holder}
    elseif q.prefab then
        call(q.prefab,'set_Standby',false)
    end
    q.go=nil;q.mesh=nil;q.colliders=nil;q.collider=nil;q.prefab=nil;q.loader=nil;q.folder=nil;q.cc=nil
    q.mesh_holder=nil;q.material_holder=nil;q.model_loader=nil;q.phase=reason or 'removed';q.destroyed=#q.retired==0;q.ready=false;q.pending_id=nil
    q.ray_query=nil;q.ray_result=nil
end
local function resource_holder(resource_type,holder_type,path)
    local resource=assert(sdk.create_resource(resource_type,path),'Resource allocation failed: '..resource_type)
    resource:add_ref()
    local ok,holder=pcall(function() return assert(resource:create_holder_global(holder_type),'GC-safe holder unavailable'):add_ref() end)
    resource:release()
    if not ok then error(holder) end
    return holder
end
local function ground_query(player)
    local cc=call(call(player,'get_GameObject'),'getComponent(System.Type)',sdk.find_type_definition('via.physics.CharacterController'):get_runtime_type())
    local p=call(call(player,'get_GameObject'),'get_Transform'):get_position()
    local query=assert(sdk.create_instance('via.physics.GetAreaPrimitiveQuery')):add_ref()
    local box=ValueType.new(sdk.find_type_definition('via.AABB'))
    box:set_field('minpos',Vector3f.new(p.x-3,p.y-1,p.z-3));box:set_field('maxpos',Vector3f.new(p.x+3,p.y+1,p.z+3))
    call(query,'set_Area',box);call(query,'set_FilterInfo',call(cc,'get_FilterInfo'))
    local result=assert(sdk.call_native_func(sdk.get_native_singleton('via.physics.System'),sdk.find_type_definition('via.physics.System'),'getAreaPrimitive',query)):add_ref()
    local n=call(result,'get_NumTriangles');local out={triangles=n,colliders={}};local seen={}
    for i=0,math.min(n,32)-1 do
        local col=call(result,'getTriangleCollidable(System.UInt32)',i)
        if col and not seen[col:get_address()] then
            seen[col:get_address()]=true
            local f=call(col,'get_FilterInfo');local filter={}
            for _,field in ipairs({'Layer','Group','SubGroup','IgnoreSubGroup','MaskBits'}) do filter[field]=call(f,'get_'..field) end
            local cr=call(col,'get_CollisionFilterResource');local go=call(col,'get_GameObject')
            out.colliders[#out.colliders+1]={type=typ(col),filter=filter,filter_resource=cr and call(cr,'get_ResourcePath'),
                owner=go and call(go,'get_Name'),shape=typ(call(col,'get_Shape'))}
        end
    end
    q.query=query;q.query_result=result
    return out
end
local function attach_mesh()
    call(q.go,'set_DrawSelf',false)
    q.mesh=assert(call(q.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type())):add_ref()
    call(q.mesh,'set_Enabled',false);call(q.mesh,'set_StaticMesh',false)
    call(q.mesh,'setMesh',q.mesh_holder);call(q.mesh,'set_Material',q.material_holder)
    call(q.mesh,'set_RenderOutputID',31);call(q.mesh,'set_DrawShadowCast',true)
    q.phase='loading';q.object_start=q.frame
end
local function verify_collision()
    assert(call(q.colliders,'getCollidersCount')==1,'Unexpected collider count')
    if not call(q.colliders,'get_Ready') then return false end
    q.collider=q.collider or assert(call(q.colliders,'getCollider(System.UInt32)',0)):add_ref()
    assert(typ(call(q.collider,'get_Shape'))=='via.physics.BoxShape','Wrong native shape')
    local owner=assert(call(q.collider,'get_GameObject'))
    assert(owner:get_address()==q.go:get_address(),'Collider belongs to another object')
    local query=assert(sdk.create_instance('via.physics.CastRayQuery')):add_ref()
    call(query,'copyFilterInfo',call(q.cc,'get_FilterInfo'))
    call(query,'enableAllHits');call(query,'enableNearSort')
    local p=q.position
    call(query,'setRay(via.vec3, via.vec3)',Vector3f.new(p.x-2,p.y,p.z),Vector3f.new(p.x+2,p.y,p.z))
    local result=assert(sdk.call_native_func(sdk.get_native_singleton('via.physics.System'),sdk.find_type_definition('via.physics.System'),'castRay',query)):add_ref()
    q.ray_query=query;q.ray_result=result
    local count=call(result,'get_NumContactPoints');assert(count>=0 and count<=256,'Unexpected ray contact count')
    local found=false
    for i=0,count-1 do
        local hit=call(result,'getContactCollidable(System.UInt32)',i)
        if hit and hit:get_address()==q.collider:get_address() then found=true end
    end
    local filters={}
    for name,obj in pairs({player=q.cc,cube=q.collider}) do
        local fi=call(obj,'get_FilterInfo');local v={}
        for _,key in ipairs({'Layer','Group','SubGroup','IgnoreSubGroup','MaskBits'}) do v[key]=call(fi,'get_'..key) end
        filters[name]=v
    end
    q.collision={registered=found,contacts=count,collider_address=q.collider:get_address(),owner_address=owner:get_address(),
        filters=filters,enabled=call(q.colliders,'get_Enabled'),collider_enabled=call(q.collider,'get_Enabled'),
        ray=snapshot(call(query,'get_Ray'),2,{}),ray_distance=call(query,'get_RayDistance'),
        ray_finished=call(result,'get_Finished'),
        owner_update=call(q.go,'get_Update'),owner_draw=call(q.go,'get_Draw'),
        ready=call(q.collider,'get_Ready'),layer=call(call(q.collider,'get_FilterInfo'),'get_Layer'),
        bounds=snapshot(call(q.colliders,'get_BoundingAabb'),2,{})}
    return found
end
local function start(c)
    assert(sdk.get_tdb_version()==82,'Only TDB82')
    assert(_G.onimusha_mc and _G.onimusha_mc.status().enabled==false,'Keep takeover disabled')
    assert(#q.retired==0 and not q.go and not q.prefab and not q.loader,'Previous probe is still retiring')
    local pm=sdk.get_managed_singleton('app.PlayerManager');assert(call(pm,'isPlayerReady',false))
    local player=call(call(pm,'getControllingPlayerInfo'),'get_Character')
    local go=call(player,'get_GameObject');local sc=assert(scene_now());local folder=assert(call(go,'get_Folder'))
    q.ground=(c.action~='render_section' and c.action~='render_userdata') and ground_query(player) or nil
    q.phase='ground_read';report()
    if c.action=='inspect_ground' then return end
    assert(c.action=='render_cube' or c.action=='physics_cube' or c.action=='render_section' or c.action=='render_userdata','Unsupported probe action')
    local p=call(go,'get_Transform'):get_position()
    q.position={x=p.x+3,y=p.y+0.55,z=p.z+3};q.name='OMC_NativeProbe_'..c.id
    q.scene_address=sc:get_address();q.start=q.frame;q.ready=false;q.destroyed=false;q.collision=nil;q.action=c.action
    q.asset_id=nil;q.motion=c.action=='render_userdata' and c.motion==true;q.motion_updates=0
    q.inspect_dynamic=c.inspect_dynamic==true;q.tint_probe=c.tint_probe==true;q.material_probe=nil;q.transform_probe=nil;q.material_isolation=nil
    q.replay_scale=c.replay_scale==true;q.flash_probe=c.flash_probe==true
    local stem=c.action=='physics_cube' and 'mc_stone_cube' or 'unit_cube'
    local resource_path='mod/onimusha_mc/probe/'..stem
    if c.action=='render_section' or c.action=='render_userdata' then
        assert(type(c.asset_id)=='string' and #c.asset_id==28 and c.asset_id:match('^section_%x+$'),'Invalid private section asset id')
        assert(type(c.section_min)=='table','Missing section-local bounds')
        for _,axis in ipairs({'x','y','z'}) do
            local v=c.section_min[axis]
            assert(type(v)=='number' and v==v and v>=-16 and v<=32,'Invalid section-local bounds')
        end
        q.asset_id=c.asset_id;resource_path='mod/onimusha_mc/sections/'..q.asset_id..'/'..q.asset_id
        q.position={x=p.x+3-c.section_min.x,y=p.y+0.05-c.section_min.y,z=p.z+3-c.section_min.z}
        if q.replay_scale and type(c.offset)=='table' then
            for _,axis in ipairs({'x','y','z'})do
                local v=c.offset[axis];assert(type(v)=='number' and v==v and math.abs(v)<=6,'Invalid private probe offset')
                q.position[axis]=p[axis]+v-c.section_min[axis]
            end
        end
    end
    if c.action=='render_userdata' then
        -- Let the engine deserialize/own its resource holders. No Montage object
        -- is mounted on the player and no costume or physics logic is invoked.
        q.model_loader=assert(sdk.create_userdata_global('app.montage.data.MontagePartsModelData',resource_path..'_loader.user')):add_ref()
        q.folder=folder:add_ref();q.phase='loading_model_userdata';report();return
    end
    q.mesh_holder=resource_holder('via.render.MeshResource','via.render.MeshResourceHolder',resource_path..'.mesh')
    q.material_holder=resource_holder('via.render.MeshMaterialResource','via.render.MeshMaterialResourceHolder',resource_path..'.mdf2')
    if c.action=='physics_cube' then
        -- sdk.deserialize cannot resolve its native entry on this game build.
        -- Load our private inert UserData holder through the resource system.
        -- Native prefab instantiation owns registration of its Colliders.
        q.prefab_stem='unit_collision'
        q.loader=assert(sdk.create_userdata('app.user_data.AmuletPrefabHolder','mod/onimusha_mc/probe/'..q.prefab_stem..'_loader.user'),'UserData load failed'):add_ref()
        assert(typ(q.loader)=='app.user_data.AmuletPrefabHolder','Wrong loader type')
        q.folder=folder:add_ref()
        q.cc=assert(call(go,'getComponent(System.Type)',sdk.find_type_definition('via.physics.CharacterController'):get_runtime_type())):add_ref()
        q.phase='loading_userdata'
    else
        q.go=assert(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,q.name,folder)):add_ref()
        call(q.go,'get_Transform'):set_position(Vector4f.new(q.position.x,q.position.y,q.position.z,1),false)
        attach_mesh()
    end
    report()
end
re.on_application_entry('LateUpdateBehavior',function()
    q.frame=q.frame+1
    local ok,err=pcall(function()
        for i=#q.retired,1,-1 do
            if q.frame-q.retired[i].frame>10 and not call(q.retired[i].go,'get_Valid') then
                if q.retired[i].prefab then call(q.retired[i].prefab,'set_Standby',false) end
                table.remove(q.retired,i);q.destroyed=true;report()
            end
        end
        if q.go or q.prefab or q.loader or q.model_loader then
            local sc=scene_now()
            if (q.action=='render_section' or q.action=='render_userdata') and (q.phase=='loading' or q.phase=='loading_model_userdata') then
                local pause=sdk.get_managed_singleton('app.PauseManager')
                if pause and (call(pause,'get_IsMenuPause') or call(pause,'get_IsPlayerPause')) then
                    q.start=q.start+1;if q.object_start then q.object_start=q.object_start+1 end
                end
            end
            if not sc or sc:get_address()~=q.scene_address or (_G.onimusha_mc and _G.onimusha_mc.status().enabled)
                or q.frame-q.start>18000 then cleanup('removed_guard');report();return end
            if q.phase=='loading_model_userdata' then
                local mh=q.model_loader:get_field('_Mesh');local md=q.model_loader:get_field('_Material')
                if mh and md then
                    assert(sdk.is_managed_object(mh) and sdk.is_managed_object(md),'Invalid deserialized resource holders')
                    q.mesh_holder=mh:add_ref();q.material_holder=md:add_ref()
                    local prefix='mod/onimusha_mc/sections/'..q.asset_id..'/'..q.asset_id
                    assert(call(mh,'get_ResourcePath')==prefix..'.mesh' and call(md,'get_ResourcePath')==prefix..'.mdf2','Wrong deserialized paths')
                    q.go=assert(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,q.name,q.folder)):add_ref()
                    call(q.go,'get_Transform'):set_position(Vector4f.new(q.position.x,q.position.y,q.position.z,1),false)
                    attach_mesh()
                elseif q.frame-q.start>600 then error('Model UserData dependency timeout') end
            end
            if q.phase=='loading_userdata' then
                local prefab=q.loader:get_field('_BeadsPrefab')
                if prefab then
                    q.prefab=prefab:add_ref();assert(typ(q.prefab)=='via.Prefab','Wrong descriptor type')
                    assert(call(q.prefab,'get_Path')=='mod/onimusha_mc/probe/'..q.prefab_stem..'.pfb','Wrong prefab path')
                    call(q.prefab,'set_Standby',true);q.phase='loading_prefab'
                elseif q.frame-q.start>600 then error('UserData has not loaded its prefab descriptor') end
            end
            if q.phase=='loading_prefab' then
                if call(q.prefab,'get_Ready') then
                    local p=q.position
                    q.go=assert(call(q.prefab,'instantiate(via.vec3, via.Folder)',Vector3f.new(p.x,p.y,p.z),q.folder),'Prefab instantiation failed'):add_ref()
                    call(q.go,'set_Name',q.name)
                    q.colliders=assert(call(q.go,'getComponent(System.Type)',sdk.find_type_definition('via.physics.Colliders'):get_runtime_type()),'Prefab has no Colliders'):add_ref()
                    attach_mesh()
                elseif q.frame-q.start>600 then error('Prefab did not become ready') end
            end
        end
        if q.go then
            if not call(q.go,'get_Valid') then cleanup('removed_invalid');report();return end
            if q.phase=='visible' and q.motion then
                -- Isolated private face: exercise the same dynamic transform
                -- setters without attaching anything to a gameplay character.
                local angle=(q.frame-q.start)*.01;local t=call(q.go,'get_Transform')
                t:set_position(Vector4f.new(q.position.x+(q.tint_probe and 0 or math.sin(angle)*.25),q.position.y,q.position.z,1),false)
                t:set_rotation(q.tint_probe and Quaternion.new(1,0,0,0) or Quaternion.new(math.cos(angle*.5),0,math.sin(angle*.5),0))
                local scale=.5+.05*math.sin(angle)
                if q.replay_scale then
                    -- Long holds allow an actual screen comparison without
                    -- creating/exploding anything in the Minecraft save.
                    scale=math.floor((q.frame-q.start)/180)%2==0 and 1 or 1.3
                    t:set_position(Vector4f.new(q.position.x,q.position.y,q.position.z,1),false)
                    t:set_rotation(Quaternion.new(.70710678,0,.70710678,0))
                end
                call(t,'set_LocalScale',Vector3f.new(scale,q.replay_scale and scale or .75,1))
                if q.flash_probe then
                    assert(call(q.mesh,'getMaterialVariableName',0,4)=='VFX_CommonRimEmissive_Color')
                    assert(call(q.mesh,'getMaterialVariableName',0,23)=='VFX_CommonRimEmissive_Intensity')
                    call(q.mesh,'setMaterialFloat4',0,4,Vector4f.new(1,1,1,1))
                    call(q.mesh,'setMaterialFloat',0,23,scale>1 and 1 or 0)
                    call(q.mesh,'setMaterialFloat',0,24,1)
                    call(q.mesh,'setMaterialFloat',0,25,0)
                end
                if q.tint_probe then
                    call(q.mesh,'setMaterialFloat4',0,0,Vector4f.new(1,.55,.55,1))
                    if q.peer_mesh and call(q.peer_mesh,'get_MaterialReady')then
                        local v=call(q.peer_mesh,'getMaterialFloat4',0,0)
                        q.material_isolation={peer={x=v.x,y=v.y,z=v.z},isolated=math.abs(v.x-1)<.0001 and math.abs(v.y-1)<.0001 and math.abs(v.z-1)<.0001}
                    end
                end
                q.motion_updates=q.motion_updates+1
                if q.inspect_dynamic and q.frame%30==0 then
                    q.transform_probe={requested={x=scale,y=q.replay_scale and scale or .75,z=1},
                        local_scale=snapshot(call(t,'get_LocalScale'),2,{}),world_scale=snapshot(call(t,'get_Scale'),2,{}),
                        world_matrix=snapshot(call(t,'get_WorldMatrix'),2,{}),
                        tint=q.tint_probe and snapshot(call(q.mesh,'getMaterialFloat4',0,0),2,{})}
                end
            end
            if q.phase=='loading' then
                if call(q.mesh,'get_MeshReady') and call(q.mesh,'get_MaterialReady') then
                    assert(call(q.mesh,'get_MaterialNum')==1,'Unexpected material count')
                    call(q.mesh,'set_Enabled',true);call(q.go,'set_DrawSelf',true)
                    q.phase=q.colliders and 'checking_collision' or 'visible';q.ready=not q.colliders;report()
                    if q.tint_probe then
                        q.peer_go=assert(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,q.name..'_untinted',q.folder)):add_ref()
                        call(q.peer_go,'set_DrawSelf',false)
                        q.peer_mesh=assert(call(q.peer_go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type())):add_ref()
                        call(q.peer_mesh,'set_Enabled',false);call(q.peer_mesh,'set_StaticMesh',false)
                        call(q.peer_mesh,'setMesh',q.mesh_holder);call(q.peer_mesh,'set_Material',q.material_holder)
                        call(q.peer_mesh,'set_RenderOutputID',31)
                    end
                    if q.inspect_dynamic then
                        q.material_probe={variables={}}
                        local n=call(q.mesh,'getMaterialVariableNum',0);assert(n<=256,'Material variable bound')
                        for i=0,n-1 do
                            local name=call(q.mesh,'getMaterialVariableName',0,i)
                            local entry={index=i,name=name,type=call(q.mesh,'getMaterialVariableType',0,i)}
                            if name=='BaseColor' then entry.value=snapshot(call(q.mesh,'getMaterialFloat4',0,i),2,{}) end
                            q.material_probe.variables[#q.material_probe.variables+1]=entry
                        end
                        q.material_probe.metadata=state.metadata['via.Float4'];report()
                    end
                elseif q.frame-q.start>600 then error('Native resources did not become ready') end
            end
            if q.phase=='checking_collision' and q.frame-q.object_start>=6 and q.frame%30==0 then
                if verify_collision() then q.phase='visible_collision_verified';q.ready=true;report()
                elseif q.frame-q.object_start>3600 then error('Identity ray did not hit the prefab collider') end
            end
        end
        if q.frame%30~=1 then return end
        local c=json.load_file(CONTROL)
        if q.pending_id and (not c or c.enabled~=true) then
            q.pending_id=nil;q.phase='idle';report()
        end
        if c and c.enabled==true and type(c.id)=='string' and c.id~=q.id then
            if (c.action=='render_section' or c.action=='render_userdata') and not q.go and not q.prefab and not q.loader and not q.model_loader then
                local pause=sdk.get_managed_singleton('app.PauseManager')
                if not pause or call(pause,'get_IsMenuPause') or call(pause,'get_IsPlayerPause') then
                    q.pending_id=c.id;q.phase='waiting_gameplay';q.error=nil;report();return
                end
            end
            q.id=c.id;q.pending_id=nil;q.error=nil
            if c.action=='remove' then cleanup('removed');report()
            else start(c) end
        end
        if q.go or q.prefab or q.loader or q.model_loader then report() end
    end)
    if not ok then q.error=tostring(err);pcall(cleanup,'failed');pcall(report) end
end)
re.on_script_reset(function() pcall(cleanup,'reset_removed');pcall(report) end)
end
-- END NATIVE OBJECT PROBE
