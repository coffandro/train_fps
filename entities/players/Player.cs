using System;
using Godot;

public partial class Player : CharacterBody3D {
	[ExportSubgroup("Properties")]
	[Export] public float moveSpeed = 5.0f;
	[Export] public float jumpVelocity = 8f;
	[Export] public float mouseSensitivity = 700;
	[Export] public float gamepadSensitivity = 0.075f;

	[ExportGroup("Internal")]
	[Export] public Camera3D camera;
	[Export] public Node3D leftContainer;
	[Export] public Node3D rightContainer;

	[ExportGroup("Item Debug")]
	[Export] public HandItem leftItem;
	[Export] public HandItem rightItem;
	[Export] public PackedScene swordContainer;

	private bool mouseCaptured = true;

	private Vector3 movementVelocity;
	private Vector3 rotationTarget;

	private Vector2 inputMouse;
	private Vector3 leftContainerOffset;
	private Vector3 rightContainerOffset;

	private int health = 100;
	private float gravity;

	private bool jumping = false;
	private bool previously_floored = false;

	public override void _Ready() {
		base._Ready();

		leftContainerOffset = leftContainer.Position;
		rightContainerOffset = rightContainer.Position;
		Input.MouseMode = Input.MouseModeEnum.Captured;

		// Move to inventory system later
		if (leftItem != null) {
			SwordItem swordItem = leftItem as SwordItem;
			if (swordItem != null) {
				Sword container = swordContainer.Instantiate() as Sword;
				container.swordItem = swordItem;
				leftContainer.AddChild(container);
			}
		}

		if (rightItem != null) {
			SwordItem swordItem = rightItem as SwordItem;
			if (swordItem != null) {
				Sword container = swordContainer.Instantiate() as Sword;
				container.swordItem = swordItem;
				rightContainer.AddChild(container);
			}
		}
	}

	public override void _PhysicsProcess(double delta) {
		// Handle functions
		HandleControls((float)delta);
		HandleGravity((float)delta);

		// Movement
		movementVelocity = Transform.Basis * movementVelocity;

		Vector3 appliedVelocity = Velocity.Lerp(movementVelocity, (float)delta * 10);
		appliedVelocity.Y = -gravity;

		Velocity = appliedVelocity;
		MoveAndSlide();

		// Rotation 
		leftContainer.Position = leftContainer.Position.Lerp(
			leftContainerOffset - (Basis.Inverse() * appliedVelocity / 30f),
			(float)delta * 10
		);

		rightContainer.Position = rightContainer.Position.Lerp(
			rightContainerOffset - (Basis.Inverse() * appliedVelocity / 30f),
			(float)delta * 10
		);

		// Return state
		if (IsOnFloor() && jumping) {
			jumping = false;
		}

		// Actions
		if (Input.IsActionJustPressed("shoot")) {
			if (rightContainer.GetChildCount() > 0) {
				ItemHand hand = rightContainer.GetChild(0) as ItemHand;
				if (hand != null) {
					hand.ActionUse();
				}
			}
		}
	}

	public override void _Input(InputEvent @event) {
		base._Input(@event);

		if (@event is InputEventMouseMotion && mouseCaptured) {
			InputEventMouseMotion motionEven = (InputEventMouseMotion)@event;
			inputMouse = motionEven.Relative / mouseSensitivity;
			HandleRotation(motionEven.Relative.X, motionEven.Relative.Y);
		}
	}

	private void HandleControls(float delta) {
		// Mouse Capture
		if (Input.IsActionJustPressed("mouse_capture")) {
			Input.MouseMode = Input.MouseModeEnum.Captured;
			mouseCaptured = true;
		} else if (Input.IsActionJustPressed("mouse_capture_exit")) {
			Input.MouseMode = Input.MouseModeEnum.Visible;
			mouseCaptured = true;

			inputMouse = Vector2.Zero;
		}

		// Movement
		Vector2 input = Input.GetVector("move_left", "move_right", "move_forward", "move_back");
		movementVelocity = new Vector3(
			input.X,
			0,
			input.Y
		).Normalized() * moveSpeed;

		// Handle controller rotation
		Vector2 rotationInput = Input.GetVector("camera_right", "camera_left", "camera_down", "camera_up");
		if (rotationInput != Vector2.Zero) {
			HandleRotation(rotationInput.X, rotationInput.Y, delta);
		}

		if (Input.IsActionJustPressed("jump")) {
			ActionJump();
		}
	}

	public void HandleRotation(float xRot, float yRot) {
		rotationTarget += new Vector3(
			-yRot,
			-xRot,
			0
		) / mouseSensitivity;

		rotationTarget.X = Mathf.Clamp(
			rotationTarget.X,
			Mathf.DegToRad(-90),
			Mathf.DegToRad(90)
		);

		camera.Rotation = new Vector3(
			rotationTarget.X,
			camera.Rotation.Y,
			camera.Rotation.Z
		);

		Rotation = new Vector3(
			Rotation.X,
			rotationTarget.Y,
			Rotation.Z
		);
	}

	public void HandleRotation(float xRot, float yRot, float delta) {
		rotationTarget -= new Vector3(
			-yRot,
			-xRot,
			0
		).LimitLength(1.0f) * gamepadSensitivity;

		rotationTarget.X = Mathf.Clamp(
			rotationTarget.X,
			Mathf.DegToRad(-90),
			Mathf.DegToRad(90)
		);

		camera.Rotation = new Vector3(
			Mathf.LerpAngle(camera.Rotation.X, rotationTarget.X, delta * 25),
			camera.Rotation.Y,
			camera.Rotation.Z
		);

		Rotation = new Vector3(
			Rotation.X,
			Mathf.LerpAngle(Rotation.Y, rotationTarget.Y, delta * 25),
			Rotation.Z
		);
	}

	private void HandleGravity(float delta) {
		gravity += 20 * delta;

		if (gravity > 0 && IsOnFloor()) {
			gravity = 0;
		}
	}

	public void ActionJump() {
		if (jumping) return;

		gravity = -jumpVelocity;
		jumping = true;
	}
}
