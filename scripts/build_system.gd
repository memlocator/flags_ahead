class_name BuildSystem
extends Node3D


@export var build_camera: Camera3D
@export var ship_root: RigidBody3D
@export var placed_pieces_node: Node3D
@export var ghost_pivot: Node3D
@export var ghost_mesh_node: Node3D

@export var rotation_step_deg: float = 15.0
@export var rotation_smooth: float = 14.0
@export var skeletons_root: Node3D

var selected_piece: StringName = &""
var _target_rots: Array[float] = [0.0, 0.0, 0.0]
var _smooth_spin_rot: Basis = Basis.IDENTITY
var _smooth_mirror_spin_rot: Basis = Basis.IDENTITY
var rot_axis_index: int = 0

var placed_pieces: Array[ShipPiece] = []
var graph := StructuralGraph.new()

var _last_hit_skel: ShipSkeleton = null

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
	&"hull_panel", &"deck_panel", &"skeleton",
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

# Hull panel state
var _hull_panel_pts_a: PackedVector3Array
var _hull_panel_pts_b: PackedVector3Array
var _hull_panel_skel: ShipSkeleton
var _hull_panel_bay_a: float = 9999.0
var _hull_panel_bay_b: float = 9999.0
var _hull_panel_bay_side: float = 0.0
var _hull_panel_stations: Array[float] = []

# Deck panel state
var _deck_panel_pts_a: PackedVector3Array
var _deck_panel_pts_b: PackedVector3Array
var _deck_panel_skel: ShipSkeleton
var _deck_panel_bay_a: float = 9999.0
var _deck_panel_bay_b: float = 9999.0
var _deck_panel_deck_y: float = 9999.0
var _deck_panel_stations: Array[float] = []


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


func _clear_node_children(node: Node3D) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func _rebuild_ghost() -> void:
	_clear_node_children(ghost_mesh_node)
	if selected_piece == &"":
		return
	ghost_mesh_node.add_child(PieceMeshBuilder.build_ghost(selected_piece))
	if _ghost_mesh_node_mirror:
		_clear_node_children(_ghost_mesh_node_mirror)
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
	_hull_panel_skel = null
	_hull_panel_bay_a = 9999.0
	_hull_panel_bay_b = 9999.0
	_hull_panel_bay_side = 0.0
	_hull_panel_stations = []
	_deck_panel_skel = null
	_deck_panel_bay_a = 9999.0
	_deck_panel_bay_b = 9999.0
	_deck_panel_deck_y = 9999.0
	_deck_panel_stations = []
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

	if selected_piece == &"hull_panel":
		_process_hull_panel(result)
		return

	if selected_piece == &"deck_panel":
		_process_deck_panel(result)
		return

	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	# Keep symmetry plane aligned to whatever skeleton we're hovering
	var hit_skel := BuildUtils.find_ancestor(result.collider, ShipSkeleton) as ShipSkeleton
	_last_hit_skel = hit_skel
	if hit_skel:
		symmetry_origin = hit_skel.global_position
		symmetry_normal = hit_skel.global_transform.basis.z.normalized()

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
	if snapping_enabled and selected_piece != &"skeleton":
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
	if selected_piece == &"hull_panel":
		_place_hull_panel()
		return
	if selected_piece == &"deck_panel":
		_place_deck_panel()
		return
	if selected_piece == &"skeleton":
		_place_skeleton()
		return
	var space := get_world_3d().direct_space_state
	var piece := _spawn_piece(selected_piece, _ghost_world_center, ghost_mesh_node.basis)
	graph.add_piece(piece, space)
	emit_signal("piece_added", piece, PlaceReason.PLAYER, null)

	if symmetry_enabled:
		var mirror := _spawn_piece(selected_piece, _ghost_mirror_center, _ghost_mirror_basis)
		graph.add_piece(mirror, space)
		emit_signal("piece_added", mirror, PlaceReason.MIRROR, null)

	graph.update_collapse_states(placed_pieces)
	graph.apply_support_colors(placed_pieces)
	emit_signal("structure_changed")


