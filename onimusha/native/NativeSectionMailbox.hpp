#pragma once
#include "RenderStore.hpp"
#include <filesystem>
#include <future>
#include <string>

namespace omc {
// Owned numeric snapshots only. No SDK/Lua/D3D work on this file-writer thread.
class NativeSectionMailbox {
    std::future<std::string> writer;
    std::uint64_t sequence{}, session{};
public:
    std::string error;
    bool busy();
    std::string request(const std::filesystem::path& root,const RenderStore& store,SectionKey key,std::uint64_t revision);
    std::uint64_t count() const{return sequence;}
};
}
