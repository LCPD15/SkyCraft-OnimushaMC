-- Onimusha TDB82: live opaque MC section meshes, native scene light/depth/shadows.
-- Files are generated outside the game; only the gameplay callback touches RE objects.
-- MOD制作：LCPD15/LCPD拉灯
local ROOT='onimusha_mc/native_sections/'
local q={frame=0,objects={},retired={},desired={},cache={},phase='disabled',converted=0,removed=0}
local function call(o,n,...) assert(o,n);return o:call(n,...) end
local function pin(o) return assert(o):add_ref() end
local function key(p) return p.sx..':'..p.sy..':'..p.sz end
local function args(p,c) return {sx=p.sx,sy=p.sy,sz=p.sz,revision=p.revision,epoch=c.epoch,mask=p.mask} end
local function holder(rt,ht,path)
    local r=pin(sdk.create_resource(rt,path))
    local ok,h=pcall(function() return pin(r:create_holder(ht)) end);r:release()
    if not ok then error(h) end;return h
end
local function retire(k)
    local b=q.objects[k];if not b then return end
    if call(b.go,'get_Valid') then
        if b.mesh then call(b.mesh,'set_Enabled',false) end
        call(b.go,'set_DrawSelf',false)
        sdk.find_type_definition('via.GameObject'):get_method('destroy(via.GameObject)'):call(nil,b.go)
    end
    b.bridge.release_section(b.ack)
    b.retired=q.frame;q.retired[#q.retired+1]=b;q.objects[k]=nil;q.removed=q.removed+1
end
local function clear(reason)
    local ks={};for k in pairs(q.objects) do ks[#ks+1]=k end
    for _,k in ipairs(ks) do retire(k) end
    if q.context then q.context.bridge.release_section() end
    q.context=nil;q.desired={};q.phase=reason or 'disabled'
end
local function reap()
    for i=#q.retired,1,-1 do
        if q.frame-q.retired[i].retired>10 and not call(q.retired[i].go,'get_Valid') then table.remove(q.retired,i) end
    end
end
local function attach(p,r,c)
    assert(type(r.asset_id)=='string' and #r.asset_id==28 and r.asset_id:match('^section_%x+$'),'Invalid resource ID')
    assert(type(r.mask)=='string' and #r.mask>0 and #r.mask<=16384 and r.mask:match('^[a-f0-9]+$'),'Invalid native mask')
    local prefix='mod/onimusha_mc/sections/'..r.asset_id..'/'..r.asset_id
    local b={source=p,bridge=c.bridge,ack=args(p,c),start=q.frame,asset_id=r.asset_id}
    b.ack.mask=r.mask
    b.mh=holder('via.render.MeshResource','via.render.MeshResourceHolder',prefix..'.mesh')
    b.th=holder('via.render.MeshMaterialResource','via.render.MeshMaterialResourceHolder',prefix..'.mdf2')
    b.go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_Section_'..key(p),c.folder))
    q.objects[key(p)]=b -- Register before further SDK calls so a failure can always clean it up.
    call(b.go,'set_DrawSelf',false)
    local pos=c.to_native(p.sx*16,p.sy*16,p.sz*16)
    call(b.go,'get_Transform'):set_position(Vector4f.new(pos.x,pos.y,pos.z,1),false)
    b.mesh=pin(call(b.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
    call(b.mesh,'set_Enabled',false);call(b.mesh,'set_StaticMesh',false)
    call(b.mesh,'setMesh',b.mh);call(b.mesh,'set_Material',b.th)
    call(b.mesh,'set_RenderOutputID',31);call(b.mesh,'set_DrawShadowCast',true)
end
local function poll_job()
    if not q.pending or q.frame%15~=0 then return end
    local p=q.pending
    local r=json.load_file(ROOT..p.id..'/result.json')
    if not r then
        if q.frame-p.start>7200 then q.error='Converter timeout; overlay retained';q.cache[p.cache_key]={empty=true,error=q.error};q.pending=nil end
        return
    end
    assert(r.id==p.id and r.revision==p.row.revision and r.epoch==p.context.epoch and r.world==p.context.world_id
        and r.mc_pid==p.context.mc_pid and r.generation==p.context.generation,'Stale converter result')
    assert(type(r.section)=='table' and r.section[1]==p.row.sx and r.section[2]==p.row.sy and r.section[3]==p.row.sz,'Mismatched section result')
    if r.ok~=true then r.empty=true;q.error=r.error or 'Conversion rejected' end
    q.cache[p.cache_key]=r;q.pending=nil;q.last_conversion_seconds=r.seconds
    local n=0;for _ in pairs(q.cache) do n=n+1 end
    if n>128 then for k in pairs(q.cache) do if k~=p.cache_key then q.cache[k]=nil;break end end end
end
local function tick()
    q.frame=q.frame+1;reap();poll_job()
    local c=q.context;if not c then return end
    if c.touch<q.frame-1 then clear('context_not_refreshed');return end
    local s=c.bridge.snapshot_sections()
    if not s or not s.ready or s.epoch~=c.epoch or s.world_id~=c.world_id or s.mc_pid~=c.mc_pid or s.generation~=c.generation then
        clear('waiting_snapshot');return
    end
    assert(type(s.sections)=='table' and #s.sections<=16,'Invalid section snapshot')
    q.jobs=s.jobs
    local desired={};for _,p in ipairs(s.sections) do
        local k=key(p);local old=q.desired[k]
        p.since=old and old.revision==p.revision and old.since or q.frame
        desired[k]=p
    end
    q.desired=desired
    local removed={};for k,b in pairs(q.objects) do
        if not desired[k] or desired[k].revision~=b.source.revision then removed[#removed+1]=k end
    end
    for _,k in ipairs(removed) do retire(k) end
    local count=0
    for k,b in pairs(q.objects) do
        count=count+1
        if not call(b.go,'get_Valid') then error('Native section object destroyed externally') end
        if not b.ready and call(b.mesh,'get_MeshReady') and call(b.mesh,'get_MaterialReady') then
            assert(call(b.mesh,'get_MaterialNum')==1,'Wrong material count')
            if b.bridge.ack_section(b.ack) then
                call(b.mesh,'set_Enabled',true);call(b.go,'set_DrawSelf',true);b.ready=true;q.converted=q.converted+1
            else retire(k) end
        elseif b.ready then
            if not b.bridge.ack_section(b.ack) then retire(k) end
        elseif q.frame-b.start>600 then
            q.cache[c.key..':'..k..':'..b.source.revision]={empty=true,error='Native resource readiness timeout'}
            q.error='Native resources not ready; overlay retained';retire(k)
        end
    end
    if q.frame%30==1 then q.worker=json.load_file(ROOT..'worker.json') end
    local worker=q.worker
    local worker_ready=worker and worker.state=='ready' and worker.host_pid==s.host_pid and type(worker.alive_at)=='number' and os.time()-worker.alive_at<120
    q.phase=worker_ready and 'synchronizing' or 'waiting_worker'
    -- At most one disk capture/conversion pending and one RE object allocation per frame.
    if count+#q.retired<16 then
        for _,p in ipairs(s.sections) do
            local k=key(p);local ck=c.key..':'..k..':'..p.revision
            if not q.objects[k] then
                local r=q.cache[ck]
                if r and not r.empty then attach(p,r,c);break end
                if not r and not q.pending and worker_ready and q.frame-desired[k].since>=12 then
                    local id=c.bridge.capture_section(args(p,c))
                    if id then
                        assert(type(id)=='string' and #id<80 and id:match('^%d+_%d+_%d+$'),'Invalid capture ID')
                        q.pending={id=id,row=p,context=c,cache_key=ck,start=q.frame}
                    end
                    break
                end
            end
        end
    end
end
local api={}
function api.update(c)
    if sdk.get_tdb_version()~=82 or c.units~=1 or type(c.bridge.snapshot_sections)~='function' then clear('unsupported_runtime');return end
    local k=table.concat({c.scene,c.epoch,c.world_id,c.mc_pid,c.generation},':')
    if q.failed_key==k then return end
    if not q.context or q.context.key~=k then clear('context_changed') end
    c.key=k;c.touch=q.frame;q.context=c
end
function api.stop() clear('disabled') end
function api.busy() return next(q.objects)~=nil or #q.retired>0 end
function api.status()
    local count,ready=0,0;for _,b in pairs(q.objects) do count=count+1;if b.ready then ready=ready+1 end end
    return {phase=q.phase,error=q.error,count=count,ready=ready,retiring=#q.retired,converted=q.converted,removed=q.removed,
        pending=q.pending and q.pending.id,jobs=q.jobs,last_conversion_seconds=q.last_conversion_seconds,limit=16,radius=48,
        opaque_static_only=true,worker=q.worker and q.worker.state}
end
_G.onimusha_native_sections=api
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick)
    if not ok then
        q.error=tostring(err);q.failed_key=q.context and q.context.key
        local done,why=pcall(clear,'failed');if not done then q.error=q.error..'; cleanup: '..tostring(why) end
        log.error('[Onimusha native sections] '..q.error)
    end
end)
re.on_script_reset(function() clear('script_reset');_G.onimusha_native_sections=nil end)
