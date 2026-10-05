#include "Renderer.hpp"
#include "RenderStore.hpp"
#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <cstdarg>
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
}
int main(){
    try{
        Gpu gpu;REFrameworkPluginFunctions f{};f.log_info=log;f.log_warn=log;f.log_error=log;REFrameworkRendererData r{};r.renderer_type=REFRAMEWORK_RENDERER_D3D12;r.device=gpu.device.Get();r.command_queue=gpu.queue.Get();r.swapchain=gpu.swap.Get();REFrameworkPluginInitializeParam p{};p.functions=&f;p.renderer_data=&r;
        RenderStore store;store.atlas.width=store.atlas.height=2;store.atlas.revision=1;for(int i=0;i<4;i++)store.atlas.rgba.insert(store.atlas.rgba.end(),{255,0,0,255});
        Mesh mesh;mesh.revision=1;mesh.vertices={{-0.6f,-0.6f,0.5f,0,0,0xFFFFFFFFu,0x0f00,0},{0.6f,-0.6f,0.5f,0,0,0xFFFFFFFFu,0x0f00,0},{0,0.6f,0.5f,0,0,0xFFFFFFFFu,0x0f00,0}};store.sections[{0,0,0}]=mesh;
        OverlayFrame hud;hud.width=hud.height=2;hud.frameId=1;hud.rgba={0,0,0,0,0,255,0,255,0,0,0,0,0,0,0,0};proto::McState mc{};mc.flags=proto::kMcInWorld;mc.fovDeg=70;CameraState camera{};camera.valid=true;camera.viewProj[0]=camera.viewProj[5]=camera.viewProj[10]=camera.viewProj[15]=1;
        gpu.clear();renderer::initialize(&p);check(!renderer::ready(),"renderer fails closed before resource preflight");check(renderer::prepare()&&renderer::ready(),"GPU preflight succeeds without drawing");unsigned w{},h{};auto image=gpu.readback(w,h);const auto* untouched=image.data()+(std::size_t(h*5/8)*w+w/2)*4;check(untouched[0]==0&&untouched[1]==0&&untouched[2]==0,"resource preflight preserves original backbuffer");renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);inspect(image,w,h,"initial");
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
        mc.flags&=~proto::kMcScreenOpen;store.sections[{0,0,0}]=mesh;
        renderer::reset();check(!renderer::ready(),"device reset revokes renderer readiness");gpu.wait();require(gpu.swap->ResizeBuffers(2,400,300,DXGI_FORMAT_R8G8B8A8_UNORM,0),"resize after renderer reset");hud.frameId=2;gpu.clear();renderer::initialize(&p);check(renderer::prepare()&&renderer::ready(),"GPU readiness restored after resize");renderer::render(store,hud,mc,camera);image=gpu.readback(w,h);check(w==400&&h==300,"resize released all wrapped backbuffers");inspect(image,w,h,"resized");renderer::reset();gpu.wait();
        printf("%u failure(s), hidden D3D12 WARP smoke test\n",failures);return failures?1:0;
    }catch(const std::exception& e){fprintf(stderr,"Renderer smoke test failed: %s\n",e.what());renderer::reset();return 2;}
}
