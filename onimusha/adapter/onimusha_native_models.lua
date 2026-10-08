-- Onimusha TDB82 / protocol15: automatic complete-model conversion and shared native resources.
-- Cache complete appearances; only new geometry/texture/state needs conversion.
-- MOD制作：LCPD15/LCPD拉灯
local q={frame=0,instances={},holders={},warm_retired={},phase='disabled',created=0,removed=0,receipts=0}
local pending={} -- host/model IDs never reused by the DLL during its lifetime
local lights={}
local dynamics={}
local function owned_count()
    local n=#q.warm_retired
    for _,b in pairs(q.instances)do if b.owner.owned_display then n=n+1 end end
    for _,r in pairs(q.holders)do if r.go then n=n+1 end end
    for _ in pairs(lights)do n=n+1 end
    for _ in pairs(dynamics)do n=n+1 end
    return n
end
local function call(o,n,...) assert(o,n);return o:call(n,...) end
local function pin(o) return assert(o):add_ref() end
local function optional(o,n)
    local ok,value=pcall(call,o,n);if ok then return value end;return tostring(value)
end
local function read_json(path)
    -- REFramework logs an error for every missing JSON; requests intentionally
    -- have no result until the background worker publishes one.
    if fs and fs.read and fs.read(path)=='' then return nil end
    return json.load_file(path)
end
local function key(p) return p.x..':'..p.y..':'..p.z end
local function holder(rt,ht,path)
    local r=pin(sdk.create_resource(rt,path));local ok,h=pcall(function()return pin(r:create_holder(ht))end);r:release()
    if not ok then error(h) end;return h