func _process_hull_panel(result: Dictionary) -> void:
	if not (result.collider.collision_layer & 1):
		ghost_pivot.visible = false
		_ghost_valid = false
		if _axis_indicator: _axis_indicator.visible = false
		return

	var skel := BuildUtils.find_ancestor(result.collider, ShipSkeleton) as ShipSkeleton
	if not skel:
		ghost_pivot.visible = false
		_ghost_valid = false
		if _axis_indicator: _axis_indicator.visible = false
		return

	var cfg_hp    := skel._get_config()
	var hit_local := skel.to_local(result.position) / cfg_hp.scale_factor
	var side      := signf(hit_local.z)
	if is_zero_approx(side): side = 1.0

	# Cache bay_stations per skeleton — config doesn't change at runtime
	if skel != _hull_panel_skel or _hull_panel_stations.is_empty():
		_hull_panel_stations = cfg_hp.bay_stations()

	# Find the bay (pair of adjacent stations) the cursor is in
	var stations := _hull_panel_stations
	var bay_a    := stations[0]
	var bay_b    := stations[1]
	for i in range(stations.size() - 1):
		if hit_local.x >= minf(stations[i], stations[i + 1]) \
				and hit_local.x <= maxf(stations[i], stations[i + 1]):
			bay_a = stations[i]
			bay_b = stations[i + 1]
			break

	if bay_a != _hull_panel_bay_a or bay_b != _hull_panel_bay_b \
			or side != _hull_panel_bay_side or _hull_panel_skel != skel:
		_hull_panel_bay_a    = bay_a
		_hull_panel_bay_b    = bay_b
		_hull_panel_bay_side = side
		_hull_panel_skel     = skel
		_hull_panel_pts_a    = _bay_profile(skel, bay_a, side)
		_hull_panel_pts_b    = _bay_profile(skel, bay_b, side)
		_rebuild_hull_panel_ghost()

	# Ghost sits at the skeleton origin; mesh verts are already in skeleton local space
	ghost_pivot.global_position = skel.global_position
	ghost_pivot.global_basis    = skel.global_basis
	ghost_pivot.visible         = true
	ghost_mesh_node.position    = Vector3.ZERO
	ghost_mesh_node.basis       = Basis.IDENTITY
	_ghost_valid                = true
	_ghost_world_center         = skel.global_position
	_ghost_pivot_mirror.visible = false
	if _axis_indicator: _axis_indicator.visible = false


func _bay_profile(skel: ShipSkeleton, station_x: float, side: float) -> PackedVector3Array:
	var cfg: ShipConfig = skel._get_config()
	if is_equal_approx(station_x, cfg.bow_x):
		return cfg.bow_stem_points()
	if is_equal_approx(station_x, cfg.stern_x):
		return cfg.stern_profile_points(side)
	return cfg.rib_profile_points(station_x, side)


func _rebuild_hull_panel_ghost() -> void:
	_clear_node_children(ghost_mesh_node)
	ghost_mesh_node.add_child(
		PieceMeshBuilder.build_hull_panel_ghost(_hull_panel_pts_a, _hull_panel_pts_b)
	)


func _place_hull_panel() -> void:
	if not _hull_panel_skel or _hull_panel_pts_a.is_empty():
		return
	var piece := ShipPiece.new()
	piece.setup(&"hull_panel", false)
	piece.add_child(PieceMeshBuilder.build_hull_panel(_hull_panel_pts_a, _hull_panel_pts_b))
	# Add collision directly to the StaticBody3D so raycasts on layer 2 block the ghost
	var cs := CollisionShape3D.new()
	cs.shape = PieceMeshBuilder.hull_panel_convex(_hull_panel_pts_a, _hull_panel_pts_b)
	piece.add_child(cs)
	_container_for(_hull_panel_skel).add_child(piece)
	piece.global_position = _hull_panel_skel.global_position
	piece.global_basis    = _hull_panel_skel.global_basis
	placed_pieces.append(piece)
	var space := get_world_3d().direct_space_state
	graph.add_piece(piece, space)
	graph.update_collapse_states(placed_pieces)
	graph.apply_support_colors(placed_pieces)
	emit_signal("piece_added", piece, PlaceReason.PLAYER, null)
	emit_signal("structure_changed")


func _process_deck_panel(result: Dictionary) -> void:
	if not (result.collider.collision_layer & 1):
		ghost_pivot.visible = false
		_ghost_valid = false
		if _axis_indicator: _axis_indicator.visible = false
		return

	var skel := BuildUtils.find_ancestor(result.collider, ShipSkeleton) as ShipSkeleton
	if not skel:
		ghost_pivot.visible = false
		_ghost_valid = false
		if _axis_indicator: _axis_indicator.visible = false
		return

	var cfg: ShipConfig = skel._get_config()
	var hit_local := skel.to_local(result.position) / cfg.scale_factor

	if skel != _deck_panel_skel or _deck_panel_stations.is_empty():
		_deck_panel_stations = cfg.bay_stations()

	# Snap to the nearest deck height (raw comparison — hit_local is already in raw space)
	var deck_y := cfg.deck_heights[0]
	for h: float in cfg.deck_heights:
		if absf(h - hit_local.y) < absf(deck_y - hit_local.y):
			deck_y = h

	# Find which bay the cursor is in
	var stations := _deck_panel_stations
	var bay_a    := stations[0]
	var bay_b    := stations[1]
	for i in range(stations.size() - 1):
		if hit_local.x >= minf(stations[i], stations[i + 1]) \
				and hit_local.x <= maxf(stations[i], stations[i + 1]):
			bay_a = stations[i]
			bay_b = stations[i + 1]
			break

	if bay_a != _deck_panel_bay_a or bay_b != _deck_panel_bay_b \
			or deck_y != _deck_panel_deck_y or skel != _deck_panel_skel:
		_deck_panel_bay_a   = bay_a
		_deck_panel_bay_b   = bay_b
		_deck_panel_deck_y  = deck_y
		_deck_panel_skel    = skel
		_deck_panel_pts_a   = _bay_deck_profile(cfg, bay_a, deck_y)
		_deck_panel_pts_b   = _bay_deck_profile(cfg, bay_b, deck_y)
		_clear_node_children(ghost_mesh_node)
		ghost_mesh_node.add_child(
			PieceMeshBuilder.build_hull_panel_ghost(_deck_panel_pts_a, _deck_panel_pts_b)
		)

	ghost_pivot.global_position = skel.global_position
	ghost_pivot.global_basis    = skel.global_basis
	ghost_pivot.visible         = true
	ghost_mesh_node.position    = Vector3.ZERO
	ghost_mesh_node.basis       = Basis.IDENTITY
	_ghost_valid                = true
	_ghost_world_center         = skel.global_position
	_ghost_pivot_mirror.visible = false
	if _axis_indicator: _axis_indicator.visible = false


