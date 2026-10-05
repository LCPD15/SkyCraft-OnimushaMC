package dev.skycraft.combat;

/** Pure policy for the native game's authoritative HP and the fixed ten-heart Minecraft HUD. */
public final class HostHealthMath {
	public static final float MC_MAX_HEALTH = 20.0F;
	private HostHealthMath() {}

	/** A host restart may reuse epoch one; an epoch alone is not a session identity. */
	public static boolean sameSession(int capturedGeneration, int capturedEpoch, int currentGeneration, int currentEpoch) {
		return capturedGeneration == currentGeneration && capturedEpoch == currentEpoch;
	}

	public static boolean valid(float current, float maximum) {
		return Float.isFinite(current) && Float.isFinite(maximum) && maximum > 0.0F;
	}

	/** Negative native HP is dead; over-healing never grows Minecraft's ten-heart display. */
	public static float minecraftHealth(float current, float maximum) {
		if (!valid(current, maximum)) {
			throw new IllegalArgumentException("Native HP must be finite and its maximum positive");
		}
		return Math.clamp(current / maximum, 0.0F, 1.0F) * MC_MAX_HEALTH;
	}

	/** Signed MC health points -> signed fraction of native max HP; zero is never a request. */
	public static float requestedFraction(float before, float requested, boolean explicitHealing) {
		if (!Float.isFinite(before) || !Float.isFinite(requested)) {
			return 0.0F;
		}
		float delta = Math.clamp(requested, 0.0F, MC_MAX_HEALTH) - Math.clamp(before, 0.0F, MC_MAX_HEALTH);
		// Loading NBT, respawn and automatic health resets must not heal the host.
		if (delta > 0.0F && !explicitHealing) {
			return 0.0F;
		}
		return delta / MC_MAX_HEALTH;
	}
}
