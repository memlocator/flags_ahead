class_name BuildUtils

# --- Placement geometry ---

# Offset from hit_point to piece center along the normal.
# face_axis: 0=X, 1=Y, 2=Z — which local axis presses against the surface.
static func half_out(size: Vector3, face_axis: int) -> float:
	match face_axis:
		0: return size.x / 2.0
		1: return size.y / 2.0
		_: return size.z / 2.0


# Base orientation: aligns piece face_axis with the surface normal, no spin.
static func surface_base(normal: Vector3, face_axis: int) -> Basis:
	var n   := normal.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var t1  := ref.cross(n).normalized()
	match face_axis:
		0: return Basis(n, n.cross(t1), -t1)
		1: return Basis(t1, n,          t1.cross(n))
		_: return Basis(t1, n.cross(t1), n)


# Full basis with spin applied in world space around the chosen axis.
static func surface_basis(normal: Vector3, face_axis: int, piece_rot: float, rot_axis: int = 0) -> Basis:
	var base := surface_base(normal, face_axis)
	const SPIN_AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var spin_v: Vector3 = SPIN_AXES[rot_axis]
	var spin_world := (base * spin_v).normalized()
	return Basis(spin_world, piece_rot) * base


# World-space center of the piece.
static func world_center(hit_point: Vector3, normal: Vector3, h_out: float) -> Vector3:
	return hit_point + normal * h_out


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


# --- Scene helpers ---

# Walk up from a collider to find the first ancestor of type T.
static func find_ancestor(node: Node, type: Script) -> Node:
	var n := node
	while n != null and not n.get_script() == type:
		n = n.get_parent()
	return n
