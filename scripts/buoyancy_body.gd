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

var _sensors: Array[BuoyancySensor] = []


func _ready() -> void:
	_sensors.clear()
	for child in get_children():
		if child is BuoyancySensor:
			_sensors.append(child as BuoyancySensor)


func _physics_process(_delta: float) -> void:
	if not ocean or _sensors.is_empty():
		return
	var body := _find_ancestor_of_type(self, RigidBody3D) as RigidBody3D
	if not body:
		return

	var n          := _sensors.size()
	var ocean_base := ocean.global_position.y

	for sensor: BuoyancySensor in _sensors:
		var world_pt := sensor.global_position
		var wave_y   := ocean_base + ocean.get_wave_height(world_pt.x, world_pt.z)
		var depth    := wave_y - world_pt.y
		# World-space offset from body origin — used for torque and as apply_force position
		var offset   := world_pt - body.global_position

		var force := Vector3.ZERO
		if depth > 0.0:
			force += Vector3.UP * buoyancy_strength * pow(depth, depth_exponent) * body.mass / n
		# Damp vertical motion within 2 m of the surface so the ship tracks waves
		# instead of free-falling through troughs
		if absf(depth) < 2.0:
			var pt_vel := body.linear_velocity + body.angular_velocity.cross(offset)
			force     -= Vector3.UP * damping * pt_vel.y * body.mass / n
		if force == Vector3.ZERO:
			continue
		body.apply_force(force, offset)


static func _find_ancestor_of_type(node: Node, type: Variant) -> Node:
	var n := node.get_parent()
	while n:
		if is_instance_of(n, type):
			return n
		n = n.get_parent()
	return null
