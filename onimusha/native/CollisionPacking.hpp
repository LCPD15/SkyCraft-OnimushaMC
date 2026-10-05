#pragma once
#include "RenderStore.hpp"
#include <string>
namespace omc {
inline constexpr std::int32_t kMaxCollisionCoordinate=30'000'000;
struct CollisionPacket { std::uint32_t type{}; std::vector<std::uint8_t> payload; };
bool pack_collision(const proto::ColRegion&,std::span<const proto::ColTri>,std::vector<CollisionPacket>& out,std::string& error);
}
