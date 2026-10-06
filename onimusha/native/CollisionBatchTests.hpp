#pragma once
// Isolated Windows IPC tests; no live game mapping, input or visible windows.
#include "Bridge.hpp"
#include "CollisionPacking.hpp"
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>

namespace omc::tests {
inline int collision_peer(const wchar_t* name,std::uint32_t epoch){
    const auto mapping=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,name);if(!mapping)return 31;
    auto* base=static_cast<std::uint8_t*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,proto::kMappingBytes));if(!base){CloseHandle(mapping);return 32;}
    const auto eventName=std::wstring(name)+L"_Consume";const auto consume=OpenEventW(SYNCHRONIZE,FALSE,eventName.c_str());if(!consume){UnmapViewOfFile(base);CloseHandle(mapping);return 33;}
    auto* header=reinterpret_cast<proto::Header*>(base);std::atomic_ref(header->mcPid).store(GetCurrentProcessId());
    auto* ring=base+proto::kOffCollisionRing;auto head=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(ring));auto tail=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(ring+proto::kColRingTailOff));const auto start=tail.load();const auto deadline=GetTickCount64()+10000;
    while(head.load(std::memory_order_acquire)==start&&GetTickCount64()<deadline){std::atomic_ref(header->mcHeartbeatMs).store(GetTickCount64(),std::memory_order_release);Sleep(1);}
    const auto stop=head.load(std::memory_order_acquire);int result=0;auto cursor=start;unsigned clears{},pads{},tris{},regions{};bool expectRegion=false;proto::ColRegion previous{};
    while(cursor<stop&&!result){
        const auto pos=cursor%proto::kColRingDataBytes,remaining=proto::kColRingDataBytes-pos;const auto* message=reinterpret_cast<const proto::ColMsgHeader*>(ring+proto::kColRingDataOff+pos);
        if(message->type==proto::kColPad){if(message->payloadBytes||remaining>stop-cursor){result=34;break;}++pads;cursor+=remaining;continue;}
        const auto length=(std::uint64_t(sizeof(*message))+message->payloadBytes+7)&~7ull;
        if(length>remaining||length>stop-cursor){result=35;break;}
        const auto* payload=reinterpret_cast<const std::uint8_t*>(message)+sizeof(*message);
        if(message->type==proto::kColClear){std::uint32_t got{};if(message->payloadBytes!=4){result=36;break;}std::memcpy(&got,payload,4);if(got!=epoch||clears||tris||regions){result=37;break;}++clears;}
        else if(message->type==proto::kColTris||message->type==proto::kColRegion){
            if(message->payloadBytes<sizeof(proto::ColRegion)){result=38;break;}proto::ColRegion region{};std::memcpy(&region,payload,sizeof(region));
            const auto rowSize=message->type==proto::kColTris?sizeof(proto::ColTri):sizeof(proto::ColBlock);
            if(region.epoch!=epoch||message->payloadBytes!=sizeof(region)+std::uint64_t(region.count)*rowSize){result=39;break;}
            if(message->type==proto::kColTris){if(expectRegion){result=40;break;}previous=region;expectRegion=true;++tris;}
            else{if(!expectRegion||std::memcmp(&previous,&region,offsetof(proto::ColRegion,count))!=0){result=41;break;}expectRegion=false;++regions;}
        }else result=42;
        cursor+=length;
    }
    if(!result&&(clears!=1||pads!=1||tris!=1||regions!=1||expectRegion||cursor!=stop))result=43;
    if(!result&&WaitForSingleObject(consume,10000)!=WAIT_OBJECT_0)result=44;
    if(!result)tail.store(stop,std::memory_order_release);CloseHandle(consume);UnmapViewOfFile(base);CloseHandle(mapping);return result;
}
inline void collision_batch_tests(void (*check)(bool,const char*)){
    const auto name=L"Local\\OnimushaMC_BatchTest_"+std::to_wstring(GetCurrentProcessId());Bridge link;check(link.open(name),"create isolated collision batch IPC mapping");if(!link.testing_base())return;
    auto* base=link.testing_base();auto* header=reinterpret_cast<proto::Header*>(base);auto* ring=base+proto::kOffCollisionRing;auto* data=ring+proto::kColRingDataOff;
    auto head=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(ring));auto tail=std::atomic_ref(*reinterpret_cast<std::uint64_t*>(ring+proto::kColRingTailOff));constexpr auto size=proto::kColRingDataBytes;
    std::atomic_ref(header->mcPid).store(GetCurrentProcessId());std::atomic_ref(header->mcHeartbeatMs).store(GetTickCount64());const auto initial=link.collision_status();
    proto::ColRegion bounds{0,64,0,7,71,7,3,0};const proto::ColTri floor[]={{{0,65,0,0,65,8,8,65,0},proto::kTriTerrain},{{8,65,0,0,65,8,8,65,8},proto::kTriTerrain}};
    std::vector<CollisionPacket> packets;std::string error;check(pack_collision(bounds,floor,packets,error),"prepare complete one-cell collision batch");std::uint64_t bytes=16;for(const auto& p:packets)bytes+=(sizeof(proto::ColMsgHeader)+p.payload.size()+7)&~7ull;
    std::memset(data,0xcd,size);head.store(size);tail.store(0);check(!link.publish_collision(3,bounds,floor)&&head.load()==size&&data[0]==0xcd&&link.collision_status().publishSeq==0,"full collision ring leaves bytes/head/sequence unchanged including epoch CLEAR");
    head.store(size-(bytes-8));tail.store(0);const auto before=head.load();const auto offset=before%size;
    check(!link.publish_collision(3,bounds,floor)&&head.load()==before&&data[offset]==0xcd&&link.collision_status().publishSeq==0,"batch with insufficient final packet capacity publishes no earlier packet");
    head.store(0);tail.store(0);auto invalid=bounds;invalid.minX=std::numeric_limits<std::int32_t>::min();
    check(!link.publish_collision(9,invalid,floor)&&head.load()==0&&data[0]==0xcd&&link.collision_status().publishSeq==0,"failed packing for a new epoch does not publish CLEAR or advance sequence");
    check(link.collisionPackFailures==1&&link.collisionQueueFailures==2&&link.collisionPackMaxMs>=link.collisionPackMs,"packing and ring-capacity failures have separate counters/timing");
    head.store(size-24);tail.store(size-24);const auto eventName=name+L"_Consume";HANDLE consume=CreateEventW(nullptr,TRUE,FALSE,eventName.c_str());
    wchar_t executable[MAX_PATH]{};GetModuleFileNameW(nullptr,executable,MAX_PATH);std::wstring command=L"\""+std::wstring(executable)+L"\" --collision-peer \""+name+L"\" 3";
    STARTUPINFOW startup{sizeof(startup)};PROCESS_INFORMATION process{};const bool started=consume&&CreateProcessW(nullptr,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process);
    check(started,"start independent consumer for atomically committed collision batch");
    if(started){
        const auto deadline=GetTickCount64()+5000;CollisionStatus current{};
        do{current=link.collision_status();if(current.connected&&current.mcPid==process.dwProcessId)break;Sleep(1);}while(GetTickCount64()<deadline);
        const bool published=current.connected&&current.mcPid==process.dwProcessId&&link.publish_collision(3,bounds,floor);check(published,"whole batch commits CLEAR/wrap-padding/TRIS/REGION after capacity preflight");
        current=link.collision_status();check(published&&current.publishSeq==1&&current.consumedSeq==0&&current.batchEnd==head.load()&&current.head>size,"publish sequence advances while consumer-held tail leaves consumption unconfirmed");
        SetEvent(consume);const auto waited=WaitForSingleObject(process.hProcess,12000);DWORD exit{};GetExitCodeProcess(process.hProcess,&exit);check(waited==WAIT_OBJECT_0&&exit==0,"independent consumer sees full ordered batch and commits tail only after processing");
        current=link.collision_status();check(current.consumedSeq==1&&current.tail==current.batchEnd,"consumed sequence advances after exact complete-batch tail acknowledgement");
        CloseHandle(process.hThread);CloseHandle(process.hProcess);
    }
    if(consume)CloseHandle(consume);
    tail.store(head.load());const auto sameEpochStart=head.load();check(link.publish_collision(3,bounds,floor),"same-epoch refresh publishes a complete replacement batch");
    auto current=link.collision_status();check(reinterpret_cast<proto::ColMsgHeader*>(data+sameEpochStart%size)->type==proto::kColTris,"successful prior epoch state suppresses redundant CLEAR on same-epoch refresh");
    tail.store(current.batchEnd-8);check(link.collision_status().consumedSeq==1,"tail before the last batch byte cannot certify partial collision consumption");
    tail.store(current.batchEnd);check(link.collision_status().consumedSeq==2,"tail at batch end certifies exactly the second complete batch");
    check(link.publish_collision(3,bounds,floor),"queue pending batch for reconnect invalidation test");current=link.collision_status();const auto oldEnd=current.batchEnd,oldGeneration=current.generation;
    std::atomic_ref(header->mcHeartbeatMs).store(GetTickCount64()-3001);const auto lost=link.collision_status();
    std::atomic_ref(header->mcHeartbeatMs).store(GetTickCount64());const auto regained=link.collision_status();tail.store(oldEnd);
    current=link.collision_status();check(!lost.connected&&regained.connected&&lost.generation>oldGeneration&&regained.generation>lost.generation&&current.consumedSeq==2,"stale then fresh same-PID link invalidates pending consumption proof");
    const auto generation=current.generation;std::atomic_ref(header->mcPid).store(GetCurrentProcessId());current=link.collision_status();
    check(current.mcPid==GetCurrentProcessId()&&(!started||current.generation>generation),"changed Minecraft PID advances collision generation");
    link.invalidate_collision();const auto invalidated=link.collision_status();check(invalidated.generation>current.generation&&invalidated.publishSeq==3&&invalidated.consumedSeq==2&&invalidated.batchEnd==0,"epoch/Lua invalidation preserves monotonic sequence counts but discards pending batches");
    const auto newEpochStart=head.load();check(link.publish_collision(4,bounds,floor)&&reinterpret_cast<proto::ColMsgHeader*>(data+newEpochStart%size)->type==proto::kColClear,"new epoch commits CLEAR together with complete region packets");
    current=link.collision_status();tail.store(current.head+8);check(!link.collision_status().ringValid&&link.collision_status().consumedSeq==2,"invalid tail beyond head cannot establish consumption proof");tail.store(current.head);
    const auto sequence=current.publishSeq;const auto closingGeneration=current.generation;link.close();check(link.open(name),"reopen isolated mapping with new native collision generation");current=link.collision_status();check(current.generation>closingGeneration&&current.publishSeq==sequence&&current.consumedSeq==2&&current.head==0&&current.tail==0,"mapping reopen resets ring and invalidates acknowledgements without recycling sequence IDs");
    check(initial.generation>0,"collision generation is initialized before first publication");
}
}
