using Godot;

public partial class Main : Node {
	[Export(PropertyHint.File, "*.tscn,")] public string loadPath;

	public override void _Ready() {
		LoadingScreen.Instance.LoadScene(loadPath);
	}
}
