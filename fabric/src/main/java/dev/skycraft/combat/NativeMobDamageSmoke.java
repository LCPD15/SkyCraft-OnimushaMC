package dev.skycraft.combat;

import dev.skycraft.SkyCraft;
import dev.skycraft.link.Proto;
import dev.skycraft.link.SkyLink;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.entity.EntityTypes;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.animal.golem.IronGolem;

/** Explicit isolated cross-process test. Refuses the production mapping and save. */
public final class NativeMobDamageSmoke {
    private static int tick;private static boolean done;private static IronGolem near,armoured,far;
    private static float first,armourFirst;private static boolean pass=true;
    private NativeMobDamageSmoke(){}
    public static void init(){
        if(!Boolean.getBoolean("onimusha.npcDamageSmoke"))return;
        if(!SkyCraft.WORLD_NAME.startsWith("OnimushaMC-NpcDamageSmoke-")
            || !"Local\\OnimushaMC_NpcDamageSmoke".equals(System.getProperty("onimusha.link")))throw new IllegalStateException("NPC smoke isolation required");
        ServerTickEvents.END_SERVER_TICK.register(server -> {
            if(done||!SkyLink.active()||server.getPlayerList().getPlayers().isEmpty()||SkyCombat.proxy(1001)==null)return;
            try{
                var level=server.overworld();tick++;
                if(tick==1){
                    near=EntityTypes.IRON_GOLEM.create(level,EntitySpawnReason.TRIGGERED);
                    armoured=EntityTypes.IRON_GOLEM.create(level,EntitySpawnReason.TRIGGERED);
                    far=EntityTypes.IRON_GOLEM.create(level,EntitySpawnReason.TRIGGERED);
                    near.setNoAi(true);armoured.setNoAi(true);far.setNoAi(true);
                    near.setNoGravity(true);armoured.setNoGravity(true);far.setNoGravity(true);
                    near.setPos(0,65.375,0);armoured.setPos(.9,65.375,0);far.setPos(5,65.375,0);
                    armoured.getAttribute(Attributes.ARMOR).setBaseValue(20);
                    level.addFreshEntity(near);level.addFreshEntity(armoured);level.addFreshEntity(far);
                }
                if(tick==20)signal(1);
                if(tick==60){
                    first=near.getHealth();armourFirst=armoured.getHealth();
                    pass&=first==96&&armourFirst>first&&armourFirst<100&&far.getHealth()==100;
                    SkyCraft.LOG.info("NPC_DAMAGE_SMOKE onceAndArmour={} near={} armour={} far={}",pass,first,armourFirst,far.getHealth());signal(2);
                }
                if(tick==100){
                    pass&=near.getHealth()==92&&armoured.getHealth()<armourFirst&&far.getHealth()==100;
                    first=near.getHealth();signal(3);
                }
                if(tick==140){pass&=near.getHealth()==first;signal(4);}
                if(tick==170){
                    boolean killed=!near.isAlive()&&!armoured.isAlive();
                    boolean outside=far.getHealth()==100;boolean player=server.getPlayerList().getPlayers().getFirst().getHealth()==20;
                    pass&=killed&&outside&&player;
                    SkyCraft.LOG.info("NPC_DAMAGE_SMOKE_RESULT passed={} death={} outside={} playerExcluded={}",pass,killed,outside,player);
                    done=true;signal(9);
                }
            }catch(Throwable error){done=true;pass=false;SkyCraft.LOG.error("NPC_DAMAGE_SMOKE_FAILED",error);signal(9);}
        });
    }
    private static void signal(int stage){SkyLink.pushEvent(Proto.EV_SKILL_USE,0x4E5043,stage,0,0,0,0,0);}
}
