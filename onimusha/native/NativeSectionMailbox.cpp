#include "NativeSectionMailbox.hpp"
#include <Windows.h>
#include <fstream>
#include <sstream>
#include <chrono>
namespace omc {
bool NativeSectionMailbox::busy(){
    if(!writer.valid())return false;
    if(writer.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return true;
    error=writer.get();return false;
}
std::string NativeSectionMailbox::request(const std::filesystem::path& root,const RenderStore&s,SectionKey k,std::uint64_t rev){
    if(busy()||sequence>=512||!s.cubeConnected||!s.cubeCleared||s.atlas.rgba.empty())return {};
    auto it=s.sections.find(k);if(it==s.sections.end()||it->second.nativeRevision!=rev||it->second.vertices.size()>196608)return {};
    if(!session)session=GetTickCount64();
    const auto id=std::to_string(GetCurrentProcessId())+"_"+std::to_string(session)+"_"+std::to_string(++sequence);
    auto vertices=it->second.vertices;auto atlas=s.atlas;auto animated=s.animatedAtlasRects;
    const auto world=s.cubeWorld,epoch=s.cubeEpoch,pid=s.cubePid;const auto gen=s.cubeGeneration;
    writer=std::async(std::launch::async,[=,v=std::move(vertices),a=std::move(atlas),rects=std::move(animated)]() -> std::string {
        try{
            const auto dir=root/id;if(std::filesystem::exists(dir))return "Capture ID already exists";
            std::filesystem::create_directories(dir);
            auto write=[&](const char*name,const void*h,std::size_t hs,const void*data,std::size_t n){std::ofstream f(dir/name,std::ios::binary);f.exceptions(std::ios::badbit|std::ios::failbit);f.write(static_cast<const char*>(h),hs);f.write(static_cast<const char*>(data),n);};
            proto::RenSection sh{k.x,k.y,k.z,std::uint32_t(v.size())};write("section.bin",&sh,sizeof(sh),v.data(),v.size()*sizeof(proto::RenVertex));
            proto::RenAtlas ah{a.width,a.height};write("atlas.bin",&ah,sizeof(ah),a.rgba.data(),a.rgba.size());
            std::ostringstream j;j<<"{\"id\":\""<<id<<"\",\"host_pid\":"<<GetCurrentProcessId()<<",\"world\":"<<world<<",\"epoch\":"<<epoch<<",\"mc_pid\":"<<pid<<",\"generation\":"<<gen<<",\"revision\":"<<rev<<",\"section\":["<<k.x<<','<<k.y<<','<<k.z<<"],\"animated\":[";
            bool first=true;for(auto r:rects){if(!first)j<<',';first=false;j<<'['<<r.x<<','<<r.y<<','<<r.w<<','<<r.h<<']';}j<<"]}";
            const auto data=j.str();write("request.tmp",data.data(),data.size(),"",0);
            std::filesystem::rename(dir/"request.tmp",dir/"request.json");return {};
        }catch(const std::exception&e){return e.what();}
    });return id;
}
}
