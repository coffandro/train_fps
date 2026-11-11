@tool
class_name YavcFileSystemWatcher
extends RefCounted
## Monitors file system for opened/closed files
##
## Since Godot doesn't have direct file open/close events,
## we track edited scenes and scripts to detect opens and closes.

signal file_opened(path: String)
signal file_closed(path: String)

var _editor_interface: EditorInterface
var _tracked_files: Dictionary = {}  # path -> true
var _last_edited_scene: String = ""
var _last_edited_scripts: Array[String] = []

func _init(editor: EditorInterface) -> void:
	_editor_interface = editor

func check_for_changes() -> void:
	var current_files: Dictionary = {}
	
	# Check edited scene
	var edited_scene := _editor_interface.get_edited_scene_root()
	if edited_scene:
		var scene_path := edited_scene.scene_file_path
		if not scene_path.is_empty():
			current_files[scene_path] = true
	
	# Check open scripts
	var script_editor := _editor_interface.get_script_editor()
	var open_scripts := script_editor.get_open_scripts()
	for script in open_scripts:
		if script:
			var script_path := script.resource_path
			if not script_path.is_empty():
				current_files[script_path] = true
	
	# Detect newly opened files
	for path in current_files:
		if path not in _tracked_files:
			file_opened.emit(path)
	
	# Detect closed files
	for path in _tracked_files:
		if path not in current_files:
			file_closed.emit(path)
	
	# Update tracking
	_tracked_files = current_files

func get_open_files() -> Array[String]:
	var files: Array[String] = []
	for path in _tracked_files:
		files.append(path)
	return files

func is_file_open(path: String) -> bool:
	return path in _tracked_files
