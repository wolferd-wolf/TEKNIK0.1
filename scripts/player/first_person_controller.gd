extends CharacterBody3D
class_name FirstPersonController

@export var walk_speed: float = 6.0
@export var ground_acceleration: float = 28.0
@export var air_acceleration: float = 8.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 20.0
@export var look_sensitivity: float = 0.0025
@export var action_look_speed: float = 2.2
@export var pitch_limit_degrees: float = 89.0

@onready var camera: Camera3D = $Camera3D

var _pitch_radians: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch_radians = camera.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look_delta(event.relative * look_sensitivity)


func _process(delta: float) -> void:
	var action_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	if not action_look.is_zero_approx():
		apply_look_delta(action_look * action_look_speed * delta)


func apply_look_delta(look_delta: Vector2) -> void:
	rotate_y(-look_delta.x)
	_pitch_radians = clampf(
		_pitch_radians - look_delta.y,
		deg_to_rad(-pitch_limit_degrees),
		deg_to_rad(pitch_limit_degrees)
	)
	camera.rotation.x = _pitch_radians


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
