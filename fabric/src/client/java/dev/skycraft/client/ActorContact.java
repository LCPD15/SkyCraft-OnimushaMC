package dev.skycraft.client;

import dev.skycraft.combat.ActorProxyIdentity;
import dev.skycraft.combat.ActorSeparation;
import dev.skycraft.combat.SkyrimActorEntity;
import dev.skycraft.link.SkyLink;
import net.minecraft.client.Minecraft;
import net.minecraft.world.entity.MoverType;

/** Host actors own their transforms; move the MC player through normal collision instead. */
final class ActorContact {
    private ActorContact() {}
    static void tick(Minecraft mc) {
        var player=mc.player;
        if(player==null||mc.level==null||player.noPhysics||player.isSpectator()||!player.isAlive())return;
        var session=new ActorProxyIdentity.Session(SkyLink.generation(),SkyClient.sky().collisionEpoch);
        for(var actor:mc.level.getEntitiesOfClass(SkyrimActorEntity.class,player.getBoundingBox())) {
            if(!actor.belongsTo(session))continue;
            var offset=ActorSeparation.displacement(player.getBoundingBox(),actor.getBoundingBox());
            if(offset.lengthSqr()==0)continue;
            // Entity.move also executes our native-terrain triangle collision mixin.
            // One correction per tick bounds crowd pushes and never teleports through walls.
            player.move(MoverType.SELF,offset);break;
        }
    }
}
