#pragma once
#include "../../protocol/skycraft_protocol.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <map>
#include <span>
#include <tuple>
#include <vector>

namespace omc {
namespace proto = skycraft::proto;
struct SectionKey {
    std::int32_t x{}, y{}, z{};
    auto operator<=>(const SectionKey&) const = default;
};
struct Texture {
    std::uint32_t width{}, height{};
    std::vector<std::uint8_t> rgba;
    std::uint64_t revision{};
};
struct Mesh {
    std::vector<proto::RenVertex> vertices;
    std::vector<proto::RenBatch> batches;
    double origin[3]{};
    std::uint64_t revision{};
};
struct OverlayFrame {
    std::uint32_t width{}, height{}, flags{};
    std::uint64_t frameId{};
    std::vector<std::uint8_t> rgba;
};
struct SolidChange { std::int32_t x{}, y{}, z{}; bool solid{}; };
struct RenderStore {
    Texture atlas;
    std::map<std::uint32_t, Texture> textures;
    std::map<SectionKey, Mesh> sections;
    Mesh avatar, scene;
    proto::WorldEntities worldEntities{};
    std::vector<proto::ColTri> collisionTriangles;
    std::uint64_t collisionRevision{};
    std::map<SectionKey, std::array<std::uint8_t,512>> solids;
    std::vector<SolidChange> solidChanges;
    std::uint64_t revision{}, invalidMessages{};
    bool consume(std::uint32_t type, std::span<const std::uint8_t> payload);
    void clear();
};
}
