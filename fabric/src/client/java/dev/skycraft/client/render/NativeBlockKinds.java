package dev.skycraft.client.render;

import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/** Protocol 14 bits 8..15: prebuilt vanilla opaque cube resources. Zero stays in overlay. */
public final class NativeBlockKinds {
    private NativeBlockKinds() {}
    public static int of(BlockState s) {
        if(s.is(Blocks.STONE)) return 1;
        if(s.is(Blocks.COBBLESTONE)) return 2;
        if(s.is(Blocks.IRON_BLOCK)) return 3;
        if(s.is(Blocks.TNT)) return 4;
        if(s.is(Blocks.DIRT)) return 5;
        if(s.is(Blocks.OAK_PLANKS)) return 6;
        if(s.is(Blocks.OBSIDIAN)) return 7;
        if(s.is(Blocks.GOLD_BLOCK)) return 8;
        if(s.is(Blocks.DIAMOND_BLOCK)) return 9;
        if(s.is(Blocks.STONE_BRICKS)) return 10;
        if(s.is(Blocks.BRICKS)) return 11;
        if(s.is(Blocks.NETHERITE_BLOCK)) return 12;
        if(s.is(Blocks.EMERALD_BLOCK)) return 13;
        if(s.getBlock().getDescriptionId().equals("block.minecraft.copper_block")) return 14;
        if(s.is(Blocks.QUARTZ_BLOCK)) return 15;
        if(s.is(Blocks.BEDROCK)) return 16;
        return 0;
    }
}
