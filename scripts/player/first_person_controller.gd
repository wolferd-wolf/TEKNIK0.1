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
@export var target_distance: float = 6.0
@export var chunk_manager_path: NodePath = NodePath("../ChunkManager")

@onready var camera: Camera3D = $Camera3D
@onready var _chunk_manager: ChunkManager = get_node_or_null(chunk_manager_path) as ChunkManager
@onready var _target_highlight: MeshInstance3D = get_node_or_null("../TargetHighlight") as MeshInstance3D

var _pitch_radians: float = 0.0
var _has_block_target: bool = false
var _targeted_block_coord: Vector3i = Vector3i.ZERO
var _targeted_hit_face: Vector3i = Vector3i.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch_radians = camera.rotation.x
	_configure_target_highlight()


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
	_update_block_target()
	if Input.is_action_just_pressed("mine_block"):
		mine_targeted_block()


func apply_look_delta(look_delta: Vector2) -> void:
	rotate_y(-look_delta.x)
	_pitch_radians = clampf(
		_pitch_radians - look_delta.y,
		deg_to_rad(-pitch_limit_degrees),
		deg_to_rad(pitch_limit_degrees)
	)
	camera.rotation.x = _pitch_radians


func get_block_target() -> Dictionary:
	if not _has_block_target:
		return {}
	return {
		"block_coord": _targeted_block_coord,
		"hit_face": _targeted_hit_face,
	}


func get_target_highlight() -> MeshInstance3D:
	return _target_highlight


func mine_targeted_block() -> bool:
	if not _has_block_target or _chunk_manager == null:
		return false

	var mined_coord := _targeted_block_coord
	if not _chunk_manager.mine_block_world(mined_coord):
		return false

	_clear_block_target()
	return true


func _configure_target_highlight() -> void:
	if _target_highlight == null:
		return

	_target_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * 1.015
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.82, 0.12, 0.32)
	box_mesh.material = material
	_target_highlight.mesh = box_mesh
	_target_highlight.visible = false


func _update_block_target() -> void:
	if camera == null or _chunk_manager == null or get_world_3d() == null:
		_clear_block_target()
		return

	var ray_origin := camera.global_position
	var ray_end := ray_origin - camera.global_transform.basis.z * target_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_clear_block_target()
		return

	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var hit_face := _normal_to_face(hit_normal)
	var inside_sample := hit_position - Vector3(hit_face) * 0.001
	var block_coord := Vector3i(
		floori(inside_sample.x),
		floori(inside_sample.y),
		floori(inside_sample.z)
	)
	if _chunk_manager.get_block_world(block_coord) == 0:
		_clear_block_target()
		return

	_has_block_target = true
	_targeted_block_coord = block_coord
	_targeted_hit_face = hit_face
	if is_instance_valid(_target_highlight):
		_target_highlight.global_position = Vector3(
			block_coord.x + 0.5,
			block_coord.y + 0.5,
			block_coord.z + 0.5
		)
		_target_highlight.visible = true


func _clear_block_target() -> void:
	_has_block_target = false
	_targeted_block_coord = Vector3i.ZERO
	_targeted_hit_face = Vector3i.ZERO
	if is_instance_valid(_target_highlight):
		_target_highlight.visible = false


static func _normal_to_face(normal: Vector3) -> Vector3i:
	var absolute := normal.abs()
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		return Vector3i(1 if normal.x >= 0.0 else -1, 0, 0)
	if absolute.y >= absolute.z:
		return Vector3i(0, 1 if normal.y >= 0.0 else -1, 0)
	return Vector3i(0, 0, 1 if normal.z >= 0.0 else -1)


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
