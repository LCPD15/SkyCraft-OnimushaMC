// Onimusha TDB82 only. Generate isolated, engine-owned static collision prefab.
// No original asset is edited. MOD制作：LCPD15/LCPD拉灯.
using System.Numerics;
using ReeLib;
using ReeLib.Pfb;
using ReeLib.via;

if (args.Length is < 2 or > 3) throw new ArgumentException("schema.json output-directory [navigation-offline-only]");
bool navigation = args.Length == 3 && args[2] == "navigation-offline-only";
if (args.Length == 3 && !navigation) throw new ArgumentException("Unknown prefab variant");
if (navigation) Console.Error.WriteLine("QUARANTINED: reproduces the 2026-10-07 navigation experiment. Do not deploy or instantiate.");
string stem = navigation ? "unit_navigation" : "unit_collision";
var parser = new RszParser(Path.GetFullPath(args[0]));
var options = new RszFileOption(GameName.oniws, parser);
var output = Path.GetFullPath(args[1]);
Directory.CreateDirectory(output);
RszInstance New(string name) {
    var obj=RszInstance.CreateInstance(parser, parser.GetRSZClass(name)!, createChildren:false);
    for (int i=0;i<obj.Fields.Length;i++)
        if (obj.Fields[i].IsReference && !obj.Fields[i].array) obj.Values[i]=RszInstance.NULL;
    return obj;
}
void Set(RszInstance obj, string name, object value) {
    if (!obj.SetFieldValue(name, value)) throw new InvalidDataException($"Missing {obj.RszClass.name}.{name}");
}
var path = Path.Combine(output, stem + ".pfb.18");
using (var file = new PfbFile(options, new FileHandler(new MemoryStream(), path) { FileVersion = 18 })) {
    var go = new PfbGameObject { Instance = New("via.GameObject") };
    Set(go.Instance, "Name", "OMC_NativeCollisionProbe");
    Set(go.Instance, "UpdateSelf", true); Set(go.Instance, "DrawSelf", true); Set(go.Instance, "Timescale", 1f);
    var transform = New("via.Transform");
    Set(transform, "Position", Vector3.Zero); Set(transform, "Rotation", Quaternion.Identity); Set(transform, "Scale", Vector3.One);
    go.Components.Add(transform);
    var filter = New("via.physics.FilterInfo");
    // Terrain_Default.cfil is the live st100_Ground filter, not a damage sensor.
    Set(filter, "Layer", 1u); Set(filter, "Group", 0u); Set(filter, "MaskBits", 0u);
    var box = New("via.physics.BoxShape");
    Set(box, "BoundingAabb", new AABB(new Vector3(-.5f), new Vector3(.5f)));
    Set(box, "OBB", new OBB(mat4.Identity, new Vector3(.5f)));
    var collider = New("via.physics.Collider");
    Set(collider, "Enabled", true); Set(collider, "Shape", box); Set(collider, "FilterInfo", filter);
    Set(collider, "CollisionFilterResource", "GameDesign/System/Setting/Collision/Filter/Terrain/Terrain_Default.cfil");
    var colliders = New("via.physics.Colliders");
    Set(colliders, "Enabled", true); Set(colliders, "Static", true);
    Set(colliders, "Colliders", new List<object> { collider });
    go.Components.Add(colliders);
    if (navigation) {
        var shape = New("via.navigation.map.InteractionShapeOBB");
        Set(shape, "Shape", new OBB(mat4.Identity, new Vector3(.5f, 1.5f, .5f)));
        Set(shape, "BoundingOBBType", 0);
        var effector = New("via.navigation.AIMapEffector");
        Set(effector, "Enabled", true);Set(effector, "EffectType", 1);Set(effector, "ShapeType", 2);
        Set(effector, "Shape", shape);Set(effector, "Fixed(?)", false);Set(effector, "AddEdge(?)", false);
        Set(effector, "MapName", "AIMap_Zako");
        Set(effector, "MapNames", new List<object> { "AIMap_Zako", "AIMap_MidBoss", "AIMap_Boss", "AIMap_Water" });
        Set(effector, "Attributes", new List<object>());
        go.Components.Add(effector);
    }
    file.GameObjects.Add(go);file.RebuildInfoTables();
    if (!file.Write()) throw new InvalidDataException("Prefab write failed");
    file.FileHandler.Save(path);
}
using (var check = new PfbFile(options, new FileHandler(path))) {
    if (!check.Read()) throw new InvalidDataException("Prefab read failed");
    check.SetupGameObjects();
    var go = check.GameObjects.Single();
    if (go.Components.Count != (navigation ? 3 : 2) || go.Name != "OMC_NativeCollisionProbe") throw new InvalidDataException("Unexpected hierarchy");
    var cs = go.Components.Single(x=>x.RszClass.name=="via.physics.Colliders");
    var collider = (RszInstance)((List<object>)cs.GetFieldValue("Colliders")!).Single();
    var shape = (RszInstance)collider.GetFieldValue("Shape")!;
    if (((OBB)shape.GetFieldValue("OBB")!).Extent != new Vector3(.5f)) throw new InvalidDataException("Wrong extent");
    if (navigation) {
        var nav = go.Components.Single(x=>x.RszClass.name=="via.navigation.AIMapEffector");
        if ((int)nav.GetFieldValue("EffectType")! != 1 || ((List<object>)nav.GetFieldValue("MapNames")!).Count != 4)
            throw new InvalidDataException("Wrong navigation settings");
    }
}
// Current REFramework cannot resolve sdk.deserialize on this executable.
// Use an inert, known UserData holder loaded by the native resource system.
// This is a new private asset; no original amulet asset is modified or attached.
var loaderPath = Path.Combine(output, stem + "_loader.user.3");
using (var file = new UserFile(options, new FileHandler(new MemoryStream(), loaderPath))) {
    var prefab = New("via.Prefab");
    Set(prefab, "Standby", false);Set(prefab, "Path", "mod/onimusha_mc/probe/" + stem + ".pfb");
    var holder = New("app.user_data.AmuletPrefabHolder");
    Set(holder, "_BeadsPrefab", prefab);Set(holder, "_Data", new List<object>());
    file.RSZ.ObjectList.Add(holder);file.RebuildInfoTable();
    if (!file.Write()) throw new InvalidDataException("Loader UserData write failed");
    file.FileHandler.Save(loaderPath);
}
using (var file = new UserFile(options, new FileHandler(loaderPath))) {
    if (!file.Read() || file.Instance!.RszClass.name != "app.user_data.AmuletPrefabHolder") throw new InvalidDataException("Loader UserData read failed");
    var prefab = (RszInstance)file.Instance.GetFieldValue("_BeadsPrefab")!;
    if ((string)prefab.GetFieldValue("Path")! != "mod/onimusha_mc/probe/" + stem + ".pfb") throw new InvalidDataException("Wrong prefab path");
}
Console.WriteLine($"Validated {stem}: one GO, Transform + Colliders, one unit Box, terrain filter; navigation={navigation}. Private UserData prefab holder validated.");
