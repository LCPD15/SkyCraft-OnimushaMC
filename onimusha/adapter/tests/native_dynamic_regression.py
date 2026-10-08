"""Real Lua module: posed faces, native point lights and independent error cleanup."""
from pathlib import Path
source=Path(__file__).with_name('native_models_regression.py').read_text(encoding='utf-8')
exec(source.rsplit("lua.execute((Path",1)[0])
lua.execute(r'''
local base=create_go
function create_go(name,folder)
 local go=base(name,folder);local b=objects[#objects];local old=go.call;b.name=name
 local mesh_call=b.mesh.call
 b.mesh.call=function(self,m,...)
  if m=='set_DrawShadowCast'then b.shadow=(...);return end
  return mesh_call(self,m,...)
 end
 local transform=obj({set_LocalScale=function(v)b.scale=v end})
 transform.set_position=function(_,v)b.p=v end
 transform.set_rotation=function(_,v)b.rotation=v end
 local light=obj({set_Enabled=function(v)b.enabled=v end,set_RenderOutputID=function(v)assert(v==31)end,
 set_Unit=function(v)assert(v==0)end,set_ShadowEnable=function(v)assert(not v)end,set_SourceRadius=function(v)assert(v>0)end,
 set_Color=function(v)b.color=v end,set_Radius=function(v)b.radius=v end,set_Intensity=function(v)b.intensity=v end})
 go.call=function(self,m,...)
  if m=='get_Transform'then return transform end
  if m=='createComponent(System.Type)' and (...)=='via.render.PointLight'then return light end
  return old(self,m,...)
 end
 return go
end
Vector3f={new=function(x,y,z)return{x=x,y=y,z=z}end}
Quaternion={new=function(w,x,y,z)return{w=w,x=x,y=y,z=z}end}
sample.cubes={};sample.lights={{x=1,y=2,z=3,color=0x00ffffff,level=14}}
dynamic={ready=true,epoch=81,avatar={{first=0,kind=101,x=5,y=6,z=7,qw=1,qx=0,qy=0,qz=0,sx=.5,sy=1}},scene={}}
ctx.bridge.snapshot_native_dynamic=function()return dynamic end
dynamic_rows={};dynamic_ack_ok=true
ctx.bridge.ack_native_dynamic=function(a)dynamic_rows[a.hands and 'hands' or (a.avatar and 'avatar' or 'scene')]=a.faces;return dynamic_ack_ok end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
advance(30);loaded=true;advance(20)
assert(onimusha_native_sections.status().dynamic_ready==1 and #dynamic_rows.avatar==1)
assert(onimusha_native_sections.status().lights==1)
local face
for _,b in ipairs(objects)do if b.rotation then face=b end end
assert(face and face.draw and face.scale.x==.5 and face.rotation.w==1 and face.p.x==-5)
local captures_before=captures;dynamic.avatar[1].x=9;advance(3)
assert(face.p.x==-1 and captures==captures_before)
print('PASS actual Lua dynamic pose updates transforms without new capture or resource')
sample.lights={};dynamic.avatar={};advance(15)
assert(not face.draw and onimusha_native_sections.status().lights==0 and not onimusha_native_sections.busy())
print('PASS extinguishing light / first-person camera / NPC removal retires native objects')
dynamic.hands_complete=true
dynamic.hands={{first=0,kind=101,x=1,y=2,z=3,qw=1,qx=0,qy=0,qz=0,sx=.2,sy=.4}}
advance(3)
local hand
for _,b in ipairs(objects)do if b.valid and b.name=='OMC_Dynamic_hands:0' then hand=b end end
assert(hand and hand.draw and not hand.shadow and #dynamic_rows.hands==1)
-- A second appearance is still loading: restore the entire vanilla hand draw,
-- never mix a half-ready native sword/shield with the complete MC HUD layer.
dynamic.hands[2]={first=6,kind=102,x=1,y=2,z=3,qw=1,qx=0,qy=0,qz=0,sx=.2,sy=.4}
loaded=false;advance(20)
assert(not hand.draw and #dynamic_rows.hands==0)
loaded=true;advance(20)
assert(hand.draw and #dynamic_rows.hands==2)
dynamic.hands_complete=false;advance(2)
assert(not hand.draw and #dynamic_rows.hands==0)
dynamic.hands_complete=true;advance(2);assert(hand.draw)
dynamic_ack_ok=false;advance(2);assert(not hand.draw)
dynamic_ack_ok=true;advance(2);assert(hand.draw)
print('PASS first-person hands require complete resource readiness and accepted receipts, otherwise all native faces hide')
-- Fully transparent faces must satisfy the completeness fence without creating
-- an empty native mesh; changing camera to F5 retires all hand GameObjects.
local capture=ctx.bridge.capture_native_model
ctx.bridge.capture_native_model=function(a)
 local id=capture(a);local r=results['onimusha_mc/native_models/'..id..'/result.json']
 if a.model==103 then r.empty=true;r.asset_id=nil end
 return id
end
dynamic.hands[3]={first=12,kind=103,x=1,y=2,z=3,qw=1,qx=0,qy=0,qz=0,sx=.2,sy=.4}
advance(30);assert(#dynamic_rows.hands==3 and hand.draw)
for _,b in ipairs(objects)do assert(b.name~='OMC_Dynamic_hands:12') end
dynamic.hands={};advance(15)
assert(not hand.draw and #dynamic_rows.hands==0 and not onimusha_native_sections.busy())
print('PASS transparent hand faces consume no GameObject, and F5 restores hands ownership')
sample.lights={{x=4,y=5,z=6,color=0xff9933,level=15}};advance(2)
onimusha_native_sections.stop();advance(15,false);assert(not onimusha_native_sections.busy())
callbacks.reset();assert(onimusha_native_sections==nil)
print('PASS light and animated resource reset is bounded and leaves no owned GameObjects')
''')
