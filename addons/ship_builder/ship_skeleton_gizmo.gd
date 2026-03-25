@tool
class_name ShipSkeletonGizmoPlugin
extends EditorNode3DGizmoPlugin

# Handle ID layout  (P = hull_profile.size, N = rib_x_positions.size):
#   0 .. P-1      profile points — drag in YZ plane at midship X
#   P .. P+N-1    rib positions  — drag along X (keel plane)
#   P+N           stern          — drag along X (keel)
#   P+N+1         bow            — drag along X (keel)
#   P+N+2         stern rake top — drag in XY plane (top of sternpost)
#   P+N+3         bow rake top   — drag in XY plane (top of bow stem)
#   P+N+4 ..      deck heights   — drag along Y


func _init() -> void:
	create_material("hull",     Color(0.35, 0.72, 0.95, 0.70))
	create_material("sheer",    Color(0.70, 0.95, 1.00, 1.00))
	create_material("keel",     Color(1.00, 0.90, 0.40, 1.00))
	create_material("deck",     Color(0.35, 0.95, 0.55, 0.75))
	create_material("deck_ctr", Color(0.35, 0.95, 0.55, 0.35))
	create_handle_material("h_profile")
	create_handle_material("h_rib")
	create_handle_material("h_bowstern")
	create_handle_material("h_deck")
	_tint("h_profile",  Color(0.95, 0.80, 0.20))
	_tint("h_rib",      Color(0.25, 0.65, 0.95))
	_tint("h_bowstern", Color(0.95, 0.35, 0.20))
	_tint("h_deck",     Color(0.25, 0.95, 0.50))


func _tint(name: String, color: Color) -> void:
	var mat := get_material(name, null)
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = color


func _get_gizmo_name() -> String:
	return "ShipSkeleton"


func _has_gizmo(node: Node3D) -> bool:
	return node is ShipSkeleton


# ── Handle count / name / value ───────────────────────────────────────────────

func _get_handle_count(gizmo: EditorNode3DGizmo) -> int:
	var cfg := _cfg(gizmo)
	if not cfg:
		return 0
	return cfg.hull_profile.size() + cfg.rib_x_positions.size() + 4 + cfg.deck_heights.size()


func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, secondary: bool) -> String:
	var cfg := _cfg(gizmo)
	var P := cfg.hull_profile.size()
	var N := cfg.rib_x_positions.size()
	if   id < P:         return "Profile[%d]" % id
	elif id < P + N:     return "Rib[%d]" % (id - P)
	elif id == P + N:    return "Stern"
	elif id == P+N+1:    return "Bow"
	elif id == P+N+2:    return "SternRakeTop"
	elif id == P+N+3:    return "BowRakeTop"
	else:                return "Deck[%d]" % (id - P - N - 4)


func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, secondary: bool) -> Variant:
	var cfg := _cfg(gizmo)
	var P := cfg.hull_profile.size()
	var N := cfg.rib_x_positions.size()
	if   id < P:         return cfg.hull_profile.duplicate()
	elif id < P + N:     return cfg.rib_x_positions.duplicate()
	elif id == P + N:    return cfg.stern_x
	elif id == P+N+1:    return cfg.bow_x
	elif id == P+N+2:    return cfg.stern_rake
	elif id == P+N+3:    return cfg.bow_rake
	else:                return cfg.deck_heights.duplicate()


# ── Live drag ─────────────────────────────────────────────────────────────────

