#pragma once
#include "RenderStore.hpp"
#include <filesystem>
#include <future>
#include <string>
#include <memory>

namespace omc {
// Owned numeric snapshots only. No SDK/Lua/D3D work on this file-writer thread.
class NativeSectionMailbox {
    std::future<std::string> writer;
    std::uint64_t sequence{}, session{};
    std::map<std::pair<std::uint32_t,std::uint64_t>,std::shared_ptr<const Texture>> atlasCopies;
public:
    std::string error;
    bool busy();
    std::string request(const std::filesystem::path& root,const RenderStore& store,SectionKey key,std::uint64_t revision);
    std::string request_model(const std::filesystem::path& root,const RenderStore& store,std::uint32_t model);
    std::uint64_t count() const{return sequence;}
};
}
