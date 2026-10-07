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
struct CubePosition { std::int32_t x{}, y{}, z{}; };
struct CubeSnapshot { std::vector<CubePosition> rows; std::size_t total{}; };
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
    std::map<SectionKey, std::array<std::uint8_t,512>> fullCubes;
    std::uint32_t cubeWorld{},cubeEpoch{},cubePid{};
    std::uint64_t cubeGeneration{},cubeRevision{},staleCubeMessages{};
    bool cubeConnected{},cubeCleared{};
    std::uint64_t revision{}, invalidMessages{};
    bool consume(std::uint32_t type, std::span<const std::uint8_t> payload);
    void clear();
    void set_cube_context(std::uint32_t world,std::uint32_t epoch,std::uint32_t pid,std::uint64_t generation,bool connected);
    CubeSnapshot nearby_cubes(double x,double y,double z,double radius,std::size_t limit) const;
};
}
