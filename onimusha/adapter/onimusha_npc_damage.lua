-- OnimushaWotS TDB82 only. Observe registered native attacks, export numeric geometry.
-- Never create a native hurt target, call an attack, or fan out damage taken by the player.
-- MOD制作：LCPD15/LCPD拉灯
local q={frame=0,active=false,sent=0,failed=0,unsupported=0,missing_param=0,samples={}}
local function get(o,n,...)
    assert(o and o:get_type_definition():get_method(n),'Missing NPC attack getter '..n)
    return o:call(n,...)
end
local function field(o,n) return assert(o,'Missing object'):get_field(n) end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function vec(v) assert(v and finite(v.x) and finite(v.y) and finite(v.z),'Invalid attack point');return {x=v.x,y=v.y,z=v.z}end
local function capsule(c,ctx,g,offset)
    local a=ctx.map(vec(field(c,'p0')));local b=ctx.map(vec(field(c,'p1')));local r=field(c,'r')/ctx.units
    assert(finite(r) and r>0 and r<=64,'Invalid capsule radius')
    g[offset+1]=a.x;g[offset+2]=a.y;g[offset+3]=a.z;g[offset+4]=b.x;g[offset+5]=b.y;g[offset+6]=b.z;g[offset+7]=r
end
local function sphere(c,ctx,g,offset)
    local a=ctx.map(vec(get(c,'get_Center')));local r=get(c,'get_Radius')/ctx.units
    assert(finite(r) and r>0 and r<=64,'Invalid sphere radius')
    g[offset+1]=a.x;g[offset+2]=a.y;g[offset+3]=a.z;g[offset+4]=a.x;g[offset+5]=a.y;g[offset+6]=a.z;g[offset+7]=r
end
local function geometry(shape,ctx)
    local name=shape:get_type_definition():get_full_name();local g={};for i=1,24 do g[i]=0 end
    if name=='via.physics.CapsuleShape' or name=='via.physics.ContinuousCapsuleShape' then
        local c=get(shape,'get_Capsule');capsule(c,ctx,g,0)
        capsule(name=='via.physics.ContinuousCapsuleShape' and get(shape,'get_PreviousCapsule') or c,ctx,g,7)
        return 1,g
    elseif name=='via.physics.SphereShape' or name=='via.physics.ContinuousSphereShape' then
        local c=get(shape,'get_Sphere');sphere(c,ctx,g,0)
        sphere(name=='via.physics.ContinuousSphereShape' and get(shape,'get_PreviousSphere') or c,ctx,g,7)
        return 1,g
    elseif name=='via.physics.BoxShape' then
        local box=get(shape,'get_Box');local p=ctx.map(vec(get(box,'get_Position')))
        local coord=field(box,'coord');local extent=vec(field(box,'extent'))
        g[1]=p.x;g[2]=p.y;g[3]=p.z
        for i=0,2 do
            local v=vec(coord[i]);local length=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
            assert(length>0.0001,'Degenerate OBB')
            g[4+i*3]=v.x/length;g[5+i*3]=v.y/length;g[6+i*3]=v.z/length
            g[13+i]=extent[({'x','y','z'})[i+1]]*length/ctx.units
        end
        return 2,g
    end
    q.unsupported=q.unsupported+1;q.last_unsupported=name
