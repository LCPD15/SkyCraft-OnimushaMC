#pragma once
#include <reframework/API.h>
#include "../../protocol/skycraft_protocol.h"

namespace omc {
struct RenderStore;
struct OverlayFrame;
struct CameraState {
    float viewProj[16]{}; // column-major, positions relative to origin, in MC blocks
    double origin[3]{};
    bool valid = false;
};
namespace renderer {
void initialize(const REFrameworkPluginInitializeParam*);
bool prepare(); // Creates private GPU resources without changing the game's frame.
bool ready();
// Called under the plugin mutex. Coordinates are normalized client event positions.
void set_gui_cursor(bool known,double u=0,double v=0);
void render(const RenderStore&, const OverlayFrame&, const skycraft::proto::McState&, const CameraState&);
void reset();
}
}
