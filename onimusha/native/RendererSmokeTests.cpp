#include "Renderer.hpp"
#include "CameraProjection.hpp"
#include "RenderStore.hpp"
#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <cstdarg>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;
using namespace omc;
unsigned failures{};
void require(HRESULT hr,const char* what){if(FAILED(hr)){char out[256];sprintf_s(out,"%s: HRESULT %08X",what,unsigned(hr));throw std::runtime_error(out);}}
void log(const char* format,...){va_list args;va_start(args,format);vfprintf(stderr,format,args);fputc('\n',stderr);va_end(args);}
void check(bool ok,const char* what){printf("%s: %s\n",ok?"PASS":"FAIL",what);if(!ok)++failures;}
using Point=std::array<double,3>;
struct Ndc{double x{},y{},z{},w{};};
Ndc project(const renderer::CameraProjection& camera,const Point& point){
    const double p[]={point[0]-camera.origin[0],point[1]-camera.origin[1],point[2]-camera.origin[2],1};double clip[4]{};
    // Independent scalar application of the matrix layout used by WorldVS.
    for(int c=0;c<4;c++)for(int r=0;r<4;r++)clip[c]+=p[r]*camera.viewProj[r*4+c];
    return {clip[0]/clip[3],clip[1]/clip[3],clip[2]/clip[3],clip[3]};
}
Point offset(const double origin[3],const Point& direction,double distance,const Point& lateral={},double amount=0){
    return {origin[0]+direction[0]*distance+lateral[0]*amount,origin[1]+direction[1]*distance+lateral[1]*amount,origin[2]+direction[2]*distance+lateral[2]*amount};
}
void projection_tests(){
    constexpr double rad=3.14159265358979323846/180;
    bool side=true,forwardDepth=true,vertical=true,polesFinite=true,originCorrect=true,thirdPerson=true;
    for(const float yaw:{0.f,45.f,90.f,135.f,180.f,225.f,270.f,315.f})for(const float pitch:{-90.f,-60.f,-25.f,0.f,25.f,60.f,90.f})for(unsigned mode=0;mode<3;mode++){
        proto::McState mc{};mc.eyeX=123.25;mc.eyeY=65.5;mc.eyeZ=-88.75;mc.yaw=yaw;mc.pitch=pitch;mc.fovDeg=70;mc.cameraMode=mode;mc.cameraDistance=4;
        const double sy=std::sin(yaw*rad),cy=std::cos(yaw*rad),sp=std::sin(pitch*rad),cp=std::cos(pitch*rad);
        const Point mcForward={-sy*cp,-sp,cy*cp};const Point mcRight={-cy,0,-sy};const Point up={-sy*sp,cp,cy*sp};
        const double front=mode==2?-1.0:1.0;Point viewForward{},viewRight{};
        for(int k=0;k<3;k++){viewForward[k]=mcForward[k]*front;viewRight[k]=mcRight[k]*front;}
        const auto matrix=renderer::make_camera_projection(mc,{},1920,1080);
        const auto center=project(matrix,offset(matrix.origin,viewForward,4));const auto right=project(matrix,offset(matrix.origin,viewForward,4,viewRight,1));const auto left=project(matrix,offset(matrix.origin,viewForward,4,viewRight,-1));const auto upper=project(matrix,offset(matrix.origin,viewForward,4,up,0.5));
        side=side&&right.x>0.1&&left.x<-0.1&&std::abs(center.x)<1e-5;
        forwardDepth=forwardDepth&&center.w>0&&center.z>=0&&center.z<=1&&std::abs(center.y)<1e-5;
        vertical=vertical&&upper.y>0.1;
        for(const auto value:matrix.viewProj)polesFinite=polesFinite&&std::isfinite(value);
        const double eye[]={mc.eyeX,mc.eyeY,mc.eyeZ};const double distance=mode==0?0:(mode==2?4:-4);
        for(int k=0;k<3;k++)originCorrect=originCorrect&&std::abs(matrix.origin[k]-eye[k]-mcForward[k]*distance)<2e-6;
        if(mode){const auto target=project(matrix,{mc.eyeX,mc.eyeY,mc.eyeZ});thirdPerson=thirdPerson&&target.w>0&&target.z>=0&&target.z<=1&&std::abs(target.x)<1e-5&&std::abs(target.y)<1e-5;}
    }
    check(side,"production RH projection maps MC/camera right to positive NDC and left to negative across eight yaws and all F5 modes");
    check(forwardDepth,"production fallback forward has positive clip W and D3D depth within 0..1 across pitch -90..90");
    check(vertical&&polesFinite,"production yaw/pitch up remains screen-up and finite at both vertical poles");
    check(originCorrect&&thirdPerson,"production F5 rear/front origins and player-eye target agree without coordinate mirroring");
    proto::McState mc{};mc.fovDeg=70;const auto matrix=renderer::make_camera_projection(mc,{},320,240);
    const auto nearPlane=project(matrix,{0,0,0.03});const auto farPoint=project(matrix,{0,0,2048});
    check(nearPlane.w>0&&std::abs(nearPlane.z)<1e-5&&farPoint.w>0&&std::abs(farPoint.z-1)<1e-5,"production RH near/far planes retain D3D zero-to-one depth");
}
struct Gpu {
    HWND hwnd{};ComPtr<IDXGIFactory4> factory;ComPtr<ID3D12Device> device;ComPtr<ID3D12CommandQueue> queue;ComPtr<IDXGISwapChain3> swap;
    ComPtr<ID3D12CommandAllocator> allocator;ComPtr<ID3D12GraphicsCommandList> list;ComPtr<ID3D12Fence> fence;
    HANDLE event{};std::uint64_t sequence{};
    Gpu(){
        WNDCLASSW wc{};wc.hInstance=GetModuleHandleW(nullptr);wc.lpfnWndProc=DefWindowProcW;wc.lpszClassName=L"OnimushaMCHeadlessRendererTest";RegisterClassW(&wc);
        hwnd=CreateWindowExW(0,wc.lpszClassName,L"OnimushaMC renderer test",WS_OVERLAPPEDWINDOW,0,0,320,240,nullptr,nullptr,wc.hInstance,nullptr);
        if(!hwnd)throw std::runtime_error("Create hidden window failed");
        require(CreateDXGIFactory1(IID_PPV_ARGS(&factory)),"CreateDXGIFactory");ComPtr<IDXGIAdapter> warp;require(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)),"WARP adapter");require(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)),"WARP device");
        D3D12_COMMAND_QUEUE_DESC q{};q.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;require(device->CreateCommandQueue(&q,IID_PPV_ARGS(&queue)),"queue");
        DXGI_SWAP_CHAIN_DESC1 sd{};sd.Width=320;sd.Height=240;sd.Format=DXGI_FORMAT_R8G8B8A8_UNORM;sd.SampleDesc.Count=1;sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;sd.BufferCount=2;sd.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD;
        ComPtr<IDXGISwapChain1> first;require(factory->CreateSwapChainForHwnd(queue.Get(),hwnd,&sd,nullptr,nullptr,&first),"hidden swapchain");require(first.As(&swap),"swapchain3");
        require(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)),"allocator");require(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&list)),"list");require(list->Close(),"close initial list");require(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)),"fence");event=CreateEventW(nullptr,FALSE,FALSE,nullptr);if(!event)throw std::runtime_error("event");
    }
    ~Gpu(){if(event)CloseHandle(event);if(hwnd)DestroyWindow(hwnd);}
    void wait(){require(queue->Signal(fence.Get(),++sequence),"queue signal");if(fence->GetCompletedValue()<sequence){require(fence->SetEventOnCompletion(sequence,event),"fence event");if(WaitForSingleObject(event,10000)!=WAIT_OBJECT_0)throw std::runtime_error("GPU timeout (10 s)");}}
    void begin(){wait();require(allocator->Reset(),"reset allocator");require(list->Reset(allocator.Get(),nullptr),"reset command list");}
    void submit(){require(list->Close(),"close list");ID3D12CommandList* cmds[]={list.Get()};queue->ExecuteCommandLists(1,cmds);wait();}
    ComPtr<ID3D12Resource> buffer(){ComPtr<ID3D12Resource> b;require(swap->GetBuffer(swap->GetCurrentBackBufferIndex(),IID_PPV_ARGS(&b)),"backbuffer");return b;}
    void barrier(ID3D12Resource* b,D3D12_RESOURCE_STATES from,D3D12_RESOURCE_STATES to){D3D12_RESOURCE_BARRIER rb{};rb.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;rb.Transition.pResource=b;rb.Transition.StateBefore=from;rb.Transition.StateAfter=to;rb.Transition.Subresource=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;list->ResourceBarrier(1,&rb);}
    void clear(){auto b=buffer();begin();D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;hd.NumDescriptors=1;ComPtr<ID3D12DescriptorHeap> heap;require(device->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&heap)),"rtv heap");const auto handle=heap->GetCPUDescriptorHandleForHeapStart();device->CreateRenderTargetView(b.Get(),nullptr,handle);barrier(b.Get(),D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_RENDER_TARGET);const float black[]={0,0,0,1};list->ClearRenderTargetView(handle,black,0,nullptr);barrier(b.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_PRESENT);submit();}
    std::vector<std::uint8_t> readback(unsigned& width,unsigned& height){
        auto b=buffer();const auto desc=b->GetDesc();width=unsigned(desc.Width);height=desc.Height;
        D3D12_PLACED_SUBRESOURCE_FOOTPRINT foot{};UINT rows{};UINT64 rowSize{},bytes{};device->GetCopyableFootprints(&desc,0,1,0,&foot,&rows,&rowSize,&bytes);
        D3D12_HEAP_PROPERTIES hp{};hp.Type=D3D12_HEAP_TYPE_READBACK;D3D12_RESOURCE_DESC rd{};rd.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;rd.Width=bytes;rd.Height=1;rd.DepthOrArraySize=1;rd.MipLevels=1;rd.SampleDesc.Count=1;rd.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;ComPtr<ID3D12Resource> staging;require(device->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&rd,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&staging)),"readback buffer");
        begin();barrier(b.Get(),D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_COPY_SOURCE);
        D3D12_TEXTURE_COPY_LOCATION src{};src.pResource=b.Get();src.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        D3D12_TEXTURE_COPY_LOCATION dst{};dst.pResource=staging.Get();dst.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;dst.PlacedFootprint=foot;list->CopyTextureRegion(&dst,0,0,0,&src,nullptr);barrier(b.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_PRESENT);submit();
        void* data{};D3D12_RANGE range{0,std::size_t(bytes)};require(staging->Map(0,&range,&data),"map readback");std::vector<std::uint8_t> out(std::size_t(width)*height*4);for(unsigned y=0;y<height;y++)std::memcpy(out.data()+std::size_t(y)*width*4,static_cast<std::uint8_t*>(data)+foot.Offset+std::size_t(y)*foot.Footprint.RowPitch,std::size_t(width)*4);D3D12_RANGE none{0,0};staging->Unmap(0,&none);return out;
    }
};
void inspect(const std::vector<std::uint8_t>& pixels,unsigned w,unsigned h,const char* pass){
    const auto* red=pixels.data()+(std::size_t(h*5/8)*w+w/2)*4;const auto* green=pixels.data()+(std::size_t(h/8)*w+w*7/8)*4;const auto* black=pixels.data()+(std::size_t(h/8)*w+w/8)*4;
    printf("%s readback red=%u,%u,%u,%u green=%u,%u,%u,%u background=%u,%u,%u,%u\n",pass,red[0],red[1],red[2],red[3],green[0],green[1],green[2],green[3],black[0],black[1],black[2],black[3]);
    check(red[0]>200&&red[1]<30&&red[2]<30,"MC triangle appears in D3D12 backbuffer");check(green[1]>200&&green[0]<30&&green[2]<30,"MC HUD overlay appears above world");check(black[0]<10&&black[1]<10&&black[2]<10,"transparent HUD preserves original scene");
}
void direction_gpu_test(Gpu& gpu){
    RenderStore store;store.atlas={1,1,{255,255,255,255},3};store.scene.revision=55;
    const auto quad=[&](float x,float z,std::uint32_t color){
        const float xs[]={x-0.3f,x+0.3f,x-0.3f,x+0.3f},ys[]={-0.3f,-0.3f,0.3f,0.3f};
        for(const int i:{0,1,2,2,1,3})store.scene.vertices.push_back({xs[i],ys[i],z,0,0,color,0x0f00,0});
    };
    quad(-1,4,0xff0000ffu); // yaw zero: Minecraft's right points toward negative X.
    quad(1,4,0xffff0000u);quad(0,-4,0xff00ff00u); // Behind-camera green must clip.
    proto::McState mc{};mc.flags=proto::kMcInWorld;mc.fovDeg=70;gpu.clear();renderer::render(store,{},mc,{});
    unsigned w{},h{};const auto pixels=gpu.readback(w,h);unsigned leftRed{},rightRed{},leftBlue{},rightBlue{},green{};
    for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++){
        const auto* p=pixels.data()+(std::size_t(y)*w+x)*4;
        if(p[0]>200&&p[1]<30&&p[2]<30)(x<w/2?leftRed:rightRed)++;
        if(p[2]>200&&p[0]<30&&p[1]<30)(x<w/2?leftBlue:rightBlue)++;
        if(p[1]>200&&p[0]<30&&p[2]<30)++green;
    }
    check(rightRed>100&&leftBlue>100&&!leftRed&&!rightBlue,"actual fallback GPU WorldVS pixels place MC right red on screen-right and MC left blue on screen-left");
    check(green==0,"actual fallback GPU RH projection clips geometry behind the camera");
}
void dynamic_gpu_test(Gpu&gpu){
    // Match consume(): store revision already includes every uploaded source mesh.
    RenderStore store;store.revision=90010;store.atlas={1,1,{255,255,255,255},90000};store.atlasBaseRevision=90000;
    store.textures[1]={1,1,{0,0,255,255},90001};store.textures[2]={1,1,{0,255,0,255},90001};
    const float x[]={-.6f,.6f,.6f,-.6f},y[]={-.6f,-.6f,.6f,.6f};
    for(int i:{0,1,2,0,2,3})store.scene.vertices.push_back({x[i],y[i],.3f,float(i==1||i==2),float(i>=2),0xffffffff,0x0f00,0x79});
    store.scene.batches={{1,0,6,0}};store.scene.revision=90001;
    store.avatar=store.scene;store.avatar.revision=90002;store.avatar.batches={{2,0,6,0}};for(auto&v:store.avatar.vertices)v.z=.7f;
    store.prepare_dynamic();check(store.nativeScene.faces.size()==1,"GPU fixture contains one recognized entity face");
    store.accept_dynamic(0,{{0,store.nativeScene.faces[0].model}},GetTickCount64());store.partition_dynamic(store.scene,store.nativeScene,GetTickCount64());
    CameraState camera{};camera.valid=true;camera.viewProj[0]=camera.viewProj[5]=camera.viewProj[10]=camera.viewProj[15]=1;
    proto::McState mc{};mc.flags=proto::kMcInWorld;mc.cameraMode=1;unsigned w{},h{};
    gpu.clear();renderer::render(store,{},mc,camera);auto pixels=gpu.readback(w,h);auto*p=pixels.data()+(std::size_t(h/2)*w+w/2)*4;
    check(p[0]<5&&p[1]<5&&p[2]<5,"native entity face hides duplicate MC color while depth-occluding other MC entities");
    store.textures[1].rgba[3]=0;store.textures[1].revision=90003;
    gpu.clear();renderer::render(store,{},mc,camera);pixels=gpu.readback(w,h);p=pixels.data()+(std::size_t(h/2)*w+w/2)*4;
    check(p[1]>240&&p[2]<5,"native entity private depth samples its own texture and preserves cutout holes");
    store.release_dynamic();store.textures[1].rgba[3]=255;store.textures[1].revision=90004;
    gpu.clear();renderer::render(store,{},mc,camera);pixels=gpu.readback(w,h);p=pixels.data()+(std::size_t(h/2)*w+w/2)*4;
    check(p[2]>240&&p[1]<5,"release restores source entity drawing without stale GPU ownership");
}
void transparency_gpu_tests(Gpu& gpu){
    RenderStore store;store.atlas={1,1,{255,255,255,255},101};
    proto::McState mc{};mc.flags=proto::kMcInWorld;mc.fovDeg=70;
    CameraState camera{};camera.valid=true;camera.viewProj[0]=camera.viewProj[5]=camera.viewProj[10]=camera.viewProj[15]=1;
    auto quad=[](Mesh& target,float leftDepth,float rightDepth,std::uint32_t color,std::uint32_t flags){
        const float x[]={-.8f,.8f,-.8f,.8f},y[]={-.8f,-.8f,.8f,.8f};
        for(const int i:{0,1,2,2,1,3})target.vertices.push_back({x[i],y[i],i%2?rightDepth:leftDepth,0,0,color,0x0f00,flags});
    };
    unsigned w{},h{};
    auto render=[&](){gpu.clear();renderer::render(store,{},mc,camera);return gpu.readback(w,h);};
    auto pixel=[&](const auto& pixels,unsigned x,unsigned y){return pixels.data()+(std::size_t(y)*w+x)*4;};
    Mesh mixed;mixed.revision=101;
    // The problematic original order: glass first, opaque geometry behind it last.
    quad(mixed,.2f,.2f,0x800000ffu,2);quad(mixed,.7f,.7f,0xffff0000u,0);
    store.sections[{0,0,0}]=mixed;auto pixels=render();auto* p=pixel(pixels,w/2,h/2);
    printf("glass-before-opaque pixel=%u,%u,%u,%u\n",p[0],p[1],p[2],p[3]);
    check(p[0]>115&&p[0]<140&&p[2]>115&&p[2]<140&&p[1]<5,
        "GPU glass composites over later-source opaque background instead of hiding it with depth writes");
    mixed.vertices.clear();mixed.revision=102;
    quad(mixed,.3f,.3f,0x800000ffu,2);quad(mixed,.1f,.1f,0xff00ff00u,0);
    store.sections[{0,0,0}]=mixed;pixels=render();p=pixel(pixels,w/2,h/2);
    check(p[1]>250&&p[0]<5&&p[2]<5,"GPU opaque foreground still depth-occludes transparent geometry");
    mixed.vertices.clear();mixed.revision=103;
    quad(mixed,.2f,.2f,0x400000ffu,1);quad(mixed,.7f,.7f,0xffff0000u,0);
    store.sections[{0,0,0}]=mixed;pixels=render();p=pixel(pixels,w/2,h/2);
    check(p[2]>250&&p[0]<5&&p[1]<5,"GPU cutout alpha below one-half leaves background visible and writes no depth");
    mixed.vertices.clear();mixed.revision=104;
    quad(mixed,.2f,.2f,0xc00000ffu,1);quad(mixed,.7f,.7f,0xffff0000u,0);
    store.sections[{0,0,0}]=mixed;pixels=render();p=pixel(pixels,w/2,h/2);
    check(p[0]>250&&p[1]<5&&p[2]<5,"GPU surviving cutout is opaque rather than partially blended");
    store.sections.clear();store.scene={};store.scene.revision=105;
    store.textures[1]={1,1,{255,0,0,128},105};store.textures[2]={1,1,{0,0,255,128},105};
    // Both meshes' local depths give the wrong order unless their actual origins
    // are included. RenBatch bit0 requests blending despite zero vertex flags.
    Mesh farGlass;farGlass.revision=105;farGlass.origin[2]=.6;quad(farGlass,.1f,.1f,0xffffffffu,0);farGlass.batches={{2,0,6,1}};
    Mesh background;background.revision=105;quad(background,.95f,.95f,0xffffffffu,0);
    store.sections[{0,0,0}]=farGlass;store.sections[{0,0,1}]=background;
    store.scene.origin[2]=.2;quad(store.scene,.15f,.15f,0xffffffffu,0);store.scene.batches={{1,0,6,1}};
    pixels=render();p=pixel(pixels,w/2,h/2);
    printf("sorted cross-mesh glass pixel=%u,%u,%u,%u\n",p[0],p[1],p[2],p[3]);
    check(p[0]>180&&p[0]<200&&p[1]>55&&p[1]<75&&p[2]>115&&p[2]<140,
        "GPU batch-transparent triangles sort back-to-front across scene/section origins");
    store.sections.clear();store.scene={};store.scene.revision=106;store.textures.clear();
    // The upper-left part of the sloping far-centroid triangle is locally nearer
    // than the blue plane. Both layers must contribute there: a transparent depth
    // write would incorrectly erase the later blue layer at this actual pixel.
    quad(store.scene,.15f,.85f,0x800000ffu,2);quad(store.scene,.4f,.4f,0x80ff0000u,2);
    pixels=render();p=pixel(pixels,w/4,h/8);
    printf("transparent no-depth-write pixel=%u,%u,%u,%u\n",p[0],p[1],p[2],p[3]);
    check(p[0]>40&&p[0]<90&&p[2]>110&&p[2]<145&&p[1]<5,
        "GPU transparent crossing faces retain both contributions without writing depth");
}
}
int main(){
    try{
        projection_tests();
        Gpu gpu;REFrameworkPluginFunctions f{};f.log_info=log;f.log_warn=log;f.log_error=log;REFrameworkRendererData r{};r.renderer_type=REFRAMEWORK_RENDERER_D3D12;r.device=gpu.device.Get();r.command_queue=gpu.queue.Get();r.swapchain=gpu.swap.Get();REFrameworkPluginInitializeParam p{};p.functions=&f;p.renderer_data=&r;
        RenderStore store;store.atlas.width=store.atlas.height=2;store.atlas.revision=1;for(int i=0;i<4;i++)store.atlas.rgba.insert(store.atlas.rgba.end(),{255,0,0,255});
        Mesh mesh;mesh.revision=1;mesh.vertices={{-0.6f,-0.6f,0.5f,0,0,0xFFFFFFFFu,0x0f00,0},{0.6f,-0.6f,0.5f,0,0,0xFFFFFFFFu,0x0f00,0},{0,0.6f,0.5f,0,0,0xFFFFFFFFu,0x0f00,0}};store.sections[{0,0,0}]=mesh;
        OverlayFrame hud;hud.width=hud.height=2;hud.frameId=1;hud.rgba={0,0,0,0,0,255,0,255,0,0,0,0,0,0,0,0};proto::McState mc{};mc.flags=proto::kMcInWorld;mc.fovDeg=70;CameraState camera{};camera.valid=true;camera.viewProj[0]=camera.viewProj[5]=camera.viewProj[10]=camera.viewProj[15]=1;
        gpu.clear();renderer::initialize(&p);check(!renderer::ready(),"renderer fails closed before resource preflight");check(renderer::prepare()&&renderer::ready(),"GPU preflight succeeds without drawing");unsigned w{},h{};auto image=gpu.readback(w,h);const auto* untouched=image.data()+(std::size_t(h*5/8)*w+w/2)*4;check(untouched[0]==0&&untouched[1]==0&&untouched[2]==0,"resource preflight preserves original backbuffer");renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);inspect(image,w,h,"initial");
        store.revision=10;store.sections[{0,0,0}].nativeRevision=1;
        check(store.accept_native_section({0,0,0},1,std::vector<std::uint8_t>{1},GetTickCount64()),"native draw readiness receipt accepted");
        gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);
        auto* nativeHidden=image.data()+(std::size_t(h*5/8)*w+w/2)*4;
        check(nativeHidden[0]<10&&nativeHidden[1]<10&&nativeHidden[2]<10,"native-owned triangle is absent from overlay color buffer");
        store.scene=mesh;store.scene.revision=20;for(auto&v:store.scene.vertices){v.z=.7f;v.color=0xff00ff00;}
        gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);nativeHidden=image.data()+(std::size_t(h*5/8)*w+w/2)*4;
        check(nativeHidden[1]<10,"native-owned geometry still depth-occludes overlay MC entities");
        store.atlas.rgba.assign(16,255);for(int i=0;i<4;i++)store.atlas.rgba[i*4+3]=0;store.atlas.revision=1000;
        store.textures[1]={1,1,{0,255,0,255},1000};store.scene.batches={{1,0,3,0}};store.scene.revision=21;
        gpu.clear();renderer::render(store,{},mc,camera);image=gpu.readback(w,h);nativeHidden=image.data()+(std::size_t(h*5/8)*w+w/2)*4;
        check(nativeHidden[1]>200,"native cutout holes do not occlude MC entities in private depth");
        store.atlas.rgba.clear();for(int i=0;i<4;i++)store.atlas.rgba.insert(store.atlas.rgba.end(),{255,0,0,255});store.atlas.revision=1001;
        store.scene={};store.invalidate_native_views();gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);inspect(image,w,h,"native receipt released");
        proto::ColTri blocker{};for(int i=0;i<3;i++){blocker.v[i*3]=mesh.vertices[i].x;blocker.v[i*3+1]=mesh.vertices[i].y;blocker.v[i*3+2]=0.25f;}store.collisionTriangles={blocker};store.collisionRevision=1;
        gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);const auto* occluded=image.data()+(std::size_t(h*5/8)*w+w/2)*4;check(occluded[0]<10&&occluded[1]<10&&occluded[2]<10,"original-world collider depth occludes MC mesh");
        store.collisionTriangles.clear();store.collisionRevision=2;store.sections.clear();store.avatar=mesh;store.avatar.batches={{1,0,3,0}};store.textures[1]={2,2,{0,0,255,255,0,0,255,255,0,0,255,255,0,0,255,255},1};mc.cameraMode=1;
        gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);const auto* avatar=image.data()+(std::size_t(h*5/8)*w+w/2)*4;check(avatar[2]>200&&avatar[0]<30&&avatar[1]<30,"MC third-person avatar entity texture renders");
        mc.cameraMode=0;gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);avatar=image.data()+(std::size_t(h*5/8)*w+w/2)*4;check(avatar[0]<10&&avatar[1]<10&&avatar[2]<10,"first-person camera suppresses world avatar");
        mc.flags|=proto::kMcScreenOpen;renderer::set_gui_cursor(true,0.25,0.25);
        gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);
        auto arrow=image.data()+(std::size_t(h/4+10)*w+w/4+3)*4;
        check(arrow[0]>200&&arrow[1]>200&&arrow[2]>200,"GUI arrow uses cached normalized event position, independent of OS cursor");
        renderer::set_gui_cursor(false);gpu.clear();renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);
        arrow=image.data()+(std::size_t(h/4+10)*w+w/4+3)*4;
        check(arrow[0]<10&&arrow[1]<10&&arrow[2]<10,"focus/GUI cursor reset removes stale arrow");
        direction_gpu_test(gpu);
        transparency_gpu_tests(gpu);
        dynamic_gpu_test(gpu);
        mc.flags&=~proto::kMcScreenOpen;store.sections[{0,0,0}]=mesh;
        renderer::reset();check(!renderer::ready(),"device reset revokes renderer readiness");gpu.wait();require(gpu.swap->ResizeBuffers(2,400,300,DXGI_FORMAT_R8G8B8A8_UNORM,0),"resize after renderer reset");hud.frameId=2;gpu.clear();renderer::initialize(&p);check(renderer::prepare()&&renderer::ready(),"GPU readiness restored after resize");renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);check(w==400&&h==300,"resize released all wrapped backbuffers");inspect(image,w,h,"resized");renderer::reset();gpu.wait();
        printf("%u failure(s), hidden D3D12 WARP smoke test\n",failures);return failures?1:0;
    }catch(const std::exception& e){fprintf(stderr,"Renderer smoke test failed: %s\n",e.what());renderer::reset();return 2;}
}
