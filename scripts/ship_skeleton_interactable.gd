class_name ShipSkeletonInteractable
extends Node3D

## Attach as a child of a ShipSkeleton node.
## Detects player proximity and emits interact_requested when E is pressed.

signal interact_requested(skeleton: ShipSkeleton)
signal launch_requested(skeleton: ShipSkeleton)

@export var interaction_radius: float = 5.0

var _player_in_range: bool = false
var _editing: bool = false
var _prompt: Label3D
var _player: Node3D
var _e_was_pressed: bool = false
var _f_was_pressed: bool = false


func _ready() -> void:
	_prompt = Label3D.new()
	_prompt.text = "E  Edit Hull\nF  Launch"
	_prompt.font_size = 48
	_prompt.modulate = Color(1.0, 0.9, 0.3)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position = Vector3(0.0, 6.0, 0.0)
	_prompt.visible = false
	add_child(_prompt)
	# Find player after the whole scene is ready
	call_deferred("_find_player")


func _find_player() -> void:
	_player = get_tree().root.find_child("Player", true, false)
	if not _player:
		push_warning("ShipSkeletonInteractable: could not find Player node")


func _process(_delta: float) -> void:
	if _player:
		_player_in_range = global_position.distance_to(_player.global_position) <= interaction_radius
	_prompt.visible = _player_in_range and not _editing

	var skeleton := get_parent() as ShipSkeleton

	var e_now := Input.is_key_pressed(KEY_E)
	if _player_in_range and not _editing and e_now and not _e_was_pressed:
		if skeleton:
			interact_requested.emit(skeleton)
	_e_was_pressed = e_now

	var f_now := Input.is_key_pressed(KEY_F)
	if _player_in_range and not _editing and f_now and not _f_was_pressed:
		if skeleton:
			launch_requested.emit(skeleton)
	_f_was_pressed = f_now


func set_editing(on: bool) -> void:
	_editing = on
