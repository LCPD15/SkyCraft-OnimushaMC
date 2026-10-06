package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;

import net.minecraft.SharedConstants;
import net.minecraft.core.Holder;
import net.minecraft.core.component.DataComponentMap;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.damagesource.DamageType;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.ItemUseAnimation;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.component.BlocksAttacks;
import net.minecraft.world.phys.Vec3;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

/** Uses the installed MC implementations/components, rather than duplicating shield angle math. */
class OnimushaSwordGuardTest {
	@BeforeAll
	static void bootstrapVanilla() {
		SharedConstants.tryDetectVersion();
		Bootstrap.bootStrap();
		// 26.3 separates registry bootstrap from binding the default component initializers.
		var registries = VanillaRegistries.createWorldLookup();
		BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(registries).forEach(pending -> pending.apply());
	}

	@Test
	void optInIsExplicitAndDisabledByDefault() {
		String previous = System.getProperty(OnimushaSwordGuard.PROPERTY);
		try {
			System.clearProperty(OnimushaSwordGuard.PROPERTY);
			assertFalse(OnimushaSwordGuard.enabled());
			System.setProperty(OnimushaSwordGuard.PROPERTY, "true");
			assertTrue(OnimushaSwordGuard.enabled());
		} finally {
			if (previous == null) System.clearProperty(OnimushaSwordGuard.PROPERTY);
			else System.setProperty(OnimushaSwordGuard.PROPERTY, previous);
		}
	}

	@Test
	void sevenRealSwordsGainVanillaBlockAnimationWithoutReplacingWeaponComponents() {
		assertEquals(7, OnimushaSwordGuard.swords().size());
		for (var sword : OnimushaSwordGuard.swords()) {
			assertNull(sword.components().get(DataComponents.BLOCKS_ATTACKS));
			var builder = DataComponentMap.builder().addAll(sword.components());
			OnimushaSwordGuard.addMissingBlocking(builder);
			var components = builder.build();
			assertSame(sword.components().get(DataComponents.WEAPON), components.get(DataComponents.WEAPON));
			assertSame(sword.components().get(DataComponents.TOOL), components.get(DataComponents.TOOL));
			ItemStack stack = new ItemStack(sword);
			stack.set(DataComponents.BLOCKS_ATTACKS, components.get(DataComponents.BLOCKS_ATTACKS));
			assertEquals(ItemUseAnimation.BLOCK, sword.getUseAnimation(stack));
			assertEquals(72000, sword.getUseDuration(stack, null));
			assertEquals(5, stack.get(DataComponents.BLOCKS_ATTACKS).blockDelayTicks());
		}
	}

	@Test
	void existingCustomGuardComponentIsPreserved() {
		var shield = OnimushaSwordGuard.defaultBlocking();
		var custom = new BlocksAttacks(0.75F, shield.disableCooldownScale(), shield.damageReductions(),
			shield.itemDamage(), shield.bypassedBy(), shield.blockSound(), shield.disableSound());
		var builder = DataComponentMap.builder().addAll(Items.IRON_SWORD.components())
			.set(DataComponents.BLOCKS_ATTACKS, custom);
		OnimushaSwordGuard.addMissingBlocking(builder);
		assertSame(custom, builder.build().get(DataComponents.BLOCKS_ATTACKS));
		assertEquals(15, custom.blockDelayTicks());
	}

	@Test
	void actualShieldReductionFullyBlocksFrontButNotRear() {
		var block = OnimushaSwordGuard.defaultBlocking();
		var type = Holder.direct(new DamageType("guard-test", 0.1F));
		var directional = new DamageSource(type, new Vec3(0, 0, 3));
		assertEquals(3, directional.getSourcePosition().z);
		assertNull(new DamageSource(type).getSourcePosition());
		assertEquals(7.08F, block.resolveBlockedDamage(directional, 7.08F, 0), 1.0E-5);
		assertEquals(7.08F, block.resolveBlockedDamage(directional, 7.08F, Math.toRadians(89)), 1.0E-5);
		assertEquals(0, block.resolveBlockedDamage(directional, 7.08F, Math.toRadians(91)));
		assertEquals(0, block.resolveBlockedDamage(directional, 7.08F, Math.PI));
		assertTrue(block.bypassedBy().isPresent());
		assertTrue(block.blockSound().isPresent());
	}

	@Test
	void offhandShieldAndUsableFoodHavePriorityButFullHungerFoodDoesNot() {
		assertTrue(OnimushaSwordGuard.preferOffhand(InteractionHand.MAIN_HAND, true, true, false));
		assertTrue(OnimushaSwordGuard.preferOffhand(InteractionHand.MAIN_HAND, true, false, true));
		assertFalse(OnimushaSwordGuard.preferOffhand(InteractionHand.MAIN_HAND, true, false, false));
		assertFalse(OnimushaSwordGuard.preferOffhand(InteractionHand.OFF_HAND, true, true, true));
		assertFalse(OnimushaSwordGuard.preferOffhand(InteractionHand.MAIN_HAND, false, true, true));
	}
}
