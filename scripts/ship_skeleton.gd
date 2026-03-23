@tool
class_name ShipSkeleton
extends Node3D

const LAYER_SKELETON := 1

const RIB_THICKNESS  := 0.12
const RIB_COLOR      := Color(0.35, 0.22, 0.09)
const KEEL_COLOR     := Color(0.25, 0.15, 0.06)
const BOW_COLOR      := Color(0.28, 0.18, 0.07)
const GIRDER_COLOR   := Color(0.30, 0.18, 0.07)

static var _mats: Dictionary = {}

# Assign a ShipConfig .tres to customise the frame.
# If left empty a default config is created at runtime.
@export var config: ShipConfig:
	set(value):
		config = value
		if is_inside_tree():
			_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	build()
	update_gizmos()


func _get_config() -> ShipConfig:
	if config:
		return config
	return ShipConfig.new()


func build() -> void:
	var cfg := _get_config()
	_add_keel(cfg)
	_add_ribs(cfg)
	_add_bow(cfg)
	_add_stern(cfg)
	_add_deck_girders(cfg)


# ── Keel / bow / stern ────────────────────────────────────────────────────────

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


func _add_keel(cfg: ShipConfig) -> void:
	var length := absf(cfg.bow_x - cfg.stern_x)
	var mid_x  := (cfg.bow_x + cfg.stern_x) * 0.5
	_make_box(Vector3(length, 0.3, 0.3), Vector3(mid_x, 0.15, 0), 0.0, KEEL_COLOR)


func _add_bow(cfg: ShipConfig) -> void:
	var last_rib_x := cfg.rib_x_positions[cfg.rib_x_positions.size() - 1]
	var bow_h      := cfg.rib_height(last_rib_x)
	_make_box(Vector3(0.25, bow_h, 0.25), Vector3(cfg.bow_x - 0.05, bow_h * 0.5, 0), 12.0, BOW_COLOR)


func _add_stern(cfg: ShipConfig) -> void:
	var first_rib_x := cfg.rib_x_positions[0]
	var stern_h     := cfg.rib_height(first_rib_x)
	var stern_hw    := cfg.rib_half_width(first_rib_x) * 0.88 * 2.0
	_make_box(Vector3(0.2, stern_h, stern_hw), Vector3(cfg.stern_x, stern_h * 0.5, 0), 0.0, BOW_COLOR)


# ── Curved ribs ───────────────────────────────────────────────────────────────

func _add_ribs(cfg: ShipConfig) -> void:
	for x: float in cfg.rib_x_positions:
		_add_curved_rib(cfg, x)


func _add_curved_rib(cfg: ShipConfig, rib_x: float) -> void:
	var height := cfg.rib_height(rib_x)
	var half_w := cfg.rib_half_width(rib_x)
	for i in range(cfg.hull_profile.size() - 1):
		var p1: Vector2 = cfg.hull_profile[i]
		var p2: Vector2 = cfg.hull_profile[i + 1]
		var y1 := p1.x * height;  var z1 := p1.y * half_w
		var y2 := p2.x * height;  var z2 := p2.y * half_w
		var dy      := y2 - y1
		var dz      := z2 - z1
		var seg_len := sqrt(dy * dy + dz * dz)
		var rot_x   := atan2(dz, dy)
		var mid_y   := (y1 + y2) * 0.5
		var mid_z   := (z1 + z2) * 0.5
		_make_rib_seg(Vector3(rib_x, mid_y,  mid_z), seg_len,  rot_x)
		_make_rib_seg(Vector3(rib_x, mid_y, -mid_z), seg_len, -rot_x)


func _make_rib_seg(pos: Vector3, seg_len: float, rot_x: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_SKELETON
	body.collision_mask  = 0
	body.position   = pos
	body.rotation.x = rot_x
	_attach_box(body, Vector3(RIB_THICKNESS, seg_len, RIB_THICKNESS), RIB_COLOR)
	add_child(body)
	return body


# ── Deck girders ──────────────────────────────────────────────────────────────

func _add_deck_girders(cfg: ShipConfig) -> void:
	for deck_y: float in cfg.deck_heights:
		for rib_x: float in cfg.rib_x_positions:
			var h := cfg.rib_height(rib_x)
			if deck_y >= h:
				continue
			var t       := clampf(deck_y / h, 0.0, 1.0)
			var beam_hw := cfg.rib_half_width(rib_x) * cfg.hull_z_at(t) * 0.88
			_make_box(Vector3(RIB_THICKNESS, RIB_THICKNESS, beam_hw * 2.0),
					Vector3(rib_x, deck_y, 0.0), 0.0, GIRDER_COLOR)


# ── Shared helpers ────────────────────────────────────────────────────────────

func _attach_box(body: StaticBody3D, size: Vector3, color: Color) -> void:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_mats[color] = m
	var mat: StandardMaterial3D = _mats[color]
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
