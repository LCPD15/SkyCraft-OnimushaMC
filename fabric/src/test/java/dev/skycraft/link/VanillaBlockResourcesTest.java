package dev.skycraft.link;

import org.junit.jupiter.api.Test;
import java.util.HashMap;
import java.util.List;
import java.util.Collection;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;

class VanillaBlockResourcesTest {
    private Map<String, Collection<String>> vanilla() {
        var result = new HashMap<String, Collection<String>>();
        for (String root : VanillaBlockResources.ROOTS) result.put(root, List.of("vanilla", "vanilla"));
        return result;
    }
    @Test void fabricPacksWithoutBlockOverridesDoNotDisableNativeCubes() {
        assertTrue(VanillaBlockResources.compatible(vanilla()));
    }
    @Test void textureModelBlockstateAndAtlasOverridesKeepMinecraftRendering() {
        for (String root : VanillaBlockResources.ROOTS) {
            var sources = vanilla();
            sources.put(root, List.of("vanilla", "file/custom-pack.zip"));
            assertFalse(VanillaBlockResources.compatible(sources), root);
        }
    }
    @Test void modAssetOverridesAreNotBlindlyWhitelisted() {
        var sources = vanilla();
        sources.put("textures/block", List.of("vanilla", "fabric-custom-textures"));
        assertFalse(VanillaBlockResources.compatible(sources));
    }
    @Test void missingOrEmptyResourceInventoryFailsClosed() {
        assertFalse(VanillaBlockResources.compatible(Map.of()));
        var sources = vanilla();
        sources.put("models/block", List.of());
        assertFalse(VanillaBlockResources.compatible(sources));
    }
}
