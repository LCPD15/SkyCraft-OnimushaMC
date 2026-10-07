#include <Windows.h>
#include "vendor/reframework/API.h"
extern "C" {
#include "vendor/lua/lua.h"
#include "vendor/lua/lauxlib.h"
#include "vendor/lua/lualib.h"
}
#include <cstdio>
#include <cstring>
#include "InputCallbackTests.hpp"
namespace {
REFLuaStateCreatedCb created{};
REFLuaStateDestroyedCb destroyed{};
REFOnPresentCb present{};
REFOnDeviceResetCb reset{};
REFOnMessageCb message{};
unsigned uiCalls{};
unsigned defaultProcCalls{};
bool lua_create(REFLuaStateCreatedCb cb){created=cb;return true;}
bool lua_destroy(REFLuaStateDestroyedCb cb){destroyed=cb;return true;}
bool on_present(REFOnPresentCb cb){present=cb;return true;}
bool on_reset(REFOnDeviceResetCb cb){reset=cb;return true;}
bool on_message(REFOnMessageCb cb){message=cb;return true;}
bool ui(){++uiCalls;return false;}
void log(const char*,...){ }
bool dispatch_message(void* hwnd,unsigned int msg,unsigned long long wparam,long long lparam){
    // Match pinned WindowsMessageHook.cpp: a consumed plugin callback still
    // reaches DefWindowProc, not the original application's WndProc.
    const bool pass=message(hwnd,msg,wparam,lparam);
    if(!pass){++defaultProcCalls;DefWindowProcW(static_cast<HWND>(hwnd),msg,WPARAM(wparam),LPARAM(lparam));}
    return pass;
}
}
int wmain(int argc,wchar_t** argv){
    if(argc!=2)return 2;
    // If a real game owns this mapping, do not load a second native owner into the test.
    HANDLE existing=OpenFileMappingW(FILE_MAP_READ,FALSE,L"Local\\OnimushaMC_v1");
    if(existing){CloseHandle(existing);std::puts("SKIP: live OnimushaMC mapping exists");return 77;}
    HMODULE dll=LoadLibraryW(argv[1]);if(!dll){std::fprintf(stderr,"LoadLibrary error %lu\n",GetLastError());return 3;}
    auto required=reinterpret_cast<REFPluginRequiredVersionFn>(GetProcAddress(dll,"reframework_plugin_required_version"));
    auto initialize=reinterpret_cast<REFPluginInitializeFn>(GetProcAddress(dll,"reframework_plugin_initialize"));
    if(!required||!initialize)return 4;
    REFrameworkPluginVersion version{};required(&version);if(!version.game_name||std::strcmp(version.game_name,"ONIMUSHA_WOTS"))return 5;
    REFrameworkPluginFunctions fn{};fn.on_lua_state_created=lua_create;fn.on_lua_state_destroyed=lua_destroy;fn.on_present=on_present;fn.on_device_reset=on_reset;fn.on_message=on_message;fn.log_info=log;fn.log_warn=log;fn.log_error=log;fn.is_drawing_ui=ui;
    REFrameworkRendererData render{};render.renderer_type=REFRAMEWORK_RENDERER_D3D12;
    REFrameworkPluginInitializeParam param{};param.functions=&fn;param.renderer_data=&render;param.version=&version;
    if(!initialize(&param)||!created||!destroyed||!present||!reset||!message)return 6;
    // Poison external GPU/SDK pointers: inactive callbacks must never dereference
    // them, initialize graphics, or request any game/physics object.
    render.device=render.swapchain=render.command_queue=reinterpret_cast<void*>(1);
    param.sdk=reinterpret_cast<const REFrameworkSDKData*>(1);
    auto* L=luaL_newstate();luaL_openlibs(L);created(L);
    for(int i=0;i<1200;i++){present();if(i%100==0)reset();if(!dispatch_message(nullptr,WM_MOUSEMOVE,0,0))return 8;}
    if(uiCalls)return 9;
    const char* script=R"(
        assert(type(onimusha_mc)=="table")
        local s=onimusha_mc.status()
        assert(s.protocol==14 and s.mapping=="Local\\OnimushaMC_v1")
        assert(onimusha_mc.snapshot_full_cubes({})==nil)
        assert(not onimusha_mc.snapshot_sections().ready and #onimusha_mc.snapshot_sections().sections==0)
        assert(onimusha_mc.capture_section({sx=0,sy=0,sz=0,revision=1,epoch=0})==nil)
        assert(not onimusha_mc.ack_section({sx=0,sy=0,sz=0,revision=1,epoch=0,mask='01'}))
        onimusha_mc.release_section()
        assert(not onimusha_mc.snapshot_native_instances().ready)
        assert(not onimusha_mc.ack_native_instances({epoch=0,cubes={}}))
        assert(onimusha_mc.snapshot_full_cubes({x=0,y=0,z=0,radius=16,limit=1281,epoch=0})==nil)
        local cubes=onimusha_mc.snapshot_full_cubes({x=0,y=0,z=0,radius=16,limit=1280,epoch=0})
        assert(cubes and not cubes.ready and #cubes.cubes==0)
        assert(not s.enabled and not s.ready and not s.connected)
        assert(s.not_ready_reason=="disabled" and s.collision_generation>0 and s.collision_publish_seq==0 and s.collision_consumed_seq==0 and not s.re_ui_sampled)
        assert(math.type(s.collision_generation)=="integer" and math.type(s.collision_publish_seq)=="integer" and math.type(s.collision_consumed_seq)=="integer")
        assert(onimusha_mc.read_mc()==nil)
        assert(not onimusha_mc.submit_host(nil))
        assert(onimusha_mc.submit_host({ready=false,x=2,y=3,z=4,epoch=2,health_current=75,health_max=100}))
        assert(not onimusha_mc.submit_host({ready=true,x=2,y=3,z=4,epoch=2,health_current=75,health_max=0}))
        assert(not onimusha_mc.status().host_ready)
        assert(not onimusha_mc.submit_host({ready=true,x=2,y=3,z=4,epoch=2,health_current=0/0,health_max=100}))
        assert(not onimusha_mc.status().renderer_ready)
        assert(onimusha_mc.set_enabled(true))
        assert(not onimusha_mc.status().ready)
        assert(onimusha_mc.status().not_ready_reason=="host_not_ready")
        assert(not onimusha_mc.send_hurt({mc_points=2}))
        assert(onimusha_mc.publish_actors({{id=101,x=2,y=1,z=3,name="test"}}))
        assert(not onimusha_mc.publish_collision_tris({epoch=1,triangles={}}))
        assert(not onimusha_mc.publish_collision_tris({epoch=2,min_x=-1e100,min_y=0,min_z=0,max_x=1e100,max_y=10,max_z=10,
            triangles={{ax=0,ay=0,az=0,bx=0,by=0,bz=10,cx=10,cy=0,cz=0}}}))
        assert(not onimusha_mc.publish_collision_tris({epoch=2,min_x=0/0,min_y=0,min_z=0,max_x=10,max_y=10,max_z=10,
            triangles={{ax=0,ay=0,az=0,bx=0,by=0,bz=10,cx=10,cy=0,cz=0}}}))
        assert(onimusha_mc.publish_collision_tris({epoch=2,min_x=0,min_y=0,min_z=0,max_x=10,max_y=10,max_z=10,
            triangles={{ax=0,ay=0,az=0,bx=0,by=0,bz=10,cx=10,cy=0,cz=0}}}))
        assert(onimusha_mc.status().collision_ready)
        assert(onimusha_mc.set_camera({binding_ready=true,valid=false}))
        assert(not onimusha_mc.status().ready)
        assert(#onimusha_mc.drain_events()==0 and #onimusha_mc.drain_solids()==0)
        onimusha_mc.set_enabled(false)
    )";
    if(luaL_dostring(L,script)!=LUA_OK){std::fprintf(stderr,"Lua API test: %s\n",lua_tostring(L,-1));return 7;}
    if(dispatch_message(nullptr,WM_SYSKEYDOWN,VK_F10,0)||luaL_dostring(L,"assert(onimusha_mc.status().enabled)")!=LUA_OK)return 10;
    if(dispatch_message(nullptr,WM_SYSKEYDOWN,VK_F10,1ll<<30)||dispatch_message(nullptr,WM_SYSKEYUP,VK_F10,0)||luaL_dostring(L,"assert(onimusha_mc.status().enabled)")!=LUA_OK)return 11;
    if(dispatch_message(nullptr,WM_SYSKEYDOWN,VK_F10,0)||luaL_dostring(L,"assert(not onimusha_mc.status().enabled)")!=LUA_OK)return 12;
    if(dispatch_message(nullptr,WM_KEYDOWN,VK_F10,0)||dispatch_message(nullptr,WM_KEYDOWN,VK_F10,1ll<<30)||dispatch_message(nullptr,WM_KEYUP,VK_F10,0)||luaL_dostring(L,"assert(onimusha_mc.status().enabled)")!=LUA_OK)return 13;
    if(dispatch_message(nullptr,WM_KEYDOWN,VK_F10,0)||luaL_dostring(L,"assert(not onimusha_mc.status().enabled)")!=LUA_OK)return 14;
    present();destroyed(L);lua_close(L);
    for(int i=0;i<16;i++){L=luaL_newstate();created(L);present();destroyed(L);lua_close(L);reset();}
    L=luaL_newstate();luaL_openlibs(L);created(L);
    const bool inputOk=omc::tests::input_callback_tests(L,render,present,reset,dispatch_message,defaultProcCalls);
    destroyed(L);lua_close(L);if(!inputOk)return 15;
    FreeLibrary(dll);
    std::puts("PASS: real DLL exports, pinned Lua state registration, API validation and fail-closed takeover");
    std::puts("PASS: F10 normal/system first press toggles once; repeats and key-up remain consumed");
    std::puts("PASS: 1200 inactive Present callbacks, 12 resets, 16 Lua recreations with poisoned GPU/SDK pointers and no UI query");return 0;
}
