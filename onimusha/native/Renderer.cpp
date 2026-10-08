// MIT; SkyCraft's exported meshes/HUD rendered through a private D3D11-on-12 context.
// The original game's scene remains in the backbuffer. Host collision triangles provide
// conservative depth occlusion until a verified native RE scene-depth binding is supplied.
#include "Renderer.hpp"
#include "CameraProjection.hpp"
#include "RenderStore.hpp"
#include <Windows.h>
#include <d3d11.h>
#include <d3d11on12.h>
#include <d3d12.h>
#include <d3dcompiler.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <iterator>
#include <string>
#include <vector>

namespace omc::renderer {
using Microsoft::WRL::ComPtr;
namespace {
const REFrameworkPluginInitializeParam* api{};
ComPtr<ID3D11Device> device;
ComPtr<ID3D11DeviceContext> context;
ComPtr<ID3D11On12Device> interop;
ComPtr<IDXGISwapChain3> swapchain;
struct Target { ComPtr<ID3D11Resource> wrapped; ComPtr<ID3D11RenderTargetView> rtv; };
std::vector<Target> targets;
ComPtr<ID3D11Texture2D> depthTexture;
ComPtr<ID3D11DepthStencilView> depthView;
ComPtr<ID3D11VertexShader> worldVs, overlayVs;
ComPtr<ID3D11PixelShader> worldPs, overlayPs;
ComPtr<ID3D11InputLayout> layout;
ComPtr<ID3D11Buffer> paramsBuffer;
ComPtr<ID3D11SamplerState> sampler;
ComPtr<ID3D11RasterizerState> raster;
ComPtr<ID3D11DepthStencilState> depthWrite, depthRead, depthOff;
ComPtr<ID3D11BlendState> solidBlend, straightAlpha, premultiplied, colorOff;
struct GpuTexture { ComPtr<ID3D11Texture2D> texture; ComPtr<ID3D11ShaderResourceView> srv; std::uint64_t revision{}; };
struct DrawRange { UINT first{},count{}; std::uint32_t texture{}; };
struct BlendedTriangle { proto::RenVertex vertices[3]; std::uint32_t texture{}; };
struct GpuMesh {
    ComPtr<ID3D11Buffer> buffer; UINT capacity{}; std::uint64_t revision{};
    std::uint64_t partitionRevision{}; bool partitionReady{};
    std::vector<DrawRange> solidRanges;
    std::vector<BlendedTriangle> blended;
};
std::map<std::uint32_t,GpuTexture> textures;
std::map<SectionKey,GpuMesh> sections;
std::map<SectionKey,GpuMesh> nativeDepth;
GpuTexture atlas, hud;
GpuMesh avatar, scene, terrain, blendedWorld, nativeAvatarDepth,nativeSceneDepth,nativeHandsDepth;
UINT width{},height{};
bool failed{};
bool guiCursorKnown{};
double guiCursorU{},guiCursorV{};
std::uint64_t lastHud{},lastTerrain{},blendedRevision{};
double terrainOrigin[3]{};
struct alignas(16) Params {
    float vp[16];
    float offset[4];
    float options[4]; // x HUD flip, y HUD cursor visible, z cursor x, w cursor y
};
constexpr char shader[]=R"HLSL(
cbuffer Parameters : register(b0) { row_major float4x4 vp; float4 offset; float4 options; };
Texture2D tex : register(t0);
SamplerState pointSampler : register(s0);
struct Input { float3 p:POSITION; float2 uv:TEXCOORD0; float4 color:COLOR0; uint light:TEXCOORD1; uint flags:TEXCOORD2; };
struct Output { float4 p:SV_Position; float2 uv:TEXCOORD0; float4 color:COLOR0; nointerpolation uint flags:TEXCOORD1; };
Output WorldVS(Input v) {
    Output o; o.p=mul(float4(v.p+offset.xyz,1),vp); o.uv=v.uv;
    float l=max(v.light&255,(v.light>>8)&255)/15.0;
    o.color=float4(v.color.rgb*(0.32+0.68*saturate(l)),v.color.a); o.flags=v.flags; return o;
}
float4 WorldPS(Output v):SV_Target {
    float4 t=tex.Sample(pointSampler,v.uv)*v.color;
    if(v.flags&(1u<<21)) t.rgb=lerp(t.rgb,float3(1,1,1),0.75);
    // Match SkyCraft's alpha-test/blend flags; opaque/cutout never blends.
    if(v.flags&2) clip(t.a-0.001);
    else { clip(t.a-0.5); t.a=1; }
    return t;
}
Output OverlayVS(uint id:SV_VertexID) {
    Output o; float2 uv=float2((id<<1)&2,id&2);
    o.p=float4(uv*float2(2,-2)+float2(-1,1),0,1); o.uv=uv; o.color=1; o.flags=0; return o;
}
float4 OverlayPS(Output v):SV_Target {
    float2 uv=v.uv; if(options.x>0.5) uv.y=1-uv.y;
    float4 c=tex.Sample(pointSampler,uv);
    if(options.y>0.5) {
        float2 p=v.p.xy-options.zw;
        if(p.x>=0 && p.y>=0 && p.y<18 && p.x<=p.y*0.6) {
            bool edge=p.x<1.5||p.x>p.y*0.6-1.5||p.y>16.5;
            c=float4(edge?float3(0,0,0):float3(1,1,1),1);
        }
    }
    return c;
}
)HLSL";
void logFailure(const char* what,HRESULT hr) {
    if(api&&api->functions) api->functions->log_error("[OnimushaMC renderer] %s HRESULT=%08X",what,static_cast<unsigned>(hr));
}
bool compile(const char* entry,const char* profile,ComPtr<ID3DBlob>& out) {
    ComPtr<ID3DBlob> errors;
    HRESULT hr=D3DCompile(shader,sizeof(shader)-1,"OnimushaMC",nullptr,nullptr,entry,profile,D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&out,&errors);
    if(FAILED(hr)) {
        logFailure(entry,hr);
        if(errors&&api)api->functions->log_error("%s",static_cast<const char*>(errors->GetBufferPointer()));
    }
    return SUCCEEDED(hr);
}
bool resources() {
    auto* rd=api?api->renderer_data:nullptr;
    if(!rd||!rd->device||!rd->swapchain||!rd->command_queue)return false;
    if(device)return true;
    ComPtr<ID3D12Device> native;
    HRESULT hr=static_cast<IUnknown*>(rd->device)->QueryInterface(IID_PPV_ARGS(&native));
    if(FAILED(hr)){logFailure("D3D12 required",hr);return false;}
    IUnknown* queues[]={static_cast<IUnknown*>(rd->command_queue)};
    D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_0};
    hr=D3D11On12CreateDevice(native.Get(),D3D11_CREATE_DEVICE_BGRA_SUPPORT,levels,1,queues,1,0,&device,&context,nullptr);
    if(FAILED(hr)){logFailure("D3D11On12CreateDevice",hr);return false;}
    if(FAILED(device.As(&interop))||FAILED(static_cast<IUnknown*>(rd->swapchain)->QueryInterface(IID_PPV_ARGS(&swapchain))))return false;
    DXGI_SWAP_CHAIN_DESC desc{}; swapchain->GetDesc(&desc);
    width=desc.BufferDesc.Width; height=desc.BufferDesc.Height;
    targets.resize(desc.BufferCount);
    for(UINT i=0;i<desc.BufferCount;++i) {
        ComPtr<ID3D12Resource> buffer;
        if(FAILED(swapchain->GetBuffer(i,IID_PPV_ARGS(&buffer))))return false;
        D3D11_RESOURCE_FLAGS flags{};flags.BindFlags=D3D11_BIND_RENDER_TARGET;
        hr=interop->CreateWrappedResource(buffer.Get(),&flags,D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_PRESENT,IID_PPV_ARGS(&targets[i].wrapped));
        if(FAILED(hr)){logFailure("wrap backbuffer",hr);return false;}
        if(FAILED(device->CreateRenderTargetView(targets[i].wrapped.Get(),nullptr,&targets[i].rtv)))return false;
    }
    ComPtr<ID3DBlob> vs,ps,ovs,ops;
    if(!compile("WorldVS","vs_5_0",vs)||!compile("WorldPS","ps_5_0",ps)||!compile("OverlayVS","vs_5_0",ovs)||!compile("OverlayPS","ps_5_0",ops))return false;
    if(FAILED(device->CreateVertexShader(vs->GetBufferPointer(),vs->GetBufferSize(),nullptr,&worldVs))||
       FAILED(device->CreatePixelShader(ps->GetBufferPointer(),ps->GetBufferSize(),nullptr,&worldPs))||
       FAILED(device->CreateVertexShader(ovs->GetBufferPointer(),ovs->GetBufferSize(),nullptr,&overlayVs))||
       FAILED(device->CreatePixelShader(ops->GetBufferPointer(),ops->GetBufferSize(),nullptr,&overlayPs)))return false;
    D3D11_INPUT_ELEMENT_DESC elements[]={
        {"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"TEXCOORD",0,DXGI_FORMAT_R32G32_FLOAT,0,12,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"COLOR",0,DXGI_FORMAT_R8G8B8A8_UNORM,0,20,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"TEXCOORD",1,DXGI_FORMAT_R32_UINT,0,24,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"TEXCOORD",2,DXGI_FORMAT_R32_UINT,0,28,D3D11_INPUT_PER_VERTEX_DATA,0}};
    if(FAILED(device->CreateInputLayout(elements,5,vs->GetBufferPointer(),vs->GetBufferSize(),&layout)))return false;
    D3D11_BUFFER_DESC cb{}; cb.ByteWidth=sizeof(Params);cb.Usage=D3D11_USAGE_DYNAMIC;cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER;cb.CPUAccessFlags=D3D11_CPU_ACCESS_WRITE;
    if(FAILED(device->CreateBuffer(&cb,nullptr,&paramsBuffer)))return false;
    D3D11_SAMPLER_DESC sd{};sd.Filter=D3D11_FILTER_MIN_MAG_MIP_POINT;sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP;sd.MaxLOD=D3D11_FLOAT32_MAX;
    if(FAILED(device->CreateSamplerState(&sd,&sampler)))return false;
    D3D11_RASTERIZER_DESC rs{};rs.FillMode=D3D11_FILL_SOLID;rs.CullMode=D3D11_CULL_NONE;rs.DepthClipEnable=TRUE;
    if(FAILED(device->CreateRasterizerState(&rs,&raster)))return false;
    D3D11_DEPTH_STENCIL_DESC ds{};ds.DepthEnable=TRUE;ds.DepthWriteMask=D3D11_DEPTH_WRITE_MASK_ALL;ds.DepthFunc=D3D11_COMPARISON_LESS_EQUAL;
    if(FAILED(device->CreateDepthStencilState(&ds,&depthWrite)))return false;
    ds.DepthWriteMask=D3D11_DEPTH_WRITE_MASK_ZERO;
    if(FAILED(device->CreateDepthStencilState(&ds,&depthRead)))return false;
    ds.DepthEnable=FALSE;
    if(FAILED(device->CreateDepthStencilState(&ds,&depthOff)))return false;
    D3D11_BLEND_DESC bs{};auto& b=bs.RenderTarget[0];b.BlendEnable=TRUE;b.SrcBlend=D3D11_BLEND_SRC_ALPHA;b.DestBlend=D3D11_BLEND_INV_SRC_ALPHA;b.BlendOp=D3D11_BLEND_OP_ADD;b.SrcBlendAlpha=D3D11_BLEND_ONE;b.DestBlendAlpha=D3D11_BLEND_INV_SRC_ALPHA;b.BlendOpAlpha=D3D11_BLEND_OP_ADD;b.RenderTargetWriteMask=D3D11_COLOR_WRITE_ENABLE_ALL;
    if(FAILED(device->CreateBlendState(&bs,&straightAlpha)))return false;
    b.SrcBlend=D3D11_BLEND_ONE;
    if(FAILED(device->CreateBlendState(&bs,&premultiplied)))return false;
    b.BlendEnable=FALSE;
    if(FAILED(device->CreateBlendState(&bs,&solidBlend)))return false;
    b.RenderTargetWriteMask=0;
    if(FAILED(device->CreateBlendState(&bs,&colorOff)))return false;
    D3D11_TEXTURE2D_DESC td{};td.Width=width;td.Height=height;td.MipLevels=1;td.ArraySize=1;td.Format=DXGI_FORMAT_D32_FLOAT;td.SampleDesc.Count=1;td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_DEPTH_STENCIL;
    if(FAILED(device->CreateTexture2D(&td,nullptr,&depthTexture))||FAILED(device->CreateDepthStencilView(depthTexture.Get(),nullptr,&depthView)))return false;
    if(api)api->functions->log_info("[OnimushaMC renderer] D3D11-on-12 ready %ux%u",width,height);
    return true;
}
bool texture(GpuTexture& out,UINT w,UINT h,const std::vector<std::uint8_t>& rgba,std::uint64_t revision) {
    if(!w||!h||w>8192||h>8192||rgba.size()!=std::uint64_t(w)*h*4)return false;
    if(out.srv&&out.revision==revision)return true;
    D3D11_TEXTURE2D_DESC td{};td.Width=w;td.Height=h;td.MipLevels=1;td.ArraySize=1;td.Format=DXGI_FORMAT_R8G8B8A8_UNORM;td.SampleDesc.Count=1;td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    if(!out.texture||out.revision==0) {
        D3D11_SUBRESOURCE_DATA init{rgba.data(),w*4,0};out={};
        if(FAILED(device->CreateTexture2D(&td,&init,&out.texture))||FAILED(device->CreateShaderResourceView(out.texture.Get(),nullptr,&out.srv)))return false;
    } else {
        D3D11_TEXTURE2D_DESC old{};out.texture->GetDesc(&old);
        if(old.Width!=w||old.Height!=h){out={};return texture(out,w,h,rgba,revision);}
        context->UpdateSubresource(out.texture.Get(),0,nullptr,rgba.data(),w*4,0);
    }
    out.revision=revision;return true;
}
bool mesh(GpuMesh& out,const std::vector<proto::RenVertex>& vertices,std::uint64_t revision) {
    if(vertices.empty())return false;
    if(out.buffer&&out.revision==revision)return true;
    auto bytes=vertices.size()*sizeof(proto::RenVertex);
    if(bytes>128ull*1024*1024)return false;
    if(bytes>out.capacity||!out.buffer) {
        out={};D3D11_BUFFER_DESC bd{};bd.ByteWidth=static_cast<UINT>(bytes);bd.Usage=D3D11_USAGE_DYNAMIC;bd.BindFlags=D3D11_BIND_VERTEX_BUFFER;bd.CPUAccessFlags=D3D11_CPU_ACCESS_WRITE;
        if(FAILED(device->CreateBuffer(&bd,nullptr,&out.buffer)))return false;
        out.capacity=bd.ByteWidth;
    }
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if(FAILED(context->Map(out.buffer.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapped)))return false;
    std::memcpy(mapped.pData,vertices.data(),bytes);context->Unmap(out.buffer.Get(),0);out.revision=revision;return true;
}
bool parameters(const Params& p) {
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if(FAILED(context->Map(paramsBuffer.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapped)))return false;
    std::memcpy(mapped.pData,&p,sizeof(p));context->Unmap(paramsBuffer.Get(),0);return true;
}
void cameraParameters(const proto::McState& mc,const CameraState& supplied,Params& p,double origin[3]) {
    const auto projection=make_camera_projection(mc,supplied,width,height);
    std::copy(projection.origin,projection.origin+3,origin);
    std::copy(projection.viewProj,projection.viewProj+16,p.vp);
}
ID3D11ShaderResourceView* meshTexture(std::uint32_t id) {
    if(!id)return atlas.srv.Get();const auto it=textures.find(id);
    return it==textures.end()?nullptr:it->second.srv.Get();
}
void appendRange(std::vector<DrawRange>& ranges,UINT first,std::uint32_t texture) {
    if(!ranges.empty()&&ranges.back().texture==texture&&ranges.back().first+ranges.back().count==first)ranges.back().count+=3;
    else ranges.push_back({first,3,texture});
}
bool partitionMesh(const Mesh& m,GpuMesh& gpu) {
    if(gpu.partitionReady&&gpu.partitionRevision==m.revision)return true;
    if(m.vertices.size()>128ull*1024*1024/sizeof(proto::RenVertex))return false;
    std::vector<proto::RenVertex> solid;
    std::vector<DrawRange> ranges;
    std::vector<BlendedTriangle> blended;
    auto collect=[&](std::size_t first,std::size_t count,std::uint32_t texture,bool batchBlended){
        if(first>m.vertices.size()||count>m.vertices.size()-first)return;
        for(std::size_t i=first;i+2<first+count;i+=3){
            const auto* v=m.vertices.data()+i;
            const bool translucent=batchBlended||((v[0].flags|v[1].flags|v[2].flags)&2)!=0;
            if(translucent){
                BlendedTriangle triangle{{v[0],v[1],v[2]},texture};
                // RenBatch bit0 also selects blending even if vertex flags are zero.
                for(auto& vertex:triangle.vertices)vertex.flags|=2;
                blended.push_back(triangle);
            }else{
                appendRange(ranges,static_cast<UINT>(solid.size()),texture);
                solid.insert(solid.end(),v,v+3);
            }
        }
    };
    if(m.batches.empty())collect(0,m.vertices.size(),0,false);
    else for(const auto& batch:m.batches)collect(batch.first,batch.count,batch.texture,(batch.flags&1)!=0);
    if(!solid.empty()&&!mesh(gpu,solid,m.revision))return false;
    gpu.solidRanges=std::move(ranges);gpu.blended=std::move(blended);
    gpu.partitionRevision=m.revision;gpu.partitionReady=true;return true;
}
struct BlendedDraw {
    const BlendedTriangle* triangle{};
    double offset[3]{},depth{};
};
void drawSolidMesh(const Mesh& m,GpuMesh& gpu,const double origin[3],Params& p,
    std::vector<BlendedDraw>& blended,const double* meshOrigin=nullptr) {
    if(!partitionMesh(m,gpu))return;
    const auto* offset=meshOrigin?meshOrigin:m.origin;
    for(int k=0;k<3;++k)p.offset[k]=static_cast<float>(offset[k]-origin[k]);
    if(!gpu.solidRanges.empty()&&parameters(p)){
        UINT stride=sizeof(proto::RenVertex),zero=0;auto* vb=gpu.buffer.Get();context->IASetVertexBuffers(0,1,&vb,&stride,&zero);
        for(const auto& range:gpu.solidRanges){
            auto* srv=meshTexture(range.texture);if(!srv)continue;
            context->PSSetShaderResources(0,1,&srv);context->Draw(range.count,range.first);
        }
    }
    for(const auto& triangle:gpu.blended){
        if(!meshTexture(triangle.texture))continue;
        BlendedDraw draw;draw.triangle=&triangle;double center[4]={0,0,0,1};
        // Exact exported vertices and mesh origins supply the centroid. There is
        // no guessed section center, material alpha classification or MC camera proxy.
        for(int k=0;k<3;++k){
            draw.offset[k]=offset[k]-origin[k];
            for(const auto& v:triangle.vertices)center[k]+=(k==0?v.x:k==1?v.y:v.z)/3.0;
            center[k]+=draw.offset[k];
        }
        double z{},w{};for(int r=0;r<4;++r){z+=center[r]*p.vp[r*4+2];w+=center[r]*p.vp[r*4+3];}
        // This renderer's production projection/depth uses near=0, far=1.
        // A centroid behind the near plane goes first and is clipped by the GPU.
        draw.depth=w>1e-9?z/w:1e100;if(std::isfinite(draw.depth))blended.push_back(draw);
    }
}
void drawBlended(std::vector<BlendedDraw>& draws,Params& p) {
    if(draws.empty())return;
    if(draws.size()>128ull*1024*1024/(3*sizeof(proto::RenVertex)))return;
    std::stable_sort(draws.begin(),draws.end(),[](const auto& a,const auto& b){return a.depth>b.depth;});
    std::vector<proto::RenVertex> vertices;vertices.reserve(draws.size()*3);
    std::vector<DrawRange> ranges;
    for(const auto& draw:draws){
        appendRange(ranges,static_cast<UINT>(vertices.size()),draw.triangle->texture);
        for(auto v:draw.triangle->vertices){v.x+=float(draw.offset[0]);v.y+=float(draw.offset[1]);v.z+=float(draw.offset[2]);vertices.push_back(v);}
    }
    if(!mesh(blendedWorld,vertices,++blendedRevision))return;
    p.offset[0]=p.offset[1]=p.offset[2]=0;if(!parameters(p))return;
    context->OMSetDepthStencilState(depthRead.Get(),0);context->OMSetBlendState(straightAlpha.Get(),nullptr,~0u);
    UINT stride=sizeof(proto::RenVertex),zero=0;auto* vb=blendedWorld.buffer.Get();context->IASetVertexBuffers(0,1,&vb,&stride,&zero);
    for(const auto& range:ranges){auto* srv=meshTexture(range.texture);if(!srv)continue;context->PSSetShaderResources(0,1,&srv);context->Draw(range.count,range.first);}
}
}
void initialize(const REFrameworkPluginInitializeParam* p){api=p;}
void set_gui_cursor(bool known,double u,double v){
    guiCursorKnown=known&&std::isfinite(u)&&std::isfinite(v);
    guiCursorU=u;guiCursorV=v;
}
bool ready() {
    return !failed && device && context && interop && swapchain && depthView &&
        worldVs && worldPs && overlayVs && overlayPs && layout && paramsBuffer &&
        !targets.empty() && std::all_of(targets.begin(),targets.end(),[](const Target& t){return t.wrapped && t.rtv;});
}
bool prepare() {
    if(failed)return false;
    auto* rd=api?api->renderer_data:nullptr;
    if(!rd||!rd->device||!rd->swapchain||!rd->command_queue)return false;
    if(!resources()){failed=true;return false;}
    return ready();
}
void reset() {
    if(context){context->ClearState();context->Flush();}
    terrain={};avatar={};scene={};blendedWorld={};nativeAvatarDepth={};nativeSceneDepth={};nativeHandsDepth={};atlas={};hud={};textures.clear();sections.clear();nativeDepth.clear();targets.clear();
    depthView.Reset();depthTexture.Reset();worldVs.Reset();worldPs.Reset();overlayVs.Reset();overlayPs.Reset();layout.Reset();paramsBuffer.Reset();sampler.Reset();raster.Reset();depthWrite.Reset();depthRead.Reset();depthOff.Reset();solidBlend.Reset();straightAlpha.Reset();premultiplied.Reset();colorOff.Reset();
    interop.Reset();context.Reset();device.Reset();swapchain.Reset();width=height=0;lastHud=lastTerrain=blendedRevision=0;failed=false;
}
void render(const RenderStore& store,const OverlayFrame& overlay,const proto::McState& mc,const CameraState& supplied) {
    if(failed||!(mc.flags&proto::kMcInWorld))return;
    if(!prepare())return;
    UINT index=swapchain->GetCurrentBackBufferIndex();if(index>=targets.size())return;
    auto* wrapped=targets[index].wrapped.Get();auto* rtv=targets[index].rtv.Get();
    interop->AcquireWrappedResources(&wrapped,1);
    struct Release { ID3D11On12Device* interop;ID3D11DeviceContext* context;ID3D11Resource* resource;~Release(){context->OMSetRenderTargets(0,nullptr,nullptr);interop->ReleaseWrappedResources(&resource,1);context->Flush();} } cleanup{interop.Get(),context.Get(),wrapped};
    context->OMSetRenderTargets(1,&rtv,depthView.Get());context->ClearDepthStencilView(depthView.Get(),D3D11_CLEAR_DEPTH,1.0f,0);
    D3D11_VIEWPORT viewport{0,0,float(width),float(height),0,1};context->RSSetViewports(1,&viewport);context->RSSetState(raster.Get());
    context->IASetInputLayout(layout.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context->VSSetShader(worldVs.Get(),nullptr,0);context->PSSetShader(worldPs.Get(),nullptr,0);
    auto* cb=paramsBuffer.Get();context->VSSetConstantBuffers(0,1,&cb);context->PSSetConstantBuffers(0,1,&cb);
    auto* smp=sampler.Get();context->PSSetSamplers(0,1,&smp);
    texture(atlas,store.atlas.width,store.atlas.height,store.atlas.rgba,store.atlas.revision);
    for(const auto& [id,t]:store.textures)texture(textures[id],t.width,t.height,t.rgba,t.revision);
    for(auto it=textures.begin();it!=textures.end();)if(!store.textures.contains(it->first))it=textures.erase(it);else++it;
    Params p{};double origin[3]{};cameraParameters(mc,supplied,p,origin);
    context->OMSetDepthStencilState(depthWrite.Get(),0);
    if(!store.collisionTriangles.empty()) {
        if(store.collisionRevision!=lastTerrain||!terrain.buffer) {
            for(int k=0;k<3;++k)terrainOrigin[k]=std::floor(double(store.collisionTriangles.front().v[k])/16.0)*16.0;
            std::vector<proto::RenVertex> vertices;vertices.reserve(store.collisionTriangles.size()*3);
            for(const auto& triangle:store.collisionTriangles)for(int i=0;i<3;++i) {
                proto::RenVertex v{};v.x=static_cast<float>(triangle.v[i*3]-terrainOrigin[0]);v.y=static_cast<float>(triangle.v[i*3+1]-terrainOrigin[1]);v.z=static_cast<float>(triangle.v[i*3+2]-terrainOrigin[2]);vertices.push_back(v);
            }
            if(mesh(terrain,vertices,store.collisionRevision))lastTerrain=store.collisionRevision;
        }
        // A collision-only prepass writes no color and avoids requiring an atlas before first transfer.
        if(terrain.buffer) {
            context->OMSetBlendState(colorOff.Get(),nullptr,~0u);context->PSSetShader(nullptr,nullptr,0);
            for(int k=0;k<3;++k)p.offset[k]=static_cast<float>(terrainOrigin[k]-origin[k]);parameters(p);
            UINT stride=sizeof(proto::RenVertex),zero=0;auto* vb=terrain.buffer.Get();context->IASetVertexBuffers(0,1,&vb,&stride,&zero);
            context->Draw(static_cast<UINT>(store.collisionTriangles.size()*3),0);context->PSSetShader(worldPs.Get(),nullptr,0);
        }
    }
    const auto nativeLeaseNow=GetTickCount64();
    // RE draws native blocks before Present. Preserve their exact opaque geometry in
    // the private depth prepass so overlay avatars/items/glass cannot draw through them.
    context->OMSetBlendState(colorOff.Get(),nullptr,~0u);context->PSSetShader(worldPs.Get(),nullptr,0);
    auto* nativeAtlas=atlas.srv.Get();context->PSSetShaderResources(0,1,&nativeAtlas);
    for(const auto&[key,view]:store.nativeViews){
        const auto src=store.sections.find(key);
        if(src==store.sections.end()||view.sourceRevision!=src->second.nativeRevision||nativeLeaseNow>=view.expires)continue;
        auto&g=nativeDepth[key];if(!mesh(g,view.depth.vertices,view.depth.revision))continue;
        for(int k=0;k<3;++k)p.offset[k]=static_cast<float>(view.depth.origin[k]-origin[k]);if(!parameters(p))continue;
        UINT stride=sizeof(proto::RenVertex),zero=0;auto*vb=g.buffer.Get();context->IASetVertexBuffers(0,1,&vb,&stride,&zero);
        context->Draw(static_cast<UINT>(view.depth.vertices.size()),0);
    }
    for(auto it=nativeDepth.begin();it!=nativeDepth.end();)if(!store.nativeViews.contains(it->first))it=nativeDepth.erase(it);else++it;
    const bool sceneNative=store.nativeScene.remainder.nativeRevision==store.scene.revision&&store.nativeScene.expires>nativeLeaseNow;
    const bool avatarNative=store.nativeAvatar.remainder.nativeRevision==store.avatar.revision&&store.nativeAvatar.expires>nativeLeaseNow;
    std::vector<BlendedDraw> noBlended;
    if(sceneNative)drawSolidMesh(store.nativeScene.depth,nativeSceneDepth,origin,p,noBlended);
    if(avatarNative&&mc.cameraMode!=0){double feet[]={mc.x,mc.y,mc.z};drawSolidMesh(store.nativeAvatar.depth,nativeAvatarDepth,origin,p,noBlended,feet);}
    if(mc.cameraMode==0&&store.hands_ready(nativeLeaseNow))drawSolidMesh(store.nativeHands.depth,nativeHandsDepth,origin,p,noBlended);
    context->PSSetShader(worldPs.Get(),nullptr,0);
    // All opaque/cutout geometry precedes every translucent triangle, across
    // sections, scene entities and the third-person avatar.
    context->OMSetBlendState(solidBlend.Get(),nullptr,~0u);
    std::vector<BlendedDraw> blended;
    for(const auto& [key,m]:store.sections)drawSolidMesh(store.section_overlay(key,m,nativeLeaseNow),sections[key],origin,p,blended);
    for(auto it=sections.begin();it!=sections.end();)if(!store.sections.contains(it->first))it=sections.erase(it);else++it;
    drawSolidMesh(sceneNative?store.nativeScene.remainder:store.scene,scene,origin,p,blended);
    if(mc.cameraMode!=0){double feet[]={mc.x,mc.y,mc.z};drawSolidMesh(avatarNative?store.nativeAvatar.remainder:store.avatar,avatar,origin,p,blended,feet);}
    drawBlended(blended,p);
    if(overlay.frameId&&texture(hud,overlay.width,overlay.height,overlay.rgba,overlay.frameId)) {
        context->OMSetDepthStencilState(depthOff.Get(),0);context->OMSetBlendState(premultiplied.Get(),nullptr,~0u);
        context->IASetInputLayout(nullptr);context->VSSetShader(overlayVs.Get(),nullptr,0);context->PSSetShader(overlayPs.Get(),nullptr,0);
        p.options[0]=(overlay.flags&1)?1.0f:0.0f;
        p.options[1]=(mc.flags&proto::kMcScreenOpen)&&guiCursorKnown?1.0f:0.0f;
        // Polling the OS cursor here would see the host's center warp, not the GUI event.
        p.options[2]=float(guiCursorU*width);p.options[3]=float(guiCursorV*height);
        parameters(p);auto* srv=hud.srv.Get();context->PSSetShaderResources(0,1,&srv);context->Draw(3,0);
    }
    ID3D11ShaderResourceView* empty=nullptr;context->PSSetShaderResources(0,1,&empty);
}
}
