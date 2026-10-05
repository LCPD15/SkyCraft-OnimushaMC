#pragma once
#include "RenderStore.hpp"
#include <Windows.h>
#include <functional>
#include <span>
#include <string>
#include <string_view>

namespace omc {
class Bridge {
public:
    ~Bridge();
    bool open(std::wstring_view mappingName=proto::kMappingName);
    void close();
    bool alive() const;
    void heartbeat();
    bool publish_host(const proto::SkyState& s);
    bool read_mc(proto::McState& s) const;
    bool input(std::uint16_t type,std::uint16_t code=0,std::int32_t a=0,std::int32_t b=0,std::int32_t c=0);
    bool publish_actors(std::span<const proto::ActorRecord> actors);
    bool publish_collision(std::uint32_t epoch,const proto::ColRegion& region,std::span<const proto::ColTri> triangles);
    std::vector<proto::McEvent> events();
    void drain_render(RenderStore& store,std::uint64_t budget=8ull<<20);
    bool overlay(OverlayFrame& frame);
    bool world_entities(proto::WorldEntities& out) const;
    std::string error;
    std::uint64_t rejected{};
    // Only used by the native cross-process integration test.
    std::uint8_t* testing_base() const {return base_;}
private:
    bool collision_message(std::uint32_t type,const void* p,std::uint32_t bytes);
    HANDLE mapping_{};
    std::uint8_t* base_{};
    std::uint32_t overlayFront_=2, lastEpoch_=~0u;
};
}
