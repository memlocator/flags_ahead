class_name StructuralGraph


# Decay cost per metre travelled, indexed by material_tier (0=wood, 1=stone, 2=iron)
# Tuned for ~2m pieces: wood=2-3 hops, stone=1-2 hops, iron=4 hops horizontal
const TIER_H_DECAY: Array[float] = [0.20, 0.34, 0.125]  # horizontal
const TIER_V_DECAY: Array[float] = [0.05, 0.03, 0.010]  # vertical (towers stay up)

# Support thresholds → display colour (checked highest-first)
const SUPPORT_COLORS: Array = [
	[0.8, Color(0.29, 0.62, 1.00)],  # blue   — well supported
	[0.6, Color(0.24, 0.86, 0.52)],  # green  — stable
	[0.4, Color(1.00, 0.84, 0.31)],  # yellow — moderate
	[0.2, Color(1.00, 0.60, 0.00)],  # orange — weak
	[0.0, Color(1.00, 0.32, 0.32)],  # red    — critical
]

# Default colours per material tier
const TIER_DEFAULT_COLORS: Array[Color] = [
	Color(0.55, 0.35, 0.15),  # wood
	Color(0.45, 0.40, 0.30),  # mid / hardwood
	Color(0.40, 0.40, 0.45),  # iron
]

const ADJACENCY_MARGIN := 0.12

var _nodes: Dictionary = {}  # piece_id -> ShipPiece
var _edges: Dictionary = {}  # piece_id -> Array[int]


func add_piece(piece: ShipPiece, space_state: PhysicsDirectSpaceState3D) -> void:
	piece.is_grounded = _check_grounded(piece, space_state)
	_nodes[piece.piece_id] = piece
	_edges[piece.piece_id] = []
	for id: int in _nodes:
		if id == piece.piece_id:
			continue
		var other: ShipPiece = _nodes[id]
		if _are_adjacent(piece, other):
			_edges[piece.piece_id].append(id)
			_edges[id].append(piece.piece_id)
	recompute()


func remove_piece(piece: ShipPiece) -> void:
	var id: int = piece.piece_id
	for neighbor_id: int in _edges.get(id, []):
		var arr: Array = _edges.get(neighbor_id, [])
		arr.erase(id)
	_edges.erase(id)
	_nodes.erase(id)
	recompute()


func recompute() -> void:
	for piece: ShipPiece in _nodes.values():
		piece.support = 0.0

	var queue: Array[ShipPiece] = []
	for piece: ShipPiece in _nodes.values():
		if piece.is_grounded:
			piece.support = 1.0
			queue.append(piece)

	# Dijkstra: always process the highest-support piece next
	while queue.size() > 0:
		var best_i := 0
		for i in range(1, queue.size()):
			if queue[i].support > queue[best_i].support:
				best_i = i
		var current: ShipPiece = queue[best_i]
		queue.remove_at(best_i)

		for neighbor_id: int in _edges.get(current.piece_id, []):
			var neighbor: ShipPiece = _nodes.get(neighbor_id)
			if not neighbor:
				continue
			var new_sup := current.support - _edge_cost(current, neighbor)
			if new_sup > neighbor.support:
				neighbor.support = maxf(0.0, new_sup)
				queue.append(neighbor)


func apply_support_colors(pieces: Array) -> void:
	for piece: ShipPiece in pieces:
		_tint_piece(piece, _support_color(piece.support))


func apply_default_colors(pieces: Array) -> void:
	for piece: ShipPiece in pieces:
		var tier: int = PieceDefs.DEFS[piece.piece_type].get("material_tier", 0)
		_tint_piece(piece, TIER_DEFAULT_COLORS[tier])


# --- Internals ---

func _edge_cost(from: ShipPiece, to: ShipPiece) -> float:
	var disp := to.global_position - from.global_position
	var h_dist := Vector2(disp.x, disp.z).length()
	var v_dist := absf(disp.y)
	var tier: int = PieceDefs.DEFS[to.piece_type].get("material_tier", 0)
	return h_dist * TIER_H_DECAY[tier] + v_dist * TIER_V_DECAY[tier]


func _check_grounded(piece: ShipPiece, space_state: PhysicsDirectSpaceState3D) -> bool:
	var sz: Vector3 = PieceDefs.DEFS[piece.piece_type].size
	var shape := BoxShape3D.new()
	shape.size = sz
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = piece.global_transform
	params.collision_mask = 1  # terrain + keel layer
	params.margin = 0.1
	params.exclude = [piece.get_rid()]
	return space_state.intersect_shape(params, 1).size() > 0


func _are_adjacent(a: ShipPiece, b: ShipPiece) -> bool:
	var a_sz: Vector3 = PieceDefs.DEFS[a.piece_type].size
	var b_sz: Vector3 = PieceDefs.DEFS[b.piece_type].size
	for axis in 3:
		var a_half := (absf(a.global_basis.x[axis]) * a_sz.x
				+ absf(a.global_basis.y[axis]) * a_sz.y
				+ absf(a.global_basis.z[axis]) * a_sz.z) * 0.5
		var b_half := (absf(b.global_basis.x[axis]) * b_sz.x
				+ absf(b.global_basis.y[axis]) * b_sz.y
				+ absf(b.global_basis.z[axis]) * b_sz.z) * 0.5
		if absf(a.global_position[axis] - b.global_position[axis]) > a_half + b_half + ADJACENCY_MARGIN:
			return false
	return true


func _support_color(support: float) -> Color:
	for entry: Array in SUPPORT_COLORS:
		if support >= float(entry[0]):
			return entry[1]
	return SUPPORT_COLORS[-1][1]


func _tint_piece(piece: ShipPiece, color: Color) -> void:
	for child: Node in piece.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat:
				mat = mat.duplicate() as StandardMaterial3D
				mat.albedo_color = color
				(child as MeshInstance3D).material_override = mat
		elif child is Node3D:
			for sub: Node in child.get_children():
				if sub is MeshInstance3D:
					var mat := (sub as MeshInstance3D).material_override as StandardMaterial3D
					if mat:
						mat = mat.duplicate() as StandardMaterial3D
						mat.albedo_color = color
						(sub as MeshInstance3D).material_override = mat
