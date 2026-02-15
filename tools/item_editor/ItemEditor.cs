using Godot;

[Tool]
public partial class ItemEditor : Node3D {
	private Item _item;

	[Export]
	public Item item {
		get {
			return _item;
		}
		set {
			isModelDirty = true;
			_item = value;
		}
	}

	[ExportGroup("Settings")]
	[Export] public float thickness;

	[ExportGroup("Components")]
	[Export] public Node3D container;

	private BoxShape3D boxShape;
	private PackedScene worldScene;
	private bool isModelDirty = false;

	public override void _Ready() {
		base._Ready();
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta) {
		if (!Engine.IsEditorHint()) return;

		if (isModelDirty) {
			// Clear model
			ClearChildren(container);
			worldScene = null;
		}

		if (item == null) return;

		using (var _w1 = DebugDraw3D.NewScopedConfig().SetThickness(thickness)) {

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
	}

	public void HandleHandItem(HandItem handItem) {
		if (container.Position != handItem.worldPos) {
			container.Position = handItem.worldPos;
		}

		if (container.RotationDegrees != handItem.worldRot) {
			container.RotationDegrees = handItem.worldRot;
		}

		if (worldScene != handItem.worldModel) {
			worldScene = handItem.worldModel;

			if (worldScene != null) {
				Node instancedNode = worldScene.Instantiate();
				Node3D node = instancedNode as Node3D;
				container.AddChild(node);
			}
		}
	}

	public void HandleSwordItem(SwordItem swordItem) {
		DebugDraw3D.DrawBox(
			swordItem.colliderPos,
			Quaternion.FromEuler(swordItem.colliderRot),
			swordItem.colliderSize,
			new Color(255, 0, 0), true
		);
	}

	public void ClearChildren(Node parent) {
		for (int i = 0; i < parent.GetChildCount(); i++) {
			Node child = parent.GetChild(i);
			parent.RemoveChild(child);
			child.QueueFree();
		}
	}
}
