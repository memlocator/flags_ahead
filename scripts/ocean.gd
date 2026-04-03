@tool
class_name Ocean
extends Node3D

## World radius of the high-res inner ring.
@export var inner_radius:  float = 120.0
## Subdivisions for the inner ring.
@export var inner_subdivs: int   = 250
## Outer ring boundary radius.
@export var outer_radius:  float = 800.0
## Subdivisions for the outer ring.
@export var outer_subdivs: int   = 140
## Diameter of the far horizon ring (fixed polygon budget regardless of size).
@export var far_size:      float = 30000.0
## Subdivisions for the far ring — coarse is fine at that distance.
@export var far_subdivs:   int   = 60
## Global wave speed multiplier.
@export var time_scale:      float = 0.45
@export var follow_target: Node3D = null

@export_group("Waves")
@export var wave_amp:        float = 1.0    ## Global wave height multiplier (1=normal, 2=storm)
@export var steepness:       float = 0.38   ## Gerstner peak sharpness (0=sine, 1=peaked)
@export var chop_amp:        float = 0.38   ## Chop amplitude
@export var chop_scale:      float = 1.0    ## Chop feature size (1=default, 2=twice as large)

@export_group("Surface Detail")
@export var detail_strength: float = 0.65   ## Normal map intensity
@export var refraction_str:  float = 0.022  ## Screen-space refraction offset
@export var clarity:         float = 0.45   ## 0=opaque/deep  1=clear/shallow
@export var depth_fog_start: float = 0.5  ## Metres below surface where fog begins
@export var depth_fog_end:   float = 12.0 ## Metres below surface where fully fogged

@export_group("Foam")
@export var foam_crest:         float = 0.72  ## Wave height fraction where whitecaps begin (0=always, 1=tips only)
@export var foam_threshold:     float = 1.85  ## Background foam density — lower = more patches (1.0–2.5)

@export_group("Color")
@export var color_deep:    Color = Color(0.02, 0.18, 0.22, 1.0)  ## Deep-water colour
@export var color_shallow: Color = Color(0.05, 0.52, 0.38, 1.0)  ## Shallow/grazing colour
@export var color_foam:    Color = Color(0.87, 0.93, 0.97, 1.0)  ## Whitecap foam colour

@export_group("Specularity")
@export var roughness_near:  float = 0.16  ## Roughness looking straight down (tight highlights)
@export var roughness_far:   float = 0.32  ## Roughness at grazing angles (spread highlights)
@export var specular_str:    float = 0.85  ## Specular intensity

@export_group("SSS")
@export var sss_str:         float = 1.0    ## Backlit translucency through thin crests
@export var sss_color:       Color = Color(0.04, 0.68, 0.35, 1.0) ## SSS tint colour

@export_group("Caustics")
@export var caustic_str:     float = 0.75   ## Fake refracted-sunlight sparkle intensity

@export_group("Macro Variation")
@export var macro_str:       float = 0.55   ## Large-scale (~300–800 m) brightness patches — breaks long-range tiling

@export_group("Foam Contact")
@export var foam_contact_band: float = 0.35   ## metres at waterline that get foam
@export var foam_contact_gain: float = 1.2    ## intensity of contact foam

@export_group("Underwater FX")
@export var underwater_env: Environment = null ## Optional environment to apply when camera is underwater
@export var underwater_fog_density: float = 0.0 ## If >0, override env fog density while underwater
@export var underwater_fog_color: Color = Color(0.08, 0.2, 0.3) ## Fog color override underwater


const _WAVES: Array[Vector4] = [
	Vector4( 1.00,  0.00, 0.38, 22.0),
	Vector4( 0.65,  0.76, 0.24, 16.0),
	Vector4(-0.22,  0.98, 0.14, 11.0),
	Vector4( 0.85, -0.53, 0.09,  8.0),
	Vector4( 0.57,  0.82, 0.05,  5.0),
	Vector4(-0.81,  0.59, 0.04,  3.8),
	Vector4( 0.31, -0.95, 0.03,  2.7),
	Vector4( 0.93,  0.37, 0.02,  1.8),
]

