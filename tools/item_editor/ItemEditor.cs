using Godot;

[Tool]
public partial class ItemEditor : Node3D {
	private Item _item;

	[ExportGroup("Item")]
	[ExportToolButton("Calculate bounding box")] public Callable CalculateBoundingBoxButton => Callable.From(CalculateBoundingBox);

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
			HandleItem();
		}
	}

	public void HandleItem() {
		DebugDraw3D.DrawBox(
			item.bound.Position,
			Quaternion.FromEuler(item.boundRot),
			item.bound.Size,
			new Color(0, 0, 255), true
		);

		if (container.Position != item.modelPos) {
			container.Position = item.modelPos;
		}

		if (container.RotationDegrees != item.modelRot) {
			container.RotationDegrees = item.modelRot;
		}

		if (worldScene != item.model) {
			worldScene = item.model;

			if (worldScene != null) {
				Node instancedNode = worldScene.Instantiate();
				Node3D node = instancedNode as Node3D;
				container.AddChild(node);
			}
		}

		// Sword items inherit items
		SwordItem swordItem = item as SwordItem;
		if (swordItem != null) {
			HandleSwordItem(swordItem);
		}
	}

	public void HandleSwordItem(SwordItem swordItem) {
		DebugDraw3D.DrawBox(
			swordItem.collider.Position,
			Quaternion.FromEuler(swordItem.colliderRot),
			swordItem.collider.Size,
			new Color(255, 0, 0), true
		);
	}

	public void CalculateBoundingBox() {
		if (!Engine.IsEditorHint()) return;
		if (item == null) return;
		if (container.GetChildCount() == 0) return;

		Aabb bounds = GetNodeAabb(container);

		bounds.Position = new Vector3(0, bounds.Size.Y / 2 + bounds.Position.Y, 0);
		item.bound = bounds;
		item.boundRot = Vector3.Zero;
	}

	public Aabb GetNodeAabb(Node3D node) {
		Aabb bounds = new Aabb();

		// Do not include children that is queued for deletion
		if (node.IsQueuedForDeletion()) {
			return bounds;
		}

		// Get the aabb of the visual instance
		if (node is VisualInstance3D) {
			VisualInstance3D visualInstance3D = node as VisualInstance3D;
			bounds = visualInstance3D.GetAabb();
		}

		// Recurse through all children
		for (int i = 0; i < node.GetChildCount(); i++) {
			Node child = node.GetChild(i);

			if (child is Light3D) {
				continue;
			}

			Aabb childBounds = GetNodeAabb(child as Node3D, false);
			if (bounds.Size == Vector3.Zero) {
				bounds = childBounds;
			} else {
				bounds = bounds.Merge(childBounds);
			}
		}

		return bounds;
	}

	public Aabb GetNodeAabb(Node3D node, bool excludeTopLevelTransform) {
		Aabb bounds = GetNodeAabb(node);

		if (!excludeTopLevelTransform) {
			bounds = node.Transform * bounds;
		}

		return bounds;
	}

	public void ClearChildren(Node parent) {
		for (int i = 0; i < parent.GetChildCount(); i++) {
			Node child = parent.GetChild(i);
			parent.RemoveChild(child);
			child.QueueFree();
		}
	}
}
