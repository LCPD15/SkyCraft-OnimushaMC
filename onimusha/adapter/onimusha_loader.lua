-- Project-local hot reload; REFramework's private global reset is not invoked.
-- Install this as the sole OnimushaMC autorun script. Payloads live in data/.
-- MOD制作：LCPD15/LCPD拉灯
local ROOT='onimusha_mc/scripts/'
local CONTROL='onimusha_reload_control.json'
local OUTPUT='onimusha_reload_status.json'
local RECEIPT='onimusha_reload_receipt.json'
local FILES={'onimusha_mc.lua','onimusha_enemy_hit.lua','onimusha_guard_probe.lua','onimusha_combat_inventory.lua','onimusha_native_blocks.lua','onimusha_native_instances.lua'}
local real_re,real_sdk=re,sdk
local current,last_good,pending
local routes,hooks={},{}
local frame,inflight,generation=0,0,0
local receipt=json.load_file(RECEIPT) or {}
local last_id=receipt.id
local status={phase='starting',generation=0}
local function report(phase,err,id)
    status={phase=phase,error=err and tostring(err):sub(1,800) or nil,id=id or last_id,
        frame=frame,generation=generation,inflight=inflight,project_only=true}
    json.dump_file(OUTPUT,status)
end
local function invoke(fn,...)
    local ok,result=pcall(fn,...)
    if not ok then log.error('[Onimusha reload callback] '..tostring(result)) end
    return ok,result
end
local function register_event(gen,kind,...)
    local args=table.pack(...);local fn=args[args.n];assert(type(fn)=='function','Callback required')
    local key=kind..':'..tostring(args.n>1 and args[1] or '')
    gen.events[key]=gen.events[key] or {};table.insert(gen.events[key],fn)
    if kind=='on_script_reset' or routes[key] then return end
    routes[key]=true
    args[args.n]=function(...)
        local g=current;if not g then return end
        local result
        for _,cb in ipairs(g.events[key] or {}) do
            local ok,value=invoke(cb,...)
            if ok and value~=nil then result=value end
        end
        return result
    end
    assert(real_re[kind],'Unsupported callback '..kind)(table.unpack(args,1,args.n))
end
local function register_hook(gen,m,pre,post,ignore_jmp)
    local key=tostring(real_sdk.to_int64(m:get_function()))
    gen.hooks[key]=gen.hooks[key] or {}
    table.insert(gen.hooks[key],{pre=pre,post=post})
    if hooks[key] then assert(hooks[key].ignore_jmp==ignore_jmp,'Hook options changed');return end
    hooks[key]={ignore_jmp=ignore_jmp}
    real_sdk.hook(m,function(args)
        local g=current;local list=g and g.hooks[key] or {}
        local token={list=list};thread.get_hook_storage().onimusha_loader=token
        inflight=inflight+1
        local result
        for _,cb in ipairs(list) do
            if cb.pre then
                local ok,value=invoke(cb.pre,args)
                if ok and value==real_sdk.PreHookResult.SKIP_ORIGINAL then result=value end
            end
        end
        return result
    end,function(ret)
        local storage=thread.get_hook_storage();local token=storage.onimusha_loader
        storage.onimusha_loader=nil
        if token then
            for _,cb in ipairs(token.list) do
                if cb.post then local ok,value=invoke(cb.post,ret);if ok and value~=nil then ret=value end end
            end
            inflight=math.max(0,inflight-1)
        end
        return ret
    end,ignore_jmp)
end
local function environment(gen)
    local rp=setmetatable({},{__index=function(_,kind)
        if kind:match('^on_') then return function(...) return register_event(gen,kind,...) end end
        return real_re[kind]
    end})
    local sp=setmetatable({hook=function(...) return register_hook(gen,...) end},{__index=real_sdk})
    return setmetatable({re=rp,sdk=sp},{__index=_G})
end
local function compile(sources)
    local gen={events={},hooks={}};local env=environment(gen);local chunks={}
    for _,name in ipairs(FILES) do
        local source=assert(sources[name],'Missing payload '..name)
        assert(#source>0 and #source<600000,'Invalid payload size '..name)
        local chunk,err=load(source,'@'..ROOT..name,'t',env)
        assert(chunk,err);chunks[#chunks+1]=chunk
    end
    gen.chunks=chunks;return gen
end
local function shutdown(gen)
    if not gen then return true end
    for _,cb in ipairs(gen.events['on_script_reset:'] or {}) do
        local ok,err=pcall(cb);if not ok then return false,err end
    end
    return true
end
local function activate(gen)
    for _,chunk in ipairs(gen.chunks) do chunk() end
    gen.chunks=nil;current=gen;generation=generation+1
end
local function reload(sources,id)
    local ok,gen=pcall(compile,sources)
    if not ok then report('compile_failed_old_retained',gen,id);return false end
    local stopped,err=shutdown(current)
    if not stopped then report('cleanup_failed',err,id);return false end
    current=nil
    local started,err=pcall(activate,gen)
    if not started then
        shutdown(gen)
        if last_good then
            local restored,why=pcall(function() activate(compile(last_good)) end)
            report(restored and 'rolled_back' or 'rollback_failed',restored and err or why,id)
        else report('load_failed',err,id) end
        return false
    end
    last_good=sources;report('loaded',nil,id);return true
end
local function read_sources()
    local sources={};for _,name in ipairs(FILES) do sources[name]=fs.read(ROOT..name) end
    return sources
end
local function tick()
    frame=frame+1
    if frame==1 then
        local ok,err=pcall(function() reload(read_sources(),last_id) end)
        if not ok then report('load_failed',err) end
    end
    if frame%30==0 and not pending then
        local c=json.load_file(CONTROL)
        if c and c.action=='reload' and type(c.id)=='string' and #c.id<=120 and c.id~=last_id then
            -- Persist acknowledgement before cleanup/load; the same file cannot
            -- loop after either a manual framework reset or a game restart.
            local ack={id=c.id};json.dump_file(RECEIPT,ack)
            assert((json.load_file(RECEIPT) or {}).id==c.id,'Cannot persist reload acknowledgement')
            last_id=c.id;pending={id=c.id,frame=frame,quiet=0};report('disabling_takeover',nil,c.id)
        end
    end
    if not pending then return end
    local b=_G.onimusha_mc
    if b then b.set_enabled(false) end
    local a=_G.onimusha_adapter_lifecycle
    local ready=a and a.ready_for_reload() and (not b or b.status().enabled==false)
    local hit=_G.onimusha_enemy_hit
    if hit and hit.busy and hit.busy() then ready=false end
    pending.quiet=ready and inflight==0 and pending.quiet+1 or 0
    if pending.quiet>=3 then
        local id=pending.id;pending=nil;reload(read_sources(),id)
    elseif frame-pending.frame>600 then
        local id=pending.id;pending=nil;report('not_quiescent', 'Original character restoration or native hit still pending',id)
    end
end
real_re.on_application_entry('LateUpdateBehavior',function()
    local ok,err=pcall(tick);if not ok then pending=nil;report('reload_error',err) end
end)
real_re.on_script_reset(function()
    shutdown(current);current=nil;_G.onimusha_adapter_lifecycle=nil
end)
