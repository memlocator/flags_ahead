class_name ShipPiece
extends StaticBody3D


var piece_type: StringName = &""
var hp: float = 100.0
var support: float = 0.0
var is_grounded: bool = false
var piece_id: int = 0

static var _next_id: int = 0

func _init() -> void:
	piece_id = _next_id
	_next_id += 1
	collision_layer = 2
	collision_mask = 0

func setup(type: StringName) -> void:
	piece_type = type
	var def: Dictionary = PieceDefs.DEFS[type]
	hp = float(def.hp)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = def.size
	cs.shape = shape
	add_child(cs)

func to_dict() -> Dictionary:
	var q := basis.get_rotation_quaternion()
	return {
		"type": str(piece_type),
		"position": [global_position.x, global_position.y, global_position.z],
		"basis_q": [q.x, q.y, q.z, q.w],
		"hp": hp,
		"support": support,
	}
