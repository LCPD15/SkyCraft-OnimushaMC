package dev.skycraft.combat;

import java.util.Objects;
import java.util.function.Consumer;

/** Identity decisions shared by server and client actor proxies. No IPC layout changes. */
public final class ActorProxyIdentity {
	private ActorProxyIdentity() {
	}

	public record Session(int generation, int epoch) {
		public boolean matches(int candidateGeneration, int candidateEpoch) {
			return generation == candidateGeneration && epoch == candidateEpoch;
		}
	}

	/** A new host or native load invalidates every old proxy, including accumulated hits. */
	public static final class Boundary {
		private Session previous;

		public boolean observe(Session current) {
			boolean changed = !Objects.equals(previous, current);
			previous = current;
			return changed;
		}

		public void invalidate() {
			previous = null;
		}
	}

	/** Empty actor names clear an old custom name; unchanged names avoid metadata packets. */
	public static boolean refreshName(String current, String incoming, Consumer<String> assign) {
		String oldName = current == null ? "" : current;
		String newName = incoming == null ? "" : incoming;
		if (oldName.equals(newName)) {
			return false;
		}
		assign.accept(newName);
		return true;
	}
}