end
local function scan_switch(sw,entity,actor,ctx,rows,visited,depth,shell_param)
    if not sw or depth>3 or #rows>=128 then return end
    local key=sw:get_address();if visited[key] then return end;visited[key]=true
    local rsc=field(sw,'_RequestSetCollider');if not rsc then return end
    local group=get(sw,'getGroupFromType(app.ColliderSwitcher.COLLIDER_TYPE)',2)
    if group and get(group,'get_Initialized') then
        local groupid=get(group,'get_Id');local n=get(group,'get_NumRequestSets');assert(n>=0 and n<=256)
        local dictionary=field(sw,'_ReqSetRuntimeDataDic')
        for j=0,n-1 do
            if #rows>=128 then q.truncated=true;break end
            local id=get(group,'getRequestSetIdFromIndex(System.UInt32)',j)
            if get(rsc,'isRegisteredRequestSet(System.UInt32, System.UInt32)',groupid,id) then
                local ud=get(rsc,'getRequestSetUserData(System.UInt32, System.UInt32)',groupid,id)
                -- Gimmick-contact/action-break volumes are active while idle and are NOT character attacks.
                if ud and ud:get_type_definition():is_a('app.col_user_data.AttackParamBase')
                    and ud:get_type_definition():get_method('getAttackInfoCategory') and get(ud,'getAttackInfoCategory')==0 then
                    local runtime=get(dictionary,'get_Item',ud)
                    if runtime and runtime:get_type_definition():get_full_name()=='app.col_user_data.cAttackRuntimeData'
                        and field(runtime,'<IsInitialized>k__BackingField')==true then
                        local only=field(runtime,'_OnlyAttackTargets')
                        local unique=get(runtime,'getAttackUniqueID');local hit=get(runtime,'getHitID')
                        -- The native pre-hit implementation looks up by AttackUniqueID, not collider id/category.
                        local param=shell_param or get(get(entity,'get_AttackParamSupporter'),'findAttackParamByKey(System.UInt32)',unique)
                        if param and (not only or get(only,'get_Count')==0) and unique>=0 and hit>=0 then
                            local damage=get(param,'get_Attack');local origin=get(param,'get_OriginData')
                            local multi=get(param,'get_IsMultiHitEnabled') and get(param,'get_IsMultiHit')
                            local timer=get(param,'get_MultiHitTimer');local maxhits=get(origin,'get_MultiHitMaxCount')
                            -- Native attack strength -> the same 20-point/player-max-HP unit as IN_HURT.
                            -- MC's own armour/resistance runs afterwards; no native player defence is borrowed.
                            if finite(damage) and damage>0 then
                                local count=get(rsc,'getNumCollidablesFromIndex(System.UInt32, System.UInt32)',groupid,j)
                                assert(count>=0 and count<=128)
                                for k=0,count-1 do
                                    if #rows>=128 then break end
                                    local col=get(rsc,'getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)',groupid,j,k)
                                    local info=get(col,'get_UserData')
                                    if get(col,'get_Enabled') and info and field(info,'_CustomShapeType')==0 then
                                        local shape,g=geometry(get(col,'get_TransformedShape'),ctx)
                                        if shape then
                                            local p=ctx.map(vec(get(get(actor.obj,'get_GameObject'),'get_Transform'):get_position()))
                                            rows[#rows+1]={attacker=actor.id,attack=unique,hit=hit,shape=shape,geometry=g,
                                                x=p.x,y=p.y,z=p.z,damage=damage/ctx.max_health*20,
                                                flags=multi and 1 or 0,repeat_seconds=multi and math.max(0.05,timer) or 0,
                                                max_hits=multi and math.max(0,maxhits) or 1}
                                            if #q.samples<16 then q.samples[#q.samples+1]={actor=actor.id,name=actor.name,attack=unique,hit=hit,
                                                native_attack=damage,mc_damage=damage/ctx.max_health*20,shape=shape,multi=multi,timer=timer}end
                                        end
                                    end
                                end
                            end
                        elseif not param then q.missing_param=q.missing_param+1 end
                    end
                end
            end
        end
    end
    local children=field(sw,'_Children')
    if children then
        local n=get(children,'get_Count');assert(n<=64)
        for i=0,n-1 do scan_switch(get(children,'get_Item',i),entity,actor,ctx,rows,visited,depth+1,shell_param)end
    end