func _bay_deck_profile(cfg: ShipConfig, station_x: float, deck_y: float) -> PackedVector3Array:
	# station_x and deck_y are raw (design-space); output must be scaled
	var sf := cfg.scale_factor
	if is_equal_approx(station_x, cfg.bow_x):
		var h  := cfg.rib_height(cfg.rib_x_positions[-1])
		var t  := deck_y / maxf(h, 0.001)
		var pt := Vector3((cfg.bow_x + cfg.bow_rake * t) * sf, deck_y * sf, 0.0)
		return PackedVector3Array([pt, pt])
	if is_equal_approx(station_x, cfg.stern_x):
		var h  := cfg.rib_height(cfg.rib_x_positions[0])
		var t  := deck_y / maxf(h, 0.001)
		var pt := Vector3((cfg.stern_x + cfg.stern_rake * t) * sf, deck_y * sf, 0.0)
		return PackedVector3Array([pt, pt])
	return cfg.deck_profile_points(station_x, deck_y)


func _place_deck_panel() -> void:
	if not _deck_panel_skel or _deck_panel_pts_a.is_empty():
		return
	var piece := ShipPiece.new()
	piece.setup(&"deck_panel", false)
	piece.add_child(PieceMeshBuilder.build_hull_panel(_deck_panel_pts_a, _deck_panel_pts_b))
	var cs := CollisionShape3D.new()
	cs.shape = PieceMeshBuilder.hull_panel_convex(_deck_panel_pts_a, _deck_panel_pts_b)
	piece.add_child(cs)
	_container_for(_deck_panel_skel).add_child(piece)
	piece.global_position = _deck_panel_skel.global_position
	piece.global_basis    = _deck_panel_skel.global_basis
	placed_pieces.append(piece)
	var space := get_world_3d().direct_space_state
	graph.add_piece(piece, space)
	graph.update_collapse_states(placed_pieces)
	graph.apply_support_colors(placed_pieces)
	emit_signal("piece_added", piece, PlaceReason.PLAYER, null)
	emit_signal("structure_changed")


func _place_skeleton() -> void:
	if not skeletons_root:
		push_warning("BuildSystem: skeletons_root not set")
		return
	var skel := ShipSkeleton.new()
	skeletons_root.add_child(skel)
	# ghost_pivot sits at the hit_point (ground surface), which is the skeleton's origin
	skel.global_position = ghost_pivot.global_position
	skel.rotation.y = _target_rots[1]
	skel.build()
	emit_signal("structure_changed")


func _spawn_piece(type: StringName, pos: Vector3, piece_basis: Basis) -> ShipPiece:
	var piece := ShipPiece.new()
	piece.setup(type)
	piece.add_child(PieceMeshBuilder.build_piece(type))
	_container_for(_last_hit_skel).add_child(piece)
	piece.global_position = pos
	piece.basis = piece_basis
	placed_pieces.append(piece)
	return piece


## Returns the PlacedPieces node of the floating ship containing skel,
## or placed_pieces_node (the default ground container) if none found.
func _container_for(skel: ShipSkeleton) -> Node3D:
	if not skel:
		return placed_pieces_node
	var n := skel.get_parent()
	while n:
		if n is RigidBody3D and not (n as RigidBody3D).freeze:
			var pp := n.find_child("PlacedPieces", false, false) as Node3D
			if pp:
				return pp
		n = n.get_parent()
	return placed_pieces_node


func _remove_piece_at_cursor() -> void:
	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := build_camera.project_ray_origin(mouse_pos)
	var ray_dir    := build_camera.project_ray_normal(mouse_pos)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 50.0)
	query.collision_mask = 2

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var piece := BuildUtils.find_ancestor(result.collider, ShipPiece) as ShipPiece
	if piece:
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
