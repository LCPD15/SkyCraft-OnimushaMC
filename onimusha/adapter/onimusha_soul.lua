-- Onimusha TDB82. Native movement/effects/rewards remain native; each actual
-- successful absorption additionally gives one bounded MC reward receipt.
-- MOD制作：LCPD15/LCPD拉灯
local q={frame=0,injected=0,held_frames=0,bone_injections=0,overwritten=0,command_injections=0,command_held=0,successes=0,rewards=0,pending={},installed=false}
local ledger
local command_ledgers={}
local absorb_command
local function bridge_context()
    local b=_G.onimusha_mc;if not b or type(b.reward_absorbed_soul)~='function' then return end
    local n=b.status();if not n.ready or not n.enabled then return end
    local mc=b.read_mc();if not mc or not mc.in_world or mc.dead or mc.screen_open then return end
    return b,n,mc
end
local function owner()
    local pm=assert(sdk.get_managed_singleton('app.PlayerManager'))
    assert(pm:call('isPlayerReady',false),'Player not ready')
    local info=pm:call('getControllingPlayerInfo');assert(info:call('get_CharacterValid'),'Player invalid')
    local player=info:call('get_Character');local go=player:call('get_GameObject');assert(go:call('get_Valid'),'Player object invalid')
    local e=player:call('get_CharacterEntityHolder'):call('get_Entity')
    local s=e:call('get_SoulAbsorption')
    assert(s and s:get_type_definition():get_full_name()=='app.cPlayerSoulAbsorptionSupporter','Soul owner type')
    assert(s:get_field('_PlayerCharacterEntity'):get_address()==e:get_address(),'Soul entity mismatch')
    return s,player
end
local function restore_commands()
    for _,r in pairs(command_ledgers)do
        local ok,err=pcall(function()
            -- Restore just ABSORB, never a whole command word that could contain
            -- another native command. Each retained Bitset belongs to this result.
            for _,v in ipairs(r.bits)do v.object:call('set(System.Int32, System.Boolean)',absorb_command,v.original)end
            r.object:set_field('_IsSoulAbsorption',r.original)
        end)
        if not ok then q.restore_error=tostring(err)end
        for _,v in ipairs(r.bits)do v.object:release()end
        r.object:release()
    end
    command_ledgers={}
end
local function restore()
    if not ledger then return end
    local r=ledger
    local ok,err=pcall(function()
        -- Restore only our retained boolean on the retained valid player module.
        local entity=r.object:get_field('_PlayerCharacterEntity')
        local character=entity and entity:call('get_OwnerCharacter')
        local go=character and character:call('get_GameObject')
        if go and go:call('get_Valid') then
            r.object:set_field('_IsCommandAbsorb',r.original)
        end
    end)
    if not ok then q.restore_error=tostring(err)end
    r.object:release();ledger=nil