var _time:      float = 0.0
var _materials: Array[ShaderMaterial] = []
var _last_underwater: bool = false
var _orig_cam_env: Environment = null
## Set to true while the camera is inside a hull or other shelter so the
## underwater environment effect is suppressed even if geometry places the
## camera below the wave surface.
var camera_sheltered: bool = false


func _ready() -> void:
	# Ensure we don't spawn duplicate rings when the tool script re-runs in editor.
	if _materials.size() > 0 or get_child_count() > 0:
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	# Cache the camera environment on first run so we can restore it.
	var cam := get_viewport().get_camera_3d()
	if cam:
		_orig_cam_env = cam.environment

	var shader := load("res://shaders/ocean.gdshader") as Shader
	# Render priority: far=0, outer=1, inner=2 — inner renders last so its
	# depth writes always win over the outer rings (fixes water-through-water).
	_add_ring(shader, far_size,           far_subdivs,   outer_radius,  1.0e9,        0)
	_add_ring(shader, outer_radius * 2.0, outer_subdivs, inner_radius,  outer_radius, 1)
	_add_ring(shader, inner_radius * 2.0, inner_subdivs, 0.0,           inner_radius, 2)


func _add_ring(shader: Shader, size: float, subdivs: int,
			   min_dist: float, max_dist: float, priority: int) -> void:
	var plane             := PlaneMesh.new()
	plane.size             = Vector2(size, size)
	plane.subdivide_width  = subdivs
	plane.subdivide_depth  = subdivs
	var inst              := MeshInstance3D.new()
	inst.mesh              = plane
	var m                 := _make_material(shader, min_dist, max_dist, priority)
	inst.material_override = m
	_materials.append(m)
	add_child(inst)


