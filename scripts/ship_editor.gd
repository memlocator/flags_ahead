class_name ShipEditor
extends Node

## Runtime ship hull editor.
## Call start_editing(skeleton) to begin an edit session.
## The player is frozen, the camera pivots to orbit the skeleton,
## and coloured sphere handles appear that can be dragged to reshape the hull.

signal editing_started(skeleton: ShipSkeleton)
signal editing_finished(confirmed: bool)

## Assigned by game.gd before use.
var player: PlayerController
var camera: Camera3D
var camera_pivot: Node3D   # the orbit_camera node

var _active        := false
var _skeleton: ShipSkeleton
var _cfg: ShipConfig
var _snapshot      := {}

# Handle spheres (MeshInstance3D in world space)
var _handles: Array[MeshInstance3D] = []
var _handle_ids: Array[int] = []

var _hover_idx: int = -1
var _drag_idx:  int = -1
var _drag_restore: Variant

const HANDLE_RADIUS     := 0.22
const PICK_PX_RADIUS    := 22.0

# Colours matching the editor gizmo
const COL_PROFILE  := Color(0.95, 0.80, 0.20)
const COL_RIB      := Color(0.25, 0.65, 0.95)
const COL_BOWSTERN := Color(0.95, 0.35, 0.20)
const COL_DECK     := Color(0.25, 0.95, 0.50)
const COL_HOVER    := Color(1.0,  1.0,  1.0)

# HUD nodes (created in _ready)
var _hud: CanvasLayer
var _done_btn: Button
var _cancel_btn: Button
var _hint_label: Label


func _ready() -> void:
	_build_hud()
	set_process(false)
	set_process_input(false)


# ── Public API ────────────────────────────────────────────────────────────────

func start_editing(skeleton: ShipSkeleton) -> void:
	if _active:
		return
	_active    = true
	_skeleton  = skeleton
	_cfg       = skeleton._get_config()

	_take_snapshot()

	# Disable skeleton collision so camera spring arm passes through freely
	_set_skeleton_collision(false)

	# Freeze player
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED

	# Pivot camera to the skeleton
	if camera_pivot and camera_pivot.has_method("set_edit_mode"):
		camera_pivot.set_edit_mode(true, skeleton)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_spawn_handles()
	_hud.visible = true
	set_process(true)
	set_process_input(true)

	editing_started.emit(skeleton)


func stop_editing(confirm: bool) -> void:
	if not _active:
		return

	if not confirm:
		_restore_snapshot()
	else:
		_cfg.emit_changed()

	_clear_handles()
	_hud.visible = false
	set_process(false)
	set_process_input(false)

	# Restore skeleton collision
	_set_skeleton_collision(true)

	if player:
		player.process_mode = Node.PROCESS_MODE_INHERIT

	if camera_pivot and camera_pivot.has_method("set_edit_mode"):
		camera_pivot.set_edit_mode(false, null)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var was_skeleton := _skeleton
	_active   = false
	_skeleton = null
	editing_finished.emit(confirm)


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			stop_editing(false)
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _hover_idx >= 0:
					_start_drag(_hover_idx)
			else:
				_end_drag()

	if event is InputEventMouseMotion:
		if _drag_idx >= 0:
			_do_drag((event as InputEventMouseMotion).position)


func _process(_delta: float) -> void:
	if not _active:
		return
	_update_hover()


# ── Handle spawning ───────────────────────────────────────────────────────────

func _spawn_handles() -> void:
	_clear_handles()
	var cfg  := _cfg
	var P    := cfg.hull_profile.size()
	var N    := cfg.rib_x_positions.size()
	var mid  := _midship_x(cfg)
	var last_x  := cfg.rib_x_positions[N - 1]
	var first_x := cfg.rib_x_positions[0]

	var mid_pts := cfg.rib_profile_points(mid, 1.0)
	for i in P:
		_add_handle(mid_pts[i], i, COL_PROFILE)

	for i in N:
		_add_handle(Vector3(cfg.rib_x_positions[i], 0.0, 0.0), P + i, COL_RIB)

	_add_handle(Vector3(cfg.stern_x, 0.0, 0.0), P + N,     COL_BOWSTERN)
	_add_handle(Vector3(cfg.bow_x,   0.0, 0.0), P + N + 1, COL_BOWSTERN)

	var bow_h   := cfg.rib_height(last_x)
	var stern_h := cfg.rib_height(first_x)
	_add_handle(Vector3(cfg.stern_x + cfg.stern_rake, stern_h, 0.0), P + N + 2, COL_BOWSTERN)
	_add_handle(Vector3(cfg.bow_x   + cfg.bow_rake,   bow_h,   0.0), P + N + 3, COL_BOWSTERN)

	for i in cfg.deck_heights.size():
		var z := _deck_z_at(cfg, mid, cfg.deck_heights[i])
		_add_handle(Vector3(mid, cfg.deck_heights[i], z), P + N + 4 + i, COL_DECK)


