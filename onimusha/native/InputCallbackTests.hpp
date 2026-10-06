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
    void fill_input_ring(unsigned remaining){
        if(remaining>proto::kInputRingEntries)throw std::runtime_error("invalid test ring fill");auto* r=base+proto::kOffInputRing;
        auto head=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r));auto tail=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r+proto::kInputRingTailOff));const auto old=head.load();
        if(old!=tail.load())throw std::runtime_error("test input ring was not drained");
        std::memset(r+proto::kInputRingDataOff,0,proto::kInputRingEntries*sizeof(proto::InputEvent));head.store(old+proto::kInputRingEntries-remaining,std::memory_order_release);
    }
    void consume_input_entries(unsigned count){
        auto* r=base+proto::kOffInputRing;const auto head=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r)).load(std::memory_order_acquire);
        auto tail=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r+proto::kInputRingTailOff));const auto old=tail.load();
        if(count>head-old)throw std::runtime_error("invalid test input consume");tail.store(old+count,std::memory_order_release);
    }
    void set_collision_tail(bool corrupt){
        auto* r=base+proto::kOffCollisionRing;const auto head=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r)).load(std::memory_order_acquire);
        std::atomic_ref(*reinterpret_cast<std::uint64_t*>(r+proto::kColRingTailOff)).store(head+(corrupt?8:0),std::memory_order_release);
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
        peer.publish(true);if(luaL_dostring(L,setup)!=LUA_OK)throw std::runtime_error(lua_tostring(L,-1));present();
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(s.ready and s.not_ready_reason=='ready' and s.re_ui_sampled and not s.re_ui_open and s.mc_pid>0 and s.collision_epoch==9 and math.type(s.collision_publish_seq)=='integer')")!=LUA_OK)throw std::runtime_error("input callback ready/diagnostic gate");
        const HWND foreground=GetForegroundWindow();RECT rect{};if(!foreground||!GetClientRect(foreground,&rect)||rect.right<16||rect.bottom<16)throw std::runtime_error("No usable foreground HWND for read-only focus check");
        const int w=rect.right,h=rect.bottom,x=w/4,y=h*3/4;const auto pos=[](int a,int b){return LPARAM(MAKELPARAM(a,b));};peer.drain();
        const auto check_cursor=[&](int a,int b){const auto events=peer.drain();return events.size()==1&&events[0].type==proto::kInCursor&&events[0].a==a&&events[0].b==b;};
        const auto check_click=[&](unsigned kind,int a,int b,bool down,int expectedX,int expectedY){
            if(message(foreground,kind,0,pos(a,b)))return false;const auto events=peer.drain();
            return events.size()==2&&events[0].type==proto::kInCursor&&events[0].a==expectedX&&events[0].b==expectedY&&events[1].type==proto::kInMouseButton&&events[1].a==int(down);
        };
        message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));
        if(!check_cursor(960,540))throw std::runtime_error("GUI open did not publish one centered virtual baseline");
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(s.gui_cursor_known and s.gui_cursor_u==0.5 and s.gui_cursor_v==0.5 and not s.gui_cursor_raw);test_gui_opens=s.gui_open_count")!=LUA_OK)throw std::runtime_error("GUI open state/diagnostic baseline");
        if(!check_click(WM_LBUTTONDOWN,x,y,true,960,540))throw std::runtime_error("button LPARAM replaced the genuine virtual center click");
        message(foreground,WM_MOUSEMOVE,0,pos(x,y));
        const double u=0.5+double(x-w/2)/w,v=0.5+double(y-h/2)/h;const int cx=int(u*1920),cy=int(v*1080);
        if(!check_cursor(cx,cy))throw std::runtime_error("legacy GUI movement did not update virtual cursor relative to center");
        message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));message(foreground,WM_MOUSEMOVE,0,pos(w/2+1,h/2-1));if(!peer.drain().empty())throw std::runtime_error("GUI center warp forwarded");
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(s.gui_cursor_known and math.abs(s.gui_cursor_u-0.25)<0.04 and math.abs(s.gui_cursor_v-0.75)<0.04 and s.gui_fallback_packets==1 and s.gui_raw_packets==0)")!=LUA_OK)throw std::runtime_error("GUI warp replaced virtual cursor or polluted input diagnostics");
        if(!check_click(WM_LBUTTONUP,w/2,h/2,false,cx,cy)||!check_click(WM_LBUTTONDOWN,w/2,h/2,true,cx,cy))throw std::runtime_error("host-centered button did not preserve virtual cursor before down/up");
        auto defaults=defaultProcCalls;
        if(message(foreground,WM_INPUT,RIM_INPUT,0)||defaultProcCalls!=defaults+1||!peer.drain().empty())throw std::runtime_error("GUI invalid raw input must delegate one cleanup to REFramework wrapper");
        peer.publish(true);present();if(!peer.drain().empty())throw std::runtime_error("GUI-to-GUI update published a second centered baseline");
        if(!check_click(WM_LBUTTONDOWN,0,0,true,cx,cy))throw std::runtime_error("GUI-to-GUI update lost normalized virtual position");
        if(luaL_dostring(L,"assert(onimusha_mc.submit_host({ready=true,epoch=9,x=2,y=3,z=4,health_current=75,health_max=100,teleport_seq=1,viewport_w=960,viewport_h=540}))")!=LUA_OK)throw std::runtime_error("test host viewport resize");
        if(!check_click(WM_LBUTTONUP,w/2,h/2,false,int(u*960),int(v*540)))throw std::runtime_error("host viewport resize did not preserve normalized GUI cursor");
        if(luaL_dostring(L,"assert(onimusha_mc.submit_host({ready=true,epoch=9,x=2,y=3,z=4,health_current=75,health_max=100,teleport_seq=1,viewport_w=1920,viewport_h=1080}))")!=LUA_OK)throw std::runtime_error("restore test host viewport");
        message(foreground,WM_KILLFOCUS,0,0);auto events=peer.drain();if(events.size()!=1||events[0].type!=proto::kInReleaseAll)throw std::runtime_error("focus release did not clear inputs");
        if(luaL_dostring(L,"assert(not onimusha_mc.status().gui_cursor_known)")!=LUA_OK)throw std::runtime_error("focus release kept GUI cursor cache");
        message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));if(!check_cursor(960,540))throw std::runtime_error("GUI focus reacquisition did not recenter virtual cursor");
        if(!check_click(WM_LBUTTONDOWN,w/2,h/2,true,960,540))throw std::runtime_error("GUI focus reacquisition lost center selection");
        peer.publish(false);present();message(foreground,WM_MOUSEMOVE,0,pos(w/2,h/2));if(!peer.drain().empty())throw std::runtime_error("focus baseline restored as movement");
        defaults=defaultProcCalls;
        if(message(foreground,WM_INPUT,RIM_INPUT,0)||defaultProcCalls!=defaults+1||!peer.drain().empty())throw std::runtime_error("non-GUI invalid raw input must delegate one cleanup to REFramework wrapper");
        peer.publish(true);present();if(!check_cursor(960,540))throw std::runtime_error("GUI reopen without mouse events did not publish center baseline");
        if(!check_click(WM_LBUTTONDOWN,x,y,true,960,540))throw std::runtime_error("GUI reopen button LPARAM replaced virtual baseline");
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(s.gui_cursor_known and s.gui_cursor_u==0.5 and s.gui_cursor_v==0.5 and s.gui_open_count==test_gui_opens+2 and s.gui_raw_packets==0 and s.gui_raw_dx==0 and s.gui_raw_dy==0 and not s.raw_look)")!=LUA_OK)throw std::runtime_error("GUI transition diagnostics or raw-mode reset");
        for(const unsigned remaining:{0u,1u}){
            peer.fill_input_ring(remaining);message(foreground,WM_LBUTTONUP,0,pos(w/2,h/2));events=peer.drain();
            if(events.size()!=proto::kInputRingEntries||(remaining&&events.back().type!=proto::kInCursor))throw std::runtime_error("button overflow test did not hit intended cursor/button boundary");
            if(luaL_dostring(L,"assert(not onimusha_mc.status().gui_cursor_known)")!=LUA_OK)throw std::runtime_error("failed button did not reset routed inputs");
            present();events=peer.drain();
            if(events.size()!=2||events[0].type!=proto::kInReleaseAll||events[1].type!=proto::kInCursor||events[1].a!=960||events[1].b!=540)throw std::runtime_error("button-up overflow did not retry ReleaseAll before GUI reopen");
        }
        if(luaL_dostring(L,"test_pending_opens=onimusha_mc.status().gui_open_count")!=LUA_OK)throw std::runtime_error("pending release baseline snapshot");
        peer.fill_input_ring(0);message(foreground,WM_LBUTTONUP,0,pos(w/2,h/2));present();
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(not s.gui_cursor_known and s.gui_open_count==test_pending_opens)")!=LUA_OK)throw std::runtime_error("full-ring Present created a GUI baseline before ReleaseAll");
        if(!message(foreground,WM_KEYDOWN,VK_INSERT,0)||!message(foreground,WM_CLOSE,0,0)||!message(foreground,WM_ACTIVATEAPP,1,0))throw std::runtime_error("pending release swallowed REFramework/system window messages");
        defaults=defaultProcCalls;
        if(message(foreground,WM_INPUT,RIM_INPUT,0)||defaultProcCalls!=defaults+1||message(foreground,WM_KEYDOWN,'W',0)||message(foreground,WM_CHAR,'x',0))throw std::runtime_error("pending release did not consume MC input with one framework RAW cleanup");
        peer.publish(false);present();
        if(!message(foreground,WM_KEYDOWN,VK_ESCAPE,0)||!message(foreground,WM_SYSKEYUP,'G',0)||!message(foreground,WM_KILLFOCUS,0,0))throw std::runtime_error("pending release swallowed original-game/focus exceptions");
        // F10 is processed before the focus/routing guard; use a null HWND here
        // so the real default-proc wrapper cannot activate the desktop menu.
        if(message(nullptr,WM_SYSKEYDOWN,VK_F10,0)||luaL_dostring(L,"assert(not onimusha_mc.status().enabled)")!=LUA_OK)throw std::runtime_error("pending release prevented F10 disable");
        if(message(nullptr,WM_SYSKEYDOWN,VK_F10,1ll<<30)||message(nullptr,WM_SYSKEYUP,VK_F10,0)||luaL_dostring(L,"assert(not onimusha_mc.status().enabled)")!=LUA_OK)throw std::runtime_error("pending release changed F10 repeat/up behavior");
        if(message(nullptr,WM_SYSKEYDOWN,VK_F10,0)||luaL_dostring(L,"assert(onimusha_mc.status().enabled)")!=LUA_OK)throw std::runtime_error("pending release prevented F10 enable");
        peer.publish(true);present();events=peer.drain();
        if(events.size()!=proto::kInputRingEntries)throw std::runtime_error("pending release overwrote a full input ring");
        const auto release_then_click=[&](){
            if(message(foreground,WM_LBUTTONDOWN,0,pos(w/2,h/2)))return false;const auto e=peer.drain();
            return e.size()==4&&e[0].type==proto::kInReleaseAll&&e[1].type==proto::kInCursor&&e[1].a==960&&e[1].b==540&&e[2].type==proto::kInCursor&&e[3].type==proto::kInMouseButton&&e[3].a==1;
        };
        if(!release_then_click())throw std::runtime_error("next message before Present did not queue ReleaseAll ahead of GUI/button");
        peer.fill_input_ring(0);message(foreground,WM_LBUTTONUP,0,pos(w/2,h/2));peer.consume_input_entries(1);
        if(message(foreground,WM_LBUTTONDOWN,0,pos(w/2,h/2)))throw std::runtime_error("single-slot recovery passed button to host");events=peer.drain();
        if(events.size()!=proto::kInputRingEntries||events.back().type!=proto::kInReleaseAll)throw std::runtime_error("single free slot was used by GUI/button before ReleaseAll");
        if(luaL_dostring(L,"assert(not onimusha_mc.status().gui_cursor_known)")!=LUA_OK)throw std::runtime_error("single-slot failed GUI/button retained routed state");
        if(!release_then_click())throw std::runtime_error("single-slot recovery did not restore release-before-button ordering");
        peer.set_collision_tail(true);
        if(luaL_dostring(L,"local s=onimusha_mc.status();assert(not s.ready and not s.collision_ready and not s.collision_ring_valid and s.not_ready_reason=='collision_not_ready')")!=LUA_OK)throw std::runtime_error("invalid collision tail did not revoke native readiness");
        peer.set_collision_tail(false);
        if(luaL_dostring(L,"assert(onimusha_mc.publish_collision_tris({epoch=9,min_x=0,min_y=0,min_z=0,max_x=10,max_y=10,max_z=10,triangles={{ax=0,ay=0,az=0,bx=0,by=0,bz=10,cx=10,cy=0,cz=0}}}));local s=onimusha_mc.status();assert(s.ready and s.collision_ring_valid and s.collision_pack_ms>=0 and s.collision_pack_max_ms>=s.collision_pack_ms)")!=LUA_OK)throw std::runtime_error("fresh complete collision batch did not restore readiness after ring test");
        std::puts("PASS: real DLL callbacks queue cached virtual GUI cursor before buttons regardless of host-centered LPARAM");
        std::puts("PASS: real DLL GUI open/reopen center, legacy warp suppression, focus release, GUI retention and viewport normalization");
        std::puts("PASS: full ring and final-slot button-up failure retry ReleaseAll before GUI center baseline");
        std::puts("PASS: pending ReleaseAll precedes next-message GUI/button without Present; one-slot recovery, system shortcuts and RAW cleanup remain correct");
        std::puts("PASS: actual DLL diagnostic reasons preserve gate order; invalid collision tail revokes readiness until a fresh complete batch");
        std::puts("NOTE: genuine relative HRAWINPUT packets require physical mouse acceptance; pure router tests cover RAW accumulation and deduplication");return true;
    }catch(const std::exception& e){std::fprintf(stderr,"Input callback test: %s\n",e.what());reset();return false;}
}
}
