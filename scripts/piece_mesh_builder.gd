class_name PieceMeshBuilder


# Materials (created once, reused)
static var _wood_mat: StandardMaterial3D
static var _hull_mat: StandardMaterial3D  # double-sided for hull panels
static var _iron_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _ghost_mat: StandardMaterial3D

static func _ensure_materials() -> void:
	if _wood_mat:
		return
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.55, 0.35, 0.15)

	_hull_mat = StandardMaterial3D.new()
	_hull_mat.albedo_color = Color(0.50, 0.30, 0.12)
	_hull_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_iron_mat = StandardMaterial3D.new()
	_iron_mat.albedo_color = Color(0.4, 0.4, 0.45)
	_iron_mat.metallic = 0.6

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.45)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


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

	return root


# Build a ghost (transparent, no collision)
static func build_ghost(type: StringName) -> Node3D:
	_ensure_materials()
	var def: Dictionary = PieceDefs.DEFS[type]
	var sz: Vector3 = def.size
	var root := Node3D.new()

	match type:
		&"skeleton":
			_build_skeleton_ghost(root)
		&"window_wall":
			_build_window(root, sz, _ghost_mat)
		&"mast":
			_build_mast(root, sz, _ghost_mat)
		&"cannon":
			_build_cannon(root, sz, _ghost_mat)
		_:
			root.add_child(_box_mi(sz, Vector3.ZERO, _ghost_mat))
	return root


static func _build_skeleton_ghost(root: Node3D) -> void:
	var cfg := ShipConfig.new()
	var cy  := PieceDefs.DEFS[&"skeleton"].size.y * 0.5
	var keel_len := absf(cfg.bow_x - cfg.stern_x)
	var mid_x    := (cfg.bow_x + cfg.stern_x) * 0.5
	root.add_child(_box_mi(Vector3(keel_len, 0.3, 0.3), Vector3(mid_x, 0.15 - cy, 0.0), _ghost_mat))
	var last_x := cfg.rib_x_positions[cfg.rib_x_positions.size() - 1]
	var bow_h  := cfg.rib_height(last_x)
	root.add_child(_box_mi(Vector3(0.25, bow_h, 0.25), Vector3(cfg.bow_x - 0.05, bow_h * 0.5 - cy, 0.0), _ghost_mat))
	var first_x  := cfg.rib_x_positions[0]
	var stern_h  := cfg.rib_height(first_x)
	var stern_hw := cfg.rib_half_width(first_x) * 0.88 * 2.0
	root.add_child(_box_mi(Vector3(0.2, stern_h, stern_hw), Vector3(cfg.stern_x, stern_h * 0.5 - cy, 0.0), _ghost_mat))
	for xf: float in cfg.rib_x_positions:
		var h  := cfg.rib_height(xf)
		var hw := cfg.rib_half_width(xf)
		root.add_child(_box_mi(Vector3(0.12, h, hw * 2.0), Vector3(xf, h * 0.5 - cy, 0.0), _ghost_mat))


static func _build_window(root: Node3D, _sz: Vector3, mat: Material) -> void:
	# 4 frame pieces + glass pane (matches design doc dimensions)
	root.add_child(_box_mi(Vector3(1.0, 0.25, 0.12), Vector3(0, -0.375, 0), mat))
	root.add_child(_box_mi(Vector3(1.0, 0.25, 0.12), Vector3(0,  0.375, 0), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.5, 0.12), Vector3(-0.425, 0, 0), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.5, 0.12), Vector3( 0.425, 0, 0), mat))
	root.add_child(_box_mi(Vector3(0.7, 0.5, 0.03), Vector3.ZERO, mat))


static func _build_mast(root: Node3D, sz: Vector3, mat: Material) -> void:
	# Vertical pole + cross-beam
	root.add_child(_box_mi(Vector3(0.15, sz.y, 0.15), Vector3.ZERO, mat))
	root.add_child(_box_mi(Vector3(sz.x * 2.5, 0.12, 0.12), Vector3(0, sz.y * 0.35, 0), mat))


# ── Bent (hull) mesh ──────────────────────────────────────────────────────────

## Build a bent hull piece (mesh + convex collision).
## offsets: PackedFloat32Array of (segments+1) Y-displacements in local space.
static func build_bent_piece(type: StringName, offsets: PackedFloat32Array) -> Node3D:
	_ensure_materials()
	var def: Dictionary = PieceDefs.DEFS[type]
	var mat: Material = _iron_mat if def.get("material_tier", 0) == 2 else _wood_mat
	var sz: Vector3 = def.size
	var root := Node3D.new()
	root.add_child(_bent_mesh(sz, mat, offsets))
	var cs := CollisionShape3D.new()
	cs.shape = _bent_convex(sz, offsets)
	root.add_child(cs)
	return root


