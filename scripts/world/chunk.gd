extends Node3D
class_name VoxelChunk

const SIZE := Vector3i(16, 16, 16)

var chunk_coord: Vector3i = Vector3i.ZERO


func configure(coord: Vector3i) -> void:
	chunk_coord = coord
	position = Vector3(
		coord.x * SIZE.x,
		coord.y * SIZE.y,
		coord.z * SIZE.z
	)
