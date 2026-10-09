-- Onimusha TDB82 / protocol15: automatic complete-model conversion and shared native resources.
-- Cache complete appearances; only new geometry/texture/state needs conversion.
-- MOD鍒朵綔锛歀CPD15/LCPD鎷夌伅
local q={frame=0,instances={},holders={},warm_retired={},phase='disabled',created=0,removed=0,receipts=0}
local pending={} -- host/model IDs never reused by the DLL during its lifetime
local lights={}
local dynamics={}
-- Disabled Mesh instances keep their engine-owned dependencies. They may be reused
-- only within the same scene/session, never across a native scene unload or reset.
local dynamic_pool={}
local pool_count=0
-- Disabled by default; staged tests opt in through an explicit project control.
-- Resource loading uses only the game-tested engine USER3 dependency owner.
local DYNAMIC_NATIVE_ENABLED=false
local dynamic_settings={enabled=DYNAMIC_NATIVE_ENABLED,preload_only=false,max_instances=768,per_frame=2,streams={hands=true,avatar=true,scene=true}}
local function dynamic_control()
    local path='onimusha_native_dynamic_control.json'
    if fs and fs.read and fs.read(path)=='' then return end
    local ok,v=pcall(json.load_file,path)
    if not ok or type(v)~='table' then return end
    dynamic_settings.enabled=v.enabled==true
    dynamic_settings.preload_only=v.preload_only==true
    dynamic_settings.max_instances=math.max(1,math.min(768,math.floor(tonumber(v.max_instances) or 768)))
    dynamic_settings.per_frame=math.max(1,math.min(2,math.floor(tonumber(v.per_frame) or 2)))
    if type(v.streams)=='table' then
        for _,stream in ipairs({'hands','avatar','scene'})do dynamic_settings.streams[stream]=v.streams[stream]==true end
    end
end
local function owned_count()
    local n=#q.warm_retired
    for _,b in pairs(q.instances)do if b.owner.owned_display then n=n+1 end end
    for _,r in pairs(q.holders)do if r.go then n=n+1 end end
    for _ in pairs(lights)do n=n+1 end
    for _ in pairs(dynamics)do n=n+1 end
    n=n+pool_count
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
local function retire_warmer(r)
    if not r.go then return end
    if call(r.go,'get_Valid') then
        if r.warm_mesh then call(r.warm_mesh,'set_Enabled',false) end
        call(r.go,'set_DrawSelf',false)
        sdk.find_type_definition('via.GameObject'):get_method('destroy(via.GameObject)'):call(nil,r.go)
    end
    -- Keep the engine-owned dependency graph through deferred destruction,
    -- including reset/error paths which discard the active resource cache.
    q.warm_retired[#q.warm_retired+1]={go=r.go,mesh=r.warm_mesh,frame=q.frame,
        loader=r.loader,mesh_holder=r.mesh,material_holder=r.material,asset=r.asset_owner,white_asset=r.white_asset_owner}
    r.go=nil;r.warm_mesh=nil
end
local function evict_dynamic_pool()
    local oldest_key,oldest_index,oldest
    for k,rows in pairs(dynamic_pool)do for i,r in ipairs(rows)do
        if not oldest or r.cached_at<oldest.cached_at then oldest_key=k;oldest_index=i;oldest=r end
    end end
    if not oldest then return false end
    table.remove(dynamic_pool[oldest_key],oldest_index)
    if #dynamic_pool[oldest_key]==0 then dynamic_pool[oldest_key]=nil end
    pool_count=pool_count-1;retire_warmer(oldest);q.dynamic_removed=(q.dynamic_removed or 0)+1
    q.dynamic_pool_evicted=(q.dynamic_pool_evicted or 0)+1;return true
end
local function purge_dynamic_pool()
    while evict_dynamic_pool()do end
end
local function release_dynamic_object(k,r,keep)
    if keep and dynamic_settings.enabled and not dynamic_settings.preload_only and r.loaded
        and r.go and call(r.go,'get_Valid') and pool_count<dynamic_settings.max_instances then
        call(r.warm_mesh,'set_Enabled',false);call(r.go,'set_DrawSelf',false)
        local bucket=k:match('^([^:]+)')..':'..r.kind
        r.cached_at=q.frame;dynamic_pool[bucket]=dynamic_pool[bucket] or {}
        table.insert(dynamic_pool[bucket],r);pool_count=pool_count+1
        q.dynamic_parked=(q.dynamic_parked or 0)+1
    else
        retire_warmer(r);q.dynamic_removed=(q.dynamic_removed or 0)+1
    end
