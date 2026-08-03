extends CharacterBody3D
class_name FirstPersonController

@export var walk_speed: float = 6.0
@export var ground_acceleration: float = 28.0
@export var air_acceleration: float = 8.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 20.0


func _physics_process(delta: float) -> void:
	var movement_input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var local_direction := Vector3(movement_input.x, 0.0, movement_input.y)
	var world_direction := (global_transform.basis * local_direction).normalized()
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, world_direction.x * walk_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, world_direction.z * walk_speed, acceleration * delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	move_and_slide()
