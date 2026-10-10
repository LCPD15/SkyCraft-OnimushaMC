#pragma once
#include "RenderStore.hpp"
#include "CollisionPacking.hpp"
#include <Windows.h>
#include <functional>
#include <deque>
#include <span>
#include <string>
#include <string_view>

namespace omc {
struct CollisionStatus {
    std::uint64_t generation{},publishSeq{},consumedSeq{},head{},tail{},batchEnd{};
    std::uint32_t mcPid{};
    bool connected{},ringValid{};
    double heartbeatAgeMs=-1;
};
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
    bool publish_attacks(bool enabled,std::uint32_t epoch,std::uint32_t world,std::span<const proto::NativeAttack> attacks);
    std::uint64_t attackPublished{},attackRejected{};
    bool publish_collision(std::uint32_t epoch,const proto::ColRegion& region,std::span<const proto::ColTri> triangles);
    bool publish_packed_collision(std::uint32_t epoch,std::vector<CollisionPacket> packets);
    CollisionStatus collision_status();
    void invalidate_collision();
    std::vector<proto::McEvent> events();
    void drain_render(RenderStore& store,std::uint64_t budget=8ull<<20);
    bool overlay(OverlayFrame& frame);
    bool world_entities(proto::WorldEntities& out) const;
    std::string error;
    std::uint64_t rejected{};
    std::uint64_t collisionPackFailures{},collisionQueueFailures{};
    double collisionPackMs{},collisionPackMaxMs{};
    std::string collisionFailure;
    // Only used by the native cross-process integration test.
    std::uint8_t* testing_base() const {return base_;}
private:
    void refresh_collision_link();
    HANDLE mapping_{};
    std::uint8_t* base_{};
    std::uint32_t overlayFront_=2, lastEpoch_=~0u;
    struct CollisionBatch {std::uint64_t seq,end;};
    std::deque<CollisionBatch> collisionBatches_;
    std::uint64_t collisionGeneration_{},collisionPublishSeq_{},collisionConsumedSeq_{},collisionBatchEnd_{};
    std::uint32_t observedMcPid_{};
    bool observedConnected_{};
    bool attacksEnabled_{};
    std::uint32_t attackSession_{},attackEpoch_{},attackWorld_{},attackPid_{};
};
}
