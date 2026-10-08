#pragma once
#include "RenderStore.hpp"
#include <cstring>
namespace omc::tests {
template<class Check>void native_section_tests(Check check){
    RenderStore s;s.set_cube_context(1,2,3,4,true);s.consume(proto::kRenClearAll,{});
    auto packet=[](const auto&h,const auto&data){std::vector<std::uint8_t>p(sizeof(h)+data.size()*sizeof(data[0]));std::memcpy(p.data(),&h,sizeof(h));std::memcpy(p.data()+sizeof(h),data.data(),p.size()-sizeof(h));return p;};
    std::vector<std::uint8_t>rgba(64*64*4,255);s.consume(proto::kRenAtlas,packet(proto::RenAtlas{64,64},rgba));
    std::vector<proto::RenVertex>v(6);for(auto&x:v){x.u=.1f;x.v=.1f;x.color=0xffffffff;}
    const SectionKey k{0,0,0};auto send=[&]{return s.consume(proto::kRenSection,packet(proto::RenSection{0,0,0,std::uint32_t(v.size())},v));};
    send();auto rev=s.sections[k].nativeRevision;std::vector<std::uint8_t>mask{1};
    check(s.accept_native_section(k,rev,mask,100)&&s.section_overlay(k,s.sections[k],101).vertices.size()==3,"native receipt suppresses only acknowledged triangles");
    check(s.section_overlay(k,s.sections[k],600).vertices.size()==6,"missing Lua renewal restores overlay after bounded lease");
    check(!s.accept_native_section(k,rev,std::vector<std::uint8_t>{3},102),"mask cannot change under existing resource receipt");
    check(!s.accept_native_section(k,rev,std::vector<std::uint8_t>{5},102),"reject out-of-range triangle mask padding");
    check(s.accept_native_section(k,rev,mask,200)&&s.section_overlay(k,s.sections[k],699).vertices.size()==3,"same receipt renews without reallocating mesh");
    std::vector<std::uint8_t>one(4,255);s.consume(proto::kRenAtlasRegion,packet(proto::RenAtlasRegion{50,50,1,1},one));
    check(s.sections[k].nativeRevision==rev&&s.nativeViews.size()==1,"unrelated animated atlas tile does not invalidate native geometry");
    s.consume(proto::kRenAtlasRegion,packet(proto::RenAtlasRegion{6,6,1,1},one));
    check(s.sections[k].nativeRevision!=rev&&s.nativeViews.empty(),"newly animated used tile invalidates stale native capture");
    rev=s.sections[k].nativeRevision;s.consume(proto::kRenAtlasRegion,packet(proto::RenAtlasRegion{6,6,1,1},one));
    check(s.sections[k].nativeRevision==rev,"known animation stays overlay without rebuilding static portion every frame");
    check(s.accept_native_section(k,rev,mask,300),"fresh partition accepted after animation discovery");
    send();check(!s.accept_native_section(k,rev,mask,310)&&s.nativeViews.empty(),"block edit immediately rejects stale resource receipt");
    rev=s.sections[k].nativeRevision;v[0].flags=2;send();check(!s.accept_native_section(k,s.sections[k].nativeRevision,mask,320),"translucent source triangles cannot be hidden by opaque renderer");
    v[0].flags=0;send();s.accept_native_section(k,s.sections[k].nativeRevision,mask,330);s.set_cube_context(1,3,3,4,true);
    check(s.nativeViews.empty(),"epoch/connection changes clear native visibility receipts");
    v.clear();send();check(s.sections.empty()&&s.nativeViews.empty(),"empty section/explosion removes native source and receipts");
    s.set_cube_context(1,2,3,4,true);s.consume(proto::kRenClearAll,{});
    s.animatedAtlasRects.clear();
    const proto::RenVertex tagged[]={{0,0,0,.1f,.1f,0xffffffff,0,0x131},{0,1,0,.2f,.1f,0xffffffff,0,0x131},{1,0,0,.1f,.2f,0xffffffff,0,0x131}};
    v.assign(std::begin(tagged),std::end(tagged));send();
    auto cubes=s.nearby_instances(.5,.5,.5);check(cubes.size()==1&&cubes[0].kind>0&&cubes[0].x==0,"protocol15 complete model owner tags recover exact cell");
    check(s.accept_instances(cubes,400)&&s.section_overlay(k,s.sections[k],401).vertices.empty(),"ready prebuilt cube suppresses source geometry with depth retained");
    const auto receipt=s.nativeViews[k].remainder.revision;
    s.accept_instances(cubes,450);check(s.nativeViews[k].remainder.revision==receipt,"unchanged instance set only renews lease, no GPU mesh rebuild");
    const auto deadline=s.nativeViews[k].expires;
    auto added=v;for(auto&x:added){x.x+=1;x.flags+=256;}
    v.insert(v.begin(),added.begin(),added.end());send();
    check(s.section_overlay(k,s.sections[k],451).vertices.size()==3&&s.nativeViews[k].mask==std::vector<std::uint8_t>{2},"adding a block and reordering triangles keeps existing native block hidden in MC without another acknowledgement");
    check(s.nativeViews[k].expires==deadline&&s.section_overlay(k,s.sections[k],deadline).vertices.size()==6,"edit preserves old native lease deadline, never extends an unrenewed receipt");
    v.erase(v.begin(),v.begin()+3);send();
    check(s.section_overlay(k,s.sections[k],452).vertices.empty(),"breaking the new block keeps unchanged native block suppressed");
    const auto oldKind=cubes[0].kind;for(auto&x:v)x.u+=.3f;send();s.accept_instances(cubes,460);
    check(s.nativeViews.empty(),"replacing stone with iron cannot reuse old stone visibility receipt");
    cubes=s.nearby_instances(.5,.5,.5);check(cubes.size()==1&&cubes[0].kind!=oldKind&&s.accept_instances(cubes,470),"new kind becomes native only after its own ready instance acknowledgement");
    s.invalidate_native_views();s.accept_instances(cubes,480);check(s.nativeViews.size()==1,"F10 restart rebuilds visibility even when same instance set resumes");
    for(auto&x:v)x.z=.2f;send();check(s.nearby_instances(.5,.5,.5).size()==1,"thin and inset models preserve actual geometry without solid cube substitution");
    auto thin=s.nearby_instances(.5,.5,.5)[0].kind;send();check(s.nearby_instances(.5,.5,.5)[0].kind==thin,"unchanged full appearance survives neighbor section rebuild without new model ID");
    for(auto&x:v){x.x+=1;x.flags+=256;}send();check(s.nearby_instances(1.5,.5,.5)[0].kind==thin,"same appearance at another cell shares model ID");
    v.assign(std::begin(tagged),std::end(tagged));s.consume(proto::kRenSection,packet(proto::RenSection{-1,2,-3,3},v));
    cubes=s.nearby_instances(-15.5,32.5,-47.5);check(cubes.size()==2&&cubes[0].x==-16&&cubes[0].y==32&&cubes[0].z==-48,"negative/distant section offsets preserve native cube placement");
    cubes=s.nearby_instances(40.5,.5,.5);check(cubes.size()==2,"native display stays available beyond old 16m collision radius");
    check(s.nearby_instances(200,.5,.5).empty(),"native display range is bounded to 128m");
    check(!s.accept_instances(std::vector<NativeCube>(1281,{0,0,0,1}),500),"instance receipt enforces the 1280 bound");
}
}
