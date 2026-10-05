package dev.skycraft.combat;

import dev.skycraft.link.Proto;
import dev.skycraft.link.SkyLink;
import java.util.UUID;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;

/**
 * Onimusha owns HP, death and respawn. MC runs armour/shield/environment damage, then requests a
 * percentage change instead of owning a second health pool. Only confirmed native state changes
 * the heart display; a lost/full event ring can never accidentally resurrect or heal Onimusha.
 */
public final class HostHealth {
	private record Snapshot(float hearts, int generation, int epoch, boolean dead, boolean playable) {}
	private static volatile Snapshot snapshot;
	private static volatile UUID owner;
	private static final ThreadLocal<Boolean> SYNCING = ThreadLocal.withInitial(() -> false);
	private static final ThreadLocal<Boolean> HEALING = ThreadLocal.withInitial(() -> false);
	private HostHealth() {}

	public static void init() {
		ServerTickEvents.END_SERVER_TICK.register(HostHealth::tick);
	}

	public static boolean mirrored(Entity entity) {
		return owner != null && owner.equals(entity.getUUID()) && SkyLink.active();
	}

	public static boolean intercepts(ServerPlayer player) {
		return mirrored(player) && !SYNCING.get();
	}

	public static void beginHealing() { HEALING.set(true); }
	public static void endHealing() { HEALING.set(false); }

	/** Reject work queued before a native load/restart, even if the restarted host reuses an epoch. */
	public static boolean currentSession(int generation, int epoch) {
		Snapshot state = snapshot;
		if (state == null || !state.playable || state.dead || !SkyLink.active()
			|| !HostHealthMath.sameSession(generation, epoch, state.generation, state.epoch)) {
			return false;
		}
		SkyLink.SkyState host = new SkyLink.SkyState();
		return SkyLink.readSkyState(host) && host.authoritativeHealth() && host.inGame()
			&& !host.loading() && !host.menuOpen() && !host.hostDead()
			&& HostHealthMath.valid(host.healthCurrent, host.healthMax) && host.healthCurrent > 0
			&& HostHealthMath.sameSession(generation, epoch, SkyLink.generation(), host.collisionEpoch);
	}

	/** Called at the final health mutation, after MC shields, armour and invulnerability ran. */
	public static void request(ServerPlayer player, float requestedHealth) {
		Snapshot state = snapshot;
		if (state == null || !currentSession(state.generation, state.epoch)) {
			return;
		}
		float fraction = HostHealthMath.requestedFraction(player.getHealth(), requestedHealth, HEALING.get());
		if (fraction != 0.0F) {
			SkyLink.pushEvent(Proto.EV_HEALTH_CHANGE, 0, fraction, fraction * HostHealthMath.MC_MAX_HEALTH,
				0, 0, fraction < 0 ? Proto.HEALTH_DAMAGE : Proto.HEALTH_HEAL, state.epoch);
		}
	}

	private static void tick(MinecraftServer server) {
		if (!SkyLink.active()) {
			snapshot = null;
			return;
		}
		SkyLink.SkyState host = new SkyLink.SkyState();
		if (!SkyLink.readSkyState(host) || !host.authoritativeHealth()
			|| !HostHealthMath.valid(host.healthCurrent, host.healthMax)) {
			snapshot = null;
			return;
		}
		for (ServerPlayer player : server.getPlayerList().getPlayers()) {
			if (!dev.skycraft.net.SkyNet.isHost(player)) {
				continue;
			}
			owner = player.getUUID();
			float health = HostHealthMath.minecraftHealth(host.healthCurrent, host.healthMax);
			snapshot = new Snapshot(health, SkyLink.generation(), host.collisionEpoch, host.hostDead() || health == 0,
				host.inGame() && !host.loading() && !host.menuOpen());
			SYNCING.set(true);
			try {
				player.setHealth(health);
			} finally {
				SYNCING.set(false);
			}
		}
	}
}
