package dev.skycraft.combat;

/** Scoped observations of one real vanilla hurtServer call, never a decision to cancel damage. */
public final class GuardObservation {
	private static final ThreadLocal<Scope> CURRENT = new ThreadLocal<>();
	private GuardObservation() {}

	public static Scope capture(Object defender, boolean nativeHealth) {
		Scope scope = new Scope(defender, CURRENT.get(), nativeHealth);
		CURRENT.set(scope);
		return scope;
	}

	public static void blockingApplied(Object defender, float incoming, float blocked) {
		Scope scope = CURRENT.get();
		if (scope == null || !scope.capturing || scope.defender != defender || scope.closed) return;
		scope.blockingCalls++;
		if (Float.isFinite(incoming) && incoming > 0 && Float.isFinite(blocked)) {
			scope.blocked += Math.clamp(blocked, 0, incoming);
		}
	}

	/** Called by the real vanilla sound callback. True once per genuinely blocked controlled hit. */
	public static boolean vanillaFeedback(Object defender) {
		Scope scope = CURRENT.get();
		if (scope == null || !scope.capturing || scope.defender != defender || scope.closed || scope.blocked <= 0 || scope.vanillaFeedback) return false;
		scope.vanillaFeedback = true;
		return true;
	}

	public static final class Scope implements AutoCloseable {
		private final Object defender;
		private final Scope previous;
		private final boolean capturing;
		private boolean closed;
		private float blocked;
		private boolean vanillaFeedback;
		private int blockingCalls;
		private Scope(Object defender, Scope previous, boolean capturing) {
			this.defender = defender;
			this.previous = previous;
			this.capturing = capturing;
		}
		public float blocked() { return blocked; }
		public boolean vanillaFeedback() { return vanillaFeedback; }
		public int blockingCalls() { return blockingCalls; }
		@Override public void close() {
			if (closed) return;
			closed = true;
			if (previous == null) CURRENT.remove();
			else CURRENT.set(previous);
		}
	}
}
