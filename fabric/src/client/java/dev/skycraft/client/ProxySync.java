package dev.skycraft.client;

import dev.skycraft.combat.SkyrimActorEntity;
import dev.skycraft.combat.ActorProxyIdentity;
import dev.skycraft.link.SkyLink;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import net.minecraft.client.Minecraft;
import net.minecraft.world.entity.Entity;

/**
 * Puts the client's copies of the Skyrim actor stand-ins exactly where Skyrim has the actors this
 * frame, so the crosshair and melee reach line up with what's on screen (the server copy only
 * moves once per tick and reaches the client a tick or two later).
 */
final class ProxySync {
	private static final List<SkyLink.Actor> ACTORS = new ArrayList<>();
	private static final Map<Integer, SkyLink.Actor> BY_ID = new HashMap<>();
	private static final SkyLink.SkyState HOST = new SkyLink.SkyState();

	private ProxySync() {
	}

	static void frame(Minecraft minecraft) {
		if (minecraft.level == null || !SkyLink.active()) {
			return;
		}
		int generation = SkyLink.generation();
		if (!SkyLink.readSkyState(HOST) || generation != SkyLink.generation()) return;
		var session = new ActorProxyIdentity.Session(generation, HOST.collisionEpoch);
		if (!SkyLink.readActors(ACTORS) || !SkyLink.readSkyState(HOST)
			|| !session.matches(SkyLink.generation(), HOST.collisionEpoch)) return;
		BY_ID.clear();
		for (SkyLink.Actor a : ACTORS) {
			BY_ID.put(a.formId(), a);
		}
		List<Entity> stale = new ArrayList<>();
		for (Entity entity : minecraft.level.entitiesForRendering()) {
			if (entity instanceof SkyrimActorEntity proxy) {
				// Do not delete a newly spawned server copy before its initial metadata arrives.
				if (!proxy.hasHostSession()) continue;
				if (!proxy.belongsTo(session)) {
					stale.add(proxy);
					continue;
				}
				SkyLink.Actor a = BY_ID.get(proxy.formId());
				if (a == null) {
					continue;
				}
				proxy.refreshHostName(a.name());
				proxy.setSize(a.width(), a.height());
				proxy.setPos(a.x(), a.y(), a.z());
				proxy.xo = a.x();
				proxy.yo = a.y();
				proxy.zo = a.z();
				proxy.setYRot(a.yaw());
				proxy.yRotO = a.yaw();
			}
		}
		stale.forEach(Entity::discard);
	}
}
