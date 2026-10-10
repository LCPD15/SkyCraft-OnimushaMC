package dev.skycraft.combat;

import dev.skycraft.SkyCraft;
import dev.skycraft.link.NativeAttackReader;
import dev.skycraft.link.SkyLink;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.AABB;

/** Native attack volumes affect real MC living mobs through vanilla hurtServer. */
public final class NativeMobDamage {
    private static final AttackLedger LEDGER=new AttackLedger();
    private static int generation=-1,epoch,world;
    private static Object levelOwner;
    private static long attempts,accepted;
    private NativeMobDamage(){}
    public static void tick(MinecraftServer server){
        var messages=NativeAttackReader.drain();var host=new SkyLink.SkyState();
        var players=server.getPlayerList().getPlayers();
        if(!SkyLink.active()||players.isEmpty()||!SkyLink.readSkyState(host)||!host.inGame()||host.loading()||host.menuOpen()||host.hostDead()){
            LEDGER.clear();return;
        }
        var level=players.getFirst().level();int gen=SkyLink.generation();
        if(gen!=generation||host.collisionEpoch!=epoch||host.worldId!=world||levelOwner!=level){
            LEDGER.clear();generation=gen;epoch=host.collisionEpoch;world=host.worldId;levelOwner=level;
        }
        for(var a:messages){
            if(a.epoch()!=epoch||a.world()!=world||!NativeAttackReader.liveSession(a.session(),epoch,world))continue;
            var source=SkyCombat.proxy(a.attacker());
            if(source==null||source.isRemoved()||source.level()!=level||!source.isAlive())continue;
            LEDGER.observe(a,SkyLink.tickCount());var b=AttackGeometry.bounds(a);
            for(var victim:level.getEntitiesOfClass(LivingEntity.class,new AABB(b.minX(),b.minY(),b.minZ(),b.maxX(),b.maxY(),b.maxZ()),
                e -> !(e instanceof Player)&&!(e instanceof SkyrimActorEntity)&&e.isAlive()&&!e.isRemoved())){
                var v=victim.getBoundingBox();
                if(!AttackGeometry.intersects(a,new AttackGeometry.Box(v.minX,v.minY,v.minZ,v.maxX,v.maxY,v.maxZ)))continue;
                if(!NativeAttackReader.liveSession(a.session(),epoch,world)||SkyLink.generation()!=generation)break;
                if(!LEDGER.admit(a,victim.getUUID()))continue;
                float before=victim.getHealth();boolean hit=victim.hurtServer(level,level.damageSources().mobAttack(source),a.damage());
                attempts++;if(hit)accepted++;
                SkyCraft.LOG.info("NATIVE_MOB_HIT attacker={} attack={}/{} victim={} id={} damage={} health={}->{} accepted={} attempts={} acceptedTotal={}",
                    a.attacker(),a.attack(),a.hit(),victim.getType(),victim.getUUID(),a.damage(),before,victim.getHealth(),hit,attempts,accepted);
            }
        }
    }
}
