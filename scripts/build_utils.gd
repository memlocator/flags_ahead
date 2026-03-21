class_name BuildUtils

# --- Placement geometry ---

# Distance from hit_point to piece center along the normal.
# Vertical surfaces: piece extends outward (long axis = normal), end sits at hit_point.
# Horizontal surfaces: piece rests on top (Y-face down).
static func half_out(normal: Vector3, size: Vector3) -> float:
	if absf(normal.y) > 0.9:
		return size.y / 2.0
	return size.x / 2.0


# Y rotation that aligns local X (long axis) with the horizontal component of the normal.
# Derived from: after Ry(θ), local X = (cosθ, 0, −sinθ). Set = normalize(N.x, 0, N.z).
static func auto_rot(normal: Vector3) -> float:
	if absf(normal.y) < 0.9:
		return atan2(-normal.z, normal.x)
	return 0.0


# World-space center of the piece, accounting for piece_rot rotating the normal offset.
static func world_center(hit_point: Vector3, normal: Vector3, h_out: float, piece_rot: float) -> Vector3:
	var off := normal * h_out
	var c := cos(piece_rot)
	var s := sin(piece_rot)
	return hit_point + Vector3(
		off.x * c - off.z * s,
		off.y,
		off.x * s + off.z * c
	)


# --- Snapping ---

const SNAP_THRESHOLD := 0.22

# Snap hit_point.y so piece top/bottom aligns with a nearby edge.
static func snap_vertical(hit_point: Vector3, size: Vector3, edge_ys: Array[float]) -> Vector3:
	var half_y := size.y / 2.0
	var best_y := hit_point.y
	var best_dist := SNAP_THRESHOLD

	for edge_y: float in edge_ys:
		for candidate: float in [edge_y + half_y, edge_y - half_y]:
			var d := absf(hit_point.y - candidate)
			if d < best_dist:
				best_dist = d
				best_y = candidate

	return Vector3(hit_point.x, best_y, hit_point.z)


# Collect top/bottom Y edges from a StaticBody3D with a BoxShape3D child.
static func body_edge_ys(body: StaticBody3D) -> Array[float]:
	var edges: Array[float] = []
	for child: Node in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var half_y := (child.shape as BoxShape3D).size.y / 2.0
			edges.append(body.global_position.y + half_y)
			edges.append(body.global_position.y - half_y)
			break
	return edges


# --- Symmetry / reflection ---

# Reflect a world-space point across a plane (origin + normal).
static func reflect_point(p: Vector3, origin: Vector3, normal: Vector3) -> Vector3:
	var d := (p - origin).dot(normal)
	return p - 2.0 * d * normal


# Reflect a direction vector (no translation).
static func reflect_dir(v: Vector3, normal: Vector3) -> Vector3:
	return v - 2.0 * v.dot(normal) * normal


# Y rotation of the mirrored piece across the given plane normal.
static func mirror_rot(piece_rot: float, auto_rotation: float, normal: Vector3, sym_normal: Vector3) -> float:
	var m_normal := reflect_dir(normal, sym_normal)
	var m_auto := auto_rot(m_normal)
	return -piece_rot + m_auto


# --- Scene helpers ---

# Walk up from a collider to find the first ancestor of type T.
static func find_ancestor(node: Node, type: Script) -> Node:
	var n := node
	while n != null and not n.get_script() == type:
		n = n.get_parent()
	return n
