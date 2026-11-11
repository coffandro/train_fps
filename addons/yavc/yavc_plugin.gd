@tool
extends EditorPlugin
## YAVC Editor Plugin - File locking integration
##
## This plugin integrates with YAVC (Yet Another Version Control) to provide:
## - Automatic file locking on open
## - Block saving to files locked by others  
## - Auto-refresh and lock acquisition when files are unlocked by others

const YavcClientScript := preload("res://addons/yavc/yavc_client.gd")
const FileSystemWatcherScript := preload("res://addons/yavc/file_system_watcher.gd")

# Configuration
var _config_host := "127.0.0.1"
var _config_port := 7879
var _config_username := ""

# State
var _client: YavcClient
var _file_watcher: YavcFileSystemWatcher
var _locked_by_us: Dictionary = {}  # path -> true
var _locked_by_others: Dictionary = {}  # path -> holder name
var _pending_locks: Dictionary = {}  # path -> true (files we want to lock when available)
var _poll_timer: Timer
var _dock: Control
var _status_label: Label
var _locks_list: ItemList
var _save_blocked: bool = false

func _enter_tree() -> void:
	_load_config()
	_setup_client()
	_setup_dock()
	_setup_polling()
	_setup_file_watcher()
	_connect_editor_signals()
	print("YAVC Plugin: Initialized")

func _exit_tree() -> void:
	_disconnect_editor_signals()
	
	if _poll_timer:
		_poll_timer.stop()
		_poll_timer.queue_free()
	
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	
	# Unlock all our files before exiting
	if _client and _client.is_connected_to_server():
		for path in _locked_by_us.keys():
			_client.unlock_file(path)
		_client.disconnect_from_server()
	
	print("YAVC Plugin: Shutdown")

func _setup_file_watcher() -> void:
	_file_watcher = FileSystemWatcherScript.new(get_editor_interface())
	_file_watcher.file_opened.connect(_on_file_opened)
	_file_watcher.file_closed.connect(_on_file_closed)

func _load_config() -> void:
	# Load from project settings or environment
	_config_host = ProjectSettings.get_setting("yavc/server_host", "127.0.0.1")
	_config_port = ProjectSettings.get_setting("yavc/server_port", 7879)
	_config_username = ProjectSettings.get_setting("yavc/username", "")
	
	if _config_username.is_empty():
		# Try environment variable
		_config_username = OS.get_environment("YAVC_USER")
	
	if _config_username.is_empty():
		# Fall back to system username
		_config_username = OS.get_environment("USER")
		if _config_username.is_empty():
			_config_username = OS.get_environment("USERNAME")
		if _config_username.is_empty():
			_config_username = "GodotUser"
	
	# Register project settings if not exist
	if not ProjectSettings.has_setting("yavc/server_host"):
		ProjectSettings.set_setting("yavc/server_host", _config_host)
		ProjectSettings.add_property_info({
			"name": "yavc/server_host",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": ""
		})
	
	if not ProjectSettings.has_setting("yavc/server_port"):
		ProjectSettings.set_setting("yavc/server_port", _config_port)
		ProjectSettings.add_property_info({
			"name": "yavc/server_port",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "1,65535,1"
		})
	
	if not ProjectSettings.has_setting("yavc/username"):
		ProjectSettings.set_setting("yavc/username", "")
		ProjectSettings.add_property_info({
			"name": "yavc/username",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": ""
		})

func _setup_client() -> void:
	_client = YavcClientScript.new()
	
	# Connect signals
	_client.connected.connect(_on_client_connected)
	_client.disconnected.connect(_on_client_disconnected)
	_client.lock_granted.connect(_on_lock_granted)
	_client.lock_denied.connect(_on_lock_denied)
	_client.unlock_confirmed.connect(_on_unlock_confirmed)
	_client.file_locked.connect(_on_file_locked_by_other)
	_client.file_unlocked.connect(_on_file_unlocked_by_other)
	_client.error.connect(_on_client_error)
	
	# Connect to server
	_connect_to_server()

func _connect_to_server() -> void:
	var err := await _client.connect_to_server(_config_host, _config_port)
	if err == OK:
		await _client.register(_config_username)
		_update_status("Connected as %s" % _config_username)
	else:
		_update_status("Disconnected - server unavailable")

