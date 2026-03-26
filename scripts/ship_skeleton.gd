@tool
class_name ShipSkeleton
extends Node3D

const LAYER_SKELETON := 1

const RIB_THICKNESS  := 0.12
const RIB_COLOR      := Color(0.35, 0.22, 0.09)
const KEEL_COLOR     := Color(0.25, 0.15, 0.06)
const BOW_COLOR      := Color(0.28, 0.18, 0.07)
const GIRDER_COLOR   := Color(0.30, 0.18, 0.07)
const SHEER_COLOR    := Color(0.32, 0.20, 0.08)

static var _mats: Dictionary = {}

## Set true during live drag to skip physics bodies (avoids Jolt body exhaustion).
var skip_collision: bool = false

# Assign a ShipConfig .tres to customise the frame.
# If left empty a default config is created at runtime.
@export var config: ShipConfig:
	set(value):
		if config and config.changed.is_connected(_rebuild):
			config.changed.disconnect(_rebuild)
		config = value
		if config:
			config.changed.connect(_rebuild)
		if is_inside_tree():
			_rebuild()


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	if not config:
		return props
	props.append({
		"name": "Hull Config", "type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP, "hint_string": ""
	})
	const SKIP := ["script", "resource_local_to_scene", "resource_name",
			"resource_path", "resource_scene_unique_id", "metadata"]
	for p in config.get_property_list():
		if p["name"] in SKIP:
			continue
		if p["usage"] & PROPERTY_USAGE_EDITOR:
			var ep := p.duplicate()
			ep["usage"] = PROPERTY_USAGE_EDITOR  # strip STORAGE so Godot never bakes these into the scene
			props.append(ep)
	return props


const _PASSTHROUGH_SKIP := [&"script", &"resource_local_to_scene", &"resource_name",
		&"resource_path", &"resource_scene_unique_id"]

func _get(property: StringName) -> Variant:
	if property in _PASSTHROUGH_SKIP:
		return null
	if config:
		var val = config.get(property)
		if val != null:
			return val
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property in _PASSTHROUGH_SKIP:
		return false
	if config and config.get(property) != null:
		config.set(property, value)
		return true
	return false


func _ready() -> void:
	if config and not config.changed.is_connected(_rebuild):
		config.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.get_meta("built", false):
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
	_add_sheer_rails(cfg)
	_add_bow_stringers(cfg)
	_add_stern_stringers(cfg)


# ── Keel / bow / stern ────────────────────────────────────────────────────────

func _make_box(size: Vector3, pos: Vector3, rot_z_deg: float = 0.0,
		color: Color = Color(0.3, 0.2, 0.08)) -> Node3D:
	var body: Node3D
	if skip_collision:
		body = Node3D.new()
	else:
		var sb := StaticBody3D.new()
		sb.collision_layer = LAYER_SKELETON
		sb.collision_mask  = 0
		body = sb
	body.position = pos
	if rot_z_deg != 0.0:
		body.rotation_degrees.z = rot_z_deg
	body.set_meta("built", true)
	_attach_box(body, size, color)
	add_child(body)
	return body


func _add_keel(cfg: ShipConfig) -> void:
	var sf     := cfg.scale_factor
	var length := absf(cfg.bow_x - cfg.stern_x) * sf
	var mid_x  := (cfg.bow_x + cfg.stern_x) * 0.5 * sf
	_make_box(Vector3(length, 0.3 * sf, 0.3 * sf), Vector3(mid_x, 0.15 * sf, 0), 0.0, KEEL_COLOR)


func _add_bow(cfg: ShipConfig) -> void:
	var sf         := cfg.scale_factor
	var last_rib_x := cfg.rib_x_positions[cfg.rib_x_positions.size() - 1]
	var bow_h      := cfg.rib_height(last_rib_x) * sf
	_add_post_curve(cfg.bow_x * sf, bow_h, cfg.bow_rake * sf)


func _add_stern(cfg: ShipConfig) -> void:
	var sf          := cfg.scale_factor
	var first_rib_x := cfg.rib_x_positions[0]
	var stern_h     := cfg.rib_height(first_rib_x) * sf
	_add_post_curve(cfg.stern_x * sf, stern_h, cfg.stern_rake * sf)


## Builds a curved post (stem or sternpost) in the XY plane from keel to gunwale.
## rake > 0 leans the top forward (+X); rake < 0 leans it aft (−X).
func _add_post_curve(base_x: float, height: float, rake: float) -> void:
	var n    := 6
	var prev := Vector2(base_x, 0.0)
	for i in range(1, n + 1):
		var t   := float(i) / n
		var cur := Vector2(base_x + rake * t, height * t)
		var dx  := cur.x - prev.x
		var dy  := cur.y - prev.y
		var seg_len := sqrt(dx * dx + dy * dy)
		var rot_z   := rad_to_deg(atan2(-dx, dy))
		var mid     := Vector3((prev.x + cur.x) * 0.5, (prev.y + cur.y) * 0.5, 0.0)
		_make_box(Vector3(RIB_THICKNESS * 1.5, seg_len, RIB_THICKNESS * 1.5), mid, rot_z, BOW_COLOR)
		prev = cur


# ── Curved ribs ───────────────────────────────────────────────────────────────

