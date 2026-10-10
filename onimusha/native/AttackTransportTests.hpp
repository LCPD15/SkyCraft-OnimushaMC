#pragma once
#include <cstddef>
inline void test_attack_transport(omc::Bridge& link){
    using namespace omc;
    auto* b=link.testing_base();auto* h=reinterpret_cast<proto::Header*>(b);
    h->mcPid=GetCurrentProcessId();h->mcHeartbeatMs=GetTickCount64();
    auto* ring=b+proto::kOffAttackRing;
    check(offsetof(proto::NativeAttack,geometry)==68&&offsetof(proto::NativeAttack,damage)==40,"NPC wire field offsets match Java");
    proto::NativeAttack a{};a.attackerId=2;a.attackId=3;a.hitId=4;a.shape=1;a.damage=2;a.geometry[6]=a.geometry[13]=.5f;
    check(link.publish_attacks(true,9,10,std::span(&a,1)),"publish native attack with live peer");
    const auto first=*reinterpret_cast<proto::NativeAttack*>(ring+0x80);
    check(first.epoch==9&&first.worldId==10&&first.session&&first.timeMs>0&&first.damage==2,"native attack stamps session and time");
    check(link.publish_attacks(false,9,10,{}),"disable attack stream");
    check(*reinterpret_cast<std::uint32_t*>(ring+8)==0&&*reinterpret_cast<std::uint32_t*>(ring+12)!=first.session,"F10 invalidates queued attacks");
    check(link.publish_attacks(true,9,10,std::span(&a,1)),"resume with fresh session");
    auto bad=a;bad.damage=std::numeric_limits<float>::quiet_NaN();const auto head=*reinterpret_cast<std::uint64_t*>(ring);
    check(!link.publish_attacks(true,9,10,std::span(&bad,1))&&head==*reinterpret_cast<std::uint64_t*>(ring),"reject malformed batch without partial publication");
    *reinterpret_cast<std::uint64_t*>(ring)=proto::kAttackRingEntries;
    check(!link.publish_attacks(true,9,10,std::span(&a,1)),"full attack ring never overwrites unread events");
    *reinterpret_cast<std::uint64_t*>(ring)=0;*reinterpret_cast<std::uint64_t*>(ring+0x40)=0;
    link.publish_attacks(false,9,10,{});
    const std::wstring name=L"Local\\OnimushaMC_AttackReopen_"+std::to_wstring(GetCurrentProcessId());
    Bridge reopen;check(reopen.open(name),"open isolated NPC lifetime fixture");
    HANDLE keep=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,name.c_str());
    auto* held=static_cast<std::uint8_t*>(MapViewOfFile(keep,FILE_MAP_ALL_ACCESS,0,0,proto::kMappingBytes));
    check(held!=nullptr,"keep mapping alive across host close");
    if(held){
        auto* header=reinterpret_cast<proto::Header*>(held);header->mcPid=GetCurrentProcessId();header->mcHeartbeatMs=GetTickCount64();
        check(reopen.publish_attacks(true,9,10,std::span(&a,1)),"open lifetime attack gate");
        reopen.close();check(*reinterpret_cast<std::uint32_t*>(held+proto::kOffAttackRing+8)==0,"close revokes attack gate immediately");
        check(reopen.open(name),"same bridge can reopen");
        check(*reinterpret_cast<std::uint64_t*>(held+proto::kOffAttackRing)==0&&*reinterpret_cast<std::uint64_t*>(held+proto::kOffAttackRing+0x40)==0,"reopen clears previous attack ring counters");
        UnmapViewOfFile(held);
    }
    if(keep)CloseHandle(keep);
}
