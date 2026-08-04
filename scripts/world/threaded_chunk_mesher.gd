extends RefCounted
class_name ThreadedChunkMesher

const CHUNK_SIZE := Vector3i(16, 16, 16)
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const TRIANGLE_INDICES := [0, 1, 2, 0, 2, 3]

const FACE_DIRECTIONS := [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

const FACE_NORMALS := [
	Vector3.LEFT,
	Vector3.RIGHT,
	Vector3.DOWN,
	Vector3.UP,
	Vector3.FORWARD,
	Vector3.BACK,
]

const FACE_VERTICES := [
	[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)],
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)],
]


static func build_mesh_data(
	snapshot: Dictionary,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var result := _compute_mesh_data(snapshot)
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()


static func _compute_mesh_data(snapshot: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var blocks: PackedByteArray = snapshot.get("blocks", PackedByteArray())
	var neighbors: Dictionary = snapshot.get("neighbors", {})
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var visible_face_count := 0

	for local_y in range(CHUNK_SIZE.y):
		for local_z in range(CHUNK_SIZE.z):
			for local_x in range(CHUNK_SIZE.x):
				var local_coord := Vector3i(local_x, local_y, local_z)
				var block_id := _get_block(blocks, local_coord)
				if block_id == BLOCK_AIR:
					continue

				var origin := Vector3(local_coord)
				var color := _color_for_block(block_id)
				for face_index in range(FACE_VERTICES.size()):
					var neighbor_local: Vector3i = local_coord + FACE_DIRECTIONS[face_index]
					if _get_snapshot_block(blocks, neighbors, neighbor_local) != BLOCK_AIR:
						continue

					visible_face_count += 1
					var face_vertices: Array = FACE_VERTICES[face_index]
					var normal: Vector3 = FACE_NORMALS[face_index]
					for vertex_index in TRIANGLE_INDICES:
						vertices.append(origin + face_vertices[vertex_index])
						normals.append(normal)
						colors.append(color)

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"visible_face_count": visible_face_count,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}


static func _get_snapshot_block(
	blocks: PackedByteArray,
	neighbors: Dictionary,
	local_coord: Vector3i
) -> int:
	if _is_local_coord_valid(local_coord):
		return _get_block(blocks, local_coord)

	var direction := Vector3i.ZERO
	if local_coord.x < 0:
		direction = Vector3i.LEFT
	elif local_coord.x >= CHUNK_SIZE.x:
		direction = Vector3i.RIGHT
	elif local_coord.y < 0:
		direction = Vector3i.DOWN
	elif local_coord.y >= CHUNK_SIZE.y:
		direction = Vector3i.UP
	elif local_coord.z < 0:
		direction = Vector3i.FORWARD
	elif local_coord.z >= CHUNK_SIZE.z:
		direction = Vector3i.BACK

	var neighbor_blocks: PackedByteArray = neighbors.get(direction, PackedByteArray())
	if neighbor_blocks.is_empty():
		return BLOCK_AIR
	var wrapped_coord := Vector3i(
		posmod(local_coord.x, CHUNK_SIZE.x),
		posmod(local_coord.y, CHUNK_SIZE.y),
		posmod(local_coord.z, CHUNK_SIZE.z)
	)
	return _get_block(neighbor_blocks, wrapped_coord)


static func _get_block(blocks: PackedByteArray, local_coord: Vector3i) -> int:
	var index := local_coord.x + CHUNK_SIZE.x * (
		local_coord.z + CHUNK_SIZE.z * local_coord.y
	)
	if index < 0 or index >= blocks.size():
		return BLOCK_AIR
	return blocks[index]


static func _is_local_coord_valid(local_coord: Vector3i) -> bool:
	return (
		local_coord.x >= 0 and local_coord.x < CHUNK_SIZE.x
		and local_coord.y >= 0 and local_coord.y < CHUNK_SIZE.y
		and local_coord.z >= 0 and local_coord.z < CHUNK_SIZE.z
	)


static func _color_for_block(block_id: int) -> Color:
	match block_id:
		BLOCK_GRASS:
			return Color(0.29, 0.62, 0.22)
		BLOCK_DIRT:
			return Color(0.42, 0.26, 0.14)
		BLOCK_STONE:
			return Color(0.46, 0.48, 0.50)
		BLOCK_SAND:
			return Color(0.78, 0.70, 0.45)
		_:
			return Color.WHITE
