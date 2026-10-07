-- Onimusha TDB82 only: bounded exact unit-cube collision synchronization.
-- Uses the player/enemy-tested native prefab. No navigation or render components.
-- MOD制作：LCPD15/LCPD拉灯
local q={frame=0,blocks={},retired={},desired={},order={},phase='disabled'}
local MAX_CUBES=1280
local function call(o,n,...) assert(o,n);return o:call(n,...) end
local function pin(o) return assert(o):add_ref() end
local function type_name(o) return o:get_type_definition():get_full_name() end
local function component(go,n) return call(go,'getComponent(System.Type)',sdk.find_type_definition(n):get_runtime_type()) end
local function retire(key)
    local b=q.blocks[key];if not b then return end
    if call(b.go,'get_Valid') then
        if b.colliders then call(b.colliders,'set_Enabled',false) end
        sdk.find_type_definition('via.GameObject'):get_method('destroy(via.GameObject)'):call(nil,b.go)
    end
    b.retired=q.frame;q.retired[#q.retired+1]=b;q.blocks[key]=nil
end
local function clear(reason)
    local keys={};for k in pairs(q.blocks) do keys[#keys+1]=k end
    for _,k in ipairs(keys) do retire(k) end
    q.context=nil;q.desired={};q.order={};q.phase=reason or 'disabled'
end
local function reap()
    for i=#q.retired,1,-1 do
        local b=q.retired[i]
        if q.frame-b.retired>10 and not call(b.go,'get_Valid') then table.remove(q.retired,i) end
    end
    if not q.context and next(q.blocks)==nil and #q.retired==0 then
        if q.prefab then call(q.prefab,'set_Standby',false) end
        q.prefab=nil;q.loader=nil
    end
end
local function context_key(c) return table.concat({c.scene,c.epoch,c.world_id,c.mc_pid,c.generation},':') end
local function integer(v) return type(v)=='number' and v==math.floor(v) and math.abs(v)<30000000 end
local function snapshot(c)
    local s=c.bridge.snapshot_full_cubes({x=c.x,y=c.y,z=c.z,radius=16,limit=MAX_CUBES,epoch=c.epoch})
    if not s or not s.ready or s.epoch~=c.epoch or s.world_id~=c.world_id or s.mc_pid~=c.mc_pid or s.generation~=c.generation then
        clear('waiting_for_current_snapshot');return false
    end
    assert(type(s.cubes)=='table' and #s.cubes<=MAX_CUBES,'Invalid cube snapshot size')
    local desired,order={},{}
    for _,p in ipairs(s.cubes) do
        assert(integer(p.x) and integer(p.y) and integer(p.z),'Invalid cube coordinate')
        local k=p.x..':'..p.y..':'..p.z;assert(not desired[k],'Duplicate cube')
        desired[k]=p;order[#order+1]=k
    end
    q.desired=desired;q.order=order;q.revision=s.revision;q.total=s.total;q.truncated=s.truncated;q.snapshot_frame=q.frame
    local removed={};for k in pairs(q.blocks) do if not desired[k] then removed[#removed+1]=k end end
    for _,k in ipairs(removed) do retire(k) end
    return true
end
local function load_prefab()
    if not q.loader then
        q.loader=pin(sdk.create_userdata('app.user_data.AmuletPrefabHolder','mod/onimusha_mc/probe/unit_collision_loader.user'))
        assert(type_name(q.loader)=='app.user_data.AmuletPrefabHolder','Wrong loader type');q.load_start=q.frame
    end
    if not q.prefab then
        local p=q.loader:get_field('_BeadsPrefab')
        if p then
            q.prefab=pin(p);assert(type_name(p)=='via.Prefab','Wrong prefab type')
            assert(call(p,'get_Path')=='mod/onimusha_mc/probe/unit_collision.pfb','Wrong prefab path')
            call(p,'set_Standby',true)
        end
    end
    if q.prefab and call(q.prefab,'get_Ready') then return true end
    assert(q.frame-q.load_start<600,'Collision prefab load timeout');q.phase='loading_prefab';return false
end
local function tick()
    q.frame=q.frame+1;reap()
    local c=q.context
    if not c then return end
    if c.touch<q.frame-1 then clear('context_not_refreshed');return end
    if q.frame-(q.snapshot_frame or -100)>=6 and not snapshot(c) then return end
    if not next(q.desired) then q.phase='empty';return end
    if not load_prefab() then return end
    local count=0
    for _ in pairs(q.blocks) do count=count+1 end
    -- Inspect a rotating slice, not 1280 SDK objects in every frame.
    for _=1,math.min(16,#q.order) do
        q.check_cursor=((q.check_cursor or 0)%#q.order)+1
        local b=q.blocks[q.order[q.check_cursor]]
        if b then
        if not call(b.go,'get_Valid') then error('Native block destroyed externally') end
        if not b.ready then
            if call(b.colliders,'get_Ready') then
                assert(call(b.colliders,'getCollidersCount')==1,'Wrong collider count')
                b.collider=pin(call(b.colliders,'getCollider(System.UInt32)',0))
                assert(type_name(call(b.collider,'get_Shape'))=='via.physics.BoxShape','Wrong collider shape')
                assert(call(b.collider,'get_GameObject'):get_address()==b.go:get_address(),'Wrong collider owner')
                b.ready=call(b.collider,'get_Ready')==true
            end
            assert(b.ready or q.frame-b.start<600,'Native collider readiness timeout')
        end
        end
    end
    -- Include deferred removals in the cap. At most two allocations per frame.
    if count+#q.retired<MAX_CUBES then
        local allocated=0
        for _,k in ipairs(q.order) do
            if not q.blocks[k] then
                local p=q.desired[k];local pos=c.to_native(p.x+.5,p.y+.5,p.z+.5)
                local go=pin(call(q.prefab,'instantiate(via.vec3, via.Folder)',Vector3f.new(pos.x,pos.y,pos.z),c.folder))
                local b={go=go,start=q.frame,prefab=q.prefab,loader=q.loader};q.blocks[k]=b
                call(go,'set_Name','OMC_MCBlock_'..k)
                b.colliders=pin(component(go,'via.physics.Colliders'));count=count+1;allocated=allocated+1
                if allocated>=2 or count+#q.retired>=MAX_CUBES then break end
            end
        end
    end
    q.phase=count==#q.order and 'synchronized' or 'creating';q.count=count
end
local api={}
function api.update(c)
    if sdk.get_tdb_version()~=82 or c.units~=1 or type(c.bridge.snapshot_full_cubes)~='function' then
        clear('unsupported_runtime');return
    end
    local key=context_key(c)
    if q.failed_key==key then return end
    if not q.context or q.context.key~=key then
        clear('context_changed');q.snapshot_frame=nil;q.error=nil
    end
    c.key=key;c.touch=q.frame;q.context=c
end
function api.stop() clear('disabled') end
function api.busy() return next(q.blocks)~=nil or #q.retired>0 end
-- Display borrows the already owned collider object; its lifetime remains here.
function api.display_owner(x,y,z) return q.blocks[x..':'..y..':'..z] end
function api.status()
    local count,ready=0,0;for _,b in pairs(q.blocks) do count=count+1;if b.ready then ready=ready+1 end end
    return {phase=q.phase,error=q.error,count=count,ready=ready,retiring=#q.retired,desired=#q.order,
        total=q.total,truncated=q.truncated,revision=q.revision,radius=16,limit=MAX_CUBES,full_cubes_only=true}
end
_G.onimusha_native_blocks=api
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick)
    if not ok then
        q.error=tostring(err);q.failed_key=q.context and q.context.key
        local cleaned,why=pcall(clear,'failed');if not cleaned then q.error=q.error..'; cleanup: '..tostring(why) end
        log.error('[Onimusha native blocks] '..q.error)
    end
end)
re.on_script_reset(function() clear('script_reset');_G.onimusha_native_blocks=nil end)
