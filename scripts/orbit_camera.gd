extends Camera3D

@export var target: Node3D
@export var build_system: Node  # BuildSystem — untyped to avoid parse-order issues
@export var distance: float = 15.0
@export var sensitivity: float = 0.4
@export var zoom_speed: float = 1.2
@export var min_distance: float = 3.0
@export var max_distance: float = 40.0

var _yaw: float = 45.0
var _pitch: float = -30.0
var _orbiting: bool = false


func _ready() -> void:
	_update_position()


func _unhandled_input(event: InputEvent) -> void:
	var in_build: bool = build_system != null and build_system.get("build_mode_active")

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif not in_build:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				distance = clampf(distance - zoom_speed, min_distance, max_distance)
				_update_position()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				distance = clampf(distance + zoom_speed, min_distance, max_distance)
				_update_position()

	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -85.0, -5.0)
		_update_position()


func _update_position() -> void:
	var origin: Vector3 = target.global_position if target else Vector3.ZERO
	var yaw_rad := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(_pitch)
	global_position = origin + Vector3(
		distance * cos(pitch_rad) * sin(yaw_rad),
		-distance * sin(pitch_rad),
		distance * cos(pitch_rad) * cos(yaw_rad)
	)
	look_at(origin, Vector3.UP)
