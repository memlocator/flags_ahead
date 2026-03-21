class_name PieceMeshBuilder


# Materials (created once, reused)
static var _wood_mat: StandardMaterial3D
static var _iron_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _ghost_mat: StandardMaterial3D

static func _ensure_materials() -> void:
	if _wood_mat:
		return
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.55, 0.35, 0.15)

	_iron_mat = StandardMaterial3D.new()
	_iron_mat.albedo_color = Color(0.4, 0.4, 0.45)
	_iron_mat.metallic = 0.6

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.45)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


static func _box_mi(size: Vector3, offset: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = offset
	mi.material_override = mat
	return mi


# Build a placed piece node (StaticBody3D with mesh + collision)
static func build_piece(type: StringName) -> Node3D:
	_ensure_materials()
	var def: Dictionary = PieceDefs.DEFS[type]
	var tier: int = def.get("material_tier", 0)
	var mat: Material = _iron_mat if tier == 2 else _wood_mat
	var sz: Vector3 = def.size
	var root := Node3D.new()

	match type:
		&"window_wall":
			_build_window(root, sz, mat)
		&"mast":
			_build_mast(root, sz, mat)
		&"cannon":
			_build_cannon(root, sz, mat)
		_:
			root.add_child(_box_mi(sz, Vector3.ZERO, mat))

	# Single box collider sized to def.size
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	cs.shape = shape
	root.add_child(cs)
	return root


# Build a ghost (transparent, no collision)
static func build_ghost(type: StringName) -> Node3D:
	_ensure_materials()
	var def: Dictionary = PieceDefs.DEFS[type]
	var sz: Vector3 = def.size
	var root := Node3D.new()

	match type:
		&"window_wall":
			_build_window(root, sz, _ghost_mat)
		&"mast":
			_build_mast(root, sz, _ghost_mat)
		&"cannon":
			_build_cannon(root, sz, _ghost_mat)
		_:
			root.add_child(_box_mi(sz, Vector3.ZERO, _ghost_mat))
	return root


static func _build_window(root: Node3D, _sz: Vector3, mat: Material) -> void:
	# 4 frame pieces + glass pane (matches design doc dimensions)
	root.add_child(_box_mi(Vector3(1.0, 0.25, 0.12), Vector3(0, -0.375, 0), mat))
	root.add_child(_box_mi(Vector3(1.0, 0.25, 0.12), Vector3(0,  0.375, 0), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.5, 0.12), Vector3(-0.425, 0, 0), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.5, 0.12), Vector3( 0.425, 0, 0), mat))
	root.add_child(_box_mi(Vector3(0.7, 0.5, 0.03), Vector3.ZERO, _glass_mat))


static func _build_mast(root: Node3D, sz: Vector3, mat: Material) -> void:
	# Vertical pole + cross-beam
	root.add_child(_box_mi(Vector3(0.15, sz.y, 0.15), Vector3.ZERO, mat))
	root.add_child(_box_mi(Vector3(sz.x * 2.5, 0.12, 0.12), Vector3(0, sz.y * 0.35, 0), mat))


static func _build_cannon(root: Node3D, sz: Vector3, mat: Material) -> void:
	# Barrel + carriage + two wheels
	root.add_child(_box_mi(Vector3(0.25, 0.25, sz.z * 0.8), Vector3(0, 0.1, 0), mat))
	root.add_child(_box_mi(Vector3(sz.x * 0.9, 0.2, sz.z * 0.6), Vector3(0, -0.2, 0), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.3, 0.15), Vector3(-0.25, -0.25, -0.1), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.3, 0.15), Vector3( 0.25, -0.25, -0.1), mat))
