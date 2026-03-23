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

const SNAP_THRESHOLD := 0.55

# Returns the world-space delta to add to ghost_center to snap it to the nearest
# matching snap point on any placed piece. Returns Vector3.ZERO if nothing is
# within SNAP_THRESHOLD.
static func snap_to_points(ghost_center: Vector3, ghost_basis: Basis,
		ghost_size: Vector3, pieces: Array) -> Vector3:
	var ghost_pts := _snap_points(ghost_center, ghost_basis, ghost_size)
	var best_dist := SNAP_THRESHOLD
	var best_delta := Vector3.ZERO
	for piece: ShipPiece in pieces:
		var psz: Vector3 = PieceDefs.DEFS[piece.piece_type].size
		var piece_pts := _snap_points(piece.global_position, piece.global_basis, psz)
		for gp: Vector3 in ghost_pts:
			for pp: Vector3 in piece_pts:
				var d := gp.distance_to(pp)
				if d < best_dist:
					best_dist = d
					best_delta = pp - gp
	return best_delta


# 14 snap points: 8 corners + 6 face centres.
static func _snap_points(center: Vector3, basis: Basis, size: Vector3) -> Array[Vector3]:
	var hx := basis.x * (size.x * 0.5)
	var hy := basis.y * (size.y * 0.5)
	var hz := basis.z * (size.z * 0.5)
	return [
		# corners
		center + hx + hy + hz, center + hx + hy - hz,
		center + hx - hy + hz, center + hx - hy - hz,
		center - hx + hy + hz, center - hx + hy - hz,
		center - hx - hy + hz, center - hx - hy - hz,
		# face centres
		center + hx, center - hx,
		center + hy, center - hy,
		center + hz, center - hz,
	]


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
