// MIT. Generates new geometry; never rewrites an original game's collision resource.
using System.Numerics;
using ReeLib;
using ReeLib.Rcol;
using ReeLib.via;

if (args.Length != 2) throw new ArgumentException("Usage: UnitBoxCollider <copied Onimusha RSZ schema> <output unit_box.rcol.37>");
var schema = Path.GetFullPath(args[0]);
var output = Path.GetFullPath(args[1]);
Directory.CreateDirectory(Path.GetDirectoryName(output)!);
var options = new RszFileOption(GameName.oniws, new RszParser(schema));
using (var handler = new FileHandler(new MemoryStream(), output))
using (var file = new RcolFile(options, handler)) {
    handler.FileVersion = 37;
    var request = file.CreateNewRequestSet("OnimushaMC_UnitBox");
    request.Info.KeyName = "OnimushaMC_UnitBox";
    request.Group!.Info.Name = "OnimushaMC_Block";
    request.Group.Info.MaskBits = uint.MaxValue;
    var shape = new RcolShape();
    shape.Info.Guid = Guid.NewGuid();
    shape.Info.Name = "OnimushaMC_UnitBox";
    shape.Info.shapeType = ShapeType.Box;
    shape.Info.primaryJointNameStr = "";
    shape.Info.secondaryJointNameStr = "";
    shape.shape = new OBB(mat4.Identity, new Vector3(0.5f));
    request.Group.Shapes.Add(shape);
    using var destination = new FileHandler(new MemoryStream(), output) { FileVersion = 37 };
    if (!file.WriteTo(destination)) throw new InvalidOperationException("RCOL serialization failed");
    destination.Save(output);
}
using (var check = new RcolFile(options, new FileHandler(output))) {
    if (!check.Read()) throw new InvalidOperationException("RCOL re-read failed");
    if (check.Groups.Count != 1 || check.RequestSets.Count != 1 || check.Groups[0].Shapes.Count != 1 ||
        check.Groups[0].Shapes[0].Info.shapeType != ShapeType.Box) throw new InvalidOperationException("RCOL structure mismatch");
    var box = (OBB)check.Groups[0].Shapes[0].shape!;
    if (box.Extent != new Vector3(0.5f)) throw new InvalidOperationException("RCOL box extent mismatch");
    Console.WriteLine($"Validated .rcol.37: 1 group, 1 request, 1 box; extent={box.Extent}; bytes={new FileInfo(output).Length}");
}
