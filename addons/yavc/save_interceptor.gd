@tool
extends EditorInspectorPlugin
## Intercepts save operations to block saving locked files
##
## This plugin works together with YavcPlugin to prevent saving
## resources that are locked by other users.

var _yavc_plugin: EditorPlugin

func _init(plugin: EditorPlugin) -> void:
	_yavc_plugin = plugin

func _can_handle(object: Object) -> bool:
	# Handle all resources to check locks on save
	return object is Resource

func _parse_begin(object: Object) -> void:
	if not object is Resource:
		return
	
	var resource := object as Resource
	var path := resource.resource_path
	
	if path.is_empty():
		return
	
	# Check if locked by others
	if _yavc_plugin.has_method("can_save_resource"):
		if not _yavc_plugin.can_save_resource(path):
			var holder: String = ""
			if _yavc_plugin.has_method("get_lock_holder"):
				holder = _yavc_plugin.get_lock_holder(path)
			
			# Add a warning label at the top
			var warning := Label.new()
			warning.text = "⚠️ LOCKED by %s - Saving disabled" % holder
			warning.add_theme_color_override("font_color", Color.RED)
			add_custom_control(warning)
