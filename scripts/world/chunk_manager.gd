extends Node3D
class_name ChunkManager

const VOXEL_CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const CHUNK_SIZE := 16
const CHUNK_DIMENSIONS := Vector3i(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)

@export_range(1, 8, 1) var render_radius: int = 2
@export var streaming_target_path: NodePath

var chunks: Dictionary = {}
var last_center_chunk: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var _streaming_target: Node3D


func _ready() -> void:
	_streaming_target = get_node_or_null(streaming_target_path) as Node3D
	if _streaming_target != null:
		refresh_streaming(_streaming_target.global_position)


func _process(_delta: float) -> void:
	if _streaming_target == null:
		return

	var center_chunk := world_to_chunk_coord(_streaming_target.global_position)
	if center_chunk != last_center_chunk:
		refresh_streaming(_streaming_target.global_position)


static func world_to_chunk_coord(world_position: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_position.x / float(CHUNK_SIZE)),
		floori(world_position.y / float(CHUNK_SIZE)),
		floori(world_position.z / float(CHUNK_SIZE))
	)


static func chunk_coord_to_world_origin(chunk_coord: Vector3i) -> Vector3:
	return Vector3(
		chunk_coord.x * CHUNK_SIZE,
		chunk_coord.y * CHUNK_SIZE,
		chunk_coord.z * CHUNK_SIZE
	)


func refresh_streaming(world_position: Vector3) -> void:
	var center_chunk := world_to_chunk_coord(world_position)
	var desired_chunks: Dictionary = {}
	var radius_squared := render_radius * render_radius

	for offset_x in range(-render_radius, render_radius + 1):
		for offset_y in range(-render_radius, render_radius + 1):
			for offset_z in range(-render_radius, render_radius + 1):
				var offset := Vector3i(offset_x, offset_y, offset_z)
				if offset.length_squared() > radius_squared:
					continue

				var chunk_coord := center_chunk + offset
				desired_chunks[chunk_coord] = true
				if not chunks.has(chunk_coord):
					create_empty_chunk(chunk_coord)

	var loaded_coords := chunks.keys()
	for loaded_coord in loaded_coords:
		if not desired_chunks.has(loaded_coord):
			remove_chunk(loaded_coord)

	last_center_chunk = center_chunk


func expected_chunk_count() -> int:
	var count := 0
	var radius_squared := render_radius * render_radius
	for offset_x in range(-render_radius, render_radius + 1):
		for offset_y in range(-render_radius, render_radius + 1):
			for offset_z in range(-render_radius, render_radius + 1):
				var offset := Vector3i(offset_x, offset_y, offset_z)
				if offset.length_squared() <= radius_squared:
					count += 1
	return count


func has_chunk(chunk_coord: Vector3i) -> bool:
	return chunks.has(chunk_coord)


func get_chunk(chunk_coord: Vector3i) -> Node3D:
	return chunks.get(chunk_coord) as Node3D


func register_chunk(chunk_coord: Vector3i, chunk: Node3D) -> bool:
	if chunk == null or chunks.has(chunk_coord):
		return false

	chunks[chunk_coord] = chunk
	if chunk.get_parent() == null:
		add_child(chunk)
	return true


func create_empty_chunk(chunk_coord: Vector3i) -> Node3D:
	var existing_chunk := get_chunk(chunk_coord)
	if is_instance_valid(existing_chunk):
		return existing_chunk

	var chunk := VOXEL_CHUNK_SCRIPT.new()
	chunk.configure(chunk_coord)
	register_chunk(chunk_coord, chunk)
	return chunk


func remove_chunk(chunk_coord: Vector3i) -> bool:
	if not chunks.has(chunk_coord):
		return false

	var chunk := get_chunk(chunk_coord)
	chunks.erase(chunk_coord)
	if is_instance_valid(chunk):
		chunk.queue_free()
	return true


func clear_chunks() -> void:
	for chunk in chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	chunks.clear()


func chunk_count() -> int:
	return chunks.size()
