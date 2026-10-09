package dev.skycraft.client.mixin;
import dev.skycraft.client.InputBridge;
import net.minecraft.client.KeyboardHandler;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(KeyboardHandler.class)
public abstract class KeyboardReplayMixin {
    @Inject(method={"keyPress", "textInput"}, at=@At("HEAD"), cancellable=true)
    private void onimusha$hostOwnsKeys(CallbackInfo ci) {
        if (InputBridge.rejectLocalInput()) ci.cancel();
    }
}
