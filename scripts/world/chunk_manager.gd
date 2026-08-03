extends Node3D
class_name ChunkManager

const VOXEL_CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const BIOME_PROBE_SCRIPT := preload("res://scripts/world/biome_probe.gd")
const CHUNK_SIZE := 16
const CHUNK_DIMENSIONS := Vector3i(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
const BLOCK_AIR := 0
const MIN_PLACEABLE_BLOCK := 1
const MAX_PLACEABLE_BLOCK := 4
const TERRAIN_SEED := 1701
const BIOME_SEED := 2718
const TERRAIN_BASE_HEIGHT := 8
const TERRAIN_HEIGHT_AMPLITUDE := 6
const NEIGHBOR_DIRECTIONS := [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

@export_range(1, 8, 1) var render_radius: int = 2
@export var streaming_target_path: NodePath

var chunks: Dictionary = {}
var last_center_chunk: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var _streaming_target: Node3D
var _elevation_noise := FastNoiseLite.new()
var _biome_noise := FastNoiseLite.new()


func _ready() -> void:
	_configure_elevation_noise()
	_configure_biome_noise()
	_streaming_target = get_node_or_null(streaming_target_path) as Node3D
	if _streaming_target != null:
		refresh_streaming(_streaming_target.global_position)


func _process(_delta: float) -> void:
	if _streaming_target == null:
		return

	var center_chunk := world_to_chunk_coord(_streaming_target.global_position)
	if center_chunk != last_center_chunk:
		refresh_streaming(_streaming_target.global_position)


func _configure_elevation_noise() -> void:
	_elevation_noise.seed = TERRAIN_SEED
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elevation_noise.frequency = 0.015
	_elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elevation_noise.fractal_octaves = 4
	_elevation_noise.fractal_lacunarity = 2.0
	_elevation_noise.fractal_gain = 0.5


func _configure_biome_noise() -> void:
	_biome_noise.seed = BIOME_SEED
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_noise.frequency = 0.0035
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_biome_noise.fractal_octaves = 3
	_biome_noise.fractal_lacunarity = 2.0
	_biome_noise.fractal_gain = 0.5


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


func world_to_local_coord(world_block_coord: Vector3i) -> Vector3i:
	return Vector3i(
		posmod(world_block_coord.x, CHUNK_SIZE),
		posmod(world_block_coord.y, CHUNK_SIZE),
		posmod(world_block_coord.z, CHUNK_SIZE)
	)


func get_block_world(world_block_coord: Vector3i) -> int:
	var chunk_coord := Vector3i(
		floori(world_block_coord.x / float(CHUNK_SIZE)),
		floori(world_block_coord.y / float(CHUNK_SIZE)),
		floori(world_block_coord.z / float(CHUNK_SIZE))
	)
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return BLOCK_AIR
	return chunk.get_block(world_to_local_coord(world_block_coord))


func set_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	var chunk_coord := Vector3i(
		floori(world_block_coord.x / float(CHUNK_SIZE)),
		floori(world_block_coord.y / float(CHUNK_SIZE)),
		floori(world_block_coord.z / float(CHUNK_SIZE))
	)
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return false

	var local_coord := world_to_local_coord(world_block_coord)
	if chunk.get_block(local_coord) == block_id:
		return false

	chunk.set_block(local_coord, block_id)
	_rebuild_chunk(chunk_coord)
	_rebuild_boundary_neighbors(chunk_coord, local_coord)
	return true


func mine_block_world(world_block_coord: Vector3i) -> bool:
	if get_block_world(world_block_coord) == BLOCK_AIR:
		return false
	return set_block_world(world_block_coord, BLOCK_AIR)


func place_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if block_id < MIN_PLACEABLE_BLOCK or block_id > MAX_PLACEABLE_BLOCK:
		return false
	if get_block_world(world_block_coord) != BLOCK_AIR:
		return false
	return set_block_world(world_block_coord, block_id)


func _rebuild_boundary_neighbors(chunk_coord: Vector3i, local_coord: Vector3i) -> void:
	if local_coord.x == 0:
		_rebuild_chunk(chunk_coord + Vector3i.LEFT)
	elif local_coord.x == CHUNK_SIZE - 1:
		_rebuild_chunk(chunk_coord + Vector3i.RIGHT)

	if local_coord.y == 0:
		_rebuild_chunk(chunk_coord + Vector3i.DOWN)
	elif local_coord.y == CHUNK_SIZE - 1:
		_rebuild_chunk(chunk_coord + Vector3i.UP)

	if local_coord.z == 0:
		_rebuild_chunk(chunk_coord + Vector3i.FORWARD)
	elif local_coord.z == CHUNK_SIZE - 1:
		_rebuild_chunk(chunk_coord + Vector3i.BACK)


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
	chunk.generate_terrain(
		_elevation_noise,
		_biome_noise,
		TERRAIN_BASE_HEIGHT,
		TERRAIN_HEIGHT_AMPLITUDE
	)
	BIOME_PROBE_SCRIPT.run(chunk)
	register_chunk(chunk_coord, chunk)
	_rebuild_chunk_and_neighbors(chunk_coord)
	return chunk


func remove_chunk(chunk_coord: Vector3i) -> bool:
	if not chunks.has(chunk_coord):
		return false

	var chunk := get_chunk(chunk_coord)
	chunks.erase(chunk_coord)
	if is_instance_valid(chunk):
		chunk.queue_free()
	for direction in NEIGHBOR_DIRECTIONS:
		_rebuild_chunk(chunk_coord + direction)
	return true


func _rebuild_chunk_and_neighbors(chunk_coord: Vector3i) -> void:
	_rebuild_chunk(chunk_coord)
	for direction in NEIGHBOR_DIRECTIONS:
		_rebuild_chunk(chunk_coord + direction)


func _rebuild_chunk(chunk_coord: Vector3i) -> void:
	var chunk := get_chunk(chunk_coord)
	if is_instance_valid(chunk):
		chunk.rebuild_mesh(Callable(self, "get_block_world"))


func clear_chunks() -> void:
	for chunk in chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	chunks.clear()


func chunk_count() -> int:
	return chunks.size()
