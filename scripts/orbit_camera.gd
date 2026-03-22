extends Node3D

## Node the camera orbits around (usually the player CharacterBody3D).
@export var target: Node3D
## Reference to BuildSystem — disables zoom scroll while a piece is selected.
@export var build_system: Node
## Mouse pixels per degree of camera rotation.
@export var sensitivity: float = 0.3
## Horizontal offset from the orbit pivot toward the right shoulder (metres).
@export var shoulder_offset: float = 2.2
## Height of the orbit pivot above target.global_position (metres). Set to approximate eye height.
@export var pivot_height: float = 1.5
## Distance change per scroll tick (metres).
@export var zoom_step: float = 1.5
## Multiplier applied to zoom_step when Shift is held for fine-grained zoom.
@export var zoom_fine_fraction: float = 0.25
## Closest the camera can get to the pivot (metres).
@export var min_distance: float = 2.0
## Furthest the camera can get from the pivot (metres).
@export var max_distance: float = 30.0

var _yaw: float = 180.0
var _pitch: float = -25.0
var _mouse_captured: bool = true
var _distance: float = 8.0
var _target_distance: float = 8.0

@onready var _spring: SpringArm3D = $SpringArm3D
@onready var _cam: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	_spring.position = Vector3(shoulder_offset, 0.0, 0.0)
	_update_pivot()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and not _mouse_captured:
		_mouse_captured = true
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_mouse_captured = false
		return

	if event is InputEventMouseMotion and _mouse_captured:
		_yaw   -= event.relative.x * sensitivity
		_pitch  = clampf(_pitch - event.relative.y * sensitivity, -75.0, 70.0)

	var placing: bool = build_system != null and build_system.get("selected_piece") != &""
	if event is InputEventMouseButton and _mouse_captured and not placing:
		var step := zoom_step * (zoom_fine_fraction if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - step, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + step, min_distance, max_distance)


func _process(delta: float) -> void:
	var want := Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	_distance = lerpf(_distance, _target_distance, clampf(delta * 12.0, 0.0, 1.0))
	_update_pivot()


func _update_pivot() -> void:
	var origin: Vector3 = (target.global_position if target else Vector3.ZERO) + Vector3.UP * pivot_height
	global_position = origin
	rotation_order = EULER_ORDER_YXZ
	rotation.y = deg_to_rad(_yaw)
	rotation.x = deg_to_rad(_pitch)
	_spring.spring_length = _distance
	# Collapse shoulder offset only when very close, so you can zoom to near first-person.
	var t := clampf(_distance / 3.0, 0.0, 1.0)
	_spring.position.x = shoulder_offset * t
