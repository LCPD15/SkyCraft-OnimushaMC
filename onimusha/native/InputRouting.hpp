#pragma once
#include <Windows.h>
#include <cstdint>

namespace omc {
enum class ToggleKeyAction { pass, consume, toggle };
constexpr ToggleKeyAction f10_key_action(unsigned int message,std::uint64_t key,std::int64_t lparam) {
    if(key!=VK_F10)return ToggleKeyAction::pass;
    if(message==WM_KEYDOWN||message==WM_SYSKEYDOWN)
        return (lparam&(1ll<<30))?ToggleKeyAction::consume:ToggleKeyAction::toggle;
    if(message==WM_KEYUP||message==WM_SYSKEYUP)return ToggleKeyAction::consume;
    return ToggleKeyAction::pass;
}

struct CursorLookDelta { std::int32_t x{},y{};bool send{}; };
class GuiEventCursor {
public:
    void reset(){known_=false;u_=v_=0;}
    bool update(int x,int y,int width,int height,bool explicitButton=false){
        if(width<=0||height<=0)return false;
        const auto cx=std::int64_t(x)-width/2,cy=std::int64_t(y)-height/2;
        // Ignore the game's capture warp, but a button at the center is intentional.
        if(!explicitButton&&cx>=-1&&cx<=1&&cy>=-1&&cy<=1)return false;
        u_=double(x)/width;v_=double(y)/height;known_=true;return true;
    }
    bool known()const{return known_;}
    double u()const{return u_;}
    double v()const{return v_;}
private:
    double u_{},v_{};bool known_{};
};
class CursorLookFallback {
public:
    void reset(){haveBaseline_=false;}
    CursorLookDelta move(int x,int y,int width,int height){
        if(width<=0||height<=0){reset();return {};}
        const auto dx=std::int64_t(x)-x_,dy=std::int64_t(y)-y_;
        const auto cx=std::int64_t(x)-width/2,cy=std::int64_t(y)-height/2;
        // The host recenters its captured cursor. Update the baseline, but never
        // forward that synthetic jump as a Minecraft camera movement.
        const bool centered=cx>=-1&&cx<=1&&cy>=-1&&cy<=1;
        const bool send=haveBaseline_&&!centered&&(dx||dy)&&dx>=INT32_MIN&&dx<=INT32_MAX&&dy>=INT32_MIN&&dy<=INT32_MAX;
        x_=x;y_=y;haveBaseline_=true;
        return send?CursorLookDelta{std::int32_t(dx),std::int32_t(dy),true}:CursorLookDelta{};
    }
private:
    int x_{},y_{};bool haveBaseline_{};
};
}
