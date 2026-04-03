class_name ShipLauncher
extends Node

## Handles the transition from a static ShipSkeleton on land into a floating
## RigidBody3D on the ocean. Knows nothing about building or UI.

@export var ocean: Ocean

signal ship_launched(body: RigidBody3D, placed_pieces_node: Node3D)


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

	# Start at the skeleton's actual world position — let gravity + buoyancy
	# handle the drop physically rather than teleporting to the waterline.
	body.global_position = skel_pos
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

	# PlacedPieces node on the body so pieces added while sailing move with the ship
	var placed := Node3D.new()
	placed.name = "PlacedPieces"
	body.add_child(placed)

	_add_hull_stencil_mask(body, config)
	_add_hull_shelter_area(body, config)

	ship_launched.emit(body, placed)


func _add_hull_stencil_mask(body: RigidBody3D, config: ShipConfig) -> void:
	if not config:
		return

	# Pull the mask inward so the ocean still renders at the hull waterline contact zone.
	const MASK_Z_SCALE := 0.88

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stations := config.bay_stations()
	for i in range(stations.size() - 1):
		var xa: float = stations[i]
		var xb: float = stations[i + 1]

		var sa := _shrink_z(_mask_profile(config, xa,  1.0), MASK_Z_SCALE)
		var sb := _shrink_z(_mask_profile(config, xb,  1.0), MASK_Z_SCALE)
		var pa := _shrink_z(_mask_profile(config, xa, -1.0), MASK_Z_SCALE)
		var pb := _shrink_z(_mask_profile(config, xb, -1.0), MASK_Z_SCALE)

		_loft_strip(st, sa, sb)   # starboard hull side
		_loft_strip(st, pb, pa)   # port hull side

		# Deck cap
		var n := sa.size() - 1
		st.add_vertex(sa[n]); st.add_vertex(pa[n]); st.add_vertex(sb[n])
		st.add_vertex(pa[n]); st.add_vertex(pb[n]); st.add_vertex(sb[n])

	st.generate_normals()

	var mat := ShaderMaterial.new()
	mat.shader          = load("res://shaders/hull_depth_mask.gdshader")
	mat.render_priority = -1  # before ocean rings (priority 0, 1, 2)

	var mi := MeshInstance3D.new()
	mi.name              = "HullDepthMask"
	mi.mesh              = st.commit()
	mi.material_override = mat  # set on the instance so game.gd can reach it directly
	body.add_child(mi)


func _mask_profile(config: ShipConfig, x: float, side: float) -> PackedVector3Array:
	if absf(x - config.bow_x) < 0.001:
		return config.bow_stem_points(side)
	if absf(x - config.stern_x) < 0.001:
		return config.stern_profile_points(side)
	return config.rib_profile_points(x, side)


func _add_hull_shelter_area(body: RigidBody3D, config: ShipConfig) -> void:
	if not config:
		return
	# Collect all hull profile vertices — ConvexPolygonShape3D auto-computes the hull
	var pts := PackedVector3Array()
	for x: float in config.bay_stations():
		for pt: Vector3 in _mask_profile(config, x,  1.0):
			pts.append(pt)
		for pt: Vector3 in _mask_profile(config, x, -1.0):
			pts.append(pt)

	var shape := ConvexPolygonShape3D.new()
	shape.points = pts

	var col := CollisionShape3D.new()
	col.shape = shape

	var area := Area3D.new()
	area.name            = "HullShelterArea"
	area.collision_layer = 8      # layer 4 — queried by game.gd camera point test
	area.collision_mask  = 0
	area.add_child(col)
	body.add_child(area)


static func _shrink_z(pts: PackedVector3Array, scale: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector3 in pts:
		out.append(Vector3(p.x, p.y, p.z * scale))
	return out


static func _loft_strip(st: SurfaceTool, pts_a: PackedVector3Array, pts_b: PackedVector3Array) -> void:
	var n := mini(pts_a.size(), pts_b.size()) - 1
	for i in range(n):
		st.add_vertex(pts_a[i]);     st.add_vertex(pts_b[i]);     st.add_vertex(pts_a[i + 1])
		st.add_vertex(pts_b[i]);     st.add_vertex(pts_b[i + 1]); st.add_vertex(pts_a[i + 1])


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
