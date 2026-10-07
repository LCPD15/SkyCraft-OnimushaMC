package dev.skycraft.link;

import java.util.Collection;
import java.util.Map;
import java.util.List;

/** Check effective block assets, not the list of installed Fabric resource packs. */
public final class VanillaBlockResources {
    public static final List<String> ROOTS = List.of("textures/block", "models/block", "blockstates", "atlases");
    private VanillaBlockResources() {}

    public static boolean compatible(Map<String, ? extends Collection<String>> sources) {
        for (String root : ROOTS) {
            Collection<String> packs = sources.get(root);
            if (packs == null || packs.isEmpty() || packs.stream().anyMatch(p -> !"vanilla".equals(p))) return false;
        }
        return true;
    }
}
