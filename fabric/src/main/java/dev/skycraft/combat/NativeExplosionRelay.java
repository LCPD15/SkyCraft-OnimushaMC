package dev.skycraft.combat;

import dev.skycraft.link.Proto;
import dev.skycraft.link.SkyLink;
import java.util.ArrayDeque;
import java.util.concurrent.atomic.AtomicInteger;
import net.minecraft.world.level.ServerExplosion;

/** One request per MC explosion, not one request per victim. No per-item explosion tables. */
public final class NativeExplosionRelay {
	private static final AtomicInteger IDS = new AtomicInteger((int)(System.currentTimeMillis() & 0x7fffffff));
	private static final ThreadLocal<ArrayDeque<Scope>> STACK = ThreadLocal.withInitial(ArrayDeque::new);
	private NativeExplosionRelay() {}

	public static Scope begin(ServerExplosion explosion) {
		boolean sent = false;
		SkyLink.SkyState host = new SkyLink.SkyState();
		if (SkyLink.active() && SkyLink.readSkyState(host)
			&& (host.flags & Proto.SKY_NATIVE_EXPLOSIONS) != 0
			&& HostHealth.currentSession(SkyLink.generation(), host.collisionEpoch)) {
			var p = explosion.center();
			float radius = explosion.radius();
			if (Double.isFinite(p.x) && Double.isFinite(p.y) && Double.isFinite(p.z)
				&& Float.isFinite(radius) && radius > 0 && radius <= 32
				&& p.distanceToSqr(host.x, host.y, host.z) <= 128 * 128) {
				int id = IDS.updateAndGet(old -> old == Integer.MAX_VALUE ? 1 : old + 1);
				sent = SkyLink.tryPushEvent(Proto.EV_EXPLOSION, id, (float)p.x, (float)p.y, (float)p.z,
					radius, 1, host.collisionEpoch);
				dev.skycraft.SkyCraft.LOG.info("Onimusha native explosion {} epoch {} queued={} at {} radius {}",
					id, host.collisionEpoch, sent, p, radius);
			}
		}
		return scope(sent);
	}

	public static boolean forwarded() {
		return !STACK.get().isEmpty() && STACK.get().peek().forwarded;
	}

	static Scope scope(boolean forwarded) {
		Scope scope = new Scope(forwarded);
		STACK.get().push(scope);
		return scope;
	}

	public static final class Scope implements AutoCloseable {
		private final boolean forwarded;
		private boolean closed;
		private Scope(boolean forwarded) { this.forwarded = forwarded; }
		@Override public void close() {
			if (closed) return;
			var stack = STACK.get();
			if (stack.peek() != this) throw new IllegalStateException("Explosion scopes closed out of order");
			stack.pop(); closed = true;
			if (stack.isEmpty()) STACK.remove();
		}
	}
}
