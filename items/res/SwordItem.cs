using Godot;

[Tool]
[GlobalClass]
public partial class SwordItem : HandItem {
    [ExportGroup("Collider")]
    [Export] public Vector3 colliderSize;
    [Export] public Vector3 colliderPos;
    [Export] public Vector3 colliderRot;
}