func _add_handle(local_pos: Vector3, handle_id: int, color: Color) -> void:
	var mi   := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = HANDLE_RADIUS
	mesh.height = HANDLE_RADIUS * 2.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.set_meta("base_color", color)
	add_child(mi)
	mi.global_position = _skeleton.to_global(local_pos)
	_handles.append(mi)
	_handle_ids.append(handle_id)


func _reposition_handles() -> void:
	var cfg     := _cfg
	var P       := cfg.hull_profile.size()
	var N       := cfg.rib_x_positions.size()
	var mid     := _midship_x(cfg)
	var last_x  := cfg.rib_x_positions[N - 1]
	var first_x := cfg.rib_x_positions[0]
	var bow_h   := cfg.rib_height(last_x)
	var stern_h := cfg.rib_height(first_x)
	var mid_pts := cfg.rib_profile_points(mid, 1.0)

	for i in _handles.size():
		if not is_instance_valid(_handles[i]):
			continue
		var id := _handle_ids[i]
		var local_pos: Vector3
		if id < P:
			local_pos = mid_pts[id]
		elif id < P + N:
			local_pos = Vector3(cfg.rib_x_positions[id - P], 0.0, 0.0)
		elif id == P + N:
			local_pos = Vector3(cfg.stern_x, 0.0, 0.0)
		elif id == P + N + 1:
			local_pos = Vector3(cfg.bow_x, 0.0, 0.0)
		elif id == P + N + 2:
			local_pos = Vector3(cfg.stern_x + cfg.stern_rake, stern_h, 0.0)
		elif id == P + N + 3:
			local_pos = Vector3(cfg.bow_x + cfg.bow_rake, bow_h, 0.0)
		else:
			var di := id - P - N - 4
			var z  := _deck_z_at(cfg, mid, cfg.deck_heights[di])
			local_pos = Vector3(mid, cfg.deck_heights[di], z)
		_handles[i].global_position = _skeleton.to_global(local_pos)


func _clear_handles() -> void:
	for h in _handles:
		if is_instance_valid(h):
			h.queue_free()
	_handles.clear()
	_handle_ids.clear()
	_hover_idx = -1
	_drag_idx  = -1


# ── Hover / drag ──────────────────────────────────────────────────────────────

func _update_hover() -> void:
	if _drag_idx >= 0:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var best_dist := PICK_PX_RADIUS
	var best      := -1
	for i in _handles.size():
		if not is_instance_valid(_handles[i]):
			continue
		var screen_pos := camera.unproject_position(_handles[i].global_position)
		var d := screen_pos.distance_to(mouse_pos)
		if d < best_dist:
			best_dist = d
			best = i
	if best != _hover_idx:
		_hover_idx = best
		_refresh_colors()



func _start_drag(idx: int) -> void:
	if _drag_idx >= 0:
		return
	_drag_idx     = idx
	_drag_restore = _save_value(_handle_ids[idx])


func _end_drag() -> void:
	if _drag_idx < 0:
		return
	_drag_idx     = -1
	_drag_restore = null
	# Full rebuild with collision now that dragging is done
	_skeleton.skip_collision = false
	_skeleton._rebuild()
	# Still in edit mode — turn collision back off so SpringArm passes through
	_set_skeleton_collision(false)


