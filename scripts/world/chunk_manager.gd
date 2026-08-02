extends Node3D
class_name ChunkManager

const VOXEL_CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const CHUNK_SIZE := 16
const CHUNK_DIMENSIONS := Vector3i(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)

var chunks: Dictionary = {}


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
