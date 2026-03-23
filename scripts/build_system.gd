class_name BuildSystem
extends Node3D


@export var build_camera: Camera3D
@export var ship_root: RigidBody3D
@export var placed_pieces_node: Node3D
@export var ghost_pivot: Node3D
@export var ghost_mesh_node: Node3D

@export var rotation_step_deg: float = 15.0
@export var rotation_smooth: float = 14.0

var selected_piece: StringName = &"plank"
var _target_rots: Array[float] = [0.0, 0.0, 0.0]
var _smooth_spin_rot: Basis = Basis.IDENTITY
var _smooth_mirror_spin_rot: Basis = Basis.IDENTITY
var rot_axis_index: int = 0

var placed_pieces: Array[ShipPiece] = []
var graph := StructuralGraph.new()

# Symmetry — reflects placements across a plane defined by origin + normal
var symmetry_enabled: bool = false
var snapping_enabled: bool = true
var symmetry_origin: Vector3 = Vector3.ZERO
var symmetry_normal: Vector3 = Vector3(0, 0, 1)  # Z=0 plane (ship centerline)

enum PlaceReason  { PLAYER, MIRROR, LOADED }
enum RemoveReason { PLAYER, INSTABILITY, CLEARED }

signal piece_added(piece: ShipPiece, reason: PlaceReason, source: Node)
signal piece_destroyed(piece: ShipPiece, reason: RemoveReason, source: Node)
signal structure_changed()
signal piece_selected(type: StringName)
signal piece_deselected()
signal symmetry_changed(enabled: bool)
signal snapping_changed(enabled: bool)

const PIECE_CYCLE: Array = [
	&"plank", &"iron_plank", &"deck", &"wall",
	&"half_wall", &"window_wall", &"beam", &"mast", &"cannon",
	&"foundation", &"post", &"floor_board", &"roof_panel", &"door_frame", &"stair",
]

var _piece_index: int = 0
var _last_normal: Vector3 = Vector3.ZERO
var _ghost_valid: bool = false
var _ghost_world_center: Vector3 = Vector3.ZERO
var _ghost_mirror_center: Vector3 = Vector3.ZERO
var _ghost_mirror_basis: Basis = Basis.IDENTITY
var _current_normal: Vector3 = Vector3.UP
var _ghost_pivot_mirror: Node3D
var _ghost_mesh_node_mirror: Node3D
var _axis_indicator: MeshInstance3D


func _ready() -> void:
	_setup_mirror_ghost()
	await get_tree().process_frame
	_rebuild_ghost()
	_setup_axis_indicator()


func _setup_mirror_ghost() -> void:
	_ghost_pivot_mirror = Node3D.new()
	_ghost_mesh_node_mirror = Node3D.new()
	_ghost_pivot_mirror.add_child(_ghost_mesh_node_mirror)
	_ghost_pivot_mirror.visible = false
	add_child(_ghost_pivot_mirror)


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
	var prev_piece  := selected_piece
	var was_placing := selected_piece != &""
	selected_piece = type
	if type == &"":
		if was_placing:
			emit_signal("piece_deselected")
		return
	if type != prev_piece:
		var dr: Array = PieceDefs.DEFS[type].get("default_rots", [0.0, 0.0, 0.0])
		_target_rots[0] = dr[0]; _target_rots[1] = dr[1]; _target_rots[2] = dr[2]
		_smooth_spin_rot = Basis.IDENTITY
		_smooth_mirror_spin_rot = Basis.IDENTITY
	_piece_index = PIECE_CYCLE.find(type)
	_rebuild_ghost()
	emit_signal("piece_selected", type)


