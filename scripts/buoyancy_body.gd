class_name BuoyancyBody
extends Node3D

## Applies buoyancy forces to the RigidBody3D ancestor using BuoyancySensor
## children of the ShipSkeleton ancestor. Each sensor contributes an upward
## force proportional to its submersion depth.

@export var ocean: Ocean
@export var buoyancy_strength: float = 25.0
@export var damping: float = 3.0
## Force grows as depth^exponent. 1.0 = linear, 2.0 = quadratic (default).
## Higher values resist full submersion more strongly.
@export_range(1.0, 4.0, 0.1) var depth_exponent: float = 2.0
## Gravity multiplier applied through the sensors. Set this and the body's
## gravity_scale to 0 so weight and buoyancy are balanced at the same points.
@export var gravity_scale: float = 1.0

var _sensors: Array[BuoyancySensor] = []
var _body: RigidBody3D


func _ready() -> void:
	_sensors.clear()
	for child in get_children():
		if child is BuoyancySensor:
			_sensors.append(child as BuoyancySensor)


func _physics_process(_delta: float) -> void:
	if not ocean or _sensors.is_empty():
		return
	if not _body:
		_body = _find_ancestor_of_type(self, RigidBody3D) as RigidBody3D
		if not _body:
			return
		_body.gravity_scale = 0.0

	var n          := _sensors.size()
	var ocean_base := ocean.global_position.y

	for sensor: BuoyancySensor in _sensors:
		var world_pt := sensor.global_position
		var wave_y   := ocean_base + ocean.get_wave_height(world_pt.x, world_pt.z)
		var depth    := wave_y - world_pt.y
		var offset   := world_pt - _body.global_position
		var pt_vel   := _body.linear_velocity + _body.angular_velocity.cross(offset)

		# Weight distributed across sensors — replaces body gravity_scale so that
		# gravity and buoyancy act at the same points (better torque balance).
		var force := Vector3.DOWN * gravity_scale * 9.8 * _body.mass / n

		if depth > 0.0:
			force += Vector3.UP * buoyancy_strength * pow(depth, depth_exponent) * _body.mass / n
			force -= Vector3.UP * damping * pt_vel.y * _body.mass / n
		elif depth > -1.0:
			force -= Vector3.UP * damping * 0.25 * pt_vel.y * _body.mass / n

		_body.apply_force(force, offset)


static func _find_ancestor_of_type(node: Node, type: Variant) -> Node:
	var n := node.get_parent()
	while n:
		if is_instance_of(n, type):
			return n
		n = n.get_parent()
	return null