## Build a transparent bent ghost (no collision).
static func build_bent_ghost(type: StringName, offsets: PackedFloat32Array) -> Node3D:
	_ensure_materials()
	var sz: Vector3 = PieceDefs.DEFS[type].size
	var root := Node3D.new()
	root.add_child(_bent_mesh(sz, _ghost_mat, offsets))
	return root


## Generate a mesh for a plank bent along its local X axis using SurfaceTool
## (auto-computes correct normals from vertex winding).
static func _bent_mesh(sz: Vector3, mat: Material, offsets: PackedFloat32Array) -> MeshInstance3D:
	var segs := offsets.size() - 1
	var slen := sz.x / float(segs)
	var hy   := sz.y * 0.5
	var hz   := sz.z * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(segs):
		var x0 := float(i)      * slen - sz.x * 0.5
		var x1 := float(i + 1) * slen - sz.x * 0.5
		var y0 := offsets[i]
		var y1 := offsets[i + 1]

		var p: Array = [
			Vector3(x0, y0 + hy,  hz),  # 0 inner-top-back
			Vector3(x0, y0 - hy,  hz),  # 1 inner-bot-back
			Vector3(x0, y0 + hy, -hz),  # 2 inner-top-front
			Vector3(x0, y0 - hy, -hz),  # 3 inner-bot-front
			Vector3(x1, y1 + hy,  hz),  # 4 outer-top-back
			Vector3(x1, y1 - hy,  hz),  # 5 outer-bot-back
			Vector3(x1, y1 + hy, -hz),  # 6 outer-top-front
			Vector3(x1, y1 - hy, -hz),  # 7 outer-bot-front
		]

		_st_quad(st, p[0], p[1], p[4], p[5])  # +Z face
		_st_quad(st, p[6], p[7], p[2], p[3])  # -Z face
		_st_quad(st, p[2], p[0], p[6], p[4])  # +Y top
		_st_quad(st, p[1], p[3], p[5], p[7])  # -Y bottom
		if i == 0:
			_st_quad(st, p[0], p[2], p[1], p[3])  # inner cap
		if i == segs - 1:
			_st_quad(st, p[6], p[4], p[7], p[5])  # outer cap

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _st_quad(st: SurfaceTool,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(b); st.add_vertex(d); st.add_vertex(c)


## Convex hull collision from the bent segment boundary points.
static func _bent_convex(sz: Vector3, offsets: PackedFloat32Array) -> ConvexPolygonShape3D:
	var segs := offsets.size() - 1
	var slen := sz.x / float(segs)
	var hy   := sz.y * 0.5
	var hz   := sz.z * 0.5
	var pts  := PackedVector3Array()
	for i in range(segs + 1):
		var x  := float(i) * slen - sz.x * 0.5
		var yo := offsets[i]
		pts.append(Vector3(x, yo + hy,  hz))
		pts.append(Vector3(x, yo + hy, -hz))
		pts.append(Vector3(x, yo - hy,  hz))
		pts.append(Vector3(x, yo - hy, -hz))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


# ── Hull panel builders ───────────────────────────────────────────────────────

## pts_a, pts_b: PackedVector3Array in piece local space, matching HULL_PROFILE size.
## Lofts a quad strip between the two rib profiles with inner+outer faces.
static func build_hull_panel(pts_a: PackedVector3Array, pts_b: PackedVector3Array) -> Node3D:
	_ensure_materials()
	var root := Node3D.new()
	root.add_child(_hull_panel_mesh(pts_a, pts_b, _hull_mat))
	var cs := CollisionShape3D.new()
	cs.shape = _hull_panel_convex(pts_a, pts_b)
	root.add_child(cs)
	return root


static func build_hull_panel_ghost(pts_a: PackedVector3Array, pts_b: PackedVector3Array) -> Node3D:
	_ensure_materials()
	var root := Node3D.new()
	root.add_child(_hull_panel_mesh(pts_a, pts_b, _ghost_mat))
	return root


static func _hull_panel_mesh(pts_a: PackedVector3Array, pts_b: PackedVector3Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts_a.size()
	for i in range(n - 1):
		_st_quad(st, pts_a[i], pts_b[i], pts_a[i + 1], pts_b[i + 1])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _hull_panel_convex(pts_a: PackedVector3Array, pts_b: PackedVector3Array) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	for p: Vector3 in pts_a: pts.append(p)
	for p: Vector3 in pts_b: pts.append(p)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


# ── Special piece builders ────────────────────────────────────────────────────

static func _build_cannon(root: Node3D, sz: Vector3, mat: Material) -> void:
	# Barrel + carriage + two wheels
	root.add_child(_box_mi(Vector3(0.25, 0.25, sz.z * 0.8), Vector3(0, 0.1, 0), mat))
	root.add_child(_box_mi(Vector3(sz.x * 0.9, 0.2, sz.z * 0.6), Vector3(0, -0.2, 0), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.3, 0.15), Vector3(-0.25, -0.25, -0.1), mat))
	root.add_child(_box_mi(Vector3(0.15, 0.3, 0.15), Vector3( 0.25, -0.25, -0.1), mat))
