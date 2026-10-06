#pragma once
#include "Renderer.hpp"
#include <DirectXMath.h>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace omc::renderer {
struct CameraProjection {
    float viewProj[16]{}; // Row-major, matching WorldVS mul(row_position, vp).
    double origin[3]{};
};
// Used by the production renderer and its projection/GPU tests. Minecraft's
// forward is (-sin(yaw)*cos(pitch), -sin(pitch), cos(yaw)*cos(pitch)),
// right is (-cos(yaw),0,-sin(yaw)); RE/MC XYZ share that basis without mirroring.
inline CameraProjection make_camera_projection(const skycraft::proto::McState& mc,const CameraState& supplied,unsigned width,unsigned height){
    CameraProjection out;
    if(supplied.valid){
        std::copy(supplied.origin,supplied.origin+3,out.origin);
        for(int r=0;r<4;++r)for(int c=0;c<4;++c)out.viewProj[r*4+c]=supplied.viewProj[c*4+r];
        return out;
    }
    using namespace DirectX;
    const float yaw=XMConvertToRadians(mc.yaw),pitch=XMConvertToRadians(mc.pitch);
    const float sy=std::sin(yaw),cy=std::cos(yaw),sp=std::sin(pitch),cp=std::cos(pitch);
    XMVECTOR forward=XMVectorSet(-sy*cp,-sp,cy*cp,0);
    // Minecraft's yaw/pitch up vector remains non-collinear even at +/-90 pitch,
    // unlike a fixed world-up vector, which would become singular at the poles.
    const XMVECTOR up=XMVectorSet(-sy*sp,cp,cy*sp,0);
    XMFLOAT3 f;XMStoreFloat3(&f,forward);
    out.origin[0]=mc.eyeX;out.origin[1]=mc.eyeY;out.origin[2]=mc.eyeZ;
    if(mc.cameraMode!=0){
        const double sign=mc.cameraMode==2?1.0:-1.0;
        const double distance=std::clamp(double(mc.cameraDistance),0.0,32.0);
        out.origin[0]+=f.x*distance*sign;out.origin[1]+=f.y*distance*sign;out.origin[2]+=f.z*distance*sign;
        if(mc.cameraMode==2)forward=XMVectorNegate(forward);
    }
    const auto view=XMMatrixLookToRH(XMVectorZero(),forward,up);
    const auto projection=XMMatrixPerspectiveFovRH(XMConvertToRadians(std::clamp(mc.fovDeg,20.0f,160.0f)),float(std::max(width,1u))/float(std::max(height,1u)),0.03f,2048.0f);
    XMFLOAT4X4 vp;XMStoreFloat4x4(&vp,view*projection);std::memcpy(out.viewProj,&vp,sizeof(vp));
    return out;
}
}
