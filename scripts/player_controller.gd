class_name PlayerController
extends CharacterBody3D

@export var camera: Camera3D
@export var speed: float = 5.0
@export var jump_velocity: float = 6.0

const GRAVITY := 9.8


func _ready() -> void:
	collision_mask = 0b0011  # layer 1 (skeleton/ground) + layer 2 (placed pieces)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)

	if input != Vector2.ZERO:
		input = input.normalized()
		var cam_basis := camera.global_transform.basis if camera else Basis.IDENTITY
		var forward   := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
		var right     := Vector3(cam_basis.x.x,  0.0,  cam_basis.x.z).normalized()
		var dir       := forward * (-input.y) + right * input.x
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
