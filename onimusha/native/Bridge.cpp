#include "Bridge.hpp"
#include "CollisionPacking.hpp"
#include <sddl.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <chrono>
#include <limits>
#include <new>

namespace omc {
namespace {
template<class T> std::atomic_ref<T> atom(T& value){return std::atomic_ref<T>(value);}
template<class T> bool read_seq(const std::uint8_t* base,std::uint64_t off,T& out){
    auto* src=reinterpret_cast<T*>(const_cast<std::uint8_t*>(base)+off);
    for(int n=0;n<32;n++){
        const auto start=atom(src->seq).load(std::memory_order_acquire);
        if(start&1){YieldProcessor();continue;}
        std::memcpy(&out,src,sizeof(T));std::atomic_thread_fence(std::memory_order_acquire);
        if(atom(src->seq).load(std::memory_order_relaxed)==start)return true;
    }return false;
}
template<class T> void write_seq(std::uint8_t* base,std::uint64_t off,const T& value){
    auto* dst=reinterpret_cast<T*>(base+off);auto seq=atom(dst->seq);const auto s=seq.load(std::memory_order_relaxed);
    seq.store(s+1,std::memory_order_relaxed);std::atomic_thread_fence(std::memory_order_release);
    std::memcpy(reinterpret_cast<std::uint8_t*>(dst)+4,reinterpret_cast<const std::uint8_t*>(&value)+4,sizeof(T)-4);
    seq.store(s+2,std::memory_order_release);
}
PSECURITY_DESCRIPTOR access_rules(){
    std::wstring rules=L"D:P(A;;GA;;;SY)(A;;GA;;;BA)";HANDLE token{};
    if(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)){
        DWORD n{};GetTokenInformation(token,TokenUser,nullptr,0,&n);std::vector<std::uint8_t> buf(n);
        if(n&&GetTokenInformation(token,TokenUser,buf.data(),n,&n)){LPWSTR sid{};if(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buf.data())->User.Sid,&sid)){rules+=std::wstring(L"(A;;GA;;;")+sid+L")";LocalFree(sid);}}
        CloseHandle(token);
    }
    rules+=L"S:(ML;;NW;;;ME)";PSECURITY_DESCRIPTOR out{};
    ConvertStringSecurityDescriptorToSecurityDescriptorW(rules.c_str(),SDDL_REVISION_1,&out,nullptr);return out;
}
bool finite(const proto::McState& s){return std::isfinite(s.x)&&std::isfinite(s.y)&&std::isfinite(s.z)&&std::isfinite(s.yaw)&&std::isfinite(s.pitch)&&std::isfinite(s.eyeX)&&std::isfinite(s.eyeY)&&std::isfinite(s.eyeZ)&&s.cameraMode<=2;}
}
Bridge::~Bridge(){close();}
bool Bridge::open(std::wstring_view mappingName){
    if(base_)return true;
    constexpr auto bytes=proto::kMappingBytes;SECURITY_ATTRIBUTES sa{sizeof(sa),access_rules(),FALSE};
    const std::wstring mappingNameCopy(mappingName);
    mapping_=CreateFileMappingW(INVALID_HANDLE_VALUE,sa.lpSecurityDescriptor?&sa:nullptr,PAGE_READWRITE,DWORD(bytes>>32),DWORD(bytes),mappingNameCopy.c_str());
    if(sa.lpSecurityDescriptor)LocalFree(sa.lpSecurityDescriptor);
    if(!mapping_){error="CreateFileMapping failed: "+std::to_string(GetLastError());return false;}
    base_=static_cast<std::uint8_t*>(MapViewOfFile(mapping_,FILE_MAP_ALL_ACCESS,0,0,bytes));
    if(!base_){error="MapViewOfFile failed: "+std::to_string(GetLastError());CloseHandle(mapping_);mapping_=nullptr;return false;}
    auto* h=reinterpret_cast<proto::Header*>(base_);
    if(atom(h->magic).load(std::memory_order_acquire)==proto::kMagic&&h->skyrimPid&&h->skyrimPid!=GetCurrentProcessId()){
        HANDLE old=OpenProcess(SYNCHRONIZE,FALSE,h->skyrimPid);
        if(old){const bool running=WaitForSingleObject(old,0)==WAIT_TIMEOUT;CloseHandle(old);if(running){error="Another live game process owns the shared mapping";UnmapViewOfFile(base_);base_=nullptr;CloseHandle(mapping_);mapping_=nullptr;return false;}}
    }
    atom(h->magic).store(0,std::memory_order_release);
    std::memset(base_+proto::kOffSkyState,0,sizeof(proto::SkyState));
    std::memset(base_+proto::kOffMcState,0,sizeof(proto::McState));
    std::memset(base_+proto::kOffOverlayCtl,0,0x100);
    std::memset(base_+proto::kOffInputRing,0,proto::kInputRingDataOff);
    std::memset(base_+proto::kOffCollisionRing,0,proto::kColRingDataOff);
    std::memset(base_+proto::kOffEventRing,0,proto::kEventRingDataOff);
    std::memset(base_+proto::kOffRenderRing,0,proto::kRenRingDataOff);
    std::memset(base_+proto::kOffActorTable,0,sizeof(proto::ActorTable));
    std::memset(base_+proto::kOffWorldEntities,0,sizeof(proto::WorldEntities));
    auto* water=reinterpret_cast<proto::WaterGrid*>(base_+proto::kOffWaterGrid);std::memset(water,0,sizeof(*water));std::fill(std::begin(water->surface),std::end(water->surface),proto::kNoWater);
    h->version=proto::kVersion;h->skyrimPid=GetCurrentProcessId();h->mcPid=0;h->skyrimHeartbeatMs=GetTickCount64();h->mcHeartbeatMs=0;
    observedMcPid_=0;observedConnected_=false;overlayFront_=2;invalidate_collision();
    atom(h->magic).store(proto::kMagic,std::memory_order_release);return true;
}
void Bridge::close(){
    // Preserve the last host PID: Fabric's quit watchdog uses ProcessHandle.isAlive(pid).
    // Clearing it to zero would skip that watchdog and leave a hidden MC process running.
    if(base_){auto* h=reinterpret_cast<proto::Header*>(base_);atom(h->skyrimHeartbeatMs).store(0,std::memory_order_release);UnmapViewOfFile(base_);base_=nullptr;invalidate_collision();observedMcPid_=0;observedConnected_=false;}
    if(mapping_){CloseHandle(mapping_);mapping_=nullptr;}
}
bool Bridge::alive() const {
    if(!base_)return false;auto* h=reinterpret_cast<proto::Header*>(base_);
    if(atom(h->magic).load(std::memory_order_acquire)!=proto::kMagic||h->version!=proto::kVersion)return false;
    const auto beat=atom(h->mcHeartbeatMs).load(std::memory_order_acquire),now=GetTickCount64();
    return beat&&beat<=now&&now-beat<3000&&atom(h->mcPid).load(std::memory_order_acquire)!=0;
}
void Bridge::heartbeat(){if(base_)atom(reinterpret_cast<proto::Header*>(base_)->skyrimHeartbeatMs).store(GetTickCount64(),std::memory_order_release);refresh_collision_link();}
bool Bridge::publish_host(const proto::SkyState& s){
    if(!base_||!std::isfinite(s.posX)||!std::isfinite(s.posY)||!std::isfinite(s.posZ)||!std::isfinite(s.yaw)||!std::isfinite(s.pitch))return false;
    if((s.flags&proto::kSkyAuthoritativeHealth)&&(!std::isfinite(s.healthCurrent)||!std::isfinite(s.healthMax)||s.healthMax<=0||s.healthCurrent<0))return false;
    write_seq(base_,proto::kOffSkyState,s);return true;
}
bool Bridge::read_mc(proto::McState& s)const{return base_&&alive()&&read_seq(base_,proto::kOffMcState,s)&&finite(s);}
bool Bridge::input(std::uint16_t type,std::uint16_t code,std::int32_t a,std::int32_t b,std::int32_t c){
    if(!base_)return false;auto* ring=base_+proto::kOffInputRing;auto& hr=*reinterpret_cast<std::uint64_t*>(ring);auto& tr=*reinterpret_cast<std::uint64_t*>(ring+proto::kInputRingTailOff);
    const auto head=atom(hr).load(std::memory_order_relaxed),tail=atom(tr).load(std::memory_order_acquire);
    if(tail>head||head-tail>=proto::kInputRingEntries){++rejected;return false;}
    reinterpret_cast<proto::InputEvent*>(ring+proto::kInputRingDataOff)[head&(proto::kInputRingEntries-1)]={type,code,a,b,c};atom(hr).store(head+1,std::memory_order_release);return true;
}
bool Bridge::publish_actors(std::span<const proto::ActorRecord> actors){
    if(!base_||actors.size()>proto::kMaxActors)return false;proto::ActorTable t{};t.count=std::uint32_t(actors.size());std::copy(actors.begin(),actors.end(),std::begin(t.actors));write_seq(base_,proto::kOffActorTable,t);return true;
}
void Bridge::invalidate_collision(){++collisionGeneration_;collisionBatches_.clear();collisionBatchEnd_=0;lastEpoch_=~0u;}
void Bridge::refresh_collision_link(){
    const auto pid=base_?atom(reinterpret_cast<proto::Header*>(base_)->mcPid).load(std::memory_order_acquire):0;
    const bool connected=alive();if(pid!=observedMcPid_||connected!=observedConnected_){invalidate_collision();observedMcPid_=pid;observedConnected_=connected;}
}
CollisionStatus Bridge::collision_status(){
    refresh_collision_link();CollisionStatus out{};out.generation=collisionGeneration_;out.publishSeq=collisionPublishSeq_;out.consumedSeq=collisionConsumedSeq_;out.batchEnd=collisionBatchEnd_;out.mcPid=observedMcPid_;out.connected=observedConnected_;
    if(!base_)return out;auto* header=reinterpret_cast<proto::Header*>(base_);const auto beat=atom(header->mcHeartbeatMs).load(std::memory_order_acquire),now=GetTickCount64();out.heartbeatAgeMs=beat&&beat<=now?double(now-beat):-1;
    auto* ring=base_+proto::kOffCollisionRing;out.head=atom(*reinterpret_cast<std::uint64_t*>(ring)).load(std::memory_order_acquire);out.tail=atom(*reinterpret_cast<std::uint64_t*>(ring+proto::kColRingTailOff)).load(std::memory_order_acquire);
    out.ringValid=out.tail<=out.head&&out.head-out.tail<=proto::kColRingDataBytes;
    if(out.ringValid)while(!collisionBatches_.empty()&&collisionBatches_.front().end<=out.tail){collisionConsumedSeq_=collisionBatches_.front().seq;collisionBatches_.pop_front();}
    out.consumedSeq=collisionConsumedSeq_;return out;
}
bool Bridge::publish_collision(std::uint32_t epoch,const proto::ColRegion& region,std::span<const proto::ColTri> triangles){
    const auto fail=[&](std::string reason,bool packing){++rejected;if(packing)++collisionPackFailures;else ++collisionQueueFailures;collisionFailure=error=std::move(reason);return false;};
    if(!base_||triangles.size()>100000)return fail("Collision mapping unavailable or triangle count exceeds limit",true);
    (void)collision_status();proto::ColRegion h=region;h.epoch=epoch;std::vector<CollisionPacket> packets;std::string packingError;
    const auto start=std::chrono::steady_clock::now();bool packed{};
    try{packed=pack_collision(h,triangles,packets,packingError);}catch(const std::bad_alloc&){packingError="Collision packing allocation failed";}
    collisionPackMs=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();collisionPackMaxMs=std::max(collisionPackMaxMs,collisionPackMs);
    if(!packed)return fail(std::move(packingError),true);
    return publish_packed_collision(epoch,std::move(packets));
}
bool Bridge::publish_packed_collision(std::uint32_t epoch,std::vector<CollisionPacket> packets){
    const auto fail=[&](std::string reason,bool){++rejected;++collisionQueueFailures;collisionFailure=error=std::move(reason);return false;};
    if(!base_)return fail("Collision mapping unavailable",false);
    // Nothing, including COL_CLEAR, becomes visible until the entire batch fits.
    // Recheck the observed link after synchronous packing before choosing CLEAR.
    (void)collision_status();
    try{if(lastEpoch_!=epoch){CollisionPacket clear{proto::kColClear,{}};clear.payload.resize(sizeof(epoch));std::memcpy(clear.payload.data(),&epoch,sizeof(epoch));packets.insert(packets.begin(),std::move(clear));}}
    catch(const std::bad_alloc&){return fail("Collision batch allocation failed",false);}
    auto* ring=base_+proto::kOffCollisionRing;auto& hr=*reinterpret_cast<std::uint64_t*>(ring);auto& tr=*reinterpret_cast<std::uint64_t*>(ring+proto::kColRingTailOff);
    const auto head=atom(hr).load(std::memory_order_relaxed),tail=atom(tr).load(std::memory_order_acquire);constexpr auto size=proto::kColRingDataBytes;
    if(tail>head||head-tail>size)return fail("Collision ring counters are invalid",false);
    std::uint64_t end=head;
    for(const auto& p:packets){
        const auto msg=(std::uint64_t(sizeof(proto::ColMsgHeader))+p.payload.size()+7)&~7ull,pos=end%size,pad=pos+msg>size?size-pos:0;
        if(p.payload.size()>std::numeric_limits<std::uint32_t>::max()||msg>size/2||end>std::numeric_limits<std::uint64_t>::max()-pad-msg)return fail("Collision batch packet/counter exceeds bounded ring size",false);
        end+=pad+msg;
    }
    if(end-head>size-(head-tail))return fail("Collision batch needs "+std::to_string(end-head)+" bytes; free "+std::to_string(size-(head-tail)),false);
    if(collisionBatches_.size()>=4096||collisionPublishSeq_>=std::uint64_t(std::numeric_limits<std::int64_t>::max()))return fail("Collision batch acknowledgement queue is full",false);
    const auto next=collisionPublishSeq_+1;
    try{collisionBatches_.push_back({next,end});}catch(const std::bad_alloc&){return fail("Collision acknowledgement allocation failed",false);}
    auto* data=ring+proto::kColRingDataOff;std::uint64_t cursor=head;
    for(const auto& p:packets){
        const auto msg=(std::uint64_t(sizeof(proto::ColMsgHeader))+p.payload.size()+7)&~7ull,pos=cursor%size,pad=pos+msg>size?size-pos:0;
        if(pad)*reinterpret_cast<proto::ColMsgHeader*>(data+pos)={proto::kColPad,0};
        auto* dst=data+(pad?0:pos);*reinterpret_cast<proto::ColMsgHeader*>(dst)={p.type,std::uint32_t(p.payload.size())};
        if(!p.payload.empty())std::memcpy(dst+sizeof(proto::ColMsgHeader),p.payload.data(),p.payload.size());
        const auto padding=msg-sizeof(proto::ColMsgHeader)-p.payload.size();if(padding)std::memset(dst+sizeof(proto::ColMsgHeader)+p.payload.size(),0,padding);
        cursor+=pad+msg;
    }
    lastEpoch_=epoch;collisionPublishSeq_=next;collisionBatchEnd_=end;collisionFailure.clear();error.clear();
    // The only head commit. Acquire readers see either the old head or all packets.
    atom(hr).store(end,std::memory_order_release);return true;
}
std::vector<proto::McEvent> Bridge::events(){
    std::vector<proto::McEvent> out;if(!base_)return out;auto* ring=base_+proto::kOffEventRing;auto& hr=*reinterpret_cast<std::uint64_t*>(ring);auto& tr=*reinterpret_cast<std::uint64_t*>(ring+proto::kEventRingTailOff);
    const auto head=atom(hr).load(std::memory_order_acquire);auto tail=atom(tr).load(std::memory_order_relaxed);
    if(tail>head||head-tail>proto::kEventRingEntries){++rejected;atom(tr).store(head,std::memory_order_release);return out;}
    while(tail<head){auto e=reinterpret_cast<proto::McEvent*>(ring+proto::kEventRingDataOff)[tail&(proto::kEventRingEntries-1)];if(std::isfinite(e.a)&&std::isfinite(e.b)&&std::isfinite(e.c)&&std::isfinite(e.d))out.push_back(e);else ++rejected;++tail;}
    atom(tr).store(tail,std::memory_order_release);return out;
}
void Bridge::drain_render(RenderStore& store,std::uint64_t budget){
    if(!base_)return;auto* ring=base_+proto::kOffRenderRing;auto& hr=*reinterpret_cast<std::uint64_t*>(ring);auto& tr=*reinterpret_cast<std::uint64_t*>(ring+proto::kRenRingTailOff);
    const auto head=atom(hr).load(std::memory_order_acquire);auto tail=atom(tr).load(std::memory_order_relaxed);const auto size=proto::kRenRingDataBytes;std::uint64_t done=0;
    if(tail>head||head-tail>size){++rejected;atom(tr).store(head,std::memory_order_release);return;}
    auto* data=ring+proto::kRenRingDataOff;
    while(tail<head&&done<budget){
        const auto pos=tail%size,remain=size-pos;if(remain<sizeof(proto::ColMsgHeader)||head-tail<sizeof(proto::ColMsgHeader)){++rejected;tail=head;break;}
        proto::ColMsgHeader h;std::memcpy(&h,data+pos,sizeof(h));
        if(h.type==proto::kRenPad){if(remain>head-tail){++rejected;tail=head;break;}tail+=remain;continue;}
        const auto msg=(std::uint64_t(sizeof(h))+h.payloadBytes+7)&~7ull;
        if(msg>remain||msg>head-tail||msg>size/2){++rejected;tail=head;break;}
        if(!store.consume(h.type,std::span(data+pos+sizeof(h),h.payloadBytes)))++rejected;
        tail+=msg;done+=msg;
    }atom(tr).store(tail,std::memory_order_release);
}
bool Bridge::overlay(OverlayFrame& out){
    if(!base_)return false;auto& s=reinterpret_cast<proto::OverlayCtl*>(base_+proto::kOffOverlayCtl)->state;const auto state=atom(s).load(std::memory_order_acquire);
    if(!(state&proto::kOverlayDirty))return false;
    if((state&3)>=proto::kOverlaySlots){++rejected;return false;}
    const auto old=atom(s).exchange(overlayFront_,std::memory_order_acq_rel);overlayFront_=old&3;
    if(overlayFront_>=proto::kOverlaySlots){++rejected;return false;}
    proto::OverlaySlotHdr h;std::memcpy(&h,base_+proto::kOffOverlaySlotHdr+overlayFront_*sizeof(h),sizeof(h));
    if(!h.width||!h.height||h.width>proto::kMaxOverlayW||h.height>proto::kMaxOverlayH){++rejected;return false;}
    out.width=h.width;out.height=h.height;out.flags=h.flags;out.frameId=h.frameId;
    const auto* pixels=base_+proto::kOffOverlayPixels+overlayFront_*proto::kOverlaySlotBytes;
    out.rgba.assign(pixels,pixels+std::size_t(h.width)*h.height*4);return true;
}
bool Bridge::world_entities(proto::WorldEntities& out)const {return base_&&read_seq(base_,proto::kOffWorldEntities,out)&&out.count<=proto::kMaxWorldEntities;}
}
