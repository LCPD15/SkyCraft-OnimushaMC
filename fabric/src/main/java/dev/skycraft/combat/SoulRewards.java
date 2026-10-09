package dev.skycraft.combat;

import dev.skycraft.SkyCraft;
import dev.skycraft.link.Proto;
import dev.skycraft.link.SkyLink;
import java.util.ArrayList;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;

/** Integrated-server thread only; original Onimusha soul rewards are retained. */
public final class SoulRewards {
    private static int generation=-1,epoch,lastReceipt,healthRevision=-1;
    private static float reservedHeal;
    private SoulRewards() {}
    public static void apply(ServerPlayer player,int gen,int ep,int receipt) {
        if(player==null || receipt<=0 || !HostHealth.currentSession(gen,ep))return;
        if(generation!=gen || epoch!=ep){generation=gen;epoch=ep;lastReceipt=0;healthRevision=-1;reservedHeal=0;}
        if(receipt<=lastReceipt)return;
        lastReceipt=receipt;
        var host=new SkyLink.SkyState();if(!SkyLink.readSkyState(host)||host.collisionEpoch!=ep)return;
        if(healthRevision!=host.healthRevision){healthRevision=host.healthRevision;reservedHeal=0;}
        var repairs=new ArrayList<ItemStack>();var stacks=new ArrayList<ItemStack>();
        Set<ItemStack> seen=Collections.newSetFromMap(new IdentityHashMap<>());
        var inv=player.getInventory();
        for(int i=0;i<inv.getContainerSize();i++) {
            var item=inv.getItem(i);if(item.isEmpty()||!seen.add(item))continue;
            if(item.isDamageableItem()&&item.isDamaged())repairs.add(item);
            if(item.getCount()<Math.min(item.getMaxStackSize(),inv.getMaxStackSize(item)))stacks.add(item);
        }
        for(var slot:EquipmentSlot.values()) {
            var item=player.getItemBySlot(slot);
            if(!item.isEmpty()&&seen.add(item)&&item.isDamageableItem()&&item.isDamaged())repairs.add(item);
        }
        boolean heal=host.healthMax>0 && host.healthCurrent/host.healthMax+reservedHeal<.999999f;
        var options=SoulRewardMath.eligible(heal,!repairs.isEmpty(),!stacks.isEmpty());
        var random=player.getRandom();var kind=options.get(random.nextInt(options.size()));String message;
        switch(kind) {
            case HEAL -> {
                if(!SkyLink.tryPushEvent(Proto.EV_HEALTH_CHANGE,0,.05f,1,0,0,Proto.HEALTH_HEAL,ep)) {
                    SkyCraft.LOG.warn("Soul reward {}: health request queue full",receipt);return;
                }
                reservedHeal+=.05f;message="回复 5% 生命";
            }
            case REPAIR -> {
                var item=repairs.get(random.nextInt(repairs.size()));item.setDamageValue(item.getDamageValue()-1);
                message=item.getHoverName().getString()+" 耐久 +1";
            }
            case STACK -> {
                var item=stacks.get(random.nextInt(stacks.size()));item.grow(1);message=item.getHoverName().getString()+" 数量 +1";
            }
            default -> {
                float old=player.experienceProgress;int cost=player.getXpNeededForNextLevel();
                var progress=SoulRewardMath.addExperienceProgress(old);
                if(progress.levels()>0)player.giveExperienceLevels(progress.levels());
                double points=progress.levels()>0?(1-old)*cost+progress.fraction()*player.getXpNeededForNextLevel():.23*cost;
                player.totalExperience=(int)Math.min(Integer.MAX_VALUE,(long)player.totalExperience+(int)Math.round(points));
                player.experienceProgress=progress.fraction();player.giveExperiencePoints(0);
                message="经验进度 +23%";
            }
        }
        inv.setChanged();player.inventoryMenu.broadcastChanges();
        player.sendOverlayMessage(Component.literal("吸魂奖励："+message));
        SkyCraft.LOG.info("Onimusha soul reward receipt={} kind={} detail={}",receipt,kind,message);
    }
}
