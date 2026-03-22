class_name BuildSystem
extends Node3D


@export var build_camera: Camera3D
@export var ship_root: RigidBody3D
@export var placed_pieces_node: Node3D
@export var ghost_pivot: Node3D
@export var ghost_mesh_node: Node3D

@export var rotation_step_deg: float = 15.0

var selected_piece: StringName = &"plank"
var piece_rot: float = 0.0
var rot_axis_index: int = 0

var placed_pieces: Array[ShipPiece] = []
var stability := StabilitySystem.new()

# Symmetry — reflects placements across a plane defined by origin + normal
var symmetry_enabled: bool = false
var symmetry_origin: Vector3 = Vector3.ZERO
var symmetry_normal: Vector3 = Vector3(0, 0, 1)  # Z=0 plane (ship centerline)

signal piece_placed(piece: ShipPiece)
signal piece_removed(piece: ShipPiece)

const PIECE_CYCLE: Array = [
	&"plank", &"iron_plank", &"deck", &"wall",
	&"half_wall", &"window_wall", &"beam", &"mast", &"cannon",
	&"foundation", &"post", &"floor_board", &"roof_panel", &"door_frame", &"stair",
]

var _piece_index: int = 0
var _last_normal: Vector3 = Vector3.ZERO
var _ghost_valid: bool = false
var _ghost_world_center: Vector3 = Vector3.ZERO
var _current_normal: Vector3 = Vector3.UP
var _ghost_pivot_mirror: Node3D
var _ghost_mesh_node_mirror: Node3D
var _axis_indicator: MeshInstance3D


func _ready() -> void:
	_setup_mirror_ghost()
	await get_tree().process_frame
	_refresh_keel_refs()
	_rebuild_ghost()
	_setup_axis_indicator()


func _setup_mirror_ghost() -> void:
	_ghost_pivot_mirror = Node3D.new()
	_ghost_mesh_node_mirror = Node3D.new()
	_ghost_pivot_mirror.add_child(_ghost_mesh_node_mirror)
	_ghost_pivot_mirror.visible = false
	add_child(_ghost_pivot_mirror)


func _refresh_keel_refs() -> void:
	stability.keel_parts.clear()
	var keel_group := ship_root.get_node_or_null("KeelGroup") as Node3D
	if keel_group:
		for child: Node in keel_group.get_children():
			stability.keel_parts.append(child)



func _setup_axis_indicator() -> void:
	_axis_indicator = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 2.0, 0.04)
	_axis_indicator.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.RED
	_axis_indicator.material_override = mat
	ghost_pivot.add_child(_axis_indicator)
	_axis_indicator.visible = false


func _rebuild_ghost() -> void:
	for child in ghost_mesh_node.get_children():
		child.queue_free()
	ghost_mesh_node.add_child(PieceMeshBuilder.build_ghost(selected_piece))
	if _ghost_mesh_node_mirror:
		for child in _ghost_mesh_node_mirror.get_children():
			child.queue_free()
		_ghost_mesh_node_mirror.add_child(PieceMeshBuilder.build_ghost(selected_piece))


func select_piece(type: StringName) -> void:
	selected_piece = type
	if type == &"":
		return
	_piece_index = PIECE_CYCLE.find(type)
	_rebuild_ghost()


func _physics_process(_delta: float) -> void:
	if not build_camera or selected_piece == &"":
		ghost_pivot.visible = false
		_ghost_pivot_mirror.visible = false
		_ghost_valid = false
		if _axis_indicator:
			_axis_indicator.visible = false
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := build_camera.project_ray_origin(mouse_pos)
	var ray_dir    := build_camera.project_ray_normal(mouse_pos)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 50.0)
	query.collision_mask = 0b0011  # layer 1 = skeleton, layer 2 = placed pieces

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		ghost_pivot.visible = false
		_ghost_pivot_mirror.visible = false
		_ghost_valid = false
		if _axis_indicator:
			_axis_indicator.visible = false
		return

	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	if hit_normal.dot(_last_normal) < 0.99:
		piece_rot = 0.0
		_last_normal = hit_normal

	var def: Dictionary = PieceDefs.DEFS[selected_piece]
	var sz: Vector3     = def.size
	var fa: int         = def.get("face_axis", 2)
	var h_out           := BuildUtils.half_out(sz, fa)

	if absf(hit_normal.y) < 0.9:
		hit_point = BuildUtils.snap_vertical(hit_point, sz, _collect_edge_ys())

	_current_normal = hit_normal

	# Compute base orientation and world-space spin axis
	var base       := BuildUtils.surface_base(hit_normal, fa)
	var spin_local := Vector3.RIGHT if rot_axis_index == 0 else (Vector3.UP if rot_axis_index == 1 else Vector3.BACK)
	var spin_world := (base * spin_local).normalized()
	var spin_rot   := Basis(spin_world, piece_rot)

	# Primary ghost — piece rotates around pivot (hit_point)
	ghost_pivot.global_position = hit_point
	ghost_pivot.rotation        = Vector3.ZERO
	ghost_mesh_node.position    = spin_rot * (hit_normal * h_out)
	ghost_mesh_node.basis       = spin_rot * base
	ghost_pivot.visible         = true
	_ghost_valid                = true
	_ghost_world_center         = hit_point + ghost_mesh_node.position

	# Axis indicator — at pivot, oriented along spin_world
	if _axis_indicator:
		_axis_indicator.visible = true
		_axis_indicator.position = Vector3.ZERO
		const AXIS_COLORS := [Color.RED, Color.GREEN, Color.BLUE]
		var ref2 := Vector3.FORWARD if absf(spin_world.dot(Vector3.UP)) > 0.99 else Vector3.UP
		var ax := ref2.cross(spin_world).normalized()
		var az := spin_world.cross(ax).normalized()
		_axis_indicator.basis = Basis(ax, spin_world, az)
		(_axis_indicator.material_override as StandardMaterial3D).albedo_color = AXIS_COLORS[rot_axis_index]

	# Mirror ghost
	if symmetry_enabled:
		var m_hit    := BuildUtils.reflect_point(hit_point, symmetry_origin, symmetry_normal)
		var m_normal := BuildUtils.reflect_dir(hit_normal, symmetry_normal)
		var m_base   := BuildUtils.surface_base(m_normal, fa)
		var m_spin_w := BuildUtils.reflect_dir(spin_world, symmetry_normal).normalized()
		var m_rot    := Basis(m_spin_w, -piece_rot)
		_ghost_pivot_mirror.global_position = m_hit
		_ghost_pivot_mirror.rotation        = Vector3.ZERO
		_ghost_mesh_node_mirror.position    = m_rot * (m_normal * h_out)
		_ghost_mesh_node_mirror.basis       = m_rot * m_base
		_ghost_pivot_mirror.visible         = true
	else:
		_ghost_pivot_mirror.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				rot_axis_index = (rot_axis_index + 1) % 3
				piece_rot = 0.0
				return
			KEY_M:
				symmetry_enabled = not symmetry_enabled
				_ghost_pivot_mirror.visible = false
				return
			KEY_TAB:
				_piece_index = (_piece_index + 1) % PIECE_CYCLE.size()
				select_piece(PIECE_CYCLE[_piece_index])
				return
			_:
				for i in range(mini(9, PIECE_CYCLE.size())):
					if event.keycode == KEY_1 + i:
						var t: StringName = PIECE_CYCLE[i]
						select_piece(&"" if selected_piece == t else t)
						return

	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _ghost_valid:
					_place_piece()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_remove_piece_at_cursor()
			MOUSE_BUTTON_WHEEL_UP:
				if selected_piece != &"":
					var step := deg_to_rad(rotation_step_deg * (0.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0))
					piece_rot += step
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if selected_piece != &"":
					var step := deg_to_rad(rotation_step_deg * (0.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0))
					piece_rot -= step
					get_viewport().set_input_as_handled()


func _place_piece() -> void:
	var piece := _spawn_piece(selected_piece, _ghost_world_center, ghost_mesh_node.basis)

	if symmetry_enabled:
		var fa: int = PieceDefs.DEFS[selected_piece].get("face_axis", 2)
		var m_center := BuildUtils.reflect_point(_ghost_world_center, symmetry_origin, symmetry_normal)
		var m_normal := BuildUtils.reflect_dir(_current_normal, symmetry_normal)
		_spawn_piece(selected_piece, m_center, BuildUtils.surface_basis(m_normal, fa, -piece_rot, rot_axis_index))

	stability.compute(placed_pieces)
	emit_signal("piece_placed", piece)


func _spawn_piece(type: StringName, pos: Vector3, piece_basis: Basis) -> ShipPiece:
	var piece := ShipPiece.new()
	piece.setup(type)
	piece.add_child(PieceMeshBuilder.build_piece(type))
	placed_pieces_node.add_child(piece)
	piece.global_position = pos
	piece.basis = piece_basis
	placed_pieces.append(piece)
	return piece


func _remove_piece_at_cursor() -> void:
	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := build_camera.project_ray_origin(mouse_pos)
	var ray_dir    := build_camera.project_ray_normal(mouse_pos)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 50.0)
	query.collision_mask = 2

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var node: Node = result.collider
	while node != null and not (node is ShipPiece):
		node = node.get_parent()

	if node is ShipPiece:
		placed_pieces.erase(node)
		node.queue_free()
		stability.compute(placed_pieces)
		emit_signal("piece_removed", node as ShipPiece)


func _collect_edge_ys() -> Array[float]:
	var edges: Array[float] = []

	var keel_group := ship_root.get_node_or_null("KeelGroup") as Node3D
	if keel_group:
		for child: Node in keel_group.get_children():
			if child is StaticBody3D:
				edges.append_array(BuildUtils.body_edge_ys(child as StaticBody3D))

	for piece: ShipPiece in placed_pieces:
		var h: float = PieceDefs.DEFS[piece.piece_type].size.y / 2.0
		edges.append(piece.global_position.y + h)
		edges.append(piece.global_position.y - h)

	return edges
