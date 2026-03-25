@tool
extends EditorPlugin

var _gizmo_plugin: ShipSkeletonGizmoPlugin


func _enter_tree() -> void:
	_gizmo_plugin = ShipSkeletonGizmoPlugin.new()
	add_node_3d_gizmo_plugin(_gizmo_plugin)


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo_plugin)
	_gizmo_plugin = null


