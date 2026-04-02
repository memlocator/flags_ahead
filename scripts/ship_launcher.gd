class_name ShipLauncher
extends Node

## Handles the transition from a static ShipSkeleton on land into a floating
## RigidBody3D on the ocean. Knows nothing about building or UI.

@export var ocean: Ocean


func launch(skeleton: ShipSkeleton) -> void:
	var config := skeleton.config

	# Save world transform now — reparenting will change it
	var skel_pos   := skeleton.global_position
	var skel_basis := skeleton.global_basis

	# --- Build the physics body ---
	var body              := RigidBody3D.new()
	body.name              = "FloatingShip_" + skeleton.name
	body.mass              = 800.0
	body.linear_damp       = 1.5
	body.angular_damp      = 4.0
	# Use an isolated collision layer so the body doesn't fight its own skeleton's
	# StaticBody3D children (ribs/keel on layer 1) or placed pieces (layer 2).
	body.collision_layer   = 0b100
	body.collision_mask    = 0b100

	# Pin CoM low in the hull so the ship is bottom-heavy and self-righting.
	# Without this Jolt derives CoM from the collision box center (mid-hull),
	# which sits above the waterline and makes the ship tumble.
	if config:
		var sf := config.scale_factor
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = Vector3(
			(config.bow_x + config.stern_x) * 0.5 * sf,
			config.rib_height_base * sf * 0.15,   # low bilge, well below waterline
			0.0,
		)

	_add_collision(body, config)

	# Must be in the scene tree before global_position is valid
	skeleton.get_tree().current_scene.add_child(body)

	# Start with ~40% of hull submerged so buoyancy is immediately active
	var ocean_y := ocean.global_position.y if ocean else 0.0
	var draft   := config.rib_height_base * config.scale_factor * 0.4 if config else 0.0
	body.global_position = Vector3(skel_pos.x, ocean_y - draft, skel_pos.z)
	body.global_basis    = skel_basis

	# Move skeleton into body at local origin (keep_global_transform = false)
	skeleton.reparent(body, false)
	skeleton.position = Vector3.ZERO
	skeleton.rotation = Vector3.ZERO
	skeleton.scale    = Vector3.ONE

	# Wire ocean into the BuoyancyBody already on the skeleton (placed in scene).
	# If none exists, add a default one — sensors can be added later in the editor.
	var buoyancy := skeleton.find_child("BuoyancyBody", true, false) as BuoyancyBody
	if not buoyancy:
		buoyancy = BuoyancyBody.new()
		buoyancy.name = "BuoyancyBody"
		skeleton.add_child(buoyancy)
	buoyancy.ocean = ocean


func _add_collision(body: RigidBody3D, config: ShipConfig) -> void:
	var shape := BoxShape3D.new()
	var col   := CollisionShape3D.new()
	if config:
		var sf      := config.scale_factor
		var length  := (config.bow_x - config.stern_x) * sf
		var width   := config.rib_width_base * sf * 2.0
		var height  := config.rib_height_base * sf
		shape.size   = Vector3(length, height, width)
		col.position = Vector3(
			(config.bow_x + config.stern_x) * 0.5 * sf,
			height * 0.5,
			0.0,
		)
	else:
		shape.size = Vector3(10.0, 4.0, 5.0)
	col.shape = shape
	body.add_child(col)
