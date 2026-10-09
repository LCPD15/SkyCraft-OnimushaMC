package dev.skycraft.link;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** One render-ring message: no independently advancing camera/body/hand origin. */
public final class RenderPoseFrame {
    private RenderPoseFrame() {}
    public static boolean ready(SkyLink.McState s) {
        return s.frameCounter>0 && (s.flags&Proto.MC_IN_WORLD)!=0 && s.cameraMode>=0 && s.cameraMode<=2
            && Double.isFinite(s.x) && Double.isFinite(s.y) && Double.isFinite(s.z)
            && Math.abs(s.x)<=30_000_000 && Math.abs(s.y)<=30_000_000 && Math.abs(s.z)<=30_000_000
            && Double.isFinite(s.eyeX) && Double.isFinite(s.eyeY) && Double.isFinite(s.eyeZ)
            && Float.isFinite(s.yaw) && Float.isFinite(s.pitch) && Float.isFinite(s.fov) && s.fov>0 && s.fov<180
            && Float.isFinite(s.cameraDistance) && s.cameraDistance>=0 && s.cameraDistance<=128;
    }
    public static ByteBuffer header(SkyLink.McState s, int world, int epoch, int pid, int avatar, int scene, int hands) {
        if (avatar < 8 || scene < 32 || hands < 32 || (long) avatar + scene + hands > 8 * 1024 * 1024)
            throw new IllegalArgumentException("Invalid render pose sizes");
        ByteBuffer b=ByteBuffer.allocate(232).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(1).putInt(world).putInt(epoch).putInt(pid).putInt(avatar).putInt(scene).putInt(hands).putInt(0);
        int o=32;
        b.putInt(o+4,s.flags);b.putDouble(o+8,s.x);b.putDouble(o+16,s.y);b.putDouble(o+24,s.z);
        b.putFloat(o+32,s.yaw);b.putFloat(o+36,s.pitch);b.putFloat(o+40,s.eyeHeight);b.putFloat(o+44,s.sensitivity);
        b.putInt(o+48,s.teleportAck);b.putInt(o+52,s.guiScale);b.putLong(o+56,s.frameCounter);
        b.putFloat(o+64,s.fov);b.putFloat(o+68,s.bobPhase);b.putFloat(o+72,s.bobAmount);
        b.putDouble(o+80,s.eyeX);b.putDouble(o+88,s.eyeY);b.putDouble(o+96,s.eyeZ);
        b.putLong(o+104,s.tickQpc);
        b.putDouble(o+112,s.prevX);b.putDouble(o+120,s.prevY);b.putDouble(o+128,s.prevZ);
        b.putDouble(o+136,s.curX);b.putDouble(o+144,s.curY);b.putDouble(o+152,s.curZ);
        b.putFloat(o+160,s.eyeHeightO);b.putFloat(o+164,s.eyeHeightT);
        b.putFloat(o+168,s.walkDistO);b.putFloat(o+172,s.walkDist);b.putFloat(o+176,s.bobO);b.putFloat(o+180,s.bob);
        b.putFloat(o+184,s.tickMs);b.putInt(o+192,s.cameraMode);b.putFloat(o+196,s.cameraDistance);
        return b.position(0).limit(232);
    }
}
