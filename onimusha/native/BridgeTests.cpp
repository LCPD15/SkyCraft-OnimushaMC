#include "Bridge.hpp"
#include "CollisionPacking.hpp"
#include "InputRouting.hpp"
#include "CollisionBatchTests.hpp"
#include "CollisionSurfaceTests.hpp"
#include "FullCubeTests.hpp"
#include "NativeSectionTests.hpp"
#include "DynamicModelsTests.hpp"
#include "PoseFrameTests.hpp"
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>

namespace {
using namespace omc;
int failures{};
void check(bool condition,const char* name){if(!condition){std::fprintf(stderr,"FAIL: %s\n",name);++failures;}else std::printf("PASS: %s\n",name);}
template<class H,class T> std::vector<std::uint8_t> payload(const H& h,std::span<const T> items){std::vector<std::uint8_t> p(sizeof(h)+items.size_bytes());std::memcpy(p.data(),&h,sizeof(h));if(!items.empty())std::memcpy(p.data()+sizeof(h),items.data(),items.size_bytes());return p;}
int peer(const wchar_t* name){
    HANDLE map=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,name);if(!map)return 11;
    auto* b=static_cast<std::uint8_t*>(MapViewOfFile(map,FILE_MAP_ALL_ACCESS,0,0,proto::kMappingBytes));if(!b)return 12;
    auto* h=reinterpret_cast<proto::Header*>(b);if(h->version!=proto::kVersion)return 13;
    auto* s=reinterpret_cast<proto::McState*>(b+proto::kOffMcState);std::atomic_ref(s->seq).store(1);s->x=4.25;s->y=9;s->z=-2;s->eyeX=4.25;s->eyeY=10.62;s->eyeZ=-2;s->flags=proto::kMcInWorld;std::atomic_ref(s->seq).store(2,std::memory_order_release);
    std::atomic_ref(h->mcPid).store(GetCurrentProcessId());std::atomic_ref(h->mcHeartbeatMs).store(GetTickCount64(),std::memory_order_release);
    auto* ir=b+proto::kOffInputRing;const auto input=reinterpret_cast<proto::InputEvent*>(ir+proto::kInputRingDataOff)[0];if(input.type!=proto::kInKey||input.code!=26||input.a!=1)return 14;std::atomic_ref(*reinterpret_cast<std::uint64_t*>(ir+proto::kInputRingTailOff)).store(1,std::memory_order_release);
    auto* er=b+proto::kOffEventRing;reinterpret_cast<proto::McEvent*>(er+proto::kEventRingDataOff)[0]={proto::kEvHitActor,101,3,0,0,1,0,proto::kWeaponBlade};std::atomic_ref(*reinterpret_cast<std::uint64_t*>(er)).store(1,std::memory_order_release);
    auto* ctl=reinterpret_cast<proto::OverlayCtl*>(b+proto::kOffOverlayCtl);auto* oh=reinterpret_cast<proto::OverlaySlotHdr*>(b+proto::kOffOverlaySlotHdr+sizeof(proto::OverlaySlotHdr));*oh={2,1,0,0,77,{}};auto* pixels=b+proto::kOffOverlayPixels+proto::kOverlaySlotBytes;for(int i=0;i<8;i++)pixels[i]=std::uint8_t(i);std::atomic_ref(ctl->state).store(1|proto::kOverlayDirty,std::memory_order_release);
    UnmapViewOfFile(b);CloseHandle(map);return 0;
}
}
#include "AttackTransportTests.hpp"
int wmain(int argc,wchar_t** argv){
    if(argc>3&&std::wstring(argv[1])==L"--collision-peer")return omc::tests::collision_peer(argv[2],std::uint32_t(std::wcstoul(argv[3],nullptr,10)));
    if(argc>2&&std::wstring(argv[1])==L"--peer")return peer(argv[2]);
    check(f10_key_action(WM_SYSKEYDOWN,VK_F10,0)==ToggleKeyAction::toggle&&f10_key_action(WM_KEYDOWN,VK_F10,0)==ToggleKeyAction::toggle,"F10 first normal/system key-down toggles bridge");
    check(f10_key_action(WM_SYSKEYDOWN,VK_F10,1ll<<30)==ToggleKeyAction::consume&&f10_key_action(WM_KEYDOWN,VK_F10,1ll<<30)==ToggleKeyAction::consume,"F10 repeated down is consumed without toggling");
    check(f10_key_action(WM_SYSKEYUP,VK_F10,0)==ToggleKeyAction::consume&&f10_key_action(WM_KEYUP,VK_F10,0)==ToggleKeyAction::consume,"F10 normal/system key-up is consumed without toggling");
    check(f10_key_action(WM_SYSKEYDOWN,VK_F11,0)==ToggleKeyAction::pass&&f10_key_action(WM_CHAR,VK_F10,0)==ToggleKeyAction::pass,"unrelated messages retain original routing");
    check(captured_input_message(WM_LBUTTONDOWN,0,true)&&captured_input_message(WM_INPUT,0,true)&&captured_input_message(WM_CHAR,'x',false)&&captured_input_message(WM_KEYDOWN,'W',false),"pending-release guard identifies existing routed MC input categories");
    check(!captured_input_message(WM_KEYDOWN,VK_INSERT,true)&&!captured_input_message(WM_KEYUP,VK_ESCAPE,false)&&!captured_input_message(WM_SYSKEYDOWN,'G',false),"pending-release guard preserves REFramework Insert and non-GUI host Escape/G");
    check(!captured_input_message(WM_CLOSE,0,true)&&!captured_input_message(WM_ACTIVATEAPP,1,true)&&!captured_input_message(WM_PAINT,0,true)&&captured_input_message(WM_KEYDOWN,VK_ESCAPE,true),"pending-release guard passes system window messages while retaining GUI key capture");
    CursorLookFallback look;check(!look.move(150,400,1920,1080).send,"newly routed cursor initializes baseline without a camera jump");
    auto lookDelta=look.move(158,395,1920,1080);check(lookDelta.send&&lookDelta.x==8&&lookDelta.y==-5,"ordinary relative cursor movement preserves both signed deltas");
    check(!look.move(960,540,1920,1080).send,"host center warp does not emit a look delta");
    lookDelta=look.move(970,536,1920,1080);check(lookDelta.send&&lookDelta.x==10&&lookDelta.y==-4,"movement after center warp uses updated center baseline");
    look.reset();check(!look.move(1700,900,1920,1080).send,"focus or menu transition resets old cursor baseline");
    lookDelta=look.move(1696,905,1920,1080);check(lookDelta.send&&lookDelta.x==-4&&lookDelta.y==5,"movement resumes normally after focus or menu transition");
    check(!look.move(961,539,1920,1080).send,"one-pixel rounded center warp is ignored");
    check(!look.move(5,6,0,0).send&&!look.move(1920,1080,3840,2160).send,"invalid client extent resets baseline and different viewport center remains safe");
    const auto closeTo=[](double a,double b){return std::abs(a-b)<1e-12;};
    MouseInputRouter mouse;
    check(mouse.sync_mode(true)&&mouse.cursor().known()&&mouse.cursor().u()==0.5&&mouse.cursor().v()==0.5&&mouse.guiOpens==1,"GUI open establishes one centered virtual cursor baseline");
    auto moved=mouse.raw_delta(-385,47,2560,1440);
    check(moved.send&&closeTo(mouse.cursor().u(),895.0/2560)&&closeTo(mouse.cursor().v(),767.0/1440)&&mouse.cursor().raw(),"GUI relative RAW deltas accumulate normalized client coordinates");
    check(!mouse.legacy_move(895,767,2560,1440).send&&!mouse.legacy_move(1280,720,2560,1440).send&&closeTo(mouse.cursor().u(),895.0/2560),"RAW GUI input excludes duplicate legacy events and host center warps");
    check(!mouse.sync_mode(true)&&mouse.guiOpens==1&&closeTo(mouse.cursor().u(),895.0/2560),"GUI-to-GUI transition retains normalized cursor without a second baseline");
    moved=mouse.raw_delta(385,-47,2560,1440);
    check(moved.send&&closeTo(mouse.cursor().u(),0.5)&&closeTo(mouse.cursor().v(),0.5),"relative motion can select the genuine GUI center after prior movement");
    moved=mouse.raw_delta(192,108,1920,1080);
    check(moved.send&&closeTo(mouse.cursor().u(),0.6)&&closeTo(mouse.cursor().v(),0.6),"client resize retains normalized cursor and scales subsequent RAW deltas");
    mouse.raw_delta(INT32_MAX,INT32_MIN,1920,1080);
    check(mouse.cursor().u()==1&&mouse.cursor().v()==0,"extreme signed RAW movement clamps virtual cursor to client edges");
    check(!mouse.raw_delta(40,50,0,0).send&&mouse.cursor().u()==1&&mouse.cursor().v()==0,"invalid client extent cannot change virtual cursor");
    check(mouse.guiRawPackets==5&&mouse.guiFallbackPackets==0&&mouse.guiRawDx==std::int64_t(INT32_MAX)+192+40&&mouse.guiRawDy==std::int64_t(INT32_MIN)+108+50,"GUI diagnostic counters count packets and signed deltas without frame logging");
    mouse.release();check(!mouse.known_mode()&&!mouse.cursor().known()&&!mouse.raw_look()&&!mouse.cursor().raw(),"focus or route release clears RAW selection and cursor state");
    check(mouse.sync_mode(true)&&mouse.guiOpens==2&&mouse.cursor().u()==0.5&&mouse.guiRawPackets==5,"GUI reopen recenters while retaining lifetime diagnostic counts");
    moved=mouse.legacy_move(480,810,1920,1080);
    check(moved.send&&closeTo(mouse.cursor().u(),0.25)&&closeTo(mouse.cursor().v(),0.75),"legacy GUI fallback uses centered baseline before the first relative RAW packet");
    check(!mouse.legacy_move(960,540,1920,1080).send&&!mouse.legacy_move(961,539,1920,1080).send&&closeTo(mouse.cursor().u(),0.25),"legacy GUI center warps only rebase movement and never replace virtual position");
    mouse.raw_delta(10,0,1920,1080);
    check(!mouse.legacy_move(600,800,1920,1080).send&&mouse.guiFallbackPackets==1,"first relative RAW packet disables fallback double counting for this GUI session");
    mouse.sync_mode(false);moved=mouse.raw_delta(-12,8,1920,1080);
    check(moved.send&&moved.x==-12&&moved.y==8&&mouse.raw_look()&&!mouse.legacy_move(5,10,1920,1080).send,"non-GUI RAW preserves signed look deltas and prevents duplicate legacy movement");
    mouse.release();mouse.sync_mode(false);
    check(!mouse.raw_look()&&!mouse.legacy_move(400,300,1920,1080).send,"new route resets historical RAW look and initializes the fallback baseline");
    moved=mouse.legacy_move(406,294,1920,1080);
    check(moved.send&&moved.x==6&&moved.y==-6,"look fallback resumes after routing reset rather than remaining permanently disabled");
    const std::wstring testName=L"Local\\OnimushaMC_Test_"+std::to_wstring(GetCurrentProcessId());
    Bridge link;check(link.open(testName),"create isolated real Windows shared memory");if(!link.testing_base())return 1;
    check(!link.alive(),"no peer fails closed");proto::SkyState sky{};sky.posX=1;sky.posY=2;sky.posZ=3;check(link.publish_host(sky),"publish seqlock host state");check(link.input(proto::kInKey,26,1),"publish keyboard input ring");
    wchar_t exe[MAX_PATH]{};GetModuleFileNameW(nullptr,exe,MAX_PATH);std::wstring cmd=L"\""+std::wstring(exe)+L"\" --peer \""+testName+L"\"";STARTUPINFOW si{sizeof(si)};PROCESS_INFORMATION pi{};const bool started=CreateProcessW(nullptr,cmd.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&si,&pi);check(started,"start independent IPC consumer process");
    if(started){WaitForSingleObject(pi.hProcess,10000);DWORD exit{};GetExitCodeProcess(pi.hProcess,&exit);check(exit==0,"peer validates layout and consumes input");CloseHandle(pi.hThread);CloseHandle(pi.hProcess);}
    proto::McState mc{};check(link.read_mc(mc)&&mc.x==4.25&&mc.y==9,"read peer seqlock state");auto events=link.events();check(events.size()==1&&events[0].formId==101&&events[0].a==3,"consume peer combat event");check(link.events().empty(),"event consumed exactly once");
    OverlayFrame frame;check(link.overlay(frame)&&frame.frameId==77&&frame.rgba.size()==8&&frame.rgba[7]==7,"triple-buffer deep-copy ownership");check(!link.overlay(frame),"no duplicate overlay acquire");
    test_attack_transport(link);
    auto* base=link.testing_base();auto* state=reinterpret_cast<proto::McState*>(base+proto::kOffMcState);state->x=std::numeric_limits<double>::quiet_NaN();check(!link.read_mc(mc),"reject non-finite movement");
    RenderStore store;proto::RenAtlas ah{2,2};std::uint8_t pixels[16]{};auto ap=payload(ah,std::span<const std::uint8_t>(pixels));check(store.consume(proto::kRenAtlas,ap)&&store.atlas.rgba.size()==16,"decode atlas");ap.pop_back();check(!store.consume(proto::kRenAtlas,ap),"reject truncated texture");
    proto::ColRegion cr{-8,56,-8,15,71,15,1,0};proto::ColTri floor[2]={{{-8,65,-8,-8,65,16,16,65,-8},proto::kTriTerrain},{{16,65,-8,-8,65,16,16,65,16},proto::kTriTerrain}};
    std::vector<CollisionPacket> packets;std::string packingError;check(pack_collision(cr,floor,packets,packingError),"split large floor into Fabric eight-block collision regions");bool occupied=false,knownFeet=false,knownBelow=false;std::size_t trianglePackets=0,voxelPackets=0;
    for(const auto& p:packets){proto::ColRegion header{};std::memcpy(&header,p.payload.data(),sizeof(header));if(p.type==proto::kColTris)++trianglePackets;if(p.type==proto::kColRegion){++voxelPackets;occupied=occupied||header.count>0;if(header.minX==0&&header.minZ==0&&header.minY==64)knownFeet=true;if(header.minX==0&&header.minZ==0&&header.minY==56)knownBelow=true;}}
    check(occupied&&knownFeet&&knownBelow&&trianglePackets==voxelPackets,"publish voxel support and known empty regions needed to release MC player hold");
    auto invalidBounds=cr;invalidBounds.minX=std::numeric_limits<std::int32_t>::min();invalidBounds.maxX=std::numeric_limits<std::int32_t>::max();
    check(!pack_collision(invalidBounds,floor,packets,packingError)&&packets.empty(),"reject extreme integer bounds before region division/multiplication");
    invalidBounds=cr;invalidBounds.minY=30'000'001;invalidBounds.maxY=30'000'002;
    check(!pack_collision(invalidBounds,floor,packets,packingError),"reject collision bounds outside MC coordinate safety range");
    // A real Onimusha scene reported 8450 triangles in arbitrary radius-32 bounds.
    // Exercise that count and all 729 cells, rather than only a two-triangle floor.
    proto::ColRegion stressBounds{-31,33,-31,33,97,33,2,0};std::vector<proto::ColTri> stressTriangles;stressTriangles.reserve(8450);
    for(int i=0;i<8450;i++){const float x=-30.7f+float(i%65),y=34.3f+float((i/65)%63),z=-30.7f+float((i/(65*63))%63);stressTriangles.push_back({{x,y,z,x+0.08f,y,z,x,y+0.08f,z+0.08f},proto::kTriTerrain});}
    const auto stressStart=std::chrono::steady_clock::now();const bool stressOk=pack_collision(stressBounds,stressTriangles,packets,packingError);std::size_t stressBytes=0;bool stressPayloadValid=true;
    for(const auto& p:packets){stressBytes+=p.payload.size();proto::ColRegion header{};std::memcpy(&header,p.payload.data(),sizeof(header));const auto rowSize=p.type==proto::kColTris?sizeof(proto::ColTri):sizeof(proto::ColBlock);stressPayloadValid=stressPayloadValid&&p.payload.size()==sizeof(header)+std::size_t(header.count)*rowSize;}
    check(stressOk&&stressPayloadValid&&packets.size()==729*2&&stressBytes<proto::kColRingDataBytes,"8450 triangles and arbitrary 729-region scene pack within memory/ring bounds");
    std::printf("Collision scene stress: %zu packets, %zu bytes, %lld ms\n",packets.size(),stressBytes,std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-stressStart).count());
    auto* colRing=base+proto::kOffCollisionRing;auto& colHead=*reinterpret_cast<std::uint64_t*>(colRing);auto& colTail=*reinterpret_cast<std::uint64_t*>(colRing+proto::kColRingTailOff);colHead=proto::kColRingDataBytes;colTail=0;
    check(!link.publish_collision(2,stressBounds,stressTriangles)&&colHead==proto::kColRingDataBytes,"full collision ring rejects without overwriting or crashing");colHead=colTail=0;
    proto::RenSection sh{1,2,3,3};proto::RenVertex verts[3]{};auto sp=payload(sh,std::span<const proto::RenVertex>(verts));check(store.consume(proto::kRenSection,sp)&&store.sections.size()==1,"persistent section mesh");sh.vertexCount=0;auto empty=payload(sh,std::span<const proto::RenVertex>());check(store.consume(proto::kRenSection,empty)&&store.sections.empty(),"remove section mesh");
    proto::RenSolids solid{0,0,0,1};std::uint8_t bits[512]{};bits[0]=1;auto bp=payload(solid,std::span<const std::uint8_t>(bits));check(store.consume(proto::kRenSolids,bp)&&store.solidChanges.size()==1&&store.solidChanges[0].solid,"solid block collider change");solid.count=0;auto rp=payload(solid,std::span<const std::uint8_t>());check(store.consume(proto::kRenSolids,rp)&&!store.solidChanges.back().solid,"collider removed with block");
    auto* rr=base+proto::kOffRenderRing;*reinterpret_cast<proto::ColMsgHeader*>(rr+proto::kRenRingDataOff)={proto::kRenAtlas,0xFFFFFFFFu};*reinterpret_cast<std::uint64_t*>(rr)=8;link.drain_render(store);check(link.rejected>0&&*reinterpret_cast<std::uint64_t*>(rr+proto::kRenRingTailOff)==8,"malformed ring skipped within bounds");
    omc::tests::collision_batch_tests(check);
    omc::tests::collision_surface_tests(check);
    omc::tests::full_cube_tests(check);
    omc::tests::native_section_tests(check);
    omc::tests::dynamic_models_tests(check);
    omc::tests::pose_frame_tests(check);
    std::printf("%d failure(s)\n",failures);return failures?1:0;
}
