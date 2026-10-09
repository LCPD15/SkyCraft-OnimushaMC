package dev.skycraft.client;

import com.mojang.blaze3d.pipeline.RenderTarget;
import com.mojang.blaze3d.pipeline.TextureTarget;
import com.mojang.blaze3d.systems.RenderSystem;
import dev.skycraft.client.mixin.GameRendererPreviewAccess;
import net.minecraft.client.Minecraft;
import org.joml.Vector4f;

/** Keep the visible MC world separate from the transparent overlay sent to the native game. */
public final class LocalWindowPreview {
    private static final boolean SHOW = Boolean.getBoolean("skycraft.showWindow");
    private static RenderTarget world, overlay;
    private static boolean active, saved, nativeHands, overlayPass;
    public static long frames;

    private LocalWindowPreview() {}
    public static boolean active() { return active; }
    public static boolean overlayPass() { return overlayPass; }
    public static boolean nativeHands() { return nativeHands; }
    public static void nativeHands(boolean suppressed) { nativeHands = suppressed; }

    public static void begin() {
        active = SHOW && SkyClient.linked() && Minecraft.getInstance().level != null;
        saved = nativeHands = overlayPass = false;
    }

    /** Split after world post-processing: entity-outline/post effects must not fill our overlay. */
    public static void saveWorld() {
        if (!active) return;
        var main = Minecraft.getInstance().gameRenderer.mainRenderTarget();
        if (world == null || world.width != main.width || world.height != main.height
                || world.getColorTexture().getFormat() != main.getColorTexture().getFormat()) {
            if (world != null) { world.destroyBuffers(); overlay.destroyBuffers(); }
            world = new TextureTarget("Onimusha MC local world", main.width, main.height,
                main.getColorTexture().getFormat(), null);
            overlay = new TextureTarget("Onimusha MC local overlay", main.width, main.height,
                main.getColorTexture().getFormat(), null);
        }
        world.copyColorFrom(main);
        RenderSystem.getDevice().createCommandEncoder().clearColorAndDepthTextures(
            // JOML's no-argument Vector4f has w=1, which would cover the world with black.
            main.getColorTexture(), new Vector4f(0f, 0f, 0f, 0f), main.getDepthTexture(), 0.0);
        overlayPass = true;
        var renderer = Minecraft.getInstance().gameRenderer;
        var state = renderer.gameRenderState();
        ((GameRendererPreviewAccess)renderer).onimusha$render3dHud(
            state.levelRenderState.cameraRenderState, state.levelRenderState.playerRenderState,
            state.optionsRenderState, false);
        saved = true;
    }

    /** Runs only after FrameExporter queues the clean overlay copy. Never publishes the preview. */
    public static void present(Minecraft minecraft) {
        if (!active || !saved) return;
        var renderer = minecraft.gameRenderer;
        var main = renderer.mainRenderTarget();
        overlay.copyColorFrom(main);
        main.copyColorFrom(world);
        overlay.blitAndBlendToTexture(main.getColorTextureView(), main.getDepthTextureView());
        saved = false;
        frames++;
    }
}
