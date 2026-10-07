#pragma once
#include "RenderStore.hpp"
#include <cstring>
#include <limits>

namespace omc::tests {
template<class Check> void full_cube_tests(Check check) {
    RenderStore store;
    proto::RenFullCubes h{0,0,0,1,9,81,1234,0};
    std::array<std::uint8_t,512> bits{};bits[0]=1;
    const auto packet=[&]{std::vector<std::uint8_t> p(sizeof(h)+(h.count?512:0));std::memcpy(p.data(),&h,sizeof(h));if(h.count)std::memcpy(p.data()+sizeof(h),bits.data(),512);return p;};
    const auto send=[&]{return store.consume(proto::kRenFullCubes,packet());};
    store.set_cube_context(9,81,1234,1,true);
    check(send()&&store.fullCubes.empty(),"full cubes require clear fence in new native context");
    store.consume(proto::kRenClearAll,{});
    check(send()&&store.fullCubes.size()==1,"context-tagged exact cube section is accepted");
    auto s=store.nearby_cubes(.5,.5,.5,16,128);
    check(s.total==1&&s.rows.size()==1&&s.rows[0].x==0,"snapshot includes nearest actual cube");
    h.epoch=80;check(send()&&store.fullCubes.size()==1,"old epoch cannot replace block collision");h.epoch=81;
    h.mcPid=5678;check(send()&&store.fullCubes.size()==1,"different MC process cannot replace block collision");h.mcPid=1234;
    h.worldId=10;check(send()&&store.fullCubes.size()==1,"different world cannot replace block collision");h.worldId=9;
    h.count=2;check(!send()&&store.fullCubes.size()==1,"invalid population count retains last valid section");h.count=1;
    h.reserved=1;check(!send(),"unknown full cube flags are rejected");h.reserved=0;
    h.sx=INT32_MAX;check(!send(),"section overflow rejected before coordinate multiplication");h.sx=0;
    auto p=packet();p.pop_back();check(!store.consume(proto::kRenFullCubes,p),"truncated cube packet cannot partially mutate store");
    h.count=0;check(send()&&store.nearby_cubes(.5,.5,.5,16,128).rows.empty(),"last block removed or exploded clears native snapshot");
    bits.fill(255);h.count=4096;check(send(),"full section accepts bounded 4096-bit population");
    s=store.nearby_cubes(8,8,8,16,1280);
    check(s.rows.size()==1280&&s.total>1280,"dense builds select 1280 nearest cubes and expose truncation");
    check(store.nearby_cubes(8,8,8,17,1280).rows.empty()&&store.nearby_cubes(8,8,8,16,1281).rows.empty(),"snapshot rejects oversized range and count");
    check(store.nearby_cubes(std::numeric_limits<double>::quiet_NaN(),0,0,16,128).rows.empty(),"non-finite native query rejected");
    store.set_cube_context(9,81,1234,2,true);
    check(store.fullCubes.empty()&&!store.cubeCleared&&send()&&store.fullCubes.empty(),"generation reset revokes cached cubes until producer clear fence");
    store.consume(proto::kRenClearAll,{});check(send()&&store.fullCubes.size()==1,"fresh resend restores cubes after generation reset");
    store.set_cube_context(9,81,1234,2,false);
    check(store.nearby_cubes(8,8,8,16,128).rows.empty()&&store.fullCubes.empty(),"disconnect removes old native cube snapshot");
}
}