func _set_handle(gizmo: EditorNode3DGizmo, id: int, secondary: bool,
		camera: Camera3D, screen_pos: Vector2) -> void:
	var skel := gizmo.get_node_3d() as ShipSkeleton
	var cfg  := _cfg(gizmo)
	var P    := cfg.hull_profile.size()
	var N    := cfg.rib_x_positions.size()
	var mid  := _midship_x(cfg)

	var ro := skel.to_local(camera.global_position)
	var rd := (skel.global_transform.basis.inverse() *
			camera.project_ray_normal(screen_pos)).normalized()

	if id < P:
		# YZ plane at midship X
		var hit: Variant = Plane(Vector3(1, 0, 0), mid).intersects_ray(ro, rd)
		if hit != null:
			var p := hit as Vector3
			cfg.hull_profile[id] = Vector2(
				clampf(p.y / cfg.rib_height(mid),      0.0, 1.05),
				clampf(p.z / cfg.rib_half_width(mid),  0.0, 1.50))

	elif id < P + N:
		# Keel plane (Y=0), take X
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
		# Stern rake top — drag in XY plane (Z=0); horizontal offset from stern_x sets rake
		var hit: Variant = Plane(Vector3(0, 0, 1), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.stern_rake = clampf((hit as Vector3).x - cfg.stern_x, -3.0, 2.0)

	elif id == P + N + 3:
		# Bow rake top — drag in XY plane (Z=0); horizontal offset from bow_x sets rake
		var hit: Variant = Plane(Vector3(0, 0, 1), 0.0).intersects_ray(ro, rd)
		if hit != null:
			cfg.bow_rake = clampf((hit as Vector3).x - cfg.bow_x, -1.0, 4.0)

	else:
		# Deck: pick the vertical plane most face-on to camera for Y dragging
		var deck_idx := id - P - N - 4
		var cam_local := (skel.global_transform.basis.inverse() *
				camera.global_transform.basis.z).normalized()
		var plane: Plane
		if absf(cam_local.z) > absf(cam_local.x):
			plane = Plane(Vector3(1, 0, 0), mid)   # ZY plane at midship
		else:
			var z := _deck_z(cfg, mid, cfg.deck_heights[deck_idx])
			plane = Plane(Vector3(0, 0, 1), z)      # XY plane at handle Z
		var hit: Variant = plane.intersects_ray(ro, rd)
		if hit != null:
			cfg.deck_heights[deck_idx] = clampf(
				(hit as Vector3).y, 0.1, cfg.rib_height(mid) - 0.1)

	skel._rebuild()


func _commit_handle(gizmo: EditorNode3DGizmo, id: int, secondary: bool,
		restore: Variant, cancel: bool) -> void:
	var cfg := _cfg(gizmo)
	if cancel:
		var P := cfg.hull_profile.size()
		var N := cfg.rib_x_positions.size()
		if   id < P:         cfg.hull_profile      = restore
		elif id < P + N:     cfg.rib_x_positions   = restore
		elif id == P + N:    cfg.stern_x            = restore
		elif id == P+N+1:    cfg.bow_x              = restore
		elif id == P+N+2:    cfg.stern_rake         = restore
		elif id == P+N+3:    cfg.bow_rake           = restore
		else:                cfg.deck_heights       = restore
	# Full rebuild — also marks resource dirty so Ctrl+S saves changes
	cfg.emit_changed()


# ── Draw ──────────────────────────────────────────────────────────────────────

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var skel: ShipSkeleton = gizmo.get_node_3d() as ShipSkeleton
	if not skel or not skel.get_script():
		return
	var cfg := skel._get_config()

	var hull:  PackedVector3Array = PackedVector3Array()
	var sheer: PackedVector3Array = PackedVector3Array()
	var keel:  PackedVector3Array = PackedVector3Array()
	var deck:  PackedVector3Array = PackedVector3Array()
	var dctr:  PackedVector3Array = PackedVector3Array()

	for rib_x: float in cfg.rib_x_positions:
		var s := cfg.rib_profile_points(rib_x,  1.0)
		var p := cfg.rib_profile_points(rib_x, -1.0)
		for i in range(s.size() - 1):
			hull.append(s[i]); hull.append(s[i + 1])
			hull.append(p[i]); hull.append(p[i + 1])
		hull.append(s[0]); hull.append(p[0])

	keel.append(Vector3(cfg.stern_x, 0.0, 0.0))
	keel.append(Vector3(cfg.bow_x,   0.0, 0.0))

	# Draw bow stem curve (centerline, XY plane)
	var bow_last_x  := cfg.rib_x_positions[cfg.rib_x_positions.size() - 1]
	var stern_first_x := cfg.rib_x_positions[0]
	var bow_h_wire   := cfg.rib_height(bow_last_x)
	var stern_h_wire := cfg.rib_height(stern_first_x)
	var n_segs := 6
	var prev_bow  := Vector3(cfg.bow_x, 0.0, 0.0)
	var prev_str  := Vector3(cfg.stern_x, 0.0, 0.0)
	for i in range(1, n_segs + 1):
		var t := float(i) / float(n_segs)
		var cur_bow := Vector3(cfg.bow_x   + cfg.bow_rake   * t, bow_h_wire   * t, 0.0)
		var cur_str := Vector3(cfg.stern_x + cfg.stern_rake * t, stern_h_wire * t, 0.0)
		keel.append(prev_bow); keel.append(cur_bow)
		keel.append(prev_str); keel.append(cur_str)
		prev_bow = cur_bow
		prev_str = cur_str

	var stations := cfg.bay_stations()
	for i in range(stations.size() - 1):
		var x0: float = stations[i];  var x1: float = stations[i + 1]
		var g0s := _station_pts(cfg, x0,  1.0);  var g1s := _station_pts(cfg, x1,  1.0)
		var g0p := _station_pts(cfg, x0, -1.0);  var g1p := _station_pts(cfg, x1, -1.0)
		if g0s.is_empty() or g1s.is_empty():
			continue
		sheer.append(g0s[-1]); sheer.append(g1s[-1])
		sheer.append(g0p[-1]); sheer.append(g1p[-1])
		if is_equal_approx(x1, cfg.bow_x):
			for j in range(g0s.size()):
				hull.append(g0s[j]); hull.append(g1s[j])
				hull.append(g0p[j]); hull.append(g1p[j])

	var all_x: Array[float] = []
	all_x.append(cfg.stern_x)
	for rx: float in cfg.rib_x_positions: all_x.append(rx)
	all_x.append(cfg.bow_x)

	for deck_y: float in cfg.deck_heights:
		dctr.append(Vector3(cfg.stern_x, deck_y, 0.0))
		dctr.append(Vector3(cfg.bow_x,   deck_y, 0.0))
		for i in range(all_x.size() - 1):
			var z0 := _deck_z(cfg, all_x[i],     deck_y)
			var z1 := _deck_z(cfg, all_x[i + 1], deck_y)
			deck.append(Vector3(all_x[i],     deck_y,  z0)); deck.append(Vector3(all_x[i+1], deck_y,  z1))
			deck.append(Vector3(all_x[i],     deck_y, -z0)); deck.append(Vector3(all_x[i+1], deck_y, -z1))
		for rx: float in all_x:
			var z := _deck_z(cfg, rx, deck_y)
			deck.append(Vector3(rx, deck_y, -z)); deck.append(Vector3(rx, deck_y, z))

	gizmo.add_lines(hull,  get_material("hull",     gizmo))
	gizmo.add_lines(sheer, get_material("sheer",    gizmo))
	gizmo.add_lines(keel,  get_material("keel",     gizmo))
	gizmo.add_lines(deck,  get_material("deck",     gizmo))
	gizmo.add_lines(dctr,  get_material("deck_ctr", gizmo))

	# Handles
	var mid := _midship_x(cfg)
	var P   := cfg.hull_profile.size()
	var N   := cfg.rib_x_positions.size()

	var pp := PackedVector3Array(); var pi := PackedInt32Array()
	var rp := PackedVector3Array(); var ri := PackedInt32Array()
	var bp := PackedVector3Array(); var bi := PackedInt32Array()
	var dp := PackedVector3Array(); var di := PackedInt32Array()

	var mid_pts := cfg.rib_profile_points(mid, 1.0)
	for i in P:
		pp.append(mid_pts[i]); pi.append(i)

	for i in N:
		rp.append(Vector3(cfg.rib_x_positions[i], 0.0, 0.0)); ri.append(P + i)

	bp.append(Vector3(cfg.stern_x, 0.0, 0.0)); bi.append(P + N)
	bp.append(Vector3(cfg.bow_x,   0.0, 0.0)); bi.append(P + N + 1)

	# Rake-top handles: draggable tops of bow stem and sternpost
	var last_rib_x  := cfg.rib_x_positions[cfg.rib_x_positions.size() - 1]
	var first_rib_x := cfg.rib_x_positions[0]
	var bow_h   := cfg.rib_height(last_rib_x)
	var stern_h := cfg.rib_height(first_rib_x)
	bp.append(Vector3(cfg.stern_x + cfg.stern_rake, stern_h, 0.0)); bi.append(P + N + 2)
	bp.append(Vector3(cfg.bow_x   + cfg.bow_rake,   bow_h,   0.0)); bi.append(P + N + 3)

	for i in cfg.deck_heights.size():
		var z := _deck_z(cfg, mid, cfg.deck_heights[i])
		dp.append(Vector3(mid, cfg.deck_heights[i], z)); di.append(P + N + 4 + i)

	gizmo.add_handles(pp, get_material("h_profile",  gizmo), pi)
	gizmo.add_handles(rp, get_material("h_rib",      gizmo), ri)
	gizmo.add_handles(bp, get_material("h_bowstern", gizmo), bi)
	if not dp.is_empty():
		gizmo.add_handles(dp, get_material("h_deck", gizmo), di)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _cfg(gizmo: EditorNode3DGizmo) -> ShipConfig:
	return (gizmo.get_node_3d() as ShipSkeleton)._get_config()


func _midship_x(cfg: ShipConfig) -> float:
	var best: float = cfg.rib_x_positions[0]
	for x: float in cfg.rib_x_positions:
		if absf(x) < absf(best): best = x
	return best


func _station_pts(cfg: ShipConfig, x: float, side: float) -> PackedVector3Array:
	if is_equal_approx(x, cfg.bow_x):   return cfg.bow_stem_points(side)
	if is_equal_approx(x, cfg.stern_x): return cfg.stern_profile_points(side)
	return cfg.rib_profile_points(x, side)


func _deck_z(cfg: ShipConfig, x: float, deck_y: float) -> float:
	if is_equal_approx(x, cfg.bow_x): return 0.0
	var h := cfg.rib_height(x)
	if deck_y >= h: return 0.0
	return cfg.rib_half_width(x) * cfg.hull_z_at(deck_y / h)
