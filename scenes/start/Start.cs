using Godot;

public partial class Start : Node {
    [Export(PropertyHint.File, "*.tscn,")] public string loadPath;

    public void _on_play_button_pressed() {
        LoadingScreen.Instance.LoadScene(loadPath);
    }
}
