#pragma once
#include <Windows.h>
#include <cstdint>
#include <algorithm>
#include <limits>

namespace omc {
enum class ToggleKeyAction { pass, consume, toggle };
constexpr ToggleKeyAction f10_key_action(unsigned int message,std::uint64_t key,std::int64_t lparam) {
    if(key!=VK_F10)return ToggleKeyAction::pass;
    if(message==WM_KEYDOWN||message==WM_SYSKEYDOWN)
        return (lparam&(1ll<<30))?ToggleKeyAction::consume:ToggleKeyAction::toggle;
    if(message==WM_KEYUP||message==WM_SYSKEYUP)return ToggleKeyAction::consume;
    return ToggleKeyAction::pass;
}
constexpr bool captured_input_message(unsigned int message,std::uint64_t key,bool gui){
    switch(message){
    case WM_KEYDOWN:case WM_KEYUP:case WM_SYSKEYDOWN:case WM_SYSKEYUP:
        return key!=VK_INSERT&&(gui||(key!=VK_ESCAPE&&key!='G'));
    case WM_CHAR:case WM_MOUSEMOVE:case WM_INPUT:case WM_MOUSEWHEEL:
    case WM_LBUTTONDOWN:case WM_LBUTTONUP:case WM_RBUTTONDOWN:case WM_RBUTTONUP:
    case WM_MBUTTONDOWN:case WM_MBUTTONUP:case WM_XBUTTONDOWN:case WM_XBUTTONUP:return true;
    default:return false;
    }
}

struct CursorLookDelta { std::int32_t x{},y{};bool send{}; };
class CursorLookFallback {
public:
    void reset(){haveBaseline_=false;}
    void center_baseline(int width,int height){x_=width/2;y_=height/2;haveBaseline_=width>0&&height>0;}
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
class GuiVirtualCursor {
public:
    void reset(){known_=raw_=false;u_=v_=0;fallback_.reset();width_=height_=0;}
    void begin(){reset();known_=true;u_=v_=0.5;}
    bool raw_delta(int dx,int dy,int width,int height){raw_=true;return relative(dx,dy,width,height);}
    bool legacy_move(int x,int y,int width,int height){
        if(!known_||raw_||width<=0||height<=0)return false;
        if(width_!=width||height_!=height){width_=width;height_=height;fallback_.center_baseline(width,height);}
        const auto delta=fallback_.move(x,y,width,height);
        return delta.send&&relative(delta.x,delta.y,width,height);
    }
    bool known()const{return known_;}
    bool raw()const{return raw_;}
    double u()const{return u_;}
    double v()const{return v_;}
private:
    bool relative(int dx,int dy,int width,int height){
        if(!known_||width<=0||height<=0||(!dx&&!dy))return false;
        u_=std::clamp(u_+double(dx)/width,0.0,1.0);v_=std::clamp(v_+double(dy)/height,0.0,1.0);return true;
    }
    double u_{},v_{};bool known_{},raw_{};int width_{},height_{};CursorLookFallback fallback_;
};
struct RoutedMouseDelta { bool send{};std::int32_t x{},y{}; };
class MouseInputRouter {
public:
    bool sync_mode(bool gui){
        if(modeKnown_&&gui==gui_)return false;
        modeKnown_=true;gui_=gui;look_.reset();rawLook_=false;cursor_.reset();
        if(gui){cursor_.begin();++guiOpens;}return true;
    }
    void release(){modeKnown_=gui_=rawLook_=false;look_.reset();cursor_.reset();}
    RoutedMouseDelta raw_delta(int dx,int dy,int width,int height){
        if(!modeKnown_)return {};
        if(gui_){++guiRawPackets;add(guiRawDx,dx);add(guiRawDy,dy);return {cursor_.raw_delta(dx,dy,width,height),0,0};}
        rawLook_=true;++lookRawPackets;return {dx!=0||dy!=0,dx,dy};
    }
    RoutedMouseDelta legacy_move(int x,int y,int width,int height){
        if(!modeKnown_)return {};
        if(gui_){const bool moved=cursor_.legacy_move(x,y,width,height);if(moved)++guiFallbackPackets;return {moved,0,0};}
        if(rawLook_)return {};const auto d=look_.move(x,y,width,height);return {d.send,d.x,d.y};
    }
    bool known_mode()const{return modeKnown_;}
    bool gui_open()const{return gui_;}
    bool raw_look()const{return rawLook_;}
    const GuiVirtualCursor& cursor()const{return cursor_;}
    std::uint64_t guiOpens{},guiRawPackets{},guiFallbackPackets{},lookRawPackets{};
    std::int64_t guiRawDx{},guiRawDy{};
private:
    static void add(std::int64_t& total,int delta){
        constexpr auto lo=std::numeric_limits<std::int64_t>::min(),hi=std::numeric_limits<std::int64_t>::max();
        if(delta>0&&total>hi-delta)total=hi;else if(delta<0&&total<lo-delta)total=lo;else total+=delta;
    }
    bool modeKnown_{},gui_{},rawLook_{};CursorLookFallback look_;GuiVirtualCursor cursor_;
};
}
