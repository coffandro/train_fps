using Godot;

[Tool]
[GlobalClass]
public partial class SwordItem : Item {
    [ExportGroup("Sword Settings")]

    [ExportSubgroup("Metadata")]
    [Export] public int damage = 10;

    // [ExportSubgroup("Animation")]
    // Some general animation and sound stuff...
    // [Export] public Array<Animation> attackAnimations

    [ExportSubgroup("Collider")]
    [Export] public Aabb collider;
    [Export] public Vector3 colliderRot;
}