func _do_drag(screen_pos: Vector2) -> void:
	var id  := _handle_ids[_drag_idx]
	var cfg := _cfg
	var P   := cfg.hull_profile.size()
	var N   := cfg.rib_x_positions.size()
	var mid := _midship_x(cfg)

	var ro := _skeleton.to_local(camera.project_ray_origin(screen_pos))
	var rd := (_skeleton.global_transform.basis.inverse() *
			camera.project_ray_normal(screen_pos)).normalized()

	if id < P:
		var hit: Variant = Plane(Vector3(1, 0, 0), mid).intersects_ray(ro, rd)
		if hit != null:
			var p := hit as Vector3
			cfg.hull_profile[id] = Vector2(
				clampf(p.y / cfg.rib_height(mid),     0.0, 1.05),
				clampf(p.z / cfg.rib_half_width(mid), 0.0, 1.50))

	elif id < P + N:
		var hit: Variant = Plane(Vector3(0, 1, 0), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.rib_x_positions[id - P] = (hit as Vector3).x

	elif id == P + N:
		var hit: Variant = Plane(Vector3(0, 1, 0), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.stern_x = minf((hit as Vector3).x, cfg.rib_x_positions[0] - 0.5)

	elif id == P + N + 1:
		var hit: Variant = Plane(Vector3(0, 1, 0), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.bow_x = maxf((hit as Vector3).x, cfg.rib_x_positions[N - 1] + 0.5)

	elif id == P + N + 2:
		var hit: Variant = Plane(Vector3(0, 0, 1), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.stern_rake = clampf((hit as Vector3).x - cfg.stern_x, -3.0, 2.0)

	elif id == P + N + 3:
		var hit: Variant = Plane(Vector3(0, 0, 1), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.bow_rake = clampf((hit as Vector3).x - cfg.bow_x, -1.0, 4.0)

	else:
		var deck_idx := id - P - N - 4
		var hit: Variant = Plane(Vector3(1, 0, 0), mid).intersects_ray(ro, rd)
		if hit != null:
			cfg.deck_heights[deck_idx] = clampf(
				(hit as Vector3).y, 0.1, cfg.rib_height(mid) - 0.1)

	# Live mesh preview — rebuild without physics bodies (avoids Jolt spam)
	_skeleton.skip_collision = true
	_skeleton._rebuild()
	_skeleton.skip_collision = false
	_reposition_handles()


func _refresh_colors() -> void:
	for i in _handles.size():
		if not is_instance_valid(_handles[i]):
			continue
		var mat := _handles[i].material_override as StandardMaterial3D
		if not mat:
			continue
		if i == _hover_idx:
			mat.albedo_color = COL_HOVER
		elif i == _drag_idx:
			mat.albedo_color = COL_HOVER
		else:
			mat.albedo_color = _handles[i].get_meta("base_color") as Color


# ── Snapshot / restore ────────────────────────────────────────────────────────

func _take_snapshot() -> void:
	_snapshot = {
		"hull_profile":    _cfg.hull_profile.duplicate(),
		"rib_x_positions": _cfg.rib_x_positions.duplicate(),
		"bow_x":           _cfg.bow_x,
		"stern_x":         _cfg.stern_x,
		"bow_rake":        _cfg.bow_rake,
		"stern_rake":      _cfg.stern_rake,
		"deck_heights":    _cfg.deck_heights.duplicate(),
	}


func _restore_snapshot() -> void:
	_cfg.hull_profile    = _snapshot["hull_profile"]
	_cfg.rib_x_positions = _snapshot["rib_x_positions"]
	_cfg.bow_x           = _snapshot["bow_x"]
	_cfg.stern_x         = _snapshot["stern_x"]
	_cfg.bow_rake        = _snapshot["bow_rake"]
	_cfg.stern_rake      = _snapshot["stern_rake"]
	_cfg.deck_heights    = _snapshot["deck_heights"]
	_cfg.emit_changed()


func _save_value(id: int) -> Variant:
	var P := _cfg.hull_profile.size()
	var N := _cfg.rib_x_positions.size()
	if   id < P:         return _cfg.hull_profile.duplicate()
	elif id < P + N:     return _cfg.rib_x_positions.duplicate()
	elif id == P + N:    return _cfg.stern_x
	elif id == P + N + 1: return _cfg.bow_x
	elif id == P + N + 2: return _cfg.stern_rake
	elif id == P + N + 3: return _cfg.bow_rake
	else:                return _cfg.deck_heights.duplicate()


# ── HUD ───────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.visible = false
	add_child(_hud)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left   =  20
	panel.offset_bottom = -20
	panel.offset_right  =  220
	panel.offset_top    = -80
	_hud.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	_done_btn = Button.new()
	_done_btn.text = "Done"
	_done_btn.pressed.connect(func() -> void: stop_editing(true))
	hbox.add_child(_done_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(func() -> void: stop_editing(false))
	hbox.add_child(_cancel_btn)

	_hint_label = Label.new()
	_hint_label.text = "Drag handles  •  RMB orbit"
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left   =  20
	_hint_label.offset_bottom = -90
	_hint_label.offset_right  =  400
	_hint_label.offset_top    = -110
	_hint_label.modulate = Color(0.9, 0.9, 0.9, 0.75)
	_hud.add_child(_hint_label)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_skeleton_collision(enabled: bool) -> void:
	for child in _skeleton.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = ShipSkeleton.LAYER_SKELETON if enabled else 0


func _midship_x(cfg: ShipConfig) -> float:
	var best := cfg.rib_x_positions[0]
	var best_d := absf(best)
	for x: float in cfg.rib_x_positions:
		if absf(x) < best_d:
			best_d = absf(x)
			best = x
	return best


func _deck_z_at(cfg: ShipConfig, rib_x: float, deck_y: float) -> float:
	var pts := cfg.rib_profile_points(rib_x, 1.0)
	for i in range(pts.size() - 1):
		if deck_y >= pts[i].y and deck_y <= pts[i + 1].y:
			var f := (deck_y - pts[i].y) / maxf(pts[i + 1].y - pts[i].y, 0.0001)
			return lerpf(pts[i].z, pts[i + 1].z, f)
	return pts[-1].z if not pts.is_empty() else 0.0
