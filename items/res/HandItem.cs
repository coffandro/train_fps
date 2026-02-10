using Godot;

[Tool]
[GlobalClass]
public partial class HandItem : Item {
    [ExportGroup("World Model")]
    [Export] public PackedScene worldModel;
    [Export] public Vector3 worldPos;
    [Export] public Vector3 worldRot;
}