#pragma once
#include "RenderStore.hpp"
#include "NativeSectionMailbox.hpp"
#include <filesystem>
#include <thread>
namespace omc::tests {
template<class Check>void render_lifetime_tests(Check check){
    RenderStore s;s.set_cube_context(1,2,3,4,true);
    auto packet=[](const auto&h,const auto&data){std::vector<std::uint8_t>p(sizeof(h)+data.size()*sizeof(data[0]));std::memcpy(p.data(),&h,sizeof(h));std::memcpy(p.data()+sizeof(h),data.data(),p.size()-sizeof(h));return p;};
    const std::vector<std::uint8_t> pixels(64*64*4,255);
    const auto atlas=packet(proto::RenAtlas{64,64},pixels),tex=packet(proto::RenTexture{1,64,64,0},pixels);
    Mesh model;model.vertices={{0,0,0,.1f,.1f,0xffffffff,0,1},{1,0,0,.2f,.1f,0xffffffff,0,1},{0,1,0,.1f,.2f,0xffffffff,0,1}};
    s.consume(proto::kRenClearAll,{});s.consume(proto::kRenAtlas,atlas);s.consume(proto::kRenTexture,tex);
    const auto a=s.register_model(model,0),b=s.register_model(model,1);
    bool stable=true;
    for(int i=0;i<1000;i++){
        s.set_cube_context(1,2,3,5+i,true);s.consume(proto::kRenClearAll,{});
        s.consume(proto::kRenAtlas,atlas);s.consume(proto::kRenTexture,tex);
        stable&=s.register_model(model,0)==a&&s.register_model(model,1)==b&&s.blockModels.size()==2;
    }
    check(stable,"1000 reconnect/CLEAR/texture resends reuse block and dynamic IDs without growing registry");
    // Animated atlas writes must not turn a later identical base upload into a
    // completely new set of static resources.
    const std::vector<std::uint8_t> region(4,23);
    s.consume(proto::kRenAtlasRegion,packet(proto::RenAtlasRegion{50,50,1,1},region));
    s.consume(proto::kRenClearAll,{});s.consume(proto::kRenAtlas,atlas);
    check(s.register_model(model,0)==a,"animated tile update does not invalidate unrelated models on reconnect");
    auto changed=pixels;changed[0]=0;
    s.consume(proto::kRenTexture,packet(proto::RenTexture{1,64,64,0},changed));
    const auto fresh=s.register_model(model,1);
    check(fresh!=b&&!s.blockModels.contains(b)&&s.register_model(model,0)==a,"changed texture invalidates only affected IDs and never recycles old receipts");
    bool bounded=true;
    for(int i=0;i<9000;i++){++s.revision;auto m=model;m.vertices[0].x=float(i+10);bounded&=s.register_model(m,1)>0&&s.blockModels.size()<=4096;}
    check(bounded&&s.modelEvicted>4096,"9000 distinct appearances evict cold registry entries while new models keep registering");
    const auto current=s.register_model(model,0);
    NativeSectionMailbox box;
    const auto root=std::filesystem::temp_directory_path()/("omc-mailbox-stress-"+std::to_string(GetCurrentProcessId())+"-"+std::to_string(GetTickCount64()));
    std::filesystem::create_directories(root);bool captured=true;
    for(int i=0;i<8200;i++){
        const auto id=box.request_model(root,s,current,0,false);
        if(id.empty()){captured=false;break;}
        while(box.busy())std::this_thread::sleep_for(std::chrono::milliseconds(1));
        if(!box.error.empty()||!std::filesystem::exists(root/"inbox"/(id+".json"))){captured=false;break;}
        // Test consumer retires its own ticket/result immediately; the number of
        // outstanding requests, not lifetime count, is the work bound.
        std::filesystem::remove(root/"inbox"/(id+".json"));std::filesystem::remove_all(root/id);
    }
    check(captured&&box.count()==8200,"8200 real async captures pass old lifetime limit and publish atomic inbox tickets");
    std::filesystem::remove_all(root);
}
}
