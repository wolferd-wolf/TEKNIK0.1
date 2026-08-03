extends CharacterBody3D
class_name FirstPersonController

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const PALETTE_ENTRIES := [
	{
		"slot": 1,
		"action": "select_block_1",
		"block_id": BLOCK_STONE,
		"name": "Stone",
	},
	{
		"slot": 2,
		"action": "select_block_2",
		"block_id": BLOCK_DIRT,
		"name": "Dirt",
	},
	{
		"slot": 3,
		"action": "select_block_3",
		"block_id": BLOCK_GRASS,
		"name": "Grass",
	},
	{
		"slot": 4,
		"action": "select_block_4",
		"block_id": BLOCK_SAND,
		"name": "Sand",
	},
]

@export var walk_speed: float = 6.0
@export var ground_acceleration: float = 28.0
@export var air_acceleration: float = 8.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 20.0
@export var look_sensitivity: float = 0.0025
@export var action_look_speed: float = 2.2
@export var pitch_limit_degrees: float = 89.0
@export var target_distance: float = 6.0
@export_range(1, 4, 1) var active_placement_block_id: int = BLOCK_STONE
@export var chunk_manager_path: NodePath = NodePath("../ChunkManager")

@onready var camera: Camera3D = $Camera3D
@onready var _player_collision: CollisionShape3D = $CollisionShape3D
@onready var _chunk_manager: ChunkManager = get_node_or_null(chunk_manager_path) as ChunkManager
@onready var _target_highlight: MeshInstance3D = get_node_or_null("../TargetHighlight") as MeshInstance3D

var _pitch_radians: float = 0.0
var _has_block_target: bool = false
var _targeted_block_coord: Vector3i = Vector3i.ZERO
var _targeted_hit_face: Vector3i = Vector3i.ZERO
var _palette_indicator: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch_radians = camera.rotation.x
	_configure_target_highlight()
	call_deferred("_configure_palette_indicator")
	call_deferred("_update_palette_indicator")


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
	_update_palette_selection()
	_update_block_target()
	if Input.is_action_just_pressed("mine_block"):
		mine_targeted_block()
	if Input.is_action_just_pressed("place_block"):
		place_targeted_block()


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


func get_palette_indicator() -> Label:
	return _palette_indicator


func get_active_placement_block_name() -> String:
	for entry in PALETTE_ENTRIES:
		if entry["block_id"] == active_placement_block_id:
			return entry["name"]
	return "Unknown"


func select_placement_slot(slot: int) -> bool:
	for entry in PALETTE_ENTRIES:
		if entry["slot"] != slot:
			continue
		active_placement_block_id = entry["block_id"]
		_update_palette_indicator()
		return true
	return false


func mine_targeted_block() -> bool:
	if not _has_block_target or _chunk_manager == null:
		return false

	var mined_coord := _targeted_block_coord
	if not _chunk_manager.mine_block_world(mined_coord):
		return false

	_clear_block_target()
	return true


func place_targeted_block() -> bool:
	if not _has_block_target:
		return false

	var placement_coord := _targeted_block_coord + _targeted_hit_face
	if not place_block_at(placement_coord):
		return false

	_clear_block_target()
	return true


func place_block_at(world_block_coord: Vector3i) -> bool:
	if not can_place_block_at(world_block_coord):
		return false
	return _chunk_manager.place_block_world(world_block_coord, active_placement_block_id)


func can_place_block_at(world_block_coord: Vector3i) -> bool:
	if _chunk_manager == null:
		return false
	if _chunk_manager.get_block_world(world_block_coord) != BLOCK_AIR:
		return false
	return not _block_overlaps_player(world_block_coord)


func _block_overlaps_player(world_block_coord: Vector3i) -> bool:
	if not is_instance_valid(_player_collision):
		return true

	var capsule := _player_collision.shape as CapsuleShape3D
	if capsule == null:
		return true

	var collision_scale := _player_collision.global_transform.basis.get_scale().abs()
	var capsule_radius := capsule.radius * maxf(collision_scale.x, collision_scale.z)
	var segment_half_height := maxf(capsule.height * 0.5 - capsule.radius, 0.0) * collision_scale.y
	var capsule_center := _player_collision.global_position
	var block_min := Vector3(world_block_coord)
	var block_max := block_min + Vector3.ONE

	var distance_x := _point_interval_distance(capsule_center.x, block_min.x, block_max.x)
	var distance_z := _point_interval_distance(capsule_center.z, block_min.z, block_max.z)
	var distance_y := _interval_distance(
		capsule_center.y - segment_half_height,
		capsule_center.y + segment_half_height,
		block_min.y,
		block_max.y
	)
	var distance_squared := (
		distance_x * distance_x
		+ distance_y * distance_y
		+ distance_z * distance_z
	)
	return distance_squared < capsule_radius * capsule_radius - 0.000001


static func _point_interval_distance(value: float, interval_min: float, interval_max: float) -> float:
	if value < interval_min:
		return interval_min - value
	if value > interval_max:
		return value - interval_max
	return 0.0


static func _interval_distance(
	first_min: float,
	first_max: float,
	second_min: float,
	second_max: float
) -> float:
	if first_max < second_min:
		return second_min - first_max
	if second_max < first_min:
		return first_min - second_max
	return 0.0


func _update_palette_selection() -> void:
	for entry in PALETTE_ENTRIES:
		if Input.is_action_just_pressed(entry["action"]):
			select_placement_slot(entry["slot"])
			return


func _configure_palette_indicator() -> void:
	var main_root := get_parent()
	if main_root == null:
		return

	var palette_layer := main_root.get_node_or_null("PaletteUI") as CanvasLayer
	if palette_layer == null:
		palette_layer = CanvasLayer.new()
		palette_layer.name = "PaletteUI"
		palette_layer.layer = 10
		main_root.add_child(palette_layer)

	var palette_panel := palette_layer.get_node_or_null("PalettePanel") as PanelContainer
	if palette_panel == null:
		palette_panel = PanelContainer.new()
		palette_panel.name = "PalettePanel"
		palette_panel.offset_left = 16.0
		palette_panel.offset_top = 16.0
		palette_panel.offset_right = 564.0
		palette_panel.offset_bottom = 66.0
		palette_layer.add_child(palette_panel)

	_palette_indicator = palette_panel.get_node_or_null("PaletteIndicator") as Label
	if _palette_indicator == null:
		_palette_indicator = Label.new()
		_palette_indicator.name = "PaletteIndicator"
		_palette_indicator.custom_minimum_size = Vector2(532.0, 42.0)
		_palette_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_palette_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_palette_indicator.add_theme_font_size_override("font_size", 20)
		_palette_indicator.add_theme_color_override("font_color", Color.WHITE)
		_palette_indicator.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		_palette_indicator.add_theme_constant_override("shadow_offset_x", 2)
		_palette_indicator.add_theme_constant_override("shadow_offset_y", 2)
		palette_panel.add_child(_palette_indicator)


func _update_palette_indicator() -> void:
	if not is_instance_valid(_palette_indicator):
		return

	var parts: PackedStringArray = PackedStringArray()
	for entry in PALETTE_ENTRIES:
		var block_name: String = entry["name"]
		if entry["block_id"] == active_placement_block_id:
			parts.append("[%d] %s" % [entry["slot"], block_name.to_upper()])
		else:
			parts.append("%d %s" % [entry["slot"], block_name])
	_palette_indicator.text = "Placement: " + "   ".join(parts)


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
	if _chunk_manager.get_block_world(block_coord) == BLOCK_AIR:
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
