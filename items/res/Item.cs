using Godot;

public enum Hand {
    NONE,
    LEFT,
    RIGHT
}

[Tool]
[GlobalClass]
public partial class Item : Resource {
    [Export] public string name;
    [Export] public Hand requiredHand = Hand.NONE;

    [ExportGroup("ItemModel")]
    [Export] public PackedScene itemModel;
    [Export] public Vector3 itemPos;
    [Export] public Vector3 itemRot;
}