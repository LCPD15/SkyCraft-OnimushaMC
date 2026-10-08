package dev.skycraft.client.mixin;

import dev.skycraft.client.TntFuseAudio;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.client.sounds.SoundEngine;
import net.minecraft.client.sounds.SoundManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(SoundManager.class)
public abstract class TntFuseSoundMixin {
    @Inject(method="play", at=@At("HEAD"), cancellable=true)
    private void onimusha$fuse(SoundInstance sound, CallbackInfoReturnable<SoundEngine.PlayResult> cir) {
        if (TntFuseAudio.replaces(sound)) cir.setReturnValue(SoundEngine.PlayResult.NOT_STARTED);
    }
}