end
local function retire_warmer(r)
    if not r.go then return end
    if call(r.go,'get_Valid') then
        if r.warm_mesh then call(r.warm_mesh,'set_Enabled',false) end
        call(r.go,'set_DrawSelf',false)
        sdk.find_type_definition('via.GameObject'):get_method('destroy(via.GameObject)'):call(nil,r.go)
    end
    q.warm_retired[#q.warm_retired+1]={go=r.go,mesh=r.warm_mesh,frame=q.frame}
    r.go=nil;r.warm_mesh=nil
end
local function poll_resources()
    local pause=sdk.get_managed_singleton and sdk.get_managed_singleton('app.PauseManager')
    q.pause={menu=pause and optional(pause,'get_IsMenuPause'),player=pause and optional(pause,'get_IsPlayerPause')}
    for i=#q.warm_retired,1,-1 do
        local b=q.warm_retired[i]
        if q.frame-b.frame>10 and not call(b.go,'get_Valid') then table.remove(q.warm_retired,i) end
    end
    for _,r in pairs(q.holders) do
        if r.go then
            if q.frame%60==0 then
                r.diagnostic={model=r.kind,asset=r.asset,age_frames=q.frame-r.start,mesh_ready=optional(r.warm_mesh,'get_MeshReady'),
                    material_ready=optional(r.warm_mesh,'get_MaterialReady'),materials=optional(r.warm_mesh,'get_MaterialNum'),
                    enabled=optional(r.warm_mesh,'get_Enabled'),draw=optional(r.go,'get_Draw'),update=optional(r.go,'get_Update'),
                    folder=optional(call(r.go,'get_Folder'),'get_Path')}
            end
            if q.pause.menu==true or q.pause.player==true or q.foreground==false then r.start=r.start+1 end
            if call(r.warm_mesh,'get_MeshReady') and call(r.warm_mesh,'get_MaterialReady') then
                assert(call(r.warm_mesh,'get_MaterialNum')==1,'Wrong preloaded material count')
                r.ready=true;retire_warmer(r)
            elseif q.frame-r.start>600 then
                r.attempts=(r.attempts or 0)+1;retire_warmer(r)
                if r.attempts>=3 then r.error='Resource preload timeout after 3 attempts'
                else r.retry_frame=q.frame+60 end
            end
        end
    end
end
local function resources(kind,c,p,priority)
    -- The DLL Lua API supplies doubles (2.0), while JSON object keys are "2".
    kind=assert(math.tointeger(kind),'Invalid cube kind');assert(kind>=1 and kind<=0xffffffff,'Invalid model ID')
    local r=q.holders[kind]
    if r and (r.ready or r.go or r.error) then return r end
    if r and r.retry_frame and q.frame<r.retry_frame then return nil end
    if not r then
        local job=pending[kind]
        if not job then
            local worker=read_json('onimusha_mc/native_models/worker.json')
            q.worker=worker
            if not worker or worker.host_pid~=c.host_pid or worker.state~='ready' or math.abs(os.time()-worker.alive_at)>30 then return nil end
            if q.frame%3~=0 then return nil end
            local id=c.bridge.capture_native_model({model=kind,epoch=c.epoch,priority=priority or 0})
            if id then pending[kind]={id=id,epoch=c.epoch,world=c.world_id,mc_pid=c.mc_pid,generation=c.generation} end
            return nil
        end
        if not job.result and q.frame%15==0 then
            local value=read_json('onimusha_mc/native_models/'..job.id..'/result.json')
            if value then
                assert(value.id==job.id and value.model==kind and value.epoch==job.epoch and value.world==job.world and value.mc_pid==job.mc_pid and value.generation==job.generation,'Stale model result')
                job.result=value
            end
        end
        if not job.result then return nil end
        if job.result.ok and job.result.empty then
            r={ready=true,empty=true};q.holders[kind]=r;return r
        end
        if not job.result.ok or not job.result.asset_id then
            r={error=job.result.error or 'unsupported_model'};q.holders[kind]=r;return r
        end
    end
    if q.resource_allocated>=2 or owned_count()>=2560 then return nil end
    local loading=0;for _,value in pairs(q.holders)do if value.go then loading=loading+1 end end
    if loading>=8 then return nil end
    q.resource_allocated=q.resource_allocated+1
    if not r then
        local row=assert(pending[kind].result,'Missing model result')
        local id=row.asset_id;assert(type(id)=='string' and #id==28 and id:match('^section_%x+$'),'Invalid resource ID')
        local prefix='mod/onimusha_mc/sections/'..id..'/'..id
        r={mesh=holder('via.render.MeshResource','via.render.MeshResourceHolder',prefix..'.mesh'),
            material=holder('via.render.MeshMaterialResource','via.render.MeshMaterialResourceHolder',prefix..'.mdf2')}
        r.kind=kind;r.asset=id
        q.holders[kind]=r
    end
    -- A fresh hidden GO follows the proven render_section cold-load path. Attaching a
    -- cold resource directly to an already initialized collider GO can leave MeshReady false.
    -- This staging object is per KIND, never per placed block, and retires when ready.
    r.go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_CubePreload_'..kind,c.folder))
    local pos=c.to_native(p.x+.5,p.y+.5,p.z+.5)
    call(r.go,'get_Transform'):set_position(Vector4f.new(pos.x,pos.y,pos.z,1),false)
    r.start=q.frame;call(r.go,'set_DrawSelf',false)
    r.warm_mesh=pin(call(r.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
    call(r.warm_mesh,'set_Enabled',false);call(r.warm_mesh,'set_StaticMesh',false)
    call(r.warm_mesh,'setMesh',r.mesh);call(r.warm_mesh,'set_Material',r.material)
    call(r.warm_mesh,'set_RenderOutputID',31);call(r.warm_mesh,'set_DrawShadowCast',true)
    -- Keep drawing hidden, but let the component initialize cold resources.
    call(r.warm_mesh,'set_Enabled',true)
    return r
end
local function remove(k)
    local b=q.instances[k];if not b then return end
    if call(b.owner.go,'get_Valid') then call(b.mesh,'set_Enabled',false) end
    if b.owner.owned_display then
        retire_warmer({go=b.owner.go,warm_mesh=b.mesh})
    end
    q.instances[k]=nil;q.removed=q.removed+1
end
local function clear(reason)
    local keys={};for k in pairs(q.instances)do keys[#keys+1]=k end
    for _,k in ipairs(keys)do remove(k)end
    for _,r in pairs(q.holders) do retire_warmer(r) end
    for _,r in pairs(lights)do retire_warmer(r)end;lights={}
    for _,r in pairs(dynamics)do retire_warmer(r)end;dynamics={}
    if q.context then q.context.bridge.release_section() end
    q.context=nil;q.phase=reason or 'disabled';q.ready=0;q.dynamic_streams={}
end
local function update_lights(s,c)
    assert(type(s.lights or {})=='table' and #(s.lights or {})<=64,'Light bound exceeded')
    local want={};for _,p in ipairs(s.lights or {})do want[key(p)]=p end
    for k,r in pairs(lights)do if not want[k]then retire_warmer(r);lights[k]=nil end end
    local made=0
    for k,p in pairs(want)do
        local r=lights[k]
        if not r and made<2 and owned_count()<2560 then
            local go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_Light_'..k,c.folder))
            r={go=go};lights[k]=r;made=made+1
            local pos=c.to_native(p.x+.5,p.y+.7,p.z+.5)
            call(go,'get_Transform'):set_position(Vector4f.new(pos.x,pos.y,pos.z,1),false)
            r.warm_mesh=pin(call(go,'createComponent(System.Type)',sdk.find_type_definition('via.render.PointLight'):get_runtime_type()))
            call(r.warm_mesh,'set_Enabled',false);call(r.warm_mesh,'set_RenderOutputID',31)
            call(r.warm_mesh,'set_Unit',0);call(r.warm_mesh,'set_ShadowEnable',false)
            call(r.warm_mesh,'set_SourceRadius',0.06)
        end
        if r then
            local color=assert(math.tointeger(p.color));local level=assert(tonumber(p.level));assert(level>=1 and level<=15)
            call(r.warm_mesh,'set_Color',Vector3f.new((color&255)/255,((color>>8)&255)/255,((color>>16)&255)/255))
            call(r.warm_mesh,'set_Radius',math.max(2,level*.4))
            local kind=(color>>24)&15;local variation=1
            local phase=p.x*.37+p.y*.19+p.z*.71
            if kind==1 then variation=.94+.04*math.sin(q.frame*.51+phase)+.02*math.sin(q.frame*.23-phase)
            elseif kind==2 then variation=.97+.03*math.sin(q.frame*.035+phase) end
            call(r.warm_mesh,'set_Intensity',180*(level/15)^2*variation)
            call(r.warm_mesh,'set_Enabled',true);call(r.go,'set_DrawSelf',true)
        end
    end
end
local function update_dynamic(c)
    if type(c.bridge.snapshot_native_dynamic)~='function' then return end
    local s=c.bridge.snapshot_native_dynamic()
    if not s or not s.ready or s.epoch~=c.epoch then
        for _,r in pairs(dynamics)do retire_warmer(r)end;dynamics={};return
    end
    local wanted={}
    for _,stream in ipairs({'avatar','scene','hands'})do
        s[stream]=s[stream] or {}
        assert(type(s[stream])=='table' and #s[stream]<=512,'Invalid dynamic snapshot')
        for _,p in ipairs(s[stream])do wanted[stream..':'..p.first]=p end
    end
    for k,r in pairs(dynamics)do
        if not wanted[k] or wanted[k].kind~=r.kind then retire_warmer(r);dynamics[k]=nil end
    end
    local made=0;local count=0;q.dynamic_streams={}
    for _,stream in ipairs({'avatar','scene','hands'})do
        local receipts={};local show={};local errors={}
        for _,p in ipairs(s[stream])do
            local k=stream..':'..p.first;local r=dynamics[k]
            local asset=resources(p.kind,c,p,1)
            if asset and asset.error then errors[tostring(p.kind)]=asset.error end
            if not r and asset and asset.ready and not asset.empty and made<8 and owned_count()<2560 then
                r={kind=p.kind};dynamics[k]=r;made=made+1
                r.go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_Dynamic_'..k,c.folder))
                call(r.go,'set_DrawSelf',false)
                r.warm_mesh=pin(call(r.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
                call(r.warm_mesh,'set_Enabled',false);call(r.warm_mesh,'set_StaticMesh',false)
                call(r.warm_mesh,'setMesh',asset.mesh);call(r.warm_mesh,'set_Material',asset.material)
                call(r.warm_mesh,'set_RenderOutputID',31);call(r.warm_mesh,'set_DrawShadowCast',stream~='hands')
                r.asset=asset
            end
            if asset and asset.empty then receipts[#receipts+1]={first=p.first,kind=p.kind} end
            if r then
                -- The canonical resource is one unit rectangle. Minecraft supplies
                -- its actual animated rigid transform; no per-pose disk conversion.
                local transform=call(r.go,'get_Transform');local pos=c.to_native(p.x,p.y,p.z)
                transform:set_position(Vector4f.new(pos.x,pos.y,pos.z,1),false)
                transform:set_rotation(Quaternion.new(p.qw,p.qx,p.qy,p.qz))
                call(transform,'set_LocalScale',Vector3f.new(p.sx,p.sy,1))
                if call(r.warm_mesh,'get_MeshReady') and call(r.warm_mesh,'get_MaterialReady') then
                    receipts[#receipts+1]={first=p.first,kind=p.kind};show[#show+1]=r
                end
            end
        end
        local complete=stream~='hands' or (s.hands_complete and #receipts==#s.hands)
        q.dynamic_streams[stream]={desired=#s[stream],ready=#receipts,errors=errors,complete=complete}
        if c.bridge.ack_native_dynamic({epoch=c.epoch,avatar=stream=='avatar',hands=stream=='hands',faces=complete and receipts or {}}) and complete then
            for _,r in ipairs(show)do call(r.warm_mesh,'set_Enabled',true);call(r.go,'set_DrawSelf',true);count=count+1 end
        else
            -- No stale native mesh may remain visible over the restored MC draw.
            for k,r in pairs(dynamics)do if k:match('^'..stream..':')then call(r.warm_mesh,'set_Enabled',false);call(r.go,'set_DrawSelf',false)end end
        end
    end
    q.dynamic_ready=count
end
local function attach(owner,p,r)
    -- Display ownership is independent of the short-range collision GameObject.
    -- Match the game-tested prefab + Mesh initialization order before enabling drawing.
    call(owner.go,'set_DrawSelf',false)
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
    q.frame=q.frame+1;q.resource_allocated=0;poll_resources();local c=q.context;if not c then return end
    if c.touch<q.frame-1 then clear('context_not_refreshed');return end
    local s=c.bridge.snapshot_native_instances()
    if not s or not s.ready or s.epoch~=c.epoch or s.world_id~=c.world_id or s.mc_pid~=c.mc_pid or s.generation~=c.generation then clear('waiting_snapshot');return end
    assert(type(s.cubes)=='table' and #s.cubes<=1280,'Invalid instance snapshot')
    c.host_pid=s.host_pid;q.foreground=s.foreground
    -- A missing light binding must not revoke otherwise valid block drawing.
    if not q.light_error then
        local ok,err=pcall(update_lights,s,c)
        if not ok then
            q.light_error=tostring(err)
            for _,r in pairs(lights)do retire_warmer(r)end;lights={}
        end
    end
    local desired={};for _,p in ipairs(s.cubes)do desired[key(p)]=p end
    local removed={}
    for k,b in pairs(q.instances)do
        local p=desired[k]
        if not p or p.kind~=b.p.kind or not call(b.owner.go,'get_Valid') then removed[#removed+1]=k end
    end
    for _,k in ipairs(removed)do remove(k)end
    local allocated=0
    for _,p in ipairs(s.cubes)do
        if not q.instances[key(p)]then
            local r=resources(p.kind,c,p)
            local owner
            if r and r.ready and not r.empty and owned_count()<2560 then
                local go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_Model_'..key(p),c.folder))
                local pos=c.to_native(p.x+.5,p.y+.5,p.z+.5)
                call(go,'get_Transform'):set_position(Vector4f.new(pos.x,pos.y,pos.z,1),false)
                call(go,'set_DrawSelf',false)
                owner={go=go,ready=true,owned_display=true}
            end
            if r and r.ready and not r.empty and owner and owner.ready and call(owner.go,'get_Valid')then
                attach(owner,p,r);allocated=allocated+1;if allocated>=4 then break end
            end
        end
    end
    local ready={};local show={}
    for _,b in pairs(q.instances)do
        if b.ready or (call(b.mesh,'get_MeshReady') and call(b.mesh,'get_MaterialReady'))then
            if not b.ready then assert(call(b.mesh,'get_MaterialNum')==1,'Wrong material count') end
            ready[#ready+1]=b.p;show[#show+1]=b
        else
            if not q.waiting or q.frame%60==0 or q.frame-b.start>600 then
                local function read(o,n)local ok,v=pcall(call,o,n);if ok then return v else return tostring(v)end end
                q.waiting={kind=b.p.kind,x=b.p.x,y=b.p.y,z=b.p.z,age_frames=q.frame-b.start,
                    mesh_ready=call(b.mesh,'get_MeshReady'),material_ready=call(b.mesh,'get_MaterialReady'),
                    materials=call(b.mesh,'get_MaterialNum'),owner_draw=read(b.owner.go,'get_Draw'),
                    owner_update=read(b.owner.go,'get_Update'),component_enabled=read(b.mesh,'get_Enabled')}
            end
            if q.frame-b.start>600 then error('Cube resource timeout; overlay restored') end
        end
    end
    if not c.bridge.ack_native_instances({epoch=c.epoch,cubes=ready})then clear('receipt_rejected');return end
    for _,b in ipairs(show)do if not b.ready then call(b.mesh,'set_Enabled',true);call(b.owner.go,'set_DrawSelf',true);b.ready=true end end
    q.ready=#ready;q.desired=#s.cubes;q.phase=#ready==#s.cubes and 'synchronized' or 'loading';q.receipts=q.receipts+1
    if #ready==#s.cubes then q.waiting=nil end
    if not q.dynamic_error then
        local ok,err=pcall(update_dynamic,c)
        if not ok then
            q.dynamic_error=tostring(err)
            for _,r in pairs(dynamics)do retire_warmer(r)end;dynamics={}
            c.bridge.ack_native_dynamic({epoch=c.epoch,avatar=true,faces={}})
            c.bridge.ack_native_dynamic({epoch=c.epoch,avatar=false,faces={}})
            c.bridge.ack_native_dynamic({epoch=c.epoch,hands=true,faces={}})
        end
    end
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
function api.busy()
    if next(q.instances) or next(lights) or next(dynamics) or #q.warm_retired>0 then return true end
    for _,r in pairs(q.holders) do if r.go then return true end end
    return false
end
function api.status()
    local count=0;for _ in pairs(q.instances)do count=count+1 end
    local light_count=0;for _ in pairs(lights)do light_count=light_count+1 end
    local resources_ready,resources_loading,resource_errors=0,0,{}
    local diagnostics={}
    for kind,r in pairs(q.holders) do
        if r.ready then resources_ready=resources_ready+1 end
        if r.go then resources_loading=resources_loading+1 end
        if r.error then resource_errors[tostring(kind)]=r.error end
        if r.diagnostic and #diagnostics<24 then diagnostics[#diagnostics+1]=r.diagnostic end
    end
    return{phase=q.phase,error=q.error,count=count,ready=q.ready or 0,desired=q.desired,created=q.created,removed=q.removed,
        receipts=q.receipts,waiting=q.waiting,resources_ready=resources_ready,resources_loading=resources_loading,lights=light_count,light_limit=64,
        resource_errors=resource_errors,resource_diagnostics=diagnostics,pause=q.pause,foreground=q.foreground,worker=q.worker,light_error=q.light_error,dynamic_error=q.dynamic_error,dynamic_ready=q.dynamic_ready,dynamic_streams=q.dynamic_streams,owned_total=owned_count(),owned_limit=2560,warm_retiring=#q.warm_retired,limit=1280,radius=128,mode='automatic_models',live_conversion=true,shared_collision_objects=false,nonfull_display_only=true}
end
_G.onimusha_native_sections=api
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick)
    if not ok then q.error=tostring(err);q.failed_key=q.context and q.context.key;pcall(clear,'failed');log.error('[Onimusha cube rendering] '..q.error) end
end)
re.on_script_reset(function()clear('script_reset');q.holders={};_G.onimusha_native_sections=nil end)
