@tool
extends EditorScript

## Run this from Script → Run (Ctrl+Shift+X) to hot-reload the Ship Builder plugin.
func _run() -> void:
	var ep := get_editor_interface()
	ep.set_plugin_enabled("ship_builder", false)
	ep.set_plugin_enabled("ship_builder", true)
	print("Ship Builder plugin reloaded.")