func _add_ribs(cfg: ShipConfig) -> void:
	for x: float in cfg.rib_x_positions:
		_add_curved_rib(cfg, x)


func _add_curved_rib(cfg: ShipConfig, rib_x: float) -> void:
	var sf     := cfg.scale_factor
	var height := cfg.rib_height(rib_x) * sf
	var half_w := cfg.rib_half_width(rib_x) * sf
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
		_make_rib_seg(Vector3(rib_x * sf, mid_y,  mid_z), seg_len,  rot_x)
		_make_rib_seg(Vector3(rib_x * sf, mid_y, -mid_z), seg_len, -rot_x)


func _make_rib_seg(pos: Vector3, seg_len: float, rot_x: float) -> Node3D:
	var body: Node3D
	if skip_collision:
		body = Node3D.new()
	else:
		var sb := StaticBody3D.new()
		sb.collision_layer = LAYER_SKELETON
		sb.collision_mask  = 0
		body = sb
	body.position   = pos
	body.rotation.x = rot_x
	body.set_meta("built", true)
	_attach_box(body, Vector3(RIB_THICKNESS, seg_len, RIB_THICKNESS), RIB_COLOR)
	add_child(body)
	return body


# ── Deck girders ──────────────────────────────────────────────────────────────

func _add_deck_girders(cfg: ShipConfig) -> void:
	var sf := cfg.scale_factor
	for deck_y: float in cfg.deck_heights:
		var y_pos := deck_y * sf
		for rib_x: float in cfg.rib_x_positions:
			if deck_y >= cfg.rib_height(rib_x):
				continue
			var beam_hw := _rib_z_at_y(cfg, rib_x, y_pos)
			_make_box(Vector3(RIB_THICKNESS, RIB_THICKNESS, beam_hw * 2.0),
					Vector3(rib_x * sf, y_pos, 0.0), 0.0, GIRDER_COLOR)


## Interpolate the Z half-width of the hull at world Y = y on rib at rib_x,
## by walking the rib_profile_points the same way the rib mesh is built.
func _rib_z_at_y(cfg: ShipConfig, rib_x: float, y: float) -> float:
	var pts := cfg.rib_profile_points(rib_x, 1.0)
	for i in range(pts.size() - 1):
		if y >= pts[i].y and y <= pts[i + 1].y:
			var f := (y - pts[i].y) / maxf(pts[i + 1].y - pts[i].y, 0.0001)
			return lerpf(pts[i].z, pts[i + 1].z, f)
	return pts[-1].z if not pts.is_empty() else 0.0


# ── Bow / stern stringers (profile points → post at same height) ──────────────

func _add_bow_stringers(cfg: ShipConfig) -> void:
	var sf     := cfg.scale_factor
	var last_x := cfg.rib_x_positions[cfg.rib_x_positions.size() - 1]
	var h      := cfg.rib_height(last_x) * sf
	for side in [-1.0, 1.0]:
		var pts := cfg.rib_profile_points(last_x, side)
		for i in range(pts.size()):
			var t    := cfg.hull_profile[i].x
			var stem := Vector3((cfg.bow_x + cfg.bow_rake * t) * sf, t * h, 0.0)
			_add_rail_seg(pts[i], stem)


func _add_stern_stringers(cfg: ShipConfig) -> void:
	var sf      := cfg.scale_factor
	var first_x := cfg.rib_x_positions[0]
	var h       := cfg.rib_height(first_x) * sf
	for side in [-1.0, 1.0]:
		var pts := cfg.rib_profile_points(first_x, side)
		for i in range(pts.size()):
			var t    := cfg.hull_profile[i].x
			var post := Vector3((cfg.stern_x + cfg.stern_rake * t) * sf, t * h, 0.0)
			_add_rail_seg(pts[i], post)


# ── Sheer rails (longitudinal gunwale beams along rib tops) ──────────────────

func _add_sheer_rails(cfg: ShipConfig) -> void:
	var N := cfg.rib_x_positions.size()
	for side in [-1.0, 1.0]:
		for i in range(N - 1):
			var x1  := cfg.rib_x_positions[i]
			var x2  := cfg.rib_x_positions[i + 1]
			var A   := cfg.rib_profile_points(x1, side)[-1]
			var B   := cfg.rib_profile_points(x2, side)[-1]
			_add_rail_seg(A, B)


func _add_rail_seg(A: Vector3, B: Vector3) -> void:
	var dir     := (B - A)
	var seg_len := dir.length()
	if seg_len < 0.001:
		return
	var body: Node3D
	if skip_collision:
		body = Node3D.new()
	else:
		var sb := StaticBody3D.new()
		sb.collision_layer = LAYER_SKELETON
		sb.collision_mask  = 0
		body = sb
	body.position = (A + B) * 0.5
	body.quaternion = Quaternion(Vector3.UP, dir / seg_len)
	body.set_meta("built", true)
	_attach_box(body, Vector3(RIB_THICKNESS, seg_len, RIB_THICKNESS), SHEER_COLOR)
	add_child(body)



# ── Shared helpers ────────────────────────────────────────────────────────────

func _attach_box(body: Node3D, size: Vector3, color: Color) -> void:
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
