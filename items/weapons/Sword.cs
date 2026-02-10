using Godot;

public partial class Sword : ItemHand {
    [Export] public SwordItem swordItem;

    [ExportSubgroup("Components")]
    [Export] public AnimationPlayer player;
    [Export] public Node3D pivot;
    [Export] public Node3D container;
    [Export] public CollisionShape3D collisionShape;

    public override void _Ready() {
        base._Ready();
        Debug.Assert(swordItem != null, "No Sword Item");

        // Set collider
        BoxShape3D shape = new BoxShape3D();
        shape.Size = swordItem.colliderSize;
        collisionShape.Shape = shape;
        collisionShape.Position = swordItem.colliderPos;
        collisionShape.RotationDegrees = swordItem.colliderRot;

        // Set mesh
        Node instanceNode = swordItem.worldModel.Instantiate();
        Node3D mesh = instanceNode as Node3D;
        container.AddChild(mesh);
        container.Position = swordItem.worldPos;
        container.RotationDegrees = swordItem.worldRot;

        //
    }

    public override void ActionUse() {
        if (player.IsPlaying()) return;

        player.Play("Swing");
    }

    public void _on_detector_body_entered(Node3D body) {

    }
}