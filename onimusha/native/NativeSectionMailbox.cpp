#include "NativeSectionMailbox.hpp"
#include <Windows.h>
#include <fstream>
#include <sstream>
#include <chrono>
#include <algorithm>
namespace omc {
std::string NativeSectionMailbox::request_model(const std::filesystem::path&root,const RenderStore&s,std::uint32_t model,unsigned priority,bool whiteFlash){
    if(busy()||sequence==UINT64_MAX||!s.cubeConnected||!s.cubeCleared||s.atlas.rgba.empty())return {};
    auto it=s.blockModels.find(model);if(it==s.blockModels.end())return {};
    if(!session)session=GetTickCount64();
    const auto id=std::to_string(GetCurrentProcessId())+"_"+std::to_string(session)+"_"+std::to_string(++sequence);
    const auto *sourceTexture=s.model_texture(model);if(!sourceTexture)return {};
    const auto textureId=s.modelTextures.at(model);
    const auto texRevision=textureId?sourceTexture->revision:s.atlasBaseRevision;
    const auto atlasName="atlas_"+std::to_string(GetCurrentProcessId())+"_"+std::to_string(session)+"_"+std::to_string(textureId)+"_"+std::to_string(texRevision)+".bin";
    // Snapshot the large atlas once per base upload, never once per placed model.
    // The writer captures shared immutable ownership, not game/render memory.
    const auto cacheKey=std::make_pair(textureId,texRevision);
    if(!atlasCopies.contains(cacheKey)){
        for(auto i=atlasCopies.begin();i!=atlasCopies.end();)if(i->first.first==textureId)i=atlasCopies.erase(i);else++i;
        auto bytes=[&]{std::size_t n=0;for(const auto&[key,t]:atlasCopies)n+=t->rgba.size();return n;};
        while(!atlasCopies.empty()&&(atlasCopies.size()>=16||bytes()+sourceTexture->rgba.size()>64ull*1024*1024))atlasCopies.erase(atlasCopies.begin());
        atlasCopies[cacheKey]=std::make_shared<Texture>(*sourceTexture);
    }
    auto vertices=it->second.vertices;auto atlas=atlasCopies.at(cacheKey);auto animated=textureId?std::vector<AtlasRect>{}:s.animatedAtlasRects;
    const auto world=s.cubeWorld,epoch=s.cubeEpoch,pid=s.cubePid;const auto gen=s.cubeGeneration;
    writer=std::async(std::launch::async,[=,v=std::move(vertices),a=std::move(atlas),rects=std::move(animated)]()->std::string{
        try{
            const auto dir=root/id;if(std::filesystem::exists(dir))return "Capture ID already exists";
            std::filesystem::create_directories(dir);
            auto write=[](const std::filesystem::path&p,const void*h,std::size_t hs,const void*d,std::size_t n){std::ofstream f(p,std::ios::binary);f.exceptions(std::ios::badbit|std::ios::failbit);f.write(static_cast<const char*>(h),hs);f.write(static_cast<const char*>(d),n);};
            if(!std::filesystem::exists(root/atlasName)){
                proto::RenAtlas ah{a->width,a->height};write(root/(atlasName+".tmp"),&ah,sizeof(ah),a->rgba.data(),a->rgba.size());
                std::filesystem::rename(root/(atlasName+".tmp"),root/atlasName);
            }
            proto::RenSection sh{0,0,0,std::uint32_t(v.size())};write(dir/"section.bin",&sh,sizeof(sh),v.data(),v.size()*sizeof(proto::RenVertex));
            std::ostringstream j;j<<"{\"id\":\""<<id<<"\",\"host_pid\":"<<GetCurrentProcessId()<<",\"world\":"<<world<<",\"epoch\":"<<epoch<<",\"mc_pid\":"<<pid<<",\"generation\":"<<gen<<",\"model\":"<<model<<",\"atlas\":\""<<atlasName<<"\",\"animated\":[";
            bool first=true;for(auto r:rects){if(!first)j<<',';first=false;j<<'['<<r.x<<','<<r.y<<','<<r.w<<','<<r.h<<']';}j<<"]}";
            auto data=j.str();data.pop_back();data+=",\"priority\":"+std::to_string(std::min(priority,2u))+",\"white_flash\":"+(whiteFlash?"true":"false")+"}";
            write(dir/"request.tmp",data.data(),data.size(),"",0);std::filesystem::rename(dir/"request.tmp",dir/"request.json");
            // Only pending tickets are scanned. Completed results remain directly
            // addressable without a growing per-poll walk of all historical jobs.
            const auto inbox=root/"inbox";std::filesystem::create_directories(inbox);
            write(inbox/(id+".tmp"),data.data(),data.size(),"",0);std::filesystem::rename(inbox/(id+".tmp"),inbox/(id+".json"));return {};
        }catch(const std::exception&e){return e.what();}
    });return id;
}
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