func _make_material(shader: Shader, min_dist: float, max_dist: float, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader           = shader
	m.render_priority  = priority
	m.set_shader_parameter("wave_a",       _WAVES[0])
	m.set_shader_parameter("wave_b",       _WAVES[1])
	m.set_shader_parameter("wave_c",       _WAVES[2])
	m.set_shader_parameter("wave_d",       _WAVES[3])
	m.set_shader_parameter("wave_e",       _WAVES[4])
	m.set_shader_parameter("wave_f",       _WAVES[5])
	m.set_shader_parameter("wave_g",       _WAVES[6])
	m.set_shader_parameter("wave_h",       _WAVES[7])
	m.set_shader_parameter("lod_min_dist", min_dist)
	m.set_shader_parameter("lod_max_dist", max_dist)
	return m


func _process(delta: float) -> void:
	_time += delta

	# In the editor, drive time from a monotonic clock so the ocean animates in the viewport.
	var t: float = (Time.get_ticks_msec() / 1000.0) if Engine.is_editor_hint() else _time * time_scale
	var cam := get_viewport().get_camera_3d()
	var is_underwater := false
	if cam:
		var surf_y := global_position.y + _sample_wave_height(Vector2(cam.global_position.x, cam.global_position.z), t)
		is_underwater = not camera_sheltered and cam.global_position.y < surf_y - 0.2
		if is_underwater != _last_underwater:
			print("Ocean is_underwater=", is_underwater, " cam_y=", cam.global_position.y, " surf_y=", surf_y)
			_last_underwater = is_underwater
			_apply_underwater_fx(is_underwater)
	

	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("wave_time",      t)
		m.set_shader_parameter("wave_amp",       wave_amp)
		m.set_shader_parameter("steepness",      steepness)
		m.set_shader_parameter("chop_amp",       chop_amp)
		m.set_shader_parameter("chop_scale",     chop_scale)
		m.set_shader_parameter("detail_strength",detail_strength)
		m.set_shader_parameter("refraction_str", refraction_str)
		m.set_shader_parameter("clarity",          clarity)
		m.set_shader_parameter("depth_fog_start",   depth_fog_start)
		m.set_shader_parameter("depth_fog_end",     depth_fog_end)
		m.set_shader_parameter("foam_crest",        foam_crest)
		m.set_shader_parameter("foam_threshold",    foam_threshold)
		m.set_shader_parameter("foam_contact_band",   foam_contact_band)
		m.set_shader_parameter("foam_contact_gain",   foam_contact_gain)
		m.set_shader_parameter("is_underwater", is_underwater)
		m.set_shader_parameter("color_deep",     color_deep)
		m.set_shader_parameter("color_shallow",  color_shallow)
		m.set_shader_parameter("color_foam",     color_foam)
		m.set_shader_parameter("roughness_near", roughness_near)
		m.set_shader_parameter("roughness_far",  roughness_far)
		m.set_shader_parameter("specular_str",   specular_str)
		m.set_shader_parameter("sss_str",        sss_str)
		m.set_shader_parameter("sss_color",      sss_color)
		m.set_shader_parameter("caustic_str",    caustic_str)
		m.set_shader_parameter("macro_str",      macro_str)

	if follow_target and not Engine.is_editor_hint():
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z


# ── Public API ────────────────────────────────────────────────────────────────

func get_wave_height(world_x: float, world_z: float) -> float:
	return _sample_wave_height(Vector2(world_x, world_z), _time * time_scale)


func _sample_wave_height(xz: Vector2, t: float) -> float:
	# Match the shader exactly: 6 vertex waves only (g/h live in the normal map),
	# with the same phase noise offsets applied per-wave.
	var pn1 := _vnoise(xz * 0.025) * 3.2 + _vnoise(xz * 0.008) * 2.8
	var pn2 := _vnoise(xz * 0.025 + Vector2(4.1, 7.3)) * 3.2 + _vnoise(xz * 0.008 + Vector2(4.1, 7.3)) * 2.8
	var pn3 := _vnoise(xz * 0.031 + Vector2(9.7, 2.5)) * 2.8 + _vnoise(xz * 0.011 + Vector2(3.6, 6.8)) * 2.4
	var y := 0.0
	y += _gerstner_y(_WAVES[0], xz, t, pn1 * 1.0)
	y += _gerstner_y(_WAVES[1], xz, t, pn2 * 0.8)
	y += _gerstner_y(_WAVES[2], xz, t, pn3 * 1.2)
	y += _gerstner_y(_WAVES[3], xz, t, pn1 * 0.6)
	y += _gerstner_y(_WAVES[4], xz, t, pn2 * 1.4)
	y += _gerstner_y(_WAVES[5], xz, t, pn3 * 0.9)
	return y


func _apply_underwater_fx(under: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	if under:
		if underwater_env:
			cam.environment = underwater_env
		elif underwater_fog_density > 0.0:
			var env: Environment = cam.environment
			if env == null and _orig_cam_env:
				env = _orig_cam_env
			if env:
				env = env.duplicate() as Environment
			else:
				env = Environment.new()
			env.fog_enabled = true
			env.fog_density = underwater_fog_density
			env.fog_color = underwater_fog_color
			cam.environment = env
	else:
		cam.environment = _orig_cam_env


func _gerstner_y(wave: Vector4, xz: Vector2, t: float, phase: float = 0.0) -> float:
	var d := Vector2(wave.x, wave.y).normalized()
	var k := TAU / wave.w
	var c := sqrt(9.8 / k)
	var f := k * (d.dot(xz) - c * t) + phase
	var eff := wave_amp if wave_amp < 2.0 else sqrt(wave_amp * 2.0)
	return wave.z * eff * sin(f)


static func _hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


static func _vnoise(p: Vector2) -> float:
	var i := Vector2(floor(p.x), floor(p.y))
	var f := Vector2(fposmod(p.x, 1.0), fposmod(p.y, 1.0))
	var ux := f.x * f.x * f.x * (f.x * (f.x * 6.0 - 15.0) + 10.0)
	var uy := f.y * f.y * f.y * (f.y * (f.y * 6.0 - 15.0) + 10.0)
	return lerpf(
		lerpf(_hash(i),                      _hash(i + Vector2(1.0, 0.0)), ux),
		lerpf(_hash(i + Vector2(0.0, 1.0)), _hash(i + Vector2(1.0, 1.0)), ux),
		uy)
