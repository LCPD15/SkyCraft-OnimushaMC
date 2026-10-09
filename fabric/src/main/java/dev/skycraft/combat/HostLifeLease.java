package dev.skycraft.combat;

/** Life ownership lasts for the MC player/world/session, not a transient native readiness flag. */
public final class HostLifeLease {
	private Object player, level, server;
	private boolean owned;

	public boolean update(Object currentPlayer, Object currentLevel, Object currentServer, boolean claim) {
		if (player != currentPlayer || level != currentLevel || server != currentServer) {
			player = currentPlayer;
			level = currentLevel;
			server = currentServer;
			owned = false;
		}
		if (player == null || level == null || server == null) owned = false;
		else if (claim) owned = true;
		return owned;
	}
}
