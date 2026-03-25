@tool
extends EditorPlugin

var _gizmo_plugin: ShipSkeletonGizmoPlugin

const WATCHED := [
	"addons/ship_builder/ship_skeleton_gizmo.gd",
	"scripts/ship_skeleton.gd",
	"scripts/ship_config.gd",
]


func _enter_tree() -> void:
	_mount_gizmo()
	EditorInterface.get_resource_filesystem().resources_reimported.connect(_on_reimported)


func _exit_tree() -> void:
	EditorInterface.get_resource_filesystem().resources_reimported.disconnect(_on_reimported)
	_unmount_gizmo()


func _on_reimported(resources: PackedStringArray) -> void:
	for r in resources:
		if r in WATCHED:
			call_deferred("_remount_gizmo")
			return


func _remount_gizmo() -> void:
	_unmount_gizmo()
	_mount_gizmo()


func _mount_gizmo() -> void:
	_gizmo_plugin = ShipSkeletonGizmoPlugin.new()
	add_node_3d_gizmo_plugin(_gizmo_plugin)


func _unmount_gizmo() -> void:
	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null
