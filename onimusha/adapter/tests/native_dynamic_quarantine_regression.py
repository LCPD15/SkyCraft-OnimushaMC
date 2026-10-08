"""Production defaults never enter the native entity path after its game crash.

Mocks verify isolation/fallback only. They cannot validate RE resource lifetime.
"""
from pathlib import Path
source=Path(__file__).with_name('native_models_regression.py').read_text(encoding='utf-8')
exec(source.rsplit("lua.execute((Path",1)[0])
lua.execute(r'''
dynamic_calls=0
ctx.bridge.snapshot_native_dynamic=function()
 dynamic_calls=dynamic_calls+1
 error('quarantined entity snapshot must never execute')
end
ctx.bridge.ack_native_dynamic=function()
 error('quarantined entity stream must not hide MC rendering')
end
local capture=ctx.bridge.capture_native_model
ctx.bridge.capture_native_model=function(a)
 assert(a.priority==0,'entity conversion must not be queued')
 return capture(a)
end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
advance(30);loaded=true;advance(20)
local s=onimusha_native_sections.status()
assert(s.phase=='synchronized' and s.ready==2 and #ack_rows==2)
assert(s.dynamic_enabled==false and s.dynamic_ready==0 and s.dynamic_disabled_reason)
assert(dynamic_calls==0 and captures==1 and not s.error)
print('PASS block conversion and receipts work while entity capture/draw suppression stay quarantined')
onimusha_native_sections.stop();advance(15,false)
assert(not onimusha_native_sections.busy() and released>0)
advance(20)
assert(#ack_rows==2 and dynamic_calls==0 and captures==1)
callbacks.reset();assert(onimusha_native_sections==nil)
print('PASS F10 resume/reset does not reactivate quarantined dynamic loading')
''')
