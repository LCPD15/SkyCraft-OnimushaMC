"""Run the real hot-reload router with SDK lifecycle/callback fixtures."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'onimusha_loader.lua').read_text(encoding='utf-8')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
files={};events={};native_hooks={};logs={};enabled=false;ready=true;busy=false;hook_installs=0
json={load_file=function(p) return files[p] end,dump_file=function(p,v) files[p]=v end}
fs={read=function(p) return files[p] or '' end}
log={error=function(v) logs[#logs+1]=v end}
re={on_application_entry=function(n,f) events[n]=events[n] or {};table.insert(events[n],f) end,
 on_script_reset=function(f) reset=f end}
sdk={to_int64=function(x) return x end,PreHookResult={SKIP_ORIGINAL=77},
 hook=function(m,pre,post) hook_installs=hook_installs+1;native_hooks[m:get_function()]={pre=pre,post=post} end}
storage={};thread={get_hook_storage=function() return storage end}
onimusha_mc={set_enabled=function(v) enabled=v end,status=function() return {enabled=enabled} end}
count=0;cleanups=0;pre_count=0
payload=[[local tag=1
_G.onimusha_adapter_lifecycle={ready_for_reload=function() return ready end}
_G.onimusha_enemy_hit={busy=function() return busy end}
re.on_application_entry('UpdateBehavior',function() _G.count=count+tag end)
sdk.hook({get_function=function() return 99 end},function() _G.pre_count=pre_count+tag;return sdk.PreHookResult.SKIP_ORIGINAL end,function(ret) return ret+tag end)
re.on_script_reset(function() _G.cleanups=cleanups+1;if cleanup_fail then error('cleanup injected') end end)
]]
files['onimusha_mc/scripts/onimusha_mc.lua']=payload
for _,n in ipairs({'onimusha_enemy_hit.lua','onimusha_guard_probe.lua','onimusha_combat_inventory.lua','onimusha_native_blocks.lua','onimusha_native_models.lua'}) do files['onimusha_mc/scripts/'..n]='-- valid empty test module' end
function advance(n)
 for _=1,n do
  local list=events.LateUpdateBehavior or {};local copy={table.unpack(list)}
  for _,f in ipairs(copy) do f() end
 end
end
function request(id) files['onimusha_reload_control.json']={id=id,action='reload'} end
function status() return files['onimusha_reload_status.json'] end
function update() for _,f in ipairs(events.UpdateBehavior or {}) do f() end end
''')
lua.execute(source)
lua.execute(r'''
local cases=0
local function pass(s) cases=cases+1;print('PASS '..s) end
advance(1);assert(status().phase=='loaded' and hook_installs==1);update();assert(count==1)
pass('initial load registers one event dispatcher / native hook')
for i=1,20 do request('reload-'..i);advance(34);local old=count;update();assert(count==old+1) end
assert(hook_installs==1 and #events.UpdateBehavior==1 and cleanups==20)
assert(native_hooks[99].pre({})==77 and native_hooks[99].post(5)==6)
pass('20 reloads retain one hook, one live callback, and original pre/post semantics')
native_hooks[99].pre({});request('busy-hook');advance(50)
assert(status().phase=='disabling_takeover');native_hooks[99].post(0);advance(4)
assert(status().phase=='loaded');pass('reload waits until a native hook has returned')
busy=true;request('native-pending');advance(40);assert(status().phase=='disabling_takeover')
busy=false;advance(4);assert(status().phase=='loaded');pass('queued native damage settles before reload')
ready=false;enabled=true;request('restore-player');advance(40);assert(not enabled and status().phase=='disabling_takeover')
ready=true;advance(4);assert(status().phase=='loaded');pass('disable takeover and wait for original-character restoration')
files['onimusha_mc/scripts/onimusha_mc.lua']='local !broken'
request('broken');advance(40);assert(status().phase=='compile_failed_old_retained');local old=count;update();assert(count==old+1)
pass('syntax failure preserves previous callbacks and reports failure')
files['onimusha_mc/scripts/onimusha_mc.lua']=payload.."\nerror('startup injected')"
request('startup-failure');advance(40);assert(status().phase=='rolled_back');old=count;update();assert(count==old+1 and hook_installs==1)
pass('startup failure reloads last known good source without duplicate hooks')
files['onimusha_mc/scripts/onimusha_mc.lua']=payload
cleanup_fail=true;request('cleanup-failure');advance(40);assert(status().phase=='cleanup_failed');cleanup_fail=false
pass('failed original-character cleanup prevents replacement')
request('recover');advance(40);local generation=status().generation;advance(90);assert(status().generation==generation)
assert(files['onimusha_reload_receipt.json'].id=='recover')
pass('each request acknowledged once; durable receipt prevents reset/restart loops')
reset();old=count;update();assert(count==old);pass('global framework reset disconnects all project callbacks')
print('RELOAD_REGRESSION_OK '..cases..' groups')
''')
