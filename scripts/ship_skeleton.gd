class_name ShipSkeleton
extends Node3D

const LAYER_SKELETON := 1

# Hull cross-section profile (right/+Z side; mirrored for left).
# Each Vector2: (y_fraction, z_fraction) — normalized to rib height / half-width.
# y=0 = keel, y=1 = gunwale.  z=0 = centreline, z=1 = outer edge.
const HULL_PROFILE: Array = [
	Vector2(0.00, 0.00),  # keel centreline
	Vector2(0.12, 0.52),  # lower bilge
	Vector2(0.42, 0.88),  # bilge knuckle
	Vector2(0.78, 0.97),  # flare
	Vector2(1.00, 1.00),  # gunwale
]

const RIB_THICKNESS := 0.12
const RIB_COLOR  := Color(0.35, 0.22, 0.09)
const KEEL_COLOR := Color(0.25, 0.15, 0.06)
const BOW_COLOR  := Color(0.28, 0.18, 0.07)


func build() -> void:
	_add_keel()
	_add_ribs()
	_add_bow()
	_add_stern()


# ── Keel / bow / stern (simple boxes) ────────────────────────────────────────

func _make_box(size: Vector3, pos: Vector3, rot_z_deg: float = 0.0,
		color: Color = Color(0.3, 0.2, 0.08)) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_SKELETON
	body.collision_mask  = 0
	body.position = pos
	if rot_z_deg != 0.0:
		body.rotation_degrees.z = rot_z_deg
	_attach_box(body, size, color)
	add_child(body)
	return body


func _add_keel() -> void:
	_make_box(Vector3(10.0, 0.3, 0.3), Vector3(0, 0.15, 0), 0.0, KEEL_COLOR)

func _add_bow() -> void:
	_make_box(Vector3(0.25, 1.8, 0.25), Vector3(5.0, 0.9, 0), 15.0, BOW_COLOR)

func _add_stern() -> void:
	_make_box(Vector3(0.2, 2.2, 1.6), Vector3(-5.0, 1.1, 0), 0.0, BOW_COLOR)


# ── Curved ribs ───────────────────────────────────────────────────────────────

func _add_ribs() -> void:
	for x: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		var h      := 2.5  - absf(x) * 0.12
		var half_w := (2.2 - absf(x) * 0.1) * 0.5
		_add_curved_rib(x, h, half_w)


func _add_curved_rib(rib_x: float, height: float, half_w: float) -> void:
	for i in range(HULL_PROFILE.size() - 1):
		var p1: Vector2 = HULL_PROFILE[i]
		var p2: Vector2 = HULL_PROFILE[i + 1]

		var y1 := p1.x * height;  var z1 := p1.y * half_w
		var y2 := p2.x * height;  var z2 := p2.y * half_w

		var dy      := y2 - y1
		var dz      := z2 - z1
		var seg_len := sqrt(dy * dy + dz * dz)
		var rot_x   := atan2(dz, dy)          # rotation around ship's long axis

		var mid_y := (y1 + y2) * 0.5
		var mid_z := (z1 + z2) * 0.5

		_make_rib_seg(Vector3(rib_x, mid_y,  mid_z), seg_len,  rot_x)
		_make_rib_seg(Vector3(rib_x, mid_y, -mid_z), seg_len, -rot_x)


func _make_rib_seg(pos: Vector3, seg_len: float, rot_x: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_SKELETON
	body.collision_mask  = 0
	body.position   = pos
	body.rotation.x = rot_x
	var sz := Vector3(RIB_THICKNESS, seg_len, RIB_THICKNESS)
	_attach_box(body, sz, RIB_COLOR)
	add_child(body)
	return body


# ── Shared helpers ────────────────────────────────────────────────────────────

func _attach_box(body: StaticBody3D, size: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color

	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var cs    := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
