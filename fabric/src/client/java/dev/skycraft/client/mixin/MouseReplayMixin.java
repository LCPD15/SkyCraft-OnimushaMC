package dev.skycraft.client.mixin;
import dev.skycraft.client.InputBridge;
import net.minecraft.client.MouseHandler;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Native host and SDL must not both feed the virtual controls when the preview is visible. */
@Mixin(MouseHandler.class)
public abstract class MouseReplayMixin {
    @Inject(method={"onButton", "onMove", "onScroll"}, at=@At("HEAD"), cancellable=true)
    private void onimusha$hostOwnsMouse(CallbackInfo ci) {
        if (InputBridge.rejectLocalInput()) ci.cancel();
    }
}