func _setup_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "YAVC"
	
	# Status label
	_status_label = Label.new()
	_status_label.text = "Connecting..."
	_dock.add_child(_status_label)
	
	# Separator
	var sep1 := HSeparator.new()
	_dock.add_child(sep1)
	
	# Locks list header
	var locks_header := Label.new()
	locks_header.text = "Active Locks:"
	_dock.add_child(locks_header)
	
	# Locks list
	_locks_list = ItemList.new()
	_locks_list.custom_minimum_size = Vector2(200, 150)
	_locks_list.auto_height = false
	_dock.add_child(_locks_list)
	
	# Separator
	var sep2 := HSeparator.new()
	_dock.add_child(sep2)
	
	# Buttons container
	var buttons := HBoxContainer.new()
	_dock.add_child(buttons)
	
	# Refresh button
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_locks)
	buttons.add_child(refresh_btn)
	
	# Reconnect button
	var reconnect_btn := Button.new()
	reconnect_btn.text = "Reconnect"
	reconnect_btn.pressed.connect(_reconnect)
	buttons.add_child(reconnect_btn)
	
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _setup_polling() -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.1  # Poll every 100ms
	_poll_timer.timeout.connect(_on_poll_timer)
	add_child(_poll_timer)
	_poll_timer.start()

func _connect_editor_signals() -> void:
	# Connect to resource saved signal
	var editor := get_editor_interface()
	var fs := editor.get_resource_filesystem()
	fs.resources_reimported.connect(_on_resources_reimported)
	
	# Hook into saving via the edited scene
	resource_saved.connect(_on_resource_saved)

func _disconnect_editor_signals() -> void:
	var editor := get_editor_interface()
	var fs := editor.get_resource_filesystem()
	if fs.resources_reimported.is_connected(_on_resources_reimported):
		fs.resources_reimported.disconnect(_on_resources_reimported)

func _on_poll_timer() -> void:
	if _client:
		_client.poll()
	
	# Check for newly edited files using file watcher
	if _file_watcher:
		_file_watcher.check_for_changes()
	
	# Update locks list periodically
	_update_locks_list()

func _update_locks_list() -> void:
	if not _locks_list:
		return
	
	_locks_list.clear()
	
	# Add our locks (green)
	for path in _locked_by_us:
		var idx := _locks_list.add_item("🔒 %s (You)" % path)
		_locks_list.set_item_custom_fg_color(idx, Color.GREEN)
	
	# Add others' locks (red)
	for path in _locked_by_others:
		var holder: String = _locked_by_others[path]
		var idx := _locks_list.add_item("🔒 %s (%s)" % [path, holder])
		_locks_list.set_item_custom_fg_color(idx, Color.RED)

func _on_file_opened(path: String) -> void:
	if not _client or not _client.is_connected_to_server():
		return
	
	# Convert to relative path for YAVC
	var relative_path := _make_relative_path(path)
	
	# Skip if already locked by us
	if relative_path in _locked_by_us:
		return
	
	print("YAVC: File opened, requesting lock: %s" % relative_path)
	
	var err := await _client.lock_file(relative_path)
	if err == OK:
		_locked_by_us[relative_path] = true
	elif err == ERR_LOCKED:
		# File is locked by someone else, we'll wait for unlock notification
		_pending_locks[relative_path] = true

func _on_file_closed(path: String) -> void:
	if not _client or not _client.is_connected_to_server():
		return
	
	var relative_path := _make_relative_path(path)
	
	if relative_path in _locked_by_us:
		print("YAVC: File closed, releasing lock: %s" % relative_path)
		_client.unlock_file(relative_path)
		_locked_by_us.erase(relative_path)
	
	_pending_locks.erase(relative_path)

func _on_resource_saved(resource: Resource) -> void:
	var path := resource.resource_path
	var relative_path := _make_relative_path(path)
	
	# Check if file is locked by someone else
	if relative_path in _locked_by_others:
		var holder: String = _locked_by_others[relative_path]
		push_error("YAVC: Cannot save %s - locked by %s" % [path, holder])
		# Show warning dialog
		_show_lock_warning(path, holder)

func _handles(object: Object) -> bool:
	# We don't handle any specific objects, but we use this for tracking
	return false

func _save_external_data() -> void:
	# Called before saving - we can block here
	pass

## Override to block saving locked files
func _get_unsaved_status(for_scene: String) -> String:
	var relative_path := _make_relative_path(for_scene)
	if relative_path in _locked_by_others:
		var holder: String = _locked_by_others[relative_path]
		return "LOCKED by %s" % holder
	return ""

# Client signal handlers

func _on_client_connected() -> void:
	_update_status("Connected")

func _on_client_disconnected() -> void:
	_update_status("Disconnected")
	_locked_by_us.clear()
	_locked_by_others.clear()

func _on_lock_granted(path: String) -> void:
	print("YAVC: Lock granted: %s" % path)
	_locked_by_us[path] = true
	_locked_by_others.erase(path)
	_pending_locks.erase(path)
	_set_file_readonly(path, false)  # Ensure we can write

func _on_lock_denied(path: String, holder: String) -> void:
	print("YAVC: Lock denied: %s (held by %s)" % [path, holder])
	_locked_by_others[path] = holder
	_pending_locks[path] = true
	_set_file_readonly(path, true)  # Block saves at OS level
	_show_lock_notification(path, holder)

