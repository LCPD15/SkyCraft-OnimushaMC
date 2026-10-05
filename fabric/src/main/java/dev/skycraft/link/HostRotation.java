package dev.skycraft.link;

import java.util.Objects;

/** One host-owned view reset on teleport; ordinary MC look remains owned by its mouse. */
public final class HostRotation {
	public record Angles(float yaw, float pitch) {}

	private HostRotation() {}

	public static Angles resolve(Angles current, float hostYaw, float hostPitch, boolean teleport, boolean mcLook) {
		Objects.requireNonNull(current);
		if (!teleport && mcLook) {
			return current;
		}
		// Defend the client from a malformed host view without poisoning vanilla camera math.
		float yaw = Float.isFinite(hostYaw) ? hostYaw % 360.0F : 0.0F;
		if (yaw >= 180.0F) yaw -= 360.0F;
		if (yaw < -180.0F) yaw += 360.0F;
		float pitch = Float.isFinite(hostPitch) ? Math.clamp(hostPitch, -90.0F, 90.0F) : 0.0F;
		return new Angles(yaw, pitch);
	}
}
