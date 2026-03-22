class_name StabilitySystem


# [threshold, color] — checked from highest to lowest
const SUPPORT_COLORS: Array = [
	[0.8, Color(0.29, 0.62, 1.00)],   # Blue   — foundation
	[0.6, Color(0.24, 0.86, 0.52)],   # Green  — stable
	[0.4, Color(1.00, 0.84, 0.31)],   # Yellow — moderate
	[0.2, Color(1.00, 0.60, 0.00)],   # Orange — weak
	[0.0, Color(1.00, 0.32, 0.32)],   # Red    — critical
]

# Populated by BuildSystem after skeleton is built
var keel_parts: Array = []


func compute(placed_pieces: Array) -> void:
	for piece: ShipPiece in placed_pieces:
		piece.support = 0.0

	var queue: Array[ShipPiece] = []

	# Phase 1: seed grounded pieces at full support
	for piece: ShipPiece in placed_pieces:
		if _is_grounded(piece):
			piece.support = 1.0
			queue.append(piece)

	# Phase 2: Dijkstra-style propagation — re-queue whenever a better path is found
	while queue.size() > 0:
		var current: ShipPiece = queue.pop_front()
		for other: ShipPiece in placed_pieces:
			if current.global_position.distance_to(other.global_position) < 2.0:
				var decay := 1.0 / float(other.max_support)
				var new_sup := current.support - decay
				if new_sup > other.support:
					other.support = maxf(0.0, new_sup)
					queue.append(other)

	_update_colors(placed_pieces)


func get_unsupported(placed_pieces: Array) -> Array:
	var result: Array = []
	for piece: ShipPiece in placed_pieces:
		if piece.support <= 0.05 and not piece.resets_stability:
			result.append(piece)
	return result


func _is_grounded(piece: ShipPiece) -> bool:
	if piece.resets_stability:
		return true
	for keel_part: Node3D in keel_parts:
		if piece.global_position.distance_to(keel_part.global_position) < 2.2:
			return true
	return false


func _update_colors(placed_pieces: Array) -> void:
	for piece: ShipPiece in placed_pieces:
		var color: Color = SUPPORT_COLORS[-1][1]
		for entry: Array in SUPPORT_COLORS:
			if piece.support >= float(entry[0]):
				color = entry[1]
				break
		_tint_piece(piece, color)


func _tint_piece(piece: ShipPiece, color: Color) -> void:
	for child: Node in piece.get_children():
		if child is Node3D:
			for sub: Node in child.get_children():
				if sub is MeshInstance3D:
					var mat := sub.material_override as StandardMaterial3D
					if mat:
						mat = mat.duplicate() as StandardMaterial3D
						mat.albedo_color = color
						sub.material_override = mat
			if child is MeshInstance3D:
				var mat := child.material_override as StandardMaterial3D
				if mat:
					mat = mat.duplicate() as StandardMaterial3D
					mat.albedo_color = color
					child.material_override = mat
