package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class GuardObservationTest {
	@Test
	void onlyActualReductionAndVanillaCallbackProduceOneFeedback() {
		Object player = new Object();
		try (var scope = GuardObservation.capture(player, true)) {
			assertFalse(GuardObservation.vanillaFeedback(player));
			GuardObservation.blockingApplied(player, 7.08F, 7.08F);
			assertEquals(7.08F, scope.blocked());
			assertTrue(GuardObservation.vanillaFeedback(player));
			assertFalse(GuardObservation.vanillaFeedback(player));
			assertEquals(1, scope.blockingCalls());
			assertTrue(scope.vanillaFeedback());
		}
		assertFalse(GuardObservation.vanillaFeedback(player));
	}

	@Test
	void zeroReductionImmuneAndOtherDefendersDoNotProduceBlockFeedback() {
		Object player = new Object(), other = new Object();
		try (var scope = GuardObservation.capture(player, true)) {
			GuardObservation.blockingApplied(other, 3, 3);
			GuardObservation.blockingApplied(player, 3, 0);
			assertEquals(0, scope.blocked());
			assertEquals(1, scope.blockingCalls());
			assertFalse(GuardObservation.vanillaFeedback(player));
		}
	}

	@Test
	void nonNativeNestedCallCannotContaminateNativeHitAndOuterScopeResumes() {
		Object player = new Object();
		try (var outer = GuardObservation.capture(player, true)) {
			try (var ordinary = GuardObservation.capture(player, false)) {
				GuardObservation.blockingApplied(player, 3, 3);
				assertFalse(GuardObservation.vanillaFeedback(player));
				assertEquals(0, ordinary.blocked());
			}
			assertEquals(0, outer.blocked());
			GuardObservation.blockingApplied(player, 3, 1.5F);
			assertEquals(1.5F, outer.blocked());
			assertTrue(GuardObservation.vanillaFeedback(player));
		}
	}

	@Test
	void exceptionClearsScopeAndNextHitDoesNotInheritAPreviousBlock() {
		Object player = new Object();
		assertThrows(IllegalStateException.class, () -> {
			try (var scope = GuardObservation.capture(player, true)) {
				GuardObservation.blockingApplied(player, 3, 3);
				throw new IllegalStateException("hurtServer failed");
			}
		});
		assertFalse(GuardObservation.vanillaFeedback(player));
		try (var next = GuardObservation.capture(player, true)) {
			assertEquals(0, next.blocked());
			assertFalse(GuardObservation.vanillaFeedback(player));
		}
	}
}
