package dev.skycraft.client.mixin;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.client.renderer.state.level.PlayerRenderState;
import net.minecraft.client.renderer.state.OptionsRenderState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

@Mixin(GameRenderer.class)
public interface GameRendererPreviewAccess {
    @Invoker("render3dHud")
    void onimusha$render3dHud(CameraRenderState camera, PlayerRenderState player, OptionsRenderState options, boolean separateTarget);
}
