// Onimusha TDB82 only. Private inert USER3 owning Mesh/MDF dependencies.
// Does not mount any costume or run Montage logic. MOD制作：LCPD15/LCPD拉灯.
using ReeLib;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Text.Json;

if (args.Length != 3) throw new ArgumentException("schema.json asset-id output-directory");
var id = args[1];
if (!Regex.IsMatch(id, "^section_[a-f0-9]{20}$")) throw new ArgumentException("Invalid asset ID");
var parser = new RszParser(Path.GetFullPath(args[0]));
var options = new RszFileOption(GameName.oniws, parser);
const string type = "app.montage.data.MontagePartsModelData";
var schema = parser.GetRSZClass(type) ?? throw new InvalidDataException("Missing loader schema");
var holder = RszInstance.CreateInstance(parser, schema, createChildren: false);
for (int i = 0; i < holder.Fields.Length; i++)
    if (holder.Fields[i].IsReference && !holder.Fields[i].array) holder.Values[i] = RszInstance.NULL;
string prefix = "mod/onimusha_mc/sections/" + id + "/" + id;
if (!holder.SetFieldValue("_Mesh", prefix + ".mesh") || !holder.SetFieldValue("_Material", prefix + ".mdf2"))
    throw new InvalidDataException("Missing Mesh/MDF fields");
var output = Path.GetFullPath(args[2]);
Directory.CreateDirectory(output);
var path = Path.Combine(output, id + "_loader.user.3");
if (File.Exists(path)) throw new IOException("Refuse to overwrite a possibly loaded resource");
using (var file = new UserFile(options, new FileHandler(new MemoryStream(), path))) {
    file.RSZ.ObjectList.Add(holder); file.RebuildInfoTable();
    if (!file.Write()) throw new InvalidDataException("USER write failed");
    file.FileHandler.Save(path);
}
using (var file = new UserFile(options, new FileHandler(path))) {
    if (!file.Read() || file.Instance?.RszClass.name != type) throw new InvalidDataException("USER readback failed");
    if ((string)file.Instance.GetFieldValue("_Mesh")! != prefix + ".mesh" ||
        (string)file.Instance.GetFieldValue("_Material")! != prefix + ".mdf2")
        throw new InvalidDataException("Dependency path readback failed");
}
Console.WriteLine(JsonSerializer.Serialize(new {path, type, mesh = prefix + ".mesh", material = prefix + ".mdf2",
    sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))), verified = true}));
