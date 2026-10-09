package dev.skycraft.client.mixin;
import dev.skycraft.client.LocalWindowPreview;
import net.minecraft.client.renderer.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GameRenderer.class)
public abstract class GameRendererPreviewMixin {
    @Inject(method="render", at=@At("HEAD"))
    private void onimusha$beginPreview(CallbackInfo ci) { LocalWindowPreview.begin(); }

    @Inject(method="render", at=@At(value="INVOKE", target="Lnet/minecraft/client/renderer/GameRenderer;applyPostEffects()V", shift=At.Shift.AFTER))
    private void onimusha$savePreviewWorld(CallbackInfo ci) { LocalWindowPreview.saveWorld(); }
}
