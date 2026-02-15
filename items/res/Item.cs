using Godot;

public enum Hand {
    NONE,
    LEFT,
    RIGHT
}

[Tool]
[GlobalClass]
public partial class Item : Resource {
    [ExportGroup("Item Model")]
    [Export] public PackedScene model;
    [Export] public Vector3 modelPos;
    [Export] public Vector3 modelRot;

    [ExportGroup("Bounding box")]
    [Export] public Aabb bound;
    [Export] public Vector3 boundRot;

    [ExportGroup("")]
    [Export] public Hand requiredHand = Hand.NONE;
    [Export] public string name;
}