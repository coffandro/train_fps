using Godot;
using Godot.Collections;

// The backend load code, to be used by different loading screens
// You start by calling InitiateSceneLoad(string path)
// You hook into ProgressUpdated to get progress updates
// You hook into Failed to get errors
// You hook into Loaded to to know when success has been achived
// Once the process has finished and you're done with it you call LoadingManager.Instance.Finish() and be on your mary way
// (If your Node is not a global but exists in root it will be deleted upon calling Finish())
public partial class LoadingManager : Node {
	public static LoadingManager Instance { get; private set; }

	[Signal]
	public delegate void ProgressUpdatedEventHandler(float progress);
	[Signal]
	public delegate void FailedEventHandler(string error);
	[Signal]
	public delegate void LoadedEventHandler();

	private Array<Node> init_nodes;
	private Array<string> kill_nodes = ["Main"]; // Nodes to kill no matter what if it exists

	private string path = "";
	private Node loadedNode;

	public override void _Ready() {
		Instance = this; // Singleton pattern

		init_nodes = GetTree().Root.GetChildren();

		base._Ready();
	}

	public void InitiateSceneLoad(string target) {
		GD.Print("Loading ", target);
		path = target;

		// Pause game
		GetTree().Paused = true;

		if (ResourceLoader.HasCached(path)) {
			// In case it's already loaded
			InstantiateScene();
		} else {
			// otherwise, begin load
			ResourceLoader.LoadThreadedRequest(path);
		}
	}

	public bool IsLoading() {
		if (path == "") return false;

		return true;
	}

	public override void _Process(double delta) {
		base._Process(delta);
		if (!IsLoading()) return;

		Array progress = [];
		ResourceLoader.ThreadLoadStatus status = ResourceLoader.LoadThreadedGetStatus(path, progress);

		if (status == ResourceLoader.ThreadLoadStatus.InProgress) {
			// Set progress
			EmitSignal(SignalName.ProgressUpdated, progress[0]);

		} else if (status == ResourceLoader.ThreadLoadStatus.Loaded) {
			// Set loaded status
			InstantiateScene();

		} else if (status == ResourceLoader.ThreadLoadStatus.Failed) {
			Fail("Failed");
		} else if (status == ResourceLoader.ThreadLoadStatus.InvalidResource) {
			Fail("Invalid resource");
		}
	}

	private void InstantiateScene() {
		PackedScene resource = ResourceLoader.LoadThreadedGet(path) as PackedScene;

		// To block process
		path = "";

		if (resource == null) {
			Fail("Scene not valid");
			return;
		}

		loadedNode = resource.Instantiate();
		GetTree().Root.AddChild(loadedNode);
		EmitSignal(SignalName.Loaded);
	}


	public void Fail(string error) {
		GD.Print("Loading failed " + error);

		// We no longer need it
		loadedNode = null;

		EmitSignal(SignalName.Failed, error);
	}

	public void Finish() {
		GD.Print("Finished loading ", path);

		// Unload previous scene by matching nodes to the nodes of init, excluding constant kill_nodes
		Array<Node> nodes = GetTree().Root.GetChildren();

		for (int i = 0; i < nodes.Count; i++) {
			Node node = nodes[i];
			if (
				(kill_nodes.Contains(node.Name) || !init_nodes.Contains(node)) && // If a node is either in the kill_nodes OR wasn't there at the start
				node != loadedNode // Ignore if the newly loaded node
			) {
				node.QueueFree();
			}
		}

		// Clear state
		path = "";
		loadedNode = null;

		// Return to game
		GetTree().Paused = false;
	}
}
