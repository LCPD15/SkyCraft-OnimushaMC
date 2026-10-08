package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;
import com.google.gson.GsonBuilder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.SharedConstants;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.nbt.NbtOps;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.enchantment.EnchantmentHelper;
import net.minecraft.world.item.enchantment.Enchantments;
import org.junit.jupiter.api.Test;

/** Actual installed item limits, supported enchantments and 26.3 NBT codec. */
class InventoryUpgradeCodecTest {
    @Test void exportValidatedInventoryRules() throws Exception {
        SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
        var registries=VanillaRegistries.createWorldLookup();
        BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(registries).forEach(p->p.apply());
        var enchantments=registries.lookupOrThrow(Registries.ENCHANTMENT);
        var unbreaking=enchantments.getOrThrow(Enchantments.UNBREAKING);
        var infinity=enchantments.getOrThrow(Enchantments.INFINITY);
        assertEquals(3,unbreaking.value().getMaxLevel());assertEquals(1,infinity.value().getMaxLevel());
        Map<String,Object> items=new TreeMap<>();
        for(var item:BuiltInRegistries.ITEM) {
            var stack=new ItemStack(item);
            if(stack.isEmpty())continue;
            Map<String,Integer> ench=new TreeMap<>();
            if(unbreaking.value().isSupportedItem(stack))ench.put("minecraft:unbreaking",3);
            if(infinity.value().isSupportedItem(stack))ench.put("minecraft:infinity",1);
            items.put(BuiltInRegistries.ITEM.getKey(item).toString(),Map.of("max_count",stack.getMaxStackSize(),"damageable",stack.isDamageableItem(),"enchantments",ench));
        }
        var bow=new ItemStack(Items.BOW);
        EnchantmentHelper.updateEnchantments(bow,m->{m.set(unbreaking,3);m.set(infinity,1);});
        var ops=registries.createSerializationContext(NbtOps.INSTANCE);
        var nbt=ItemStack.CODEC.encodeStart(ops,bow).getOrThrow();
        var loaded=ItemStack.CODEC.parse(ops,nbt).getOrThrow();
        assertEquals(1,EnchantmentHelper.getItemEnchantmentLevel(infinity,loaded));
        assertEquals(3,EnchantmentHelper.getItemEnchantmentLevel(unbreaking,loaded));
        assertFalse(infinity.value().isSupportedItem(new ItemStack(Items.CROSSBOW)));
        Path dir=Path.of("build/test-artifacts");Files.createDirectories(dir);
        Files.writeString(dir.resolve("inventory-rules.json"),new GsonBuilder().setPrettyPrinting().create().toJson(Map.of("version","26.3","items",items,"bow_nbt",nbt.toString())));
    }
}
