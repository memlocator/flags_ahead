extends Camera3D

@export var target: Node3D
@export var build_system: Node
@export var sensitivity: float = 0.3
@export var shoulder_offset: float = 1.4
@export var zoom_speed: float = 1.5
@export var min_distance: float = 2.0
@export var max_distance: float = 30.0
@export var zoom_spring: float = 12.0  # lerp speed

var _yaw: float = 180.0
var _pitch: float = -25.0
var _mouse_captured: bool = true
var _distance: float = 8.0      # current (lerped)
var _target_distance: float = 8.0


func _ready() -> void:
	_update_position()


func _input(event: InputEvent) -> void:
	# Recapture on left-click — handled in _input so we can consume it
	# before build_system also sees it
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
		_pitch  = clampf(_pitch - event.relative.y * sensitivity, -89.0, 89.0)

	# Only zoom when nothing is selected (scroll is used for piece rotation otherwise)
	var placing: bool = build_system != null and build_system.get("selected_piece") != &""
	if event is InputEventMouseButton and _mouse_captured and not placing:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - zoom_speed, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + zoom_speed, min_distance, max_distance)


func _process(delta: float) -> void:
	var want := Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	_distance = lerp(_distance, _target_distance, delta * zoom_spring)
	_update_position()


func _update_position() -> void:
	var origin: Vector3 = target.global_position if target else Vector3.ZERO
	var yaw_rad   := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(_pitch)

	var cam_pos := origin + Vector3(
		_distance * cos(pitch_rad) * sin(yaw_rad),
		-_distance * sin(pitch_rad),
		_distance * cos(pitch_rad) * cos(yaw_rad)
	)

	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	cam_pos += right * shoulder_offset

	global_position = cam_pos
	var look_target := origin + right * shoulder_offset * 0.5 + Vector3.UP * 0.4
	if not global_position.is_equal_approx(look_target):
		look_at(look_target, Vector3.UP)
