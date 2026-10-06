package dev.skycraft.mixin;

import dev.skycraft.combat.OnimushaSwordGuard;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.Level;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Item.class)
public abstract class OnimushaSwordGuardMixin {
	@Inject(method = "use", at = @At("HEAD"), cancellable = true)
	private void onimusha$offhandPriority(Level level, Player player, InteractionHand hand,
		CallbackInfoReturnable<InteractionResult> cir) {
		if (OnimushaSwordGuard.yieldToOffhand(player, hand)) cir.setReturnValue(InteractionResult.PASS);
	}
}
