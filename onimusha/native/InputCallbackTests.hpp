#pragma once
// Test-only fixture: direct DLL callbacks, hidden WARP surface, simulated MC IPC.
// The foreground HWND is read only to satisfy the plugin's focus gate. No desktop
// input, cursor movement, focus changes, ShowWindow or SendInput are performed.
#include "../../protocol/skycraft_protocol.h"
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace omc::tests {
using Microsoft::WRL::ComPtr;
namespace proto=skycraft::proto;
inline void require(HRESULT hr,const char* what){if(FAILED(hr))throw std::runtime_error(what);}
struct InputGpu {
    HWND hwnd{};ComPtr<IDXGIFactory4> factory;ComPtr<ID3D12Device> device;
    ComPtr<ID3D12CommandQueue> queue;ComPtr<IDXGISwapChain3> swap;
    InputGpu(){
        WNDCLASSW wc{};wc.hInstance=GetModuleHandleW(nullptr);wc.lpfnWndProc=DefWindowProcW;wc.lpszClassName=L"OMCInputCallbackTest";RegisterClassW(&wc);
        hwnd=CreateWindowExW(0,wc.lpszClassName,L"Hidden input callback test",WS_OVERLAPPEDWINDOW,0,0,320,240,nullptr,nullptr,wc.hInstance,nullptr);
        if(!hwnd)throw std::runtime_error("hidden test HWND");
        require(CreateDXGIFactory1(IID_PPV_ARGS(&factory)),"DXGI factory");ComPtr<IDXGIAdapter> warp;
        require(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)),"WARP adapter");require(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)),"WARP device");
        D3D12_COMMAND_QUEUE_DESC q{};q.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;require(device->CreateCommandQueue(&q,IID_PPV_ARGS(&queue)),"WARP queue");
        DXGI_SWAP_CHAIN_DESC1 desc{};desc.Width=320;desc.Height=240;desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;desc.SampleDesc.Count=1;desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;desc.BufferCount=2;desc.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD;
        ComPtr<IDXGISwapChain1> first;require(factory->CreateSwapChainForHwnd(queue.Get(),hwnd,&desc,nullptr,nullptr,&first),"hidden swapchain");require(first.As(&swap),"swapchain3");
    }
    ~InputGpu(){if(hwnd)DestroyWindow(hwnd);}
    void wait(){
        ComPtr<ID3D12Fence> fence;require(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)),"input test fence");
        HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr);if(!event)throw std::runtime_error("input test event");
        const auto hr=queue->Signal(fence.Get(),1);if(FAILED(hr)){CloseHandle(event);require(hr,"input test queue signal");}
        require(fence->SetEventOnCompletion(1,event),"input test fence event");const auto result=WaitForSingleObject(event,10000);CloseHandle(event);if(result!=WAIT_OBJECT_0)throw std::runtime_error("input GPU wait timeout");
    }
};
struct InputPeer {
    HANDLE mapping{};std::uint8_t* base{};
    InputPeer(){mapping=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,proto::kMappingName);if(mapping)base=static_cast<std::uint8_t*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,proto::kMappingBytes));if(!base)throw std::runtime_error("test IPC view");}
    ~InputPeer(){if(base)UnmapViewOfFile(base);if(mapping)CloseHandle(mapping);}
    void publish(bool menu){
        auto* h=reinterpret_cast<proto::Header*>(base);auto* s=reinterpret_cast<proto::McState*>(base+proto::kOffMcState);
        auto seq=std::atomic_ref(s->seq);const auto old=seq.load();seq.store(old+1);proto::McState copy{};copy.x=2;copy.y=3;copy.z=4;copy.eyeX=2;copy.eyeY=4.62;copy.eyeZ=4;copy.eyeHeight=1.62f;copy.fovDeg=70;copy.teleportAck=1;copy.flags=proto::kMcInWorld|(menu?proto::kMcScreenOpen:0);
        std::memcpy(reinterpret_cast<std::uint8_t*>(s)+4,reinterpret_cast<const std::uint8_t*>(&copy)+4,sizeof(copy)-4);seq.store(old+2,std::memory_order_release);
        std::atomic_ref(h->mcPid).store(GetCurrentProcessId());std::atomic_ref(h->mcHeartbeatMs).store(GetTickCount64(),std::memory_order_release);
    }
    std::vector<proto::InputEvent> drain(){
        auto* r=base+proto::kOffInputRing;auto head=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r)).load(std::memory_order_acquire);auto tail=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r+proto::kInputRingTailOff));const auto start=tail.load();std::vector<proto::InputEvent> out;
        for(auto i=start;i<head;i++)out.push_back(reinterpret_cast<proto::InputEvent*>(r+proto::kInputRingDataOff)[i&(proto::kInputRingEntries-1)]);tail.store(head,std::memory_order_release);return out;
    }
};
inline bool input_callback_tests(lua_State* L,REFrameworkRendererData& render,REFOnPresentCb present,REFOnDeviceResetCb reset,REFOnMessageCb message,unsigned& defaultProcCalls){
    try{
        InputGpu gpu;InputPeer peer;render.device=gpu.device.Get();render.command_queue=gpu.queue.Get();render.swapchain=gpu.swap.Get();
        struct Cleanup{lua_State* L;REFOnDeviceResetCb reset;InputGpu& gpu;~Cleanup(){luaL_dostring(L,"onimusha_mc.set_enabled(false)");reset();try{gpu.wait();}catch(...){}}} cleanup{L,reset,gpu};
        const char* setup=R"(
            assert(onimusha_mc.submit_host({ready=true,epoch=9,x=2,y=3,z=4,health_current=75,health_max=100,teleport_seq=1,viewport_w=1920,viewport_h=1080}))
            assert(onimusha_mc.publish_collision_tris({epoch=9,min_x=0,min_y=0,min_z=0,max_x=10,max_y=10,max_z=10,triangles={{ax=0,ay=0,az=0,bx=0,by=0,bz=10,cx=10,cy=0,cz=0}}}))
            assert(onimusha_mc.set_camera({binding_ready=true,valid=false}))
            assert(onimusha_mc.set_enabled(true))
        )";
        if(luaL_dostring(L,setup)!=LUA_OK)throw std::runtime_error(lua_tostring(L,-1));peer.publish(true);present();
        if(luaL_dostring(L,"assert(onimusha_mc.status().ready)")!=LUA_OK)throw std::runtime_error("input callback ready gate");
        const HWND foreground=GetForegroundWindow();RECT rect{};if(!foreground||!GetClientRect(foreground,&rect)||rect.right<16||rect.bottom<16)throw std::runtime_error("No usable foreground HWND for read-only focus check");
        const int w=rect.right,h=rect.bottom,x=w/4,y=h*3/4;const auto pos=[](int a,int b){return LPARAM(MAKELPARAM(a,b));};peer.drain();
        auto defaults=defaultProcCalls;
        if(message(foreground,WM_INPUT,RIM_INPUT,0)||defaultProcCalls!=defaults+1||!peer.drain().empty())throw std::runtime_error("GUI raw input must delegate one cleanup to REFramework wrapper");
        const auto check_click=[&](unsigned kind,int a,int b,bool down){
            if(message(foreground,kind,0,pos(a,b)))return false;const auto events=peer.drain();
            return events.size()==2&&events[0].type==proto::kInCursor&&events[0].a==int(double(a)*1920/w)&&events[0].b==int(double(b)*1080/h)&&events[1].type==proto::kInMouseButton&&events[1].a==int(down);
        };
        if(!check_click(WM_LBUTTONDOWN,x,y,true))throw std::runtime_error("button LPARAM cursor ordering/position");
        message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));message(foreground,WM_MOUSEMOVE,0,pos(w/2+1,h/2-1));if(!peer.drain().empty())throw std::runtime_error("GUI center warp forwarded");
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(s.gui_cursor_known and math.abs(s.gui_cursor_u-0.25)<0.01 and math.abs(s.gui_cursor_v-0.75)<0.01)")!=LUA_OK)throw std::runtime_error("GUI warp replaced normalized event cache");
        if(!check_click(WM_LBUTTONUP,x,y,false))throw std::runtime_error("button-up reused stale OS position");
        if(!check_click(WM_LBUTTONDOWN,w/2,h/2,true))throw std::runtime_error("explicit center click filtered");
        message(foreground,WM_KILLFOCUS,0,0);auto events=peer.drain();if(events.size()!=1||events[0].type!=proto::kInReleaseAll)throw std::runtime_error("focus release did not clear inputs");
        if(luaL_dostring(L,"assert(not onimusha_mc.status().gui_cursor_known)")!=LUA_OK)throw std::runtime_error("focus release kept GUI cursor cache");
        peer.publish(false);present();message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));if(!peer.drain().empty())throw std::runtime_error("focus baseline restored as movement");
        defaults=defaultProcCalls;
        if(message(foreground,WM_INPUT,RIM_INPUT,0)||defaultProcCalls!=defaults+1||!peer.drain().empty())throw std::runtime_error("non-GUI invalid raw input must delegate one cleanup to REFramework wrapper");
        peer.publish(true);present();message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));if(!peer.drain().empty())throw std::runtime_error("GUI transition synthesized center cursor");
        if(!check_click(WM_LBUTTONDOWN,x,y,true))throw std::runtime_error("GUI transition lost explicit click");
        peer.publish(false);present();peer.publish(true);present();
        if(luaL_dostring(L,"assert(not onimusha_mc.status().gui_cursor_known)")!=LUA_OK)throw std::runtime_error("GUI transition without mouse messages retained old cursor");
        std::puts("PASS: real DLL callback queues LPARAM GUI cursor before button, unaffected by OS position");
        std::puts("PASS: real DLL callback rejects GUI center warps, allows center clicks, resets on focus/menu transitions");return true;
    }catch(const std::exception& e){std::fprintf(stderr,"Input callback test: %s\n",e.what());reset();return false;}
}
}
