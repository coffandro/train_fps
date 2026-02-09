using Godot;

public partial class LoadingScreen : Control {
	public static LoadingScreen Instance { get; private set; }

	[Export] public string loadingText = "Loading...";

	[ExportGroup("Internal")]
	[Export] public ProgressBar loadBar;
	[Export] public Label label;
	[Export] public Control container;

	// State
	private bool baloonLoadTime = true;
	private bool loaded = false;
	private float managerProgress = 0.0f;

	public override void _Ready() {
		Instance = this; // Singleton pattern

		base._Ready();
		container.Hide();

		LoadingManager.Instance.ProgressUpdated += UpdateProgress;
		LoadingManager.Instance.Failed += Failed;
		LoadingManager.Instance.Loaded += Loaded;

		// Initial values
		label.Text = loadingText;
	}

	// Begin load using manager
	public void LoadScene(string target) {
		if (target == null) {
			return;
		}

		GD.Print("starting ", target);
		baloonLoadTime = true;
		LoadingManager.Instance.InitiateSceneLoad(target);
		container.Show();
	}

	// Begin load using manager and enable internal baloonLoadTime
	public void LoadScene(string target, bool loadTimeExtend) {
		if (target == null) {
			return;
		}

		GD.Print("starting ", target);
		baloonLoadTime = loadTimeExtend;
		LoadingManager.Instance.InitiateSceneLoad(target);
		container.Show();
	}

	// Called every frame
	public override void _Process(double delta) {
		base._Process(delta);

		// Don't do anything if not loaded
		if (!LoadingManager.Instance.IsLoading() && !loaded) return;

		if (loaded) {
			GD.Print(baloonLoadTime);
			if (baloonLoadTime) {
				// If loaded and baloonLoadTime enabled we lerp until 99% before finishing
				loadBar.Value = Mathf.Lerp(loadBar.Value, 100, delta * 150);

				if (loadBar.Value > 99) {
					Finish();
				}
			}
		} else {
			// If not loaded we set our percentage according to what we've been told
			loadBar.Value = Mathf.Lerp(loadBar.Value, managerProgress, delta * 150);
		}
	}

	public void Finish() {
		// Tell manager to finish
		LoadingManager.Instance.Finish();

		// Clear state
		managerProgress = 0;
		baloonLoadTime = true;
		loaded = false;

		container.Hide();
	}

	// Manager signal responses below
	public void UpdateProgress(float progress) {
		// Update manager progress according to newly reported state
		managerProgress = (int)(progress * 100);
	}

	public void Failed(string error) {
		GD.Print("Loading failed " + error);

		// display error, hide navbar and stop loading
		label.Text = "Loading failed " + error;
		loadBar.Hide();
	}

	// Set loaded variable
	public void Loaded() {
		if (!baloonLoadTime) {
			// If loaded and baloonLoadTime disbled we finish immedietly
			Finish();
			return;
		}

		// Otherwise we set the variabel for process to update progress
		loaded = true;
	}
}
