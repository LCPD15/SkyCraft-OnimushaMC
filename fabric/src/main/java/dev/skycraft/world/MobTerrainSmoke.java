package dev.skycraft.world;

import dev.skycraft.SkyCraft;
import dev.skycraft.link.SkyLink;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.core.BlockPos;
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.entity.EntityTypes;
import net.minecraft.world.entity.animal.golem.IronGolem;
import net.minecraft.world.level.block.Blocks;

/** Opt-in integration regression in a separate throwaway world, never the user's save. */
public final class MobTerrainSmoke {
	private static int tick;
	private static IronGolem embedded, pedestal, walker;
	private static boolean done;
	private MobTerrainSmoke() {}
	public static void init() {
		if (!Boolean.getBoolean("onimusha.mobSmoke")) return;
		if (!SkyCraft.WORLD_NAME.startsWith("OnimushaMC-MobSmoke-")
			|| !"Local\\OnimushaMC_MobSmoke".equals(System.getProperty("onimusha.link")))
			throw new IllegalStateException("Mob smoke must use isolated world and mapping");
		ServerTickEvents.END_SERVER_TICK.register(server -> {
			if (done || server.getPlayerList().getPlayers().isEmpty() || !SkyLink.active()
				|| !SkyCollision.isKnown(0,65,0)) return;
			try {
				var level=server.overworld();
				if (++tick==1) {
					level.setBlockAndUpdate(new BlockPos(1,66,1),Blocks.STONE.defaultBlockState());
					embedded=EntityTypes.IRON_GOLEM.create(level,EntitySpawnReason.TRIGGERED);
					pedestal=EntityTypes.IRON_GOLEM.create(level,EntitySpawnReason.TRIGGERED);
					walker=EntityTypes.IRON_GOLEM.create(level,EntitySpawnReason.TRIGGERED);
					// NoAI disables vanilla travel/gravity too; remove goals, keep physical ticks.
					embedded.removeAllGoals(goal -> true);pedestal.removeAllGoals(goal -> true);
					embedded.setPos(-2,65,-2);pedestal.setPos(1.5,67,1.5);walker.setPos(0,65.375,5);
					level.addFreshEntity(embedded);level.addFreshEntity(pedestal);level.addFreshEntity(walker);
				}
				if(tick==40)level.removeBlock(new BlockPos(1,66,1),false);
				if(tick%20==0)SkyCraft.LOG.info("MOB_SMOKE tick={} embedded={} pedestal={} walker={} target={} path={}",
					tick,embedded.position(),pedestal.position(),walker.position(),walker.getTarget()!=null,walker.getNavigation().getPath());
				if(tick==180){
					boolean a=Math.abs(embedded.getY()-65.375)<0.01;
					boolean b=Math.abs(pedestal.getY()-65.375)<0.01;
					boolean c=walker.getX()>3;
					SkyCraft.LOG.info("MOB_SMOKE_RESULT embeddedGround={} removedSupportFalls={} walksToEnemy={}",a,b,c);
					done=true;
				}
			} catch(Throwable error){done=true;SkyCraft.LOG.error("MOB_SMOKE_FAILED",error);}
		});
	}
}