end
local function collect(ctx)
    local rows,owners={},{};q.truncated=false;q.shells=0
    for _,actor in pairs(ctx.actors)do
        local ok,err=pcall(function()
            local go=get(actor.obj,'get_GameObject')
            if not get(go,'get_Valid') or get(actor.health,'get_Health')<=0 then return end
            local entity=get(get(actor.obj,'get_CharacterEntityHolder'),'get_Entity')
            owners[go:get_address()]=actor
            local components=field(entity,'<CharacterComponents>k__BackingField')
            scan_switch(field(components,'<ColliderSwitcher>k__BackingField'),entity,actor,ctx,rows,{},0)
        end)
        if not ok then q.failed=q.failed+1;q.error=tostring(err):sub(1,300)end
    end
    -- Enemy-owned shells use the same registered collision windows. Do not echo player-owned
    -- TNT/explosion shells back into MC: vanilla already handles their mob damage.
    local shell_type=sdk.find_type_definition('app.AppShell')
    if shell_type and next(owners) then
        local ok,err=pcall(function()
            local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
            local shells=get(scene,'findComponents(System.Type)',shell_type:get_runtime_type()):get_elements()
            assert(#shells<=2048,'Unexpected shell pool size')
            for _,shell in ipairs(shells)do
                if #rows>=128 then q.truncated=true;break end
                local owner=get(shell,'get_ShellOwner')
                local actor=owner and owners[owner:get_address()]
                if not actor then local shooter=field(shell,'<ShellShooter>k__BackingField');actor=shooter and owners[shooter:get_address()] end
                if actor then
                    local hit=field(shell,'_ColHitComponent');local info=get(shell,'get_AttackInfo')
                    local param=info and field(info,'AttackParam')
                    if hit and param then
                        local sw=field(hit,'_ColSwitcher')
                        if sw and not field(hit,'_DisableRequested') and not field(hit,'_UnregistRequested') then
                            scan_switch(sw,nil,actor,ctx,rows,{},0,param);q.shells=q.shells+1
                        end
                    end
                end
            end
        end)
        if not ok then q.failed=q.failed+1;q.error=tostring(err):sub(1,300)end
    end
    return rows
end
local function tick()
    q.frame=q.frame+1
    local b=_G.onimusha_mc;local adapter=_G.onimusha_adapter_lifecycle
    if not b or type(b.publish_attacks)~='function' then q.active=false;q.mode='requires_protocol_16';return end
    local ctx=adapter and adapter.combat_context and adapter.combat_context()
    if not ctx then b.publish_attacks(false,{});q.active=false;q.mode='off';return end
    assert(sdk.get_tdb_version()==82,'Unsupported NPC damage TDB')
    local started=os.clock();local rows=collect(ctx);q.scan_ms=(os.clock()-started)*1000
    q.scan_max_ms=math.max(q.scan_max_ms or 0,q.scan_ms)
    q.active=true;q.mode='native_attack_volumes';q.current=#rows
    if b.publish_attacks(true,rows) then q.sent=q.sent+#rows else q.failed=q.failed+1;q.error='Attack ring rejected batch'end
end
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick)
    if not ok then
        q.failed=q.failed+1;q.error=tostring(err):sub(1,300);q.active=false
        if _G.onimusha_mc and _G.onimusha_mc.publish_attacks then _G.onimusha_mc.publish_attacks(false,{})end
    end
    if q.frame%120==0 then json.dump_file('onimusha_npc_damage_status.json',q)end
end)
re.on_script_reset(function()
    if _G.onimusha_mc and _G.onimusha_mc.publish_attacks then _G.onimusha_mc.publish_attacks(false,{})end
    q.active=false
end)
-- Fixed-file read-only diagnostic entry. Uses identical getters/conversion but never publishes.
return {preflight=function(ctx)
    assert(sdk.get_tdb_version()==82,'Unsupported NPC damage TDB')
    local rows=collect(ctx);local shapes={};local errors={};local params={}
    for _,actor in pairs(ctx.actors)do
        local ok,err=pcall(function()
            local entity=get(get(actor.obj,'get_CharacterEntityHolder'),'get_Entity')
            local sw=field(field(entity,'<CharacterComponents>k__BackingField'),'<ColliderSwitcher>k__BackingField')
            local rsc=field(sw,'_RequestSetCollider');local group=get(sw,'getGroupFromType(app.ColliderSwitcher.COLLIDER_TYPE)',2)
            local id=get(group,'get_Id');local n=get(group,'get_NumRequestSets');assert(n<=256)
            for j=0,n-1 do
                local setid=get(group,'getRequestSetIdFromIndex(System.UInt32)',j)
                local ud=get(rsc,'getRequestSetUserData(System.UInt32, System.UInt32)',id,setid)
                if ud and ud:get_type_definition():is_a('app.col_user_data.AttackParamBase') then
                    local runtime=get(field(sw,'_ReqSetRuntimeDataDic'),'get_Item',ud)
                    if runtime then
                        local unique=get(runtime,'getAttackUniqueID')
                        local param=get(get(entity,'get_AttackParamSupporter'),'findAttackParamByKey(System.UInt32)',unique)
                        if param then params[#params+1]={unique=unique,attack=get(param,'get_Attack'),
                            multi_enabled=get(param,'get_IsMultiHitEnabled'),multi=get(param,'get_IsMultiHit'),
                            timer=get(param,'get_MultiHitTimer'),max_hits=get(get(param,'get_OriginData'),'get_MultiHitMaxCount')}end
                    end
                end
                local count=get(rsc,'getNumCollidablesFromIndex(System.UInt32, System.UInt32)',id,j);assert(count<=128)
                for k=0,count-1 do
                    local col=get(rsc,'getCollidableFromIndex(System.UInt32, System.UInt32, System.UInt32)',id,j,k)
                    if get(col,'get_Enabled') then
                        local shape=get(col,'get_TransformedShape');local ok,g=pcall(function()local kind,data=geometry(shape,ctx);return {kind=kind,type=shape:get_type_definition():get_full_name(),geometry=data}end)
                        if ok then shapes[#shapes+1]=g else errors[#errors+1]=tostring(g)end
                    end
                end
            end
        end)
        if not ok then errors[#errors+1]=tostring(err)end
    end
    return {state=q,rows=rows,shapes=shapes,params=params,errors=errors,read_only=true}
end}
