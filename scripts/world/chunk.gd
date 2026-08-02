extends Node3D
class_name VoxelChunk

const SIZE := Vector3i(16, 16, 16)
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3

var chunk_coord: Vector3i = Vector3i.ZERO
var blocks: PackedByteArray = PackedByteArray()


func configure(coord: Vector3i) -> void:
	chunk_coord = coord
	position = Vector3(
		coord.x * SIZE.x,
		coord.y * SIZE.y,
		coord.z * SIZE.z
	)
	blocks.resize(SIZE.x * SIZE.y * SIZE.z)
	blocks.fill(BLOCK_AIR)


func generate_elevation(elevation_noise: FastNoiseLite, base_height: int, height_amplitude: int) -> void:
	for local_x in range(SIZE.x):
		for local_z in range(SIZE.z):
			var world_x := chunk_coord.x * SIZE.x + local_x
			var world_z := chunk_coord.z * SIZE.z + local_z
			var sampled_height := base_height + roundi(
				elevation_noise.get_noise_2d(world_x, world_z) * height_amplitude
			)

			for local_y in range(SIZE.y):
				var world_y := chunk_coord.y * SIZE.y + local_y
				var block_id := _block_for_depth(sampled_height - world_y)
				set_block(Vector3i(local_x, local_y, local_z), block_id)


func _block_for_depth(depth_below_surface: int) -> int:
	if depth_below_surface < 0:
		return BLOCK_AIR
	if depth_below_surface == 0:
		return BLOCK_GRASS
	if depth_below_surface <= 3:
		return BLOCK_DIRT
	return BLOCK_STONE


func set_block(local_coord: Vector3i, block_id: int) -> void:
	if not is_local_coord_valid(local_coord):
		return
	blocks[_block_index(local_coord)] = block_id


func get_block(local_coord: Vector3i) -> int:
	if not is_local_coord_valid(local_coord):
		return BLOCK_AIR
	return blocks[_block_index(local_coord)]


func is_local_coord_valid(local_coord: Vector3i) -> bool:
	return (
		local_coord.x >= 0 and local_coord.x < SIZE.x
		and local_coord.y >= 0 and local_coord.y < SIZE.y
		and local_coord.z >= 0 and local_coord.z < SIZE.z
	)


func _block_index(local_coord: Vector3i) -> int:
	return local_coord.x + SIZE.x * (local_coord.z + SIZE.z * local_coord.y)
