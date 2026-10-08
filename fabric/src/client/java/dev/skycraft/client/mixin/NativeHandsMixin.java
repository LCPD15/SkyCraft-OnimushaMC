package dev.skycraft.client.mixin;
import com.mojang.blaze3d.vertex.PoseStack;
import dev.skycraft.client.render.AvatarExporter;
import net.minecraft.client.renderer.FirstPersonHandsAndItemsRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.SubmitNodeCollector;
import net.minecraft.client.renderer.state.level.FirstPersonHandsAndItemsRenderState;
import net.minecraft.client.renderer.state.level.PlayerRenderState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;
@Mixin(GameRenderer.class)
public abstract class NativeHandsMixin {
    @Redirect(method="renderItemInHand",at=@At(value="INVOKE",target="Lnet/minecraft/client/renderer/FirstPersonHandsAndItemsRenderer;submitHandsWithItems(FLcom/mojang/blaze3d/vertex/PoseStack;Lnet/minecraft/client/renderer/SubmitNodeCollector;Lnet/minecraft/client/renderer/state/level/PlayerRenderState;Lnet/minecraft/client/renderer/state/level/FirstPersonHandsAndItemsRenderState;)V"))
    private void onimusha$hands(FirstPersonHandsAndItemsRenderer renderer,float partial,PoseStack pose,
        SubmitNodeCollector collector,PlayerRenderState player,FirstPersonHandsAndItemsRenderState hands) {
        if(!AvatarExporter.captureHands(renderer,partial,pose,player,hands)) renderer.submitHandsWithItems(partial,pose,collector,player,hands);
    }
}