end
local function install()
    assert(sdk.get_tdb_version()==82,'Unsupported soul runtime')
    local t=assert(sdk.find_type_definition('app.cPlayerSoulAbsorptionSupporter'))
    local function method(name,params,typ)
        local m=assert((typ or t):get_method(name));assert(not m:is_static() and m:get_return_type():get_full_name()=='System.Void' and m:get_num_params()==#params,'Soul signature mismatch')
        for i,p in ipairs(m:get_param_types() or {})do assert(p:get_full_name()==params[i],'Soul argument mismatch')end
        assert(sdk.to_int64(m:get_function())>0,'Missing soul method body');return m
    end
    local enum=assert(sdk.find_type_definition('app.PlayerCommand.TYPE'))
    absorb_command=assert(enum:get_field('ABSORB')):get_data(nil)
    assert(absorb_command==14,'Unsupported native ABSORB command index')
    local ct=assert(sdk.find_type_definition('app.cPlayerCommandResult'))
    sdk.hook(method('mergeResult',{'app.cPlayerCommandController'},ct),function(args)
        local storage=thread.get_hook_storage();storage.onimusha_absorb_command=nil
        q.command_calls=(q.command_calls or 0)+1
        local ok,err=pcall(function()
            local b,n,mc=bridge_context();if not b and q.command_preflight then return end
            local _,player=owner()
            local controller=assert(sdk.to_managed_object(args[3]))
            assert(controller:get_type_definition():get_full_name()=='app.cPlayerCommandController','Command controller type')
            local controlled=controller:call('get_Character')
            if not controlled or controlled:get_address()~=player:get_address()then return end
            local result=assert(sdk.to_managed_object(args[2]))
            assert(result:get_type_definition():get_full_name()=='app.cPlayerCommandResult','Command result type')
            storage.onimusha_absorb_command={object=result:add_ref(),held=mc and mc.absorb_souls==true,epoch=n and n.collision_epoch,preflight=not b}
        end)
        if not ok then q.error=tostring(err)end
    end,function(ret)
        local storage=thread.get_hook_storage();local r=storage.onimusha_absorb_command;storage.onimusha_absorb_command=nil
        if not r then return ret end
        local ok,err=pcall(function()
            local object=r.object;local address=object:get_address()
            if r.preflight then
                local samples={}
                for _,name in ipairs({'_CommandResultNormal','_CommandResultCancel'})do
                    local bits=assert(object:get_field(name));local typ=bits:get_type_definition()
                    assert(typ:is_a('ace.Bitset'),'Unexpected native command bitset '..typ:get_full_name())
                    local value=bits:call('isOn(System.Int32)',absorb_command)
                    assert(type(value)=='boolean' and bits:call('get_Length')>absorb_command)
                    -- Validate inherited method dispatch while takeover is off.
                    -- Write the EXISTING value, never synthesize an input here.
                    bits:call('set(System.Int32, System.Boolean)',absorb_command,value)
                    assert(bits:call('isOn(System.Int32)',absorb_command)==value)
                    samples[#samples+1]={type=typ:get_full_name(),length=bits:call('get_Length'),value=value}
                end
                q.command_preflight=samples;return
            end
            local b,n=bridge_context();if not b or n.collision_epoch~=r.epoch then return end
            local record=command_ledgers[address]
            if not record then
                local original=object:get_field('_IsSoulAbsorption');assert(type(original)=='boolean','Soul input result flag')
                record={object=object:add_ref(),original=original,bits={}};command_ledgers[address]=record
                for _,name in ipairs({'_CommandResultNormal','_CommandResultCancel'})do
                    local bits=assert(object:get_field(name))
                    assert(bits:get_type_definition():is_a('ace.Bitset'),'Soul command bitset type')
                    assert(bits:call('get_Length')>absorb_command,'Soul command bitset length')
                    local old=bits:call('isOn(System.Int32)',absorb_command);assert(type(old)=='boolean','Soul bitset value')
                    record.bits[#record.bits+1]={object=bits:add_ref(),original=old}
                end
            end
            for _,v in ipairs(record.bits)do v.object:call('set(System.Int32, System.Boolean)',absorb_command,r.held)end
            object:set_field('_IsSoulAbsorption',r.held)
            q.command_injections=q.command_injections+1
            if r.held then q.command_held=q.command_held+1 end
        end)
        r.object:release()
        if not ok then q.error=tostring(err);restore_commands()end
        return ret
    end)
    local function inject(args,phase)
        local ok,err=pcall(function()
            if phase=='before' then restore()end
            local b,n,mc=bridge_context();if not b then return end
            local o=owner();if sdk.to_int64(args[2])~=o:get_address()then return end
            local previous=o:get_field('_IsCommandAbsorb');assert(type(previous)=='boolean','Soul command is not boolean')
            if ledger and ledger.object:get_address()~=o:get_address()then restore()end
            if not ledger then o:add_ref();ledger={object=o,original=previous}end
            if phase=='bone' then
                q.bone_injections=q.bone_injections+1
                if mc.absorb_souls==true and not previous then q.overwritten=q.overwritten+1 end
            end
            o:set_field('_IsCommandAbsorb',mc.absorb_souls==true)
            assert(o:get_field('_IsCommandAbsorb')==(mc.absorb_souls==true),'Soul command write readback')
            q.held=mc.absorb_souls==true;q.injected=q.injected+1;q.epoch=n.collision_epoch
            if phase=='bone' and q.held then q.held_frames=q.held_frames+1;q.last_held_frame=q.frame end
        end)
        if not ok then q.error=tostring(err);restore()end
    end
    sdk.hook(method('updateBeforeAction',{}),function(args)inject(args,'before')end,function(ret)return ret end)
    -- The native command/action pass lies between updateBeforeAction and the
    -- bone-entity pass. Apply the live input at the actual absorption decision,
    -- after native command sealing, rather than relying on the early write.
    sdk.hook(method('updateAfterActionFromBoneEntity',{}),function(args)inject(args,'bone')end,function(ret)
        if ledger then
            local ok,err=pcall(function()
                q.native={command=ledger.object:get_field('_IsCommandAbsorb'),
                    absorption_type=ledger.object:get_field('_AbsorptionType'),
                    absorbing=ledger.object:get_field('_IsAbsorption'),
                    request=ledger.object:get_field('_IsRequestSoulAbsorptionAction')}
                if q.held then q.last_held_native=q.native end
            end)
            if not ok then q.error=tostring(err)end
        end
        return ret
    end)
    sdk.hook(method('lateUpdate',{}),nil,function(ret)restore();return ret end)
    sdk.hook(method('executeSoulAbsorptionSuccess',{'app.SoulBase'}),function(args)
        local storage=thread.get_hook_storage();storage.onimusha_soul_success=nil
        local ok,err=pcall(function()
            local b,n=bridge_context();if not b then return end
            local o=owner();if sdk.to_int64(args[2])~=o:get_address()then return end
            storage.onimusha_soul_success={epoch=n.collision_epoch,owner=o:get_address()}
        end)
        if not ok then q.error=tostring(err)end
    end,function(ret)
        local storage=thread.get_hook_storage();local s=storage.onimusha_soul_success;storage.onimusha_soul_success=nil
        if s then
            q.successes=q.successes+1
            if #q.pending<256 then q.pending[#q.pending+1]=s else q.error='Soul reward queue full'end
        end
        return ret
    end)
    q.installed=true
end
re.on_application_entry('LateUpdateBehavior',function()
    q.frame=q.frame+1;restore();restore_commands()
    if not q.installed and not q.install_error then
        local ok,err=pcall(install);if not ok then q.install_error=tostring(err)end
    end
    if #q.pending>0 then
        local ok,err=pcall(function()
            local b,n=bridge_context()
            if not b then q.pending={};return end
            local o=owner();local keep={}
            for _,s in ipairs(q.pending)do
                if s.epoch==n.collision_epoch and s.owner==o:get_address()then
                    if b.reward_absorbed_soul({epoch=s.epoch})then q.rewards=q.rewards+1 else keep[#keep+1]=s end
                end
            end
            q.pending=keep
        end)
        if not ok then q.error=tostring(err);q.pending={}end
    end
    if q.frame%60==0 then json.dump_file('onimusha_soul_status.json',q)end
end)
re.on_script_reset(function()restore();restore_commands();q.pending={}end)