func _physics_process(delta: float) -> void:
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

	if hit_normal.dot(_last_normal) < 0.9999:
		_smooth_spin_rot = Basis.IDENTITY
		_smooth_mirror_spin_rot = Basis.IDENTITY
		_last_normal = hit_normal

	var def: Dictionary = PieceDefs.DEFS[selected_piece]
	var sz: Vector3     = def.size
	var fa: int         = def.get("face_axis", 2)
	var h_out           := BuildUtils.half_out(sz, fa)

	_current_normal = hit_normal

	# Compute base orientation; slerp smooth spin toward target
	var base         := BuildUtils.surface_base(hit_normal, fa)
	var target_rot   := Basis(base.z, _target_rots[2]) * Basis(base.y, _target_rots[1]) * Basis(base.x, _target_rots[0])
	_smooth_spin_rot  = _smooth_spin_rot.slerp(target_rot, minf(delta * rotation_smooth, 1.0))
	var spin_rot     := _smooth_spin_rot

	# Snap ghost snap points to nearest snap point on any placed piece
	if snapping_enabled:
		var ghost_center := hit_point + spin_rot * (hit_normal * h_out)
		var snap_delta := BuildUtils.snap_to_points(ghost_center, spin_rot * base, sz, placed_pieces)
		hit_point += snap_delta

	# Active axis indicator direction (whichever axis is currently selected)
	var spin_world: Vector3
	match rot_axis_index:
		0: spin_world = Basis(base.z, _target_rots[2]) * (Basis(base.y, _target_rots[1]) * base.x)
		1: spin_world = Basis(base.z, _target_rots[2]) * base.y
		_: spin_world = base.z
	spin_world = spin_world.normalized()

	# Primary ghost — piece rotates around pivot (hit_point)
	ghost_pivot.global_position = hit_point
	ghost_pivot.rotation        = Vector3.ZERO
	ghost_mesh_node.position    = spin_rot * (hit_normal * h_out)
	ghost_mesh_node.basis       = spin_rot * base
	ghost_pivot.visible         = true
	_ghost_valid                = true
	_ghost_world_center         = hit_point + ghost_mesh_node.position

	# Axis indicator — at pivot, oriented along active spin_world
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
		var m_target := Basis(m_base.z, -_target_rots[2]) * Basis(m_base.y, -_target_rots[1]) * Basis(m_base.x, -_target_rots[0])
		_smooth_mirror_spin_rot = _smooth_mirror_spin_rot.slerp(m_target, minf(delta * rotation_smooth, 1.0))
		var m_rot    := _smooth_mirror_spin_rot
		_ghost_pivot_mirror.global_position = m_hit
		_ghost_pivot_mirror.rotation        = Vector3.ZERO
		_ghost_mesh_node_mirror.position    = m_rot * (m_normal * h_out)
		_ghost_mesh_node_mirror.basis       = m_rot * m_base
		_ghost_mirror_center                = m_hit + _ghost_mesh_node_mirror.position
		_ghost_mirror_basis                 = _ghost_mesh_node_mirror.basis
		_ghost_pivot_mirror.visible         = true
	else:
		_ghost_pivot_mirror.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				rot_axis_index = (rot_axis_index + 1) % 3
				return
			KEY_T:
				var dr: Array = PieceDefs.DEFS[selected_piece].get("default_rots", [0.0, 0.0, 0.0])
				_target_rots[0] = dr[0]; _target_rots[1] = dr[1]; _target_rots[2] = dr[2]
				_smooth_spin_rot = Basis.IDENTITY
				_smooth_mirror_spin_rot = Basis.IDENTITY
				return
			KEY_G:
				snapping_enabled = not snapping_enabled
				emit_signal("snapping_changed", snapping_enabled)
				return
			KEY_M:
				symmetry_enabled = not symmetry_enabled
				_ghost_pivot_mirror.visible = false
				emit_signal("symmetry_changed", symmetry_enabled)
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
					_target_rots[rot_axis_index] += step
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if selected_piece != &"":
					var step := deg_to_rad(rotation_step_deg * (0.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0))
					_target_rots[rot_axis_index] -= step
					get_viewport().set_input_as_handled()


func _place_piece() -> void:
	var space := get_world_3d().direct_space_state
	var piece := _spawn_piece(selected_piece, _ghost_world_center, ghost_mesh_node.basis)
	graph.add_piece(piece, space)
	graph.update_collapse_states(placed_pieces)
	emit_signal("piece_added", piece, PlaceReason.PLAYER, null)

	if symmetry_enabled:
		var mirror := _spawn_piece(selected_piece, _ghost_mirror_center, _ghost_mirror_basis)
		graph.add_piece(mirror, space)
		graph.update_collapse_states(placed_pieces)
		emit_signal("piece_added", mirror, PlaceReason.MIRROR, null)

	graph.apply_support_colors(placed_pieces)
	emit_signal("structure_changed")


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
		var piece := node as ShipPiece
		piece.stop_warning()
		placed_pieces.erase(piece)
		graph.remove_piece(piece)
		graph.update_collapse_states(placed_pieces)
		emit_signal("piece_destroyed", piece, RemoveReason.PLAYER, null)
		emit_signal("structure_changed")
		piece.queue_free()
		graph.apply_support_colors(placed_pieces)


func _process(delta: float) -> void:
	var to_collapse: Array[ShipPiece] = []
	for piece: ShipPiece in placed_pieces:
		if piece.is_warning():
			var max_hp := float(PieceDefs.DEFS[piece.piece_type].hp)
			var t := maxf(1.5, 10.0 * piece.support / StructuralGraph.COLLAPSE_THRESHOLD)
			piece.drain_hp(max_hp / t * delta)
			if piece.hp <= 0.0:
				to_collapse.append(piece)
	for piece: ShipPiece in to_collapse:
		_do_collapse(piece)


func _do_collapse(piece: ShipPiece) -> void:
	var pos := piece.global_position
	piece.collapse()
	placed_pieces.erase(piece)
	graph.remove_piece(piece)
	graph.update_collapse_states(placed_pieces)
	emit_signal("piece_destroyed", piece, RemoveReason.INSTABILITY, null)
	emit_signal("structure_changed")
	piece.queue_free()
	_spawn_collapse_effect(pos)
	graph.apply_support_colors(placed_pieces)


func _spawn_collapse_effect(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.5
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.4
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.color = Color(0.55, 0.45, 0.30, 1.0)
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.10
	p.draw_pass_1 = mesh
	add_child(p)
	p.global_position = pos
	get_tree().create_timer(p.lifetime * 1.5).timeout.connect(p.queue_free)


