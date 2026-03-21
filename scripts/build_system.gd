class_name BuildSystem
extends Node3D


@export var build_camera: Camera3D
@export var ship_root: RigidBody3D
@export var placed_pieces_node: Node3D
@export var ghost_pivot: Node3D
@export var ghost_mesh_node: Node3D

var build_mode_active: bool = false
var selected_piece: StringName = &"plank"
var piece_rot: float = 0.0

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
	&"half_wall", &"window_wall", &"beam", &"mast", &"cannon"
]

var _piece_index: int = 0
var _last_normal: Vector3 = Vector3.ZERO
var _ghost_valid: bool = false
var _ghost_world_center: Vector3 = Vector3.ZERO
var _current_normal: Vector3 = Vector3.UP
var _ghost_pivot_mirror: Node3D
var _ghost_mesh_node_mirror: Node3D


func _ready() -> void:
	_setup_mirror_ghost()
	await get_tree().process_frame
	_refresh_keel_refs()
	_rebuild_ghost()


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


func toggle_build_mode() -> void:
	build_mode_active = not build_mode_active
	ghost_pivot.visible = false


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
	_piece_index = PIECE_CYCLE.find(type)
	_rebuild_ghost()


func _physics_process(_delta: float) -> void:
	if not build_mode_active or not build_camera:
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
		return

	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	if hit_normal.dot(_last_normal) < 0.99:
		piece_rot = 0.0
		_last_normal = hit_normal

	var sz: Vector3 = PieceDefs.DEFS[selected_piece].size
	var h_out    := BuildUtils.half_out(hit_normal, sz)
	var a_rot    := BuildUtils.auto_rot(hit_normal)

	if absf(hit_normal.y) < 0.9:
		hit_point = BuildUtils.snap_vertical(hit_point, sz, _collect_edge_ys())

	# World center must be computed before the mirror ghost reads it
	_ghost_world_center = BuildUtils.world_center(hit_point, hit_normal, h_out, piece_rot)
	_current_normal = hit_normal

	# Primary ghost
	ghost_pivot.global_position = hit_point
	ghost_pivot.rotation.y     = piece_rot
	ghost_mesh_node.position   = hit_normal * h_out
	ghost_mesh_node.rotation.y = a_rot
	ghost_pivot.visible        = true
	_ghost_valid               = true

	# Mirror ghost
	if symmetry_enabled:
		var m_hit    := BuildUtils.reflect_point(hit_point, symmetry_origin, symmetry_normal)
		var m_normal := BuildUtils.reflect_dir(hit_normal, symmetry_normal)
		var m_arot   := BuildUtils.auto_rot(m_normal)
		_ghost_pivot_mirror.global_position      = m_hit
		_ghost_pivot_mirror.rotation.y           = -piece_rot
		_ghost_mesh_node_mirror.global_position  = BuildUtils.reflect_point(_ghost_world_center, symmetry_origin, symmetry_normal)
		_ghost_mesh_node_mirror.rotation.y       = m_arot
		_ghost_pivot_mirror.visible              = true
	else:
		_ghost_pivot_mirror.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_B:
				toggle_build_mode()
				return
			KEY_M:
				symmetry_enabled = not symmetry_enabled
				_ghost_pivot_mirror.visible = false
				return
			KEY_TAB:
				if build_mode_active:
					_piece_index = (_piece_index + 1) % PIECE_CYCLE.size()
					select_piece(PIECE_CYCLE[_piece_index])
				return

	if not build_mode_active:
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _ghost_valid:
					_place_piece()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_remove_piece_at_cursor()
			MOUSE_BUTTON_WHEEL_UP:
				piece_rot += PI / 4.0
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				piece_rot -= PI / 4.0
				get_viewport().set_input_as_handled()


func _place_piece() -> void:
	var piece := _spawn_piece(selected_piece, _ghost_world_center, piece_rot + ghost_mesh_node.rotation.y)

	if symmetry_enabled:
		var m_center := BuildUtils.reflect_point(_ghost_world_center, symmetry_origin, symmetry_normal)
		var m_rot    := BuildUtils.mirror_rot(piece_rot, ghost_mesh_node.rotation.y, _current_normal, symmetry_normal)
		_spawn_piece(selected_piece, m_center, m_rot)

	stability.compute(placed_pieces)
	emit_signal("piece_placed", piece)


func _spawn_piece(type: StringName, pos: Vector3, rot_y: float) -> ShipPiece:
	var piece := ShipPiece.new()
	piece.setup(type)
	piece.add_child(PieceMeshBuilder.build_piece(type))
	placed_pieces_node.add_child(piece)
	piece.global_position = pos
	piece.rotation.y = rot_y
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
