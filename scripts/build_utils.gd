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



# --- Snapping ---

const SNAP_THRESHOLD := 0.22

# Collect edges of a StaticBody3D (BoxShape3D child) along a world axis (0=X,1=Y,2=Z).
static func body_edges_on_axis(body: StaticBody3D, axis: int) -> Array[float]:
	var edges: Array[float] = []
	for child: Node in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var sz  := (child.shape as BoxShape3D).size
			var b   := body.global_basis
			var half := absf(b.x[axis]) * sz.x * 0.5 + absf(b.y[axis]) * sz.y * 0.5 + absf(b.z[axis]) * sz.z * 0.5
			edges.append(body.global_position[axis] + half)
			edges.append(body.global_position[axis] - half)
			break
	return edges


# Snap hit_point along the two surface-tangent axes (skip the axis most aligned
# with hit_normal). Uses the new piece's world-space basis for correct extents.
static func snap_to_edges(hit_point: Vector3, hit_normal: Vector3,
		size: Vector3, new_basis: Basis, edges: Array) -> Vector3:
	# Determine which axis to skip (the one most aligned with the surface normal)
	var skip := 0
	if absf(hit_normal[1]) > absf(hit_normal[skip]): skip = 1
	if absf(hit_normal[2]) > absf(hit_normal[skip]): skip = 2

	var result := hit_point
	for axis in 3:
		if axis == skip:
			continue
		var half := (absf(new_basis.x[axis]) * size.x
				+ absf(new_basis.y[axis]) * size.y
				+ absf(new_basis.z[axis]) * size.z) * 0.5
		var best      := result[axis]
		var best_dist := SNAP_THRESHOLD
		for edge: float in edges[axis]:
			for candidate: float in [edge + half, edge - half]:
				var d := absf(result[axis] - candidate)
				if d < best_dist:
					best_dist = d
					best = candidate
		result[axis] = best
	return result


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
