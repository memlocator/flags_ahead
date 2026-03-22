class_name PlayerController
extends CharacterBody3D

@export var camera: Camera3D
@export var speed: float = 5.0
@export var jump_velocity: float = 6.0
@export var turn_speed: float = 12.0

const GRAVITY := 9.8

var _anim: AnimationPlayer
var _mesh: Node3D
var _head_node: Node3D
var _facing_dir: Vector3 = Vector3.FORWARD


func _ready() -> void:
	collision_mask = 0b0011
	_mesh = get_node_or_null("CharacterMesh")
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_head_node = find_child("head", true, false) as Node3D
	if _anim:
		_anim.play("idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)

	var dir := Vector3.ZERO
	if input != Vector2.ZERO:
		input = input.normalized()
		var cam_basis := camera.global_transform.basis if camera else Basis.IDENTITY
		var forward   := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
		var right     := Vector3(cam_basis.x.x,  0.0,  cam_basis.x.z).normalized()
		dir = forward * (-input.y) + right * input.x
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# Rotate mesh to face movement direction
	if dir.length() > 0.1 and _mesh:
		_mesh.basis = _mesh.basis.slerp(Basis.looking_at(dir, Vector3.UP), minf(delta * turn_speed, 1.0))
		_facing_dir = dir

	# Drive animations
	if _anim:
		var anim := "walk" if dir.length() > 0.1 else "idle"
		if _anim.current_animation != anim:
			_anim.play(anim)

	move_and_slide()


func _process(_delta: float) -> void:
	# Deferred so it runs after AnimationPlayer updates transforms this frame
	_update_head_look.call_deferred()


func _update_head_look() -> void:
	if not _head_node or not camera or not _mesh:
		return
	# Direction from player toward where the reticle points in the world
	var aim_point := camera.global_position + (-camera.global_transform.basis.z) * 50.0
	var look_dir  := (aim_point - global_position).normalized()
	var body_fwd   := Vector3(_facing_dir.x, 0.0, _facing_dir.z).normalized()
	var body_right := Vector3(body_fwd.z, 0.0, -body_fwd.x)
	var look_h     := Vector3(look_dir.x, 0.0, look_dir.z).normalized()
	var yaw        := clampf(body_fwd.signed_angle_to(look_h, Vector3.UP), -deg_to_rad(80), deg_to_rad(80))
	look_h         = (body_fwd * cos(yaw) + body_right * sin(yaw)).normalized()
	look_dir       = Vector3(look_h.x, look_dir.y, look_h.z).normalized()
	var scale      := _head_node.global_transform.basis.get_scale()
	var new_basis  := Basis.looking_at(-look_dir, Vector3.UP).scaled(scale)
	_head_node.global_transform = Transform3D(new_basis, _head_node.global_position)
