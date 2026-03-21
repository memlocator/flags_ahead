class_name ShipSkeleton
extends Node3D

# Collision layer 1 = skeleton (build-mode raycast target)
const LAYER_SKELETON := 1

func build() -> void:
	_add_keel()
	_add_ribs()
	_add_bow()
	_add_stern()


func _make_part(mesh_size: Vector3, pos: Vector3, rot_deg: float = 0.0, color: Color = Color(0.3, 0.2, 0.08)) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_SKELETON
	body.collision_mask = 0
	body.position = pos
	if rot_deg != 0.0:
		body.rotation_degrees.z = rot_deg

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = mesh_size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh_size
	cs.shape = shape
	body.add_child(cs)

	add_child(body)
	return body


func _add_keel() -> void:
	_make_part(Vector3(10.0, 0.3, 0.3), Vector3(0, 0.15, 0), 0.0, Color(0.25, 0.15, 0.06))


func _add_ribs() -> void:
	var rib_xs := [-4.0, -2.0, 0.0, 2.0, 4.0]
	for x: float in rib_xs:
		var h := 2.5 - absf(x) * 0.12
		var w := 2.2 - absf(x) * 0.1
		_make_part(Vector3(0.12, h, w), Vector3(x, h * 0.5, 0), 0.0, Color(0.35, 0.22, 0.09))


func _add_bow() -> void:
	_make_part(Vector3(0.25, 1.8, 0.25), Vector3(5.0, 0.9, 0), 15.0, Color(0.28, 0.18, 0.07))


func _add_stern() -> void:
	_make_part(Vector3(0.2, 2.2, 1.6), Vector3(-5.0, 1.1, 0), 0.0, Color(0.28, 0.18, 0.07))