func _on_unlock_confirmed(path: String) -> void:
	print("YAVC: Unlock confirmed: %s" % path)
	_locked_by_us.erase(path)

func _on_file_locked_by_other(path: String, holder: String) -> void:
	print("YAVC: File locked by %s: %s" % [holder, path])
	_locked_by_others[path] = holder
	_set_file_readonly(path, true)  # Block saves at OS level

func _on_file_unlocked_by_other(path: String) -> void:
	print("YAVC: File unlocked: %s" % path)
	_locked_by_others.erase(path)
	_set_file_readonly(path, false)  # Restore write access
	
	# If we were waiting for this file, try to lock it
	if path in _pending_locks:
		print("YAVC: Auto-acquiring lock for: %s" % path)
		_pending_locks.erase(path)
		
		# Refresh the file first
		_refresh_file(path)
		
		# Then try to lock
		var err := await _client.lock_file(path)
		if err == OK:
			_locked_by_us[path] = true
			_show_lock_acquired_notification(path)

func _on_client_error(message: String) -> void:
	push_error("YAVC Error: %s" % message)

# Helper functions

func _make_relative_path(path: String) -> String:
	# Remove res:// prefix for YAVC
	if path.begins_with("res://"):
		return path.substr(6)
	return path

func _make_resource_path(path: String) -> String:
	# Add res:// prefix
	if not path.begins_with("res://"):
		return "res://" + path
	return path

func _refresh_file(path: String) -> void:
	# Reload the file from disk
	var resource_path := _make_resource_path(path)
	var editor := get_editor_interface()
	var fs := editor.get_resource_filesystem()
	
	# Scan for changes
	fs.scan()
	
	# If it's the current scene, reload it
	var edited_scene := editor.get_edited_scene_root()
	if edited_scene and edited_scene.scene_file_path == resource_path:
		# Reopen the scene
		editor.reload_scene_from_path(resource_path)

func _refresh_locks() -> void:
	if not _client or not _client.is_connected_to_server():
		return
	
	var locks := await _client.list_locks()
	_locked_by_others.clear()
	
	for lock_entry in locks:
		if lock_entry is Array and lock_entry.size() >= 2:
			var path: String = lock_entry[0]
			var state: Dictionary = lock_entry[1]
			
			if state.has("Locked"):
				var holder: String = state["Locked"].get("holder_name", "Unknown")
				# Check if it's our lock
				var client_id: String = state["Locked"].get("client_id", "")
				if client_id != _client._client_id:
					_locked_by_others[path] = holder
	
	_update_locks_list()
	print("YAVC: Refreshed locks - %d files locked by others" % _locked_by_others.size())

func _reconnect() -> void:
	if _client:
		_client.disconnect_from_server()
	_connect_to_server()

func _update_status(status: String) -> void:
	if _status_label:
		_status_label.text = "YAVC: %s" % status

func _show_lock_warning(path: String, holder: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Cannot Save - File Locked"
	dialog.dialog_text = "Cannot save '%s'\n\nThis file is locked by: %s\n\nWait for them to release the lock, or contact them." % [path, holder]
	dialog.dialog_hide_on_ok = true
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)

func _show_lock_notification(path: String, holder: String) -> void:
	print("YAVC: File '%s' is locked by %s" % [path, holder])
	# Could show a toast notification here

func _show_lock_acquired_notification(path: String) -> void:
	print("YAVC: Automatically acquired lock for '%s'" % path)
	# Could show a toast notification here

func _on_resources_reimported(resources: PackedStringArray) -> void:
	# Handle reimported resources if needed
	pass

## Check if saving is allowed for a resource
func can_save_resource(path: String) -> bool:
	var relative_path := _make_relative_path(path)
	if relative_path in _locked_by_others:
		return false
	return true

## Get the holder of a lock
func get_lock_holder(path: String) -> String:
	var relative_path := _make_relative_path(path)
	if relative_path in _locked_by_others:
		return _locked_by_others[relative_path]
	return ""

## Make a file read-only at the OS level
func _set_file_readonly(path: String, readonly: bool) -> void:
	var absolute_path := _get_absolute_path(path)
	if absolute_path.is_empty():
		return
	
	if not FileAccess.file_exists(absolute_path):
		return
	
	var result: int
	if readonly:
		# Remove write permission: chmod a-w
		result = OS.execute("chmod", ["a-w", absolute_path])
		if result == OK:
			print("YAVC: Made file read-only: %s" % path)
	else:
		# Add write permission: chmod u+w
		result = OS.execute("chmod", ["u+w", absolute_path])
		if result == OK:
			print("YAVC: Made file writable: %s" % path)

## Get absolute filesystem path from relative path
func _get_absolute_path(path: String) -> String:
	var resource_path := _make_resource_path(path)
	return ProjectSettings.globalize_path(resource_path)
