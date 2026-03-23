@tool
class_name ShipSkeletonGizmoPlugin
extends EditorNode3DGizmoPlugin


func _init() -> void:
	create_material("hull",     Color(0.45, 0.85, 1.00, 0.80))
	create_material("silhouette", Color(0.70, 0.95, 1.00, 0.60))
	create_material("keel",     Color(1.00, 0.90, 0.40, 0.90))
	create_material("deck",     Color(0.40, 1.00, 0.55, 0.85))


func _get_gizmo_name() -> String:
	return "ShipSkeleton"


func _has_gizmo(node: Node3D) -> bool:
	return node is ShipSkeleton


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var skel: ShipSkeleton = gizmo.get_node_3d() as ShipSkeleton
	var cfg: ShipConfig    = skel._get_config()

	var hull_lines: PackedVector3Array      = PackedVector3Array()
	var silhouette_lines: PackedVector3Array = PackedVector3Array()
	var keel_lines: PackedVector3Array      = PackedVector3Array()
	var deck_lines: PackedVector3Array      = PackedVector3Array()

	# ── Rib profile curves ───────────────────────────────────────────────────
	for rib_x: float in cfg.rib_x_positions:
		var pts_s := cfg.rib_profile_points(rib_x,  1.0)
		var pts_p := cfg.rib_profile_points(rib_x, -1.0)
		for i in range(pts_s.size() - 1):
			hull_lines.append(pts_s[i]);     hull_lines.append(pts_s[i + 1])
			hull_lines.append(pts_p[i]);     hull_lines.append(pts_p[i + 1])
		# Keel cross-connection
		hull_lines.append(pts_s[0]);  hull_lines.append(pts_p[0])
		# Gunwale cross-connection
		hull_lines.append(pts_s[-1]); hull_lines.append(pts_p[-1])

	# ── Keel line ────────────────────────────────────────────────────────────
	keel_lines.append(Vector3(cfg.stern_x, 0.0, 0.0))
	keel_lines.append(Vector3(cfg.bow_x,   0.0, 0.0))

	# ── Silhouette: gunwale and keel lines connecting all stations ───────────
	var stations := cfg.bay_stations()
	for i in range(stations.size() - 1):
		var x0: float = stations[i]
		var x1: float = stations[i + 1]
		var g0_s := _station_profile(cfg, x0,  1.0)
		var g1_s := _station_profile(cfg, x1,  1.0)
		var g0_p := _station_profile(cfg, x0, -1.0)
		var g1_p := _station_profile(cfg, x1, -1.0)
		if g0_s.is_empty() or g1_s.is_empty():
			continue
		# Starboard gunwale
		silhouette_lines.append(g0_s[-1]); silhouette_lines.append(g1_s[-1])
		# Port gunwale
		silhouette_lines.append(g0_p[-1]); silhouette_lines.append(g1_p[-1])
		# Bow fan lines (every profile point converging to stem)
		if is_equal_approx(x1, cfg.bow_x):
			for j in range(g0_s.size()):
				silhouette_lines.append(g0_s[j]); silhouette_lines.append(g1_s[j])
				silhouette_lines.append(g0_p[j]); silhouette_lines.append(g1_p[j])

	# ── Deck height planes ───────────────────────────────────────────────────
	for deck_y: float in cfg.deck_heights:
		# Longitudinal lines (fore-aft) at the deck edge on each side
		for i in range(cfg.rib_x_positions.size() - 1):
			var x0: float = cfg.rib_x_positions[i]
			var x1: float = cfg.rib_x_positions[i + 1]
			var z0 := _deck_edge_z(cfg, x0, deck_y)
			var z1 := _deck_edge_z(cfg, x1, deck_y)
			if z0 < 0.0 or z1 < 0.0:
				continue
			# Fore-aft edges
			deck_lines.append(Vector3(x0, deck_y,  z0)); deck_lines.append(Vector3(x1, deck_y,  z1))
			deck_lines.append(Vector3(x0, deck_y, -z0)); deck_lines.append(Vector3(x1, deck_y, -z1))
		# Cross-ship lines at each rib
		for rib_x: float in cfg.rib_x_positions:
			var z := _deck_edge_z(cfg, rib_x, deck_y)
			if z < 0.0:
				continue
			deck_lines.append(Vector3(rib_x, deck_y, -z))
			deck_lines.append(Vector3(rib_x, deck_y,  z))

	gizmo.add_lines(hull_lines,       get_material("hull",        gizmo))
	gizmo.add_lines(silhouette_lines, get_material("silhouette",  gizmo))
	gizmo.add_lines(keel_lines,       get_material("keel",        gizmo))
	gizmo.add_lines(deck_lines,       get_material("deck",        gizmo))


# ── Helpers ───────────────────────────────────────────────────────────────────

func _station_profile(cfg: ShipConfig, x: float, side: float) -> PackedVector3Array:
	if is_equal_approx(x, cfg.bow_x):
		return cfg.bow_stem_points()
	if is_equal_approx(x, cfg.stern_x):
		return cfg.stern_profile_points(side)
	return cfg.rib_profile_points(x, side)


## Returns the Z extent of the hull at deck_y for a given rib, or -1 if above gunwale.
func _deck_edge_z(cfg: ShipConfig, rib_x: float, deck_y: float) -> float:
	var h := cfg.rib_height(rib_x)
	if deck_y >= h:
		return -1.0
	var t := deck_y / h
	return cfg.rib_half_width(rib_x) * cfg.hull_z_at(t)
