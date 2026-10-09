package dev.skycraft.client.mixin;

import dev.skycraft.client.SkyClient;
import net.minecraft.client.gui.Gui;
import net.minecraft.client.gui.screens.DeathScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.player.LocalPlayer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Native menus own death/reload; MC must not open a competing Respawn button or save selection. */
@Mixin(Gui.class)
public abstract class HostDeathScreenMixin {
	@Inject(method = "setScreen", at = @At("HEAD"), cancellable = true)
	private void onimusha$nativeDeathMenu(Screen screen, CallbackInfo ci) {
		if (screen instanceof DeathScreen && SkyClient.nativeOwnsDeath()) {
			ci.cancel();
		}
	}

	// 26.3 also constructs DeathScreen *inside* setScreen(null). HEAD's argument check misses it.
	@Redirect(method = "setScreen", at = @At(value = "INVOKE",
		target = "Lnet/minecraft/client/player/LocalPlayer;isDeadOrDying()Z"))
	private boolean onimusha$skipImplicitDeathScreen(LocalPlayer player) {
		return !SkyClient.nativeOwnsDeath() && player.isDeadOrDying();
	}
}
