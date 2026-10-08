#pragma once
#include "../../protocol/skycraft_protocol.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <map>
#include <span>
#include <tuple>
#include <vector>
#include <string>
#include <unordered_map>

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
struct NativeCube { std::int32_t x{},y{},z{}; std::uint32_t kind{}; auto operator<=>(const NativeCube&) const=default; };
struct NativeLight {std::int32_t x{},y{},z{};std::uint32_t color{},level{};};
struct NativeFace {
    std::uint32_t first{},model{};
    float position[3]{},rotation[4]{},scale[2]{}; // quaternion w,x,y,z
};
struct Mesh {
    std::vector<proto::RenVertex> vertices;
    std::vector<proto::RenBatch> batches;
    double origin[3]{};
    std::uint64_t revision{};
    std::uint64_t nativeRevision{};
    std::vector<NativeCube> nativeTriangles;
};
struct AtlasRect { std::uint32_t x{},y{},w{},h{}; auto operator<=>(const AtlasRect&) const = default; };
struct NativeSectionView { Mesh remainder,depth; std::vector<std::uint8_t> mask; std::uint64_t sourceRevision{},expires{}; };
struct DynamicNativeView {
    Mesh remainder,depth;
    std::vector<NativeFace> faces;
    std::map<std::uint32_t,std::uint32_t> receipt;
    std::uint64_t sourceRevision{},receiptRevision{},expires{};
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
    std::uint64_t atlasBaseRevision{};
    std::uint32_t nextModelId{};
    std::size_t modelBytes{};
    std::map<std::uint32_t,Mesh> blockModels;
    std::map<std::uint32_t,std::uint32_t> modelTextures;
    std::unordered_map<std::string,std::uint32_t> modelKeys;
    std::map<std::uint32_t, Texture> textures;
    std::map<SectionKey, Mesh> sections;
    std::map<SectionKey,std::vector<proto::RenLight>> lights;
    std::map<SectionKey,std::vector<AtlasRect>> sectionAtlasRects;
    std::vector<AtlasRect> animatedAtlasRects;
    std::map<SectionKey,NativeSectionView> nativeViews;
    Mesh avatar, scene,hands;
    DynamicNativeView nativeAvatar,nativeScene,nativeHands;
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
    std::uint64_t instanceRevision{},instanceReceiptRevision{};
    bool instanceReceiptValid{};
    std::vector<NativeCube> instanceReceipts;
    bool consume(std::uint32_t type, std::span<const std::uint8_t> payload);
    void clear();
    void set_cube_context(std::uint32_t world,std::uint32_t epoch,std::uint32_t pid,std::uint64_t generation,bool connected);
    CubeSnapshot nearby_cubes(double x,double y,double z,double radius,std::size_t limit) const;
    bool accept_native_section(SectionKey key,std::uint64_t sourceRevision,std::span<const std::uint8_t> mask,std::uint64_t now);
    const Mesh& section_overlay(SectionKey key,const Mesh& original,std::uint64_t now) const;
    void invalidate_native_views();
    std::vector<NativeCube> nearby_instances(double x,double y,double z) const;
    bool accept_instances(const std::vector<NativeCube>& cubes,std::uint64_t now);
    void register_models(Mesh& mesh,SectionKey key);
    std::uint32_t register_model(Mesh model,std::uint32_t textureId);
    const Texture* model_texture(std::uint32_t model)const;
    void prepare_dynamic();
    bool accept_dynamic(unsigned stream,const std::map<std::uint32_t,std::uint32_t>&faces,std::uint64_t now);
    bool hands_ready(std::uint64_t now) const;
    void partition_dynamic(const Mesh&source,DynamicNativeView&view,std::uint64_t now);
    void release_dynamic();
    std::vector<NativeLight> nearby_lights(double x,double y,double z)const;
};
}