end
local function take_dynamic_object(stream,kind)
    local bucket=stream..':'..kind;local rows=dynamic_pool[bucket]
    while rows and #rows>0 do
        local r=table.remove(rows);pool_count=pool_count-1
        if #rows==0 then dynamic_pool[bucket]=nil end
        if r.go and call(r.go,'get_Valid') then
            r.start=q.frame;q.dynamic_pool_hits=(q.dynamic_pool_hits or 0)+1;return r
        end
        retire_warmer(r);q.dynamic_removed=(q.dynamic_removed or 0)+1
    end
end
local function poll_resource(r)
    if r.phase~='userdata' and r.phase~='mesh' then return end
    if q.pause.menu==true or q.pause.player==true or q.foreground==false then r.start=r.start+1 end
    if r.phase=='userdata' then
        local mh=r.loader:get_field('_Mesh');local md=r.loader:get_field('_Material')
        if mh and md and q.resource_allocated<2 and owned_count()<2560 then
            assert(sdk.is_managed_object(mh) and sdk.is_managed_object(md),'Invalid engine resource holders')
            assert(call(mh,'get_ResourcePath')==r.prefix..'.mesh' and call(md,'get_ResourcePath')==r.prefix..'.mdf2','Wrong dependency paths')
            r.mesh=pin(mh);r.material=pin(md);q.resource_allocated=q.resource_allocated+1
            r.go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_CubePreload_'..r.kind,r.folder))
            call(r.go,'get_Transform'):set_position(Vector4f.new(r.position.x,r.position.y,r.position.z,1),false)
            call(r.go,'set_DrawSelf',false)
            r.warm_mesh=pin(call(r.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
            call(r.warm_mesh,'set_Enabled',false);call(r.warm_mesh,'set_StaticMesh',false)
            -- Bind once. Never replace holders/rebuild the component on a timer.
            call(r.warm_mesh,'setMesh',r.mesh);call(r.warm_mesh,'set_Material',r.material)
            call(r.warm_mesh,'set_RenderOutputID',31);call(r.warm_mesh,'set_DrawShadowCast',true)
            r.phase='mesh'
        end
    end
    if r.go then
        if q.frame%60==0 then
            r.diagnostic={model=r.kind,asset=r.asset,age_frames=q.frame-r.start,loader='engine_userdata',
                mesh_ready=optional(r.warm_mesh,'get_MeshReady'),material_ready=optional(r.warm_mesh,'get_MaterialReady'),
                materials=optional(r.warm_mesh,'get_MaterialNum'),enabled=optional(r.warm_mesh,'get_Enabled')}
        end
        if call(r.warm_mesh,'get_MeshReady') and call(r.warm_mesh,'get_MaterialReady') then
            assert(call(r.warm_mesh,'get_MaterialNum')==1,'Wrong preloaded material count')
            r.ready=true;r.phase='ready';r.diagnostic=nil;retire_warmer(r);r.folder=nil;return
        end
    end
    if q.frame-r.start>600 then error('Engine dependency load timeout; only this appearance retains MC drawing') end
end
local function poll_resources()
    local pause=sdk.get_managed_singleton and sdk.get_managed_singleton('app.PauseManager')
    q.pause={menu=pause and optional(pause,'get_IsMenuPause'),player=pause and optional(pause,'get_IsPlayerPause')}
    for i=#q.warm_retired,1,-1 do
        local b=q.warm_retired[i]
        if q.frame-b.frame>10 and not call(b.go,'get_Valid') then table.remove(q.warm_retired,i) end
    end
    for _,r in pairs(q.holders) do
        local ok,err=pcall(poll_resource,r)
        if not ok then r.error=tostring(err);r.phase='error';retire_warmer(r) end
    end
end
local function resources(kind,c,p,priority,white_flash)
    -- The DLL Lua API supplies doubles (2.0), while JSON object keys are "2".
    kind=assert(math.tointeger(kind),'Invalid cube kind');assert(kind>=1 and kind<=0xffffffff,'Invalid model ID')
    local cache_key=white_flash and -kind or kind
    local r=q.holders[cache_key]
    if r and (r.ready or r.phase=='userdata' or r.phase=='mesh' or r.error) then return r end
    if not r then
        local job=pending[cache_key]
        if not job then
            local worker=read_json('onimusha_mc/native_models/worker.json')
            q.worker=worker
            if not worker or worker.host_pid~=c.host_pid or worker.state~='ready' or math.abs(os.time()-worker.alive_at)>30 then return nil end
            if q.frame%3~=0 then return nil end
            local id=c.bridge.capture_native_model({model=kind,epoch=c.epoch,priority=priority or 0,white_flash=white_flash==true})
            if id then pending[cache_key]={id=id,epoch=c.epoch,world=c.world_id,mc_pid=c.mc_pid,generation=c.generation} end
            return nil
        end
        local poll_interval=priority==1 and 3 or 15
        if not job.result and q.frame>=(job.next_poll or 0) and (q.result_polls or 0)<8 then
            job.next_poll=q.frame+poll_interval;q.result_polls=(q.result_polls or 0)+1
            local value=read_json('onimusha_mc/native_models/'..job.id..'/result.json')
            if value and (not value.ok or value.empty or value.loader_version==1) then
                assert(value.id==job.id and value.model==kind and value.epoch==job.epoch and value.world==job.world and value.mc_pid==job.mc_pid and value.generation==job.generation,'Stale model result')
                assert((value.white_flash==true)==(white_flash==true),'Wrong overlay material receipt')
                job.result=value
            end
        end
        if not job.result then return nil end
        if job.result.ok and job.result.empty then
            r={ready=true,empty=true};q.holders[cache_key]=r;return r
        end
        if not job.result.ok or not job.result.asset_id then
            r={error=job.result.error or 'unsupported_model'};q.holders[cache_key]=r;return r
        end
    end
    if q.resource_allocated>=2 or owned_count()>=2560 then return nil end
    local loading=0;for _,value in pairs(q.holders)do if value.phase=='userdata' or value.phase=='mesh' then loading=loading+1 end end
    if loading>=8 then return nil end
    q.resource_allocated=q.resource_allocated+1
    if not r then
        local row=assert(pending[cache_key].result,'Missing model result')
        local id=row.asset_id;assert(type(id)=='string' and #id==28 and id:match('^section_%x+$'),'Invalid resource ID')
        r={kind=kind,asset=id}
        q.holders[cache_key]=r
    end
    r.prefix='mod/onimusha_mc/sections/'..r.asset..'/'..r.asset
    r.position=c.to_native(p.x+.5,p.y+.5,p.z+.5);r.folder=c.folder;r.start=q.frame;r.phase='userdata'
    local ok,err=pcall(function()
        r.loader=r.loader or pin(sdk.create_userdata_global('app.montage.data.MontagePartsModelData',r.prefix..'_loader.user'))
    end)
    if not ok then r.error=tostring(err);r.phase='error' end
    return r
end
local function remove(k)
    local b=q.instances[k];if not b then return end
    if b.mesh and call(b.owner.go,'get_Valid') then call(b.mesh,'set_Enabled',false) end
    if b.owner.owned_display then
        retire_warmer({go=b.owner.go,warm_mesh=b.mesh,asset_owner=b.holders})
    end
    q.instances[k]=nil;q.removed=q.removed+1
end
local function clear(reason,keep_dynamic)
    local keys={};for k in pairs(q.instances)do keys[#keys+1]=k end
    for _,k in ipairs(keys)do remove(k)end
    for _,r in pairs(q.holders) do retire_warmer(r);if not r.ready and not r.error then r.phase='idle' end;r.folder=nil end
    for _,r in pairs(lights)do retire_warmer(r)end;lights={}
    for k,r in pairs(dynamics)do release_dynamic_object(k,r,keep_dynamic)end;dynamics={};q.dynamic_objects=0
    if not keep_dynamic then purge_dynamic_pool();q.pool_context=nil end
    if q.context then q.context.bridge.release_section() end
    q.context=nil;q.phase=reason or 'disabled';q.ready=0;q.dynamic_streams={};q.dynamic_ready=0
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
local function dynamic_remove(k,keep)
    local r=dynamics[k];if not r then return end
    release_dynamic_object(k,r,keep);dynamics[k]=nil
end
local function apply_tint(r,p)
    local tint=math.tointeger(p.tint or 0xffffffff)
    assert(tint and tint>=0 and tint<=0xffffffff,'Invalid dynamic tint')
    if r.tint==tint or (r.tint==nil and tint==0xffffffff) then r.tint=tint;return end
    -- Private converted materials have BaseColor as their first Float4. Tint
    -- the instance, not its shared TEX/MDF: hurt flashes never rebuild a mob.
    if not r.tint_validated then
        assert(call(r.warm_mesh,'getMaterialVariableName',0,0)=='BaseColor','Unexpected dynamic material')
        assert(call(r.warm_mesh,'getMaterialVariableType',0,0)==4,'BaseColor must be Float4')
        r.tint_validated=true
    end
    local function linear(byte)local v=byte/255;return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
    call(r.warm_mesh,'setMaterialFloat4',0,0,Vector4f.new(linear(tint&255),linear((tint>>8)&255),linear((tint>>16)&255),((tint>>24)&255)/255))
    r.tint=tint
end
local function update_dynamic(c)
    if type(c.bridge.snapshot_native_dynamic)~='function' then return end
    local s=c.bridge.snapshot_native_dynamic()
    if s and s.render_frame and s.render_frame~=0 and c.render_frame and s.render_frame~=c.render_frame then
        q.pose_mismatch=(q.pose_mismatch or 0)+1;return
    end
    q.render_frame=s and s.render_frame
    if not s or not s.ready or s.epoch~=c.epoch then
        local keys={};for k in pairs(dynamics)do keys[#keys+1]=k end
        for _,k in ipairs(keys)do dynamic_remove(k,true)end;return
    end
    local wanted={};local order={'hands','avatar','scene'}
    local function face_key(stream,p)return stream..':'..(s.stable_faces and p.id or p.first)end
    for _,stream in ipairs(order)do
        s[stream]=s[stream] or {}
        assert(type(s[stream])=='table' and #s[stream]<=512,'Invalid dynamic snapshot')
        if dynamic_settings.enabled and dynamic_settings.streams[stream] and not dynamic_settings.preload_only then
            for _,p in ipairs(s[stream])do wanted[face_key(stream,p)]=p end
        end
    end
    -- A weapon change can reorder the flat vertex list. Preserve matching
    -- appearances even when their offsets move; an offset is not object identity.
    local spare={};local next_objects={};local alive=0
    for k,r in pairs(dynamics)do
        if wanted[k] and wanted[k].kind==r.kind and call(r.go,'get_Valid')then next_objects[k]=r;alive=alive+1
        else
            local pool=k:match('^([^:]+)')..':'..r.kind
            spare[pool]=spare[pool] or {};spare[pool][#spare[pool]+1]={key=k,object=r}
        end
    end
    for _,stream in ipairs(order)do
        for _,p in ipairs(s[stream])do
            local k=face_key(stream,p);local pool=spare[stream..':'..p.kind]
            if wanted[k] and not next_objects[k] and pool and #pool>0 then
                local old=table.remove(pool);local r=old.object
                if call(r.go,'get_Valid')then
                    next_objects[k]=r;alive=alive+1;q.dynamic_reused=(q.dynamic_reused or 0)+1
                else dynamic_remove(old.key)end
            end
        end
    end
    for _,pool in pairs(spare)do for _,old in ipairs(pool)do dynamic_remove(old.key,true)end end
    dynamics=next_objects
    local made=0;local count=0;q.dynamic_streams={}
    q.dynamic_bind_errors=q.dynamic_bind_errors or {}
    for _,stream in ipairs(order)do
        local receipts={};local show={};local errors={};local available=0
        local enabled=dynamic_settings.enabled and dynamic_settings.streams[stream]
        for _,p in ipairs(enabled and s[stream] or {})do
            local k=face_key(stream,p);local r=dynamics[k]
            local asset=resources(p.kind,c,p,1)
            if asset and asset.error then errors[tostring(p.kind)]=asset.error end
            if asset and asset.ready then available=available+1 end
            local failed=q.dynamic_bind_errors[p.kind]
            if failed then errors[tostring(p.kind)]=failed end
            if not r and not failed and not dynamic_settings.preload_only and alive<dynamic_settings.max_instances then
                r=take_dynamic_object(stream,p.kind)
                if r then dynamics[k]=r;alive=alive+1 end
            end
            if not r and pool_count>0 and (alive+pool_count>=dynamic_settings.max_instances or owned_count()>=2560) then
                evict_dynamic_pool()
            end
            if not r and not failed and not dynamic_settings.preload_only and asset and asset.ready and not asset.empty
                and made<dynamic_settings.per_frame and alive<dynamic_settings.max_instances and owned_count()<2560 then
                -- Register ownership before binding so a caught failure retires
                -- this object while preserving blocks and the other streams.
                r={kind=p.kind,asset_owner=asset,start=q.frame};dynamics[k]=r;made=made+1;alive=alive+1
                local ok,err=pcall(function()
                    r.go=pin(sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)'):call(nil,'OMC_Dynamic_'..k,c.folder))
                    call(r.go,'set_DrawSelf',false)
                    r.warm_mesh=pin(call(r.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
                    call(r.warm_mesh,'set_Enabled',false);call(r.warm_mesh,'set_StaticMesh',false)
                    call(r.warm_mesh,'setMesh',asset.mesh);call(r.warm_mesh,'set_Material',asset.material)
                    call(r.warm_mesh,'set_RenderOutputID',31);call(r.warm_mesh,'set_DrawShadowCast',stream~='hands')
                end)
                if not ok then
                    q.dynamic_bind_errors[p.kind]=tostring(err);errors[tostring(p.kind)]=tostring(err)
                    dynamic_remove(k);r=nil;alive=alive-1
                end
            end
            if asset and asset.empty and not dynamic_settings.preload_only then receipts[#receipts+1]={first=p.first,kind=p.kind,id=p.id} end
            if r then
                local ok,err=pcall(function()
                    if p.white_flash then r.white_requested=true end
                    if r.white_requested then
                        local white=resources(p.kind,c,p,1,true)
                        if white and white.ready and not white.empty then r.white_asset_owner=white end
                    end
                    local white=p.white_flash==true and r.white_asset_owner~=nil
                    if (r.white_active or false)~=white then
                        -- Both MDFs are already engine-loaded and owned until
                        -- deferred destruction. Keep the same Mesh/pose/ID;
                        -- changing a flash never rebuilds a face or its texture.
                        call(r.warm_mesh,'set_Material',(white and r.white_asset_owner or r.asset_owner).material)
                        r.white_active=white;r.tint=nil
                    end
                    local transform=call(r.go,'get_Transform');local pos=c.to_native(p.x,p.y,p.z)
                    -- Set local dimensions before publishing world pose; native
                    -- transform consumers must observe one coherent matrix.
                    call(transform,'set_LocalScale',Vector3f.new(p.sx,p.sy,1))
                    transform:set_position(Vector4f.new(pos.x,pos.y,pos.z,1),false)
                    transform:set_rotation(Quaternion.new(p.qw,p.qx,p.qy,p.qz))
                    -- Bounded evidence for the reported primed-TNT scale loss.
                    -- Inspect actual engine scale, not just the requested pose.
                    if stream=='scene' and p.sx>=.8 and p.sx<=1.5 and p.sy>=.8 and p.sy<=1.5
                        and r.last_sx and (math.abs(r.last_sx-p.sx)>.001 or math.abs(r.last_sy-p.sy)>.001)
                        and q.scale_sample_frame~=q.frame then
                        q.scale_sample_frame=q.frame
                        local v=call(transform,'get_Scale')
                        q.dynamic_scale_samples=q.dynamic_scale_samples or {}
                        local rows=q.dynamic_scale_samples
                        local row={frame=q.frame,time=os.clock(),id=p.id,kind=p.kind,x=p.x,y=p.y,z=p.z,
                            requested={x=p.sx,y=p.sy,z=1},actual={x=v.x,y=v.y,z=v.z}}
                        -- A scale getter alone does not prove that the rendered
                        -- bounds updated. Keep this optional read outside the
                        -- display failure path; diagnostics must not hide a face.
                        local good,bounds=pcall(function()
                            local b=call(r.warm_mesh,'get_WorldAABB')
                            local lo,hi=b:get_field('minpos'),b:get_field('maxpos')
                            return {min={x=lo.x,y=lo.y,z=lo.z},max={x=hi.x,y=hi.y,z=hi.z}}
                        end)
                        if good then row.bounds=bounds else row.bounds_error=tostring(bounds) end
                        rows[#rows+1]=row
                        if #rows>32 then table.remove(rows,1)end
                    end
                    r.last_sx=p.sx;r.last_sy=p.sy
                    if call(r.warm_mesh,'get_MeshReady') and call(r.warm_mesh,'get_MaterialReady')
                        and (not r.white_requested or r.white_asset_owner) then
                        apply_tint(r,p)
                        r.loaded=true;receipts[#receipts+1]={first=p.first,kind=p.kind,id=p.id};show[#show+1]=r
                    elseif q.pause.menu==true or q.pause.player==true or q.foreground==false then r.start=r.start+1
                    elseif q.frame-r.start>600 then error('Dynamic display readiness timeout')end
                end)
                if not ok then
                    q.dynamic_bind_errors[p.kind]=tostring(err);errors[tostring(p.kind)]=tostring(err)
                    dynamic_remove(k);alive=alive-1
                end
            end
        end
        local complete=enabled and not dynamic_settings.preload_only and (stream~='hands' or (s.hands_complete and #receipts==#s.hands))
        q.dynamic_streams[stream]={desired=#s[stream],ready=#receipts,resources_ready=available,errors=errors,complete=complete,enabled=enabled}
        local accepted=c.bridge.ack_native_dynamic({epoch=c.epoch,stable_faces=s.stable_faces,avatar=stream=='avatar',hands=stream=='hands',faces=complete and receipts or {}})
        if accepted and complete then
            for _,r in ipairs(show)do call(r.warm_mesh,'set_Enabled',true);call(r.go,'set_DrawSelf',true);count=count+1 end
        else
            for k,r in pairs(dynamics)do if k:match('^'..stream..':')then call(r.warm_mesh,'set_Enabled',false);call(r.go,'set_DrawSelf',false)end end
        end
    end
    q.dynamic_ready=count;q.dynamic_created=(q.dynamic_created or 0)+made;q.dynamic_objects=alive
end
local function attach(owner,p,r)
    -- Display ownership is independent of the short-range collision GameObject.
    -- Match the game-tested prefab + Mesh initialization order before enabling drawing.
    local b={owner=owner,p=p,start=q.frame,holders=r}
    q.instances[key(p)]=b
    call(owner.go,'set_DrawSelf',false)
    if not owner.display_mesh then
        owner.display_mesh=pin(call(owner.go,'createComponent(System.Type)',sdk.find_type_definition('via.render.Mesh'):get_runtime_type()))
    end
    local mesh=owner.display_mesh
    b.mesh=mesh
    call(mesh,'set_Enabled',false);call(mesh,'set_StaticMesh',false)
    call(mesh,'setMesh',r.mesh);call(mesh,'set_Material',r.material)
    call(mesh,'set_RenderOutputID',31);call(mesh,'set_DrawShadowCast',true)
    owner.display_holders=r
    q.created=q.created+1
end
local function tick()
    q.frame=q.frame+1;q.resource_allocated=0;q.result_polls=0
    if q.frame%30==1 then dynamic_control()end
    if not dynamic_settings.enabled or dynamic_settings.preload_only then purge_dynamic_pool() end
    while pool_count>dynamic_settings.max_instances do evict_dynamic_pool()end
    poll_resources();local c=q.context;if not c then return end
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
                local ok,err=pcall(attach,owner,p,r)
                if not ok then r.error=tostring(err);r.ready=false;r.phase='error';remove(key(p)) end
                allocated=allocated+1;if allocated>=4 then break end
            end
        end
    end
    local ready={};local show={};local failed={}
    for k,b in pairs(q.instances)do
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
            if q.frame-b.start>600 then
                b.holders.error='Display binding timeout; only this appearance retains MC drawing'
                b.holders.ready=false;b.holders.phase='error';failed[#failed+1]=k
            end
        end
    end
    for _,k in ipairs(failed)do remove(k)end
    if not c.bridge.ack_native_instances({epoch=c.epoch,cubes=ready})then clear('receipt_rejected');return end
    for _,b in ipairs(show)do if not b.ready then call(b.mesh,'set_Enabled',true);call(b.owner.go,'set_DrawSelf',true);b.ready=true end end
    q.ready=#ready;q.desired=#s.cubes;q.phase=#ready==#s.cubes and 'synchronized' or 'loading';q.receipts=q.receipts+1
    if #ready==#s.cubes then q.waiting=nil end
    if (dynamic_settings.enabled or next(dynamics)) and not q.dynamic_error then
        local ok,err=pcall(update_dynamic,c)
        if not ok then
            q.dynamic_error=tostring(err)
            for _,r in pairs(dynamics)do retire_warmer(r);q.dynamic_removed=(q.dynamic_removed or 0)+1 end;dynamics={};q.dynamic_objects=0
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
    if (q.context and q.context.key~=k) or (q.pool_context and q.pool_context~=k) then clear('context_changed') end
    q.pool_context=k
    c.key=k;c.touch=q.frame;q.context=c
end
function api.stop()clear('disabled',true)end
function api.busy()
    if next(q.instances) or next(lights) or next(dynamics) or #q.warm_retired>0 then return true end
    for _,r in pairs(q.holders) do if r.phase=='userdata' or r.go then return true end end
    return false
end
function api.status()
    local count=0;for _ in pairs(q.instances)do count=count+1 end
    local light_count=0;for _ in pairs(lights)do light_count=light_count+1 end
    local resources_ready,resources_loading,resource_errors=0,0,{}
    local diagnostics={}
    for kind,r in pairs(q.holders) do
        if r.ready then resources_ready=resources_ready+1 end
        if r.phase=='userdata' or r.go then resources_loading=resources_loading+1 end
        if r.error then resource_errors[tostring(kind)]=r.error end
        if r.diagnostic and #diagnostics<24 then diagnostics[#diagnostics+1]=r.diagnostic end
    end
    return{phase=q.phase,error=q.error,count=count,ready=q.ready or 0,desired=q.desired,created=q.created,removed=q.removed,
        render_frame=q.render_frame,pose_mismatch=q.pose_mismatch or 0,
        dynamic_pool_cached=pool_count,dynamic_pool_hits=q.dynamic_pool_hits or 0,dynamic_pool_evicted=q.dynamic_pool_evicted or 0,
        receipts=q.receipts,waiting=q.waiting,resources_ready=resources_ready,resources_loading=resources_loading,lights=light_count,light_limit=64,
        resource_errors=resource_errors,resource_diagnostics=diagnostics,pause=q.pause,foreground=q.foreground,worker=q.worker,light_error=q.light_error,dynamic_enabled=dynamic_settings.enabled,dynamic_settings=dynamic_settings,dynamic_reused=q.dynamic_reused or 0,dynamic_created=q.dynamic_created or 0,dynamic_removed=q.dynamic_removed or 0,dynamic_objects=q.dynamic_objects or 0,dynamic_disabled_reason=not dynamic_settings.enabled and "staged_dynamic_control_disabled" or nil,dynamic_error=q.dynamic_error,dynamic_ready=q.dynamic_ready or 0,dynamic_streams=q.dynamic_streams,dynamic_scale_samples=q.dynamic_scale_samples,owned_total=owned_count(),owned_limit=2560,warm_retiring=#q.warm_retired,limit=1280,radius=128,mode='automatic_models',live_conversion=true,shared_collision_objects=false,nonfull_display_only=true}
end
_G.onimusha_native_sections=api
re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick)
    if not ok then q.error=tostring(err);q.failed_key=q.context and q.context.key;pcall(clear,'failed');log.error('[Onimusha cube rendering] '..q.error) end
end)
re.on_script_reset(function()clear('script_reset');q.holders={};_G.onimusha_native_sections=nil end)
