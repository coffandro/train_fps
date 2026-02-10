using Godot;

[Tool]
public partial class ItemEditor : Node3D {
	[Export] public Item item;

	[ExportGroup("Components")]
	[Export] public Node3D container;
	[Export] public CollisionShape3D collisionShape;

	private BoxShape3D boxShape;
	private PackedScene worldScene;

	public override void _Ready() {
		base._Ready();

		boxShape = new BoxShape3D();
		collisionShape.Shape = boxShape;
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta) {
		if (!Engine.IsEditorHint()) return;
		if (item == null) return;

		HandItem handItem = item as HandItem;
		if (item != null) {
			HandleHandItem(handItem);

			// Sword items inherit hand items
			SwordItem swordItem = handItem as SwordItem;
			if (swordItem != null) {
				HandleSwordItem(swordItem);
			}
		}
	}

	public void HandleHandItem(HandItem handItem) {
		if (container.Position != handItem.worldPos) {
			container.Position = handItem.worldPos;
		}

		if (container.RotationDegrees != handItem.worldRot) {
			container.RotationDegrees = handItem.worldRot;
		}

		if (worldScene != handItem.worldModel) {
			ClearChildren(container);

			worldScene = handItem.worldModel;

			if (worldScene != null) {
				Node instancedNode = worldScene.Instantiate();
				Node3D node = instancedNode as Node3D;
				container.AddChild(node);
			}
		}
	}

	public void HandleSwordItem(SwordItem swordItem) {
		if (collisionShape.Position != swordItem.colliderPos) {
			collisionShape.Position = swordItem.colliderPos;
		}

		if (collisionShape.RotationDegrees != swordItem.colliderRot) {
			collisionShape.RotationDegrees = swordItem.colliderRot;
		}

		if (boxShape.Size != swordItem.colliderSize) {
			boxShape.Size = swordItem.colliderSize;
			collisionShape.Shape = boxShape;
		}
	}

	public void ClearChildren(Node parent) {
		for (int i = 0; i < parent.GetChildCount(); i++) {
			Node child = parent.GetChild(i);
			parent.RemoveChild(child);
			child.QueueFree();
		}
	}
}
