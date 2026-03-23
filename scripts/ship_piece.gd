class_name ShipPiece
extends StaticBody3D


signal warning_started(piece: ShipPiece)
signal warning_stopped(piece: ShipPiece)
signal piece_collapsed(piece: ShipPiece)
signal hp_changed(piece: ShipPiece, new_hp: float, max_hp: float)

var piece_type: StringName = &""
var hp: float = 100.0
var support: float = 0.0
var is_grounded: bool = false
var piece_id: int = 0

var _warning_particles: GPUParticles3D = null

static var _next_id: int = 0


func _init() -> void:
	piece_id = _next_id
	_next_id += 1
	collision_layer = 2
	collision_mask = 0


func setup(type: StringName, add_collision: bool = true) -> void:
	piece_type = type
	var def: Dictionary = PieceDefs.DEFS[type]
	hp = float(def.hp)
	if add_collision:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = def.size
		cs.shape = shape
		add_child(cs)


# --- Lifecycle hooks (override in subclass or attached script) ---

func on_warning_start() -> void:
	pass

func on_warning_stop() -> void:
	pass

func on_collapse() -> void:
	pass


# --- State ---

func is_warning() -> bool:
	return _warning_particles != null


func start_warning() -> void:
	if _warning_particles != null:
		return
	on_warning_start()
	var sz: Vector3 = PieceDefs.DEFS[piece_type].size
	_warning_particles = GPUParticles3D.new()
	_warning_particles.amount = 12
	_warning_particles.lifetime = 1.8
	_warning_particles.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = sz * 0.45
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.2
	mat.gravity = Vector3.ZERO
	mat.color = Color(0.95, 0.45, 0.05, 0.75)
	_warning_particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	_warning_particles.draw_pass_1 = mesh
	add_child(_warning_particles)
	emit_signal("warning_started", self)


func stop_warning() -> void:
	if _warning_particles == null:
		return
	on_warning_stop()
	_warning_particles.queue_free()
	_warning_particles = null
	emit_signal("warning_stopped", self)


func collapse() -> void:
	stop_warning()
	on_collapse()
	emit_signal("piece_collapsed", self)


func drain_hp(amount: float) -> void:
	var max_hp: float = float(PieceDefs.DEFS[piece_type].hp)
	hp = maxf(hp - amount, 0.0)
	emit_signal("hp_changed", self, hp, max_hp)


func to_dict() -> Dictionary:
	var q := basis.get_rotation_quaternion()
	return {
		"type": str(piece_type),
		"position": [global_position.x, global_position.y, global_position.z],
		"basis_q": [q.x, q.y, q.z, q.w],
		"hp": hp,
		"support": support,
	}
