"""Long session: cached live meshes survive; abandoned dependencies are bounded."""
from pathlib import Path
source=Path(__file__).with_name('native_dynamic_pool_regression.py').read_text(encoding='utf-8')
exec(source.split("lua.execute((Path")[0])
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
loaded=true;advance(120)
local made,captured=created,captures
for i=1,1000 do
 onimusha_native_sections.stop();advance(1,false);advance(1)
 assert(onimusha_native_sections.status().dynamic_ready==50)
end
assert(created==made and captures==captured and onimusha_native_sections.status().dynamic_pool_hits==50000)
print('PASS 1000 F10 cycles keep 50 objects and their exact resource owners with zero growth')
local capture=ctx.bridge.capture_native_model
ctx.bridge.capture_native_model=function(a)
 local id=capture(a)
 if a.model>=1000 then local r=results['onimusha_mc/native_models/'..id..'/result.json'];r.empty=true;r.asset_id=nil end
 return id
end
for kind=1000,2999 do sample.cubes={{x=0,y=0,z=0,kind=kind}};advance(18)end
sample.cubes={};advance(240)
local s=onimusha_native_sections.status()
assert(s.resources_ready<=514 and s.resources_evicted>=1488 and s.dynamic_ready==50 and s.pending_requests==0)
assert(created==made)
print('PASS 2000 historical appearances retain at most 512 idle plus two live resources; body stays native')
onimusha_native_sections.stop();advance(15,false)
local releases=released
for i=1,1000 do onimusha_native_sections.stop();advance(1,false)end
assert(released==releases and created==made)
print('PASS already-disabled frames perform no repeated teardown/release')
-- A missing worker result must not allow thousands of incomplete jobs to accumulate.
ctx.bridge.capture_native_model=function(a)captures=captures+1;return 'missing_'..captures end
sample.cubes={};for i=1,200 do sample.cubes[i]={x=i,y=0,z=0,kind=10000+i}end
advance(240)
assert(onimusha_native_sections.status().pending_requests==32)
callbacks.reset()
print('PASS stalled converter admission stays at 32 incomplete requests and cleanup remains available')
''')
