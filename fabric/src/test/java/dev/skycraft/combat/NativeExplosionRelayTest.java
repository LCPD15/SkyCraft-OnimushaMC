package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class NativeExplosionRelayTest {
	@Test void nestedUnforwardedExplosionKeepsItsOwnLocalDamage() {
		assertFalse(NativeExplosionRelay.forwarded());
		try (var outer = NativeExplosionRelay.scope(true)) {
			assertTrue(NativeExplosionRelay.forwarded());
			try (var inner = NativeExplosionRelay.scope(false)) {
				assertFalse(NativeExplosionRelay.forwarded());
			}
			assertTrue(NativeExplosionRelay.forwarded());
		}
		assertFalse(NativeExplosionRelay.forwarded());
	}

	@Test void exceptionCannotSuppressLaterUnrelatedHits() {
		assertThrows(IllegalArgumentException.class, () -> {
			try (var ignored = NativeExplosionRelay.scope(true)) { throw new IllegalArgumentException(); }
		});
		assertFalse(NativeExplosionRelay.forwarded());
	}

	@Test void failedQueueLeavesLocalDamageAndRepeatedCloseIsSafe() {
		var scope = NativeExplosionRelay.scope(false);
		assertFalse(NativeExplosionRelay.forwarded());
		scope.close(); scope.close();
		assertFalse(NativeExplosionRelay.forwarded());
	}
}
