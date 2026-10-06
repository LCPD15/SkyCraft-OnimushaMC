package dev.skycraft.combat;

import java.util.List;
import java.util.Objects;
import net.fabricmc.fabric.api.item.v1.DefaultItemComponentEvents;
import net.minecraft.core.component.DataComponentMap;
import net.minecraft.core.component.DataComponents;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.component.BlocksAttacks;

/** Optional Onimusha sword guard. Vanilla handles use animation, delay, direction and durability. */
public final class OnimushaSwordGuard {
	public static final String PROPERTY = "onimusha.swordBlocking";
	private OnimushaSwordGuard() {}

	public static boolean enabled() {
		return Boolean.getBoolean(PROPERTY);
	}

	public static List<Item> swords() {
		return List.of(Items.WOODEN_SWORD, Items.COPPER_SWORD, Items.STONE_SWORD, Items.GOLDEN_SWORD,
			Items.IRON_SWORD, Items.DIAMOND_SWORD, Items.NETHERITE_SWORD);
	}

	public static void init() {
		if (!enabled()) return;
		DefaultItemComponentEvents.MODIFY.register(context -> context.modify(swords(),
			(components, item) -> addMissingBlocking(components)));
	}

	/** Read the installed version's actual default shield rules; never replace custom guard rules. */
	public static void addMissingBlocking(DataComponentMap.Builder components) {
		if (!components.build().has(DataComponents.BLOCKS_ATTACKS)) {
			components.set(DataComponents.BLOCKS_ATTACKS, defaultBlocking());
		}
	}

	public static BlocksAttacks defaultBlocking() {
		return Objects.requireNonNull(Items.SHIELD.components().get(DataComponents.BLOCKS_ATTACKS));
	}

	public static boolean addedSwordGuard(ItemStack stack) {
		return enabled() && swords().contains(stack.getItem())
			&& !stack.hasNonDefault(DataComponents.BLOCKS_ATTACKS)
			&& defaultBlocking().equals(stack.get(DataComponents.BLOCKS_ATTACKS));
	}

	/** Do not invoke offhand use to probe it: that would consume items or send a second action. */
	public static boolean yieldToOffhand(Player player, InteractionHand hand) {
		if (hand != InteractionHand.MAIN_HAND || !addedSwordGuard(player.getMainHandItem())) return false;
		ItemStack offhand = player.getOffhandItem();
		boolean ready = !offhand.isEmpty() && !player.getCooldowns().isOnCooldown(offhand);
		boolean shield = ready && offhand.is(Items.SHIELD) && offhand.has(DataComponents.BLOCKS_ATTACKS);
		var consumable = offhand.get(DataComponents.CONSUMABLE);
		boolean canConsume = ready && consumable != null && consumable.canConsume(player, offhand);
		return preferOffhand(hand, true, shield, canConsume);
	}

	/** Only confirmed shield/consumable use is prioritised; unknown item actions remain vanilla. */
	public static boolean preferOffhand(InteractionHand hand, boolean addedSwordGuard, boolean shieldReady, boolean canConsume) {
		return hand == InteractionHand.MAIN_HAND && addedSwordGuard && (shieldReady || canConsume);
	}
}
