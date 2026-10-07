-- Onimusha TDB82 / protocol14: reusable models on existing native collider GOs.
-- Shared model/material holders. No file conversion during placement.
-- MOD制作：LCPD15/LCPD拉灯
local q={frame=0,instances={},holders={},phase='disabled',created=0,removed=0,receipts=0}
local library=json.load_file('onimusha_mc/native_block_library.json') or {}
local function call(o,n,...) assert(o,n);return o:call(n,...) end
local function pin(o) return assert(o):add_ref() end
local function key(p) return p.x..':'..p.y..':'..p.z end
local function holder(rt,ht,path)
    local r=pin(sdk.create_resource(rt,path));local ok,h=pcall(function()return pin(r:create_holder(ht))end);r:release()
    if not ok then error(h) end;return h
end
local function resources(kind)
    if q.holders[kind] then return q.holders[kind] end
    local row=assert(library.items and library.items[tostring(kind)],'Missing cube kind '..kind)
    local id=row.asset_id;assert(type(id)=='string' and #id==28 and id:match('^section_%x+$'),'Invalid resource ID')
    local prefix='mod/onimusha_mc/sections/'..id..'/'..id
    local r={mesh=holder('via.render.MeshResource','via.render.MeshResourceHolder',prefix..'.mesh'),
        material=holder('via.render.MeshMaterialResource','via.render.MeshMaterialResourceHolder',prefix..'.mdf2')}
    q.holders[kind]=r;return r
end
local function remove(k)
    local b=q.instances[k];if not b then return end
    if call(b.owner.go,'get_Valid') then call(b.mesh,'set_Enabled',false) end
    q.instances[k]=nil;q.removed=q.removed+1
end
local function clear(reason)
    local keys={};for k in pairs(q.instances)do keys[#keys+1]=k end
    for _,k in ipairs(keys)do remove(k)end
    if q.context then q.context.bridge.release_section() end
    q.context=nil;q.phase=reason or 'disabled';q.ready=0
end
local function attach(owner,p)
    local r=resources(p.kind)
    -- Owner retains the Mesh through deferred destruction; never destroy its GameObject here.
    if not owner.display_mesh then
        owner.display_mesh=pin(call(owner.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
    end
    local mesh=owner.display_mesh
    call(mesh,'set_Enabled',false);call(mesh,'set_StaticMesh',false)
    call(mesh,'setMesh',r.mesh);call(mesh,'set_Material',r.material)
    call(mesh,'set_RenderOutputID',31);call(mesh,'set_DrawShadowCast',true)
    owner.display_holders=r
    q.instances[key(p)]={owner=owner,mesh=mesh,p=p,start=q.frame,holders=r};q.created=q.created+1
end
local function tick()
    q.frame=q.frame+1;local c=q.context;if not c then return end
    if c.touch<q.frame-1 then clear('context_not_refreshed');return end
    local s=c.bridge.snapshot_native_instances()
    if not s or not s.ready or s.epoch~=c.epoch or s.world_id~=c.world_id or s.mc_pid~=c.mc_pid or s.generation~=c.generation then clear('waiting_snapshot');return end
    assert(type(s.cubes)=='table' and #s.cubes<=1280,'Invalid instance snapshot')
    local desired={};for _,p in ipairs(s.cubes)do desired[key(p)]=p end
    local blocks=assert(_G.onimusha_native_blocks,'Collision owner unavailable')
    local removed={}
    for k,b in pairs(q.instances)do
        local p=desired[k];local owner=p and blocks.display_owner(p.x,p.y,p.z)
        if not p or p.kind~=b.p.kind or owner~=b.owner then removed[#removed+1]=k end
    end
    for _,k in ipairs(removed)do remove(k)end
    local allocated=0
    for _,p in ipairs(s.cubes)do
        if not q.instances[key(p)]then
            local owner=blocks.display_owner(p.x,p.y,p.z)
            if owner and owner.ready and call(owner.go,'get_Valid')then
                attach(owner,p);allocated=allocated+1;if allocated>=4 then break end
            end
        end
    end
    local ready={};local show={}
    for _,b in pairs(q.instances)do
        if b.ready or (call(b.mesh,'get_MeshReady') and call(b.mesh,'get_MaterialReady'))then
            if not b.ready then assert(call(b.mesh,'get_MaterialNum')==1,'Wrong material count') end
            ready[#ready+1]=b.p;show[#show+1]=b
        elseif q.frame-b.start>600 then error('Cube resource timeout; overlay restored') end
    end
    if not c.bridge.ack_native_instances({epoch=c.epoch,cubes=ready})then clear('receipt_rejected');return end
    for _,b in ipairs(show)do if not b.ready then call(b.mesh,'set_Enabled',true);call(b.owner.go,'set_DrawSelf',true);b.ready=true end end
    q.ready=#ready;q.desired=#s.cubes;q.phase=#ready==#s.cubes and 'synchronized' or 'loading';q.receipts=q.receipts+1
end
local api={}
function api.update(c)
    if sdk.get_tdb_version()~=82 or c.units~=1 or type(c.bridge.snapshot_native_instances)~='function' then clear('unsupported_runtime');return end
    local k=table.concat({c.scene,c.epoch,c.world_id,c.mc_pid,c.generation},':')
    if q.failed_key==k then return end
    if not q.context or q.context.key~=k then clear('context_changed') end
    c.key=k;c.touch=q.frame;q.context=c
end
function api.stop()clear('disabled')end
function api.busy()return next(q.instances)~=nil end
function api.status()
    local count=0;for _ in pairs(q.instances)do count=count+1 end
    return{phase=q.phase,error=q.error,count=count,ready=q.ready or 0,desired=q.desired,created=q.created,removed=q.removed,
        receipts=q.receipts,limit=1280,radius=16,mode='prebuilt_instances',supported_kinds=16,live_conversion=false,shared_collision_objects=true}
end
_G.onimusha_native_sections=api
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick)
    if not ok then q.error=tostring(err);q.failed_key=q.context and q.context.key;pcall(clear,'failed');log.error('[Onimusha cube rendering] '..q.error) end
end)
re.on_script_reset(function()clear('script_reset');q.holders={};_G.onimusha_native_sections=nil end)
