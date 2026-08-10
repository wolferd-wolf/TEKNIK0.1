extends RefCounted

const WATER_BLOCK_ID := 7
const WORLD_HEIGHT := 60
const WATER_TOP_COLOR := Color(0.18, 0.50, 0.72, 0.86)
const WATER_SIDE_COLOR := Color(0.12, 0.36, 0.56, 0.86)

# Dedicated fluid mesher. The renderer consumes authoritative voxel/block data:
# a cell is water only when data.get_block(cell) == WATER_BLOCK_ID. Column-level
# water_info_at() is deliberately not consulted here. This prevents a procedural
# water surface from becoming a world-scale plane and makes digging/placement
# operate on the same block state as the rest of the voxel world.
static func build(data, coord: Vector2i, chunk_size: int) -> Dictionary:
	if not data.has_method("get_block"):
		return _empty_result()

	var world_height := WORLD_HEIGHT
	var cache_width := chunk_size + 2
	var cache_voxel_count := cache_width * cache_width * world_height
	var blocks := PackedInt32Array()
	blocks.resize(cache_voxel_count)

	var origin_x := coord.x * chunk_size
	var origin_z := coord.y * chunk_size
	for world_y in range(world_height):
		for cache_z in range(cache_width):
			var world_z := origin_z + cache_z - 1
			var row := (world_y * cache_width + cache_z) * cache_width
			for cache_x in range(cache_width):
				var world_x := origin_x + cache_x - 1
				blocks[row + cache_x] = int(data.get_block(Vector3i(world_x, world_y, world_z)))

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var top_visited := PackedByteArray()
	top_visited.resize(chunk_size * chunk_size * world_height)
	var top_quad_count := 0

	# Only the uppermost water voxel in a column gets a top surface. Equal-height
	# neighboring tops are greedily merged into one quad.
	for world_y in range(world_height):
		for local_z in range(chunk_size):
			for local_x in range(chunk_size):
				var top_index := _local_voxel_index(local_x, world_y, local_z, chunk_size)
				if top_visited[top_index] != 0:
					continue
				var cache_index := _cache_index(local_x + 1, world_y, local_z + 1, cache_width)
				if not _is_water(blocks, cache_index):
					top_visited[top_index] = 1
					continue
				if world_y + 1 < world_height and _is_water(blocks, _cache_index(local_x + 1, world_y + 1, local_z + 1, cache_width)):
					continue

				var width := 1
				var candidate_local := -1
				var candidate_cache := -1
				var candidate_above := -1
				while local_x + width < chunk_size:
					candidate_local = _local_voxel_index(local_x + width, world_y, local_z, chunk_size)
					candidate_cache = _cache_index(local_x + width + 1, world_y, local_z + 1, cache_width)
					candidate_above = _cache_index(local_x + width + 1, world_y + 1, local_z + 1, cache_width)
					if top_visited[candidate_local] != 0 or not _is_water(blocks, candidate_cache):
						break
					if world_y + 1 < world_height and _is_water(blocks, candidate_above):
						break
					width += 1

				var depth := 1
				while local_z + depth < chunk_size:
					var row_compatible := true
					for span_x in range(width):
						candidate_local = _local_voxel_index(local_x + span_x, world_y, local_z + depth, chunk_size)
						candidate_cache = _cache_index(local_x + span_x + 1, world_y, local_z + depth + 1, cache_width)
						candidate_above = _cache_index(local_x + span_x + 1, world_y + 1, local_z + depth + 1, cache_width)
						if top_visited[candidate_local] != 0 or not _is_water(blocks, candidate_cache):
							row_compatible = false
							break
						if world_y + 1 < world_height and _is_water(blocks, candidate_above):
							row_compatible = false
							break
					if not row_compatible:
						break
					depth += 1

				for mark_z in range(depth):
					for mark_x in range(width):
						top_visited[_local_voxel_index(local_x + mark_x, world_y, local_z + mark_z, chunk_size)] = 1

				var top_y := float(world_y + 1)
				_append_quad(vertices, normals, colors, indices,
					Vector3(local_x, top_y, local_z),
					Vector3(local_x, top_y, local_z + depth),
					Vector3(local_x + width, top_y, local_z + depth),
					Vector3(local_x + width, top_y, local_z),
					Vector3.UP, WATER_TOP_COLOR)
				top_quad_count += 1

	# Side faces are emitted only where the adjacent voxel is air. Internal
	# water/water faces and water/terrain faces are therefore completely absent.
	for world_y in range(world_height):
		for local_z in range(chunk_size):
			for local_x in range(chunk_size):
				var cache_x := local_x + 1
				var cache_z := local_z + 1
				var index := _cache_index(cache_x, world_y, cache_z, cache_width)
				if not _is_water(blocks, index):
					continue
				_append_side_if_air(vertices, normals, colors, indices, blocks, cache_width, local_x, local_z, world_y, cache_x + 1, cache_z, Vector3.RIGHT)
				_append_side_if_air(vertices, normals, colors, indices, blocks, cache_width, local_x, local_z, world_y, cache_x - 1, cache_z, Vector3.LEFT)
				_append_side_if_air(vertices, normals, colors, indices, blocks, cache_width, local_x, local_z, world_y, cache_x, cache_z + 1, Vector3.BACK)
				_append_side_if_air(vertices, normals, colors, indices, blocks, cache_width, local_x, local_z, world_y, cache_x, cache_z - 1, Vector3.FORWARD)

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"top_quad_count": top_quad_count,
		"quad_count": vertices.size() / 4,
		"water_voxel_count": _count_water_voxels(blocks),
	}


static func water_info(data, x: int, z: int) -> Vector2i:
	# Compatibility API for diagnostics/tests only. The renderer never calls it.
	if data.has_method("water_info_at"):
		return data.water_info_at(x, z)
	return Vector2i(0, -1)


static func _append_side_if_air(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, blocks: PackedInt32Array, cache_width: int, local_x: int, local_z: int, world_y: int, neighbor_x: int, neighbor_z: int, normal: Vector3) -> void:
	if neighbor_x < 0 or neighbor_x >= cache_width or neighbor_z < 0 or neighbor_z >= cache_width:
		return
	var neighbor_index := _cache_index(neighbor_x, world_y, neighbor_z, cache_width)
	if int(blocks[neighbor_index]) != 0:
		return
	var bottom := float(world_y)
	var top := float(world_y + 1)
	if normal == Vector3.RIGHT:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x + 1, bottom, local_z), Vector3(local_x + 1, top, local_z), Vector3(local_x + 1, top, local_z + 1), Vector3(local_x + 1, bottom, local_z + 1), normal, WATER_SIDE_COLOR)
	elif normal == Vector3.LEFT:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z), Vector3(local_x, bottom, local_z + 1), Vector3(local_x, top, local_z + 1), Vector3(local_x, top, local_z), normal, WATER_SIDE_COLOR)
	elif normal == Vector3.BACK:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z + 1), Vector3(local_x + 1, bottom, local_z + 1), Vector3(local_x + 1, top, local_z + 1), Vector3(local_x, top, local_z + 1), normal, WATER_SIDE_COLOR)
	else:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z), Vector3(local_x, top, local_z), Vector3(local_x + 1, top, local_z), Vector3(local_x + 1, bottom, local_z), normal, WATER_SIDE_COLOR)


static func _is_water(blocks: PackedInt32Array, index: int) -> bool:
	return int(blocks[index]) == WATER_BLOCK_ID


static func _cache_index(cache_x: int, world_y: int, cache_z: int, cache_width: int) -> int:
	return (world_y * cache_width + cache_z) * cache_width + cache_x


static func _local_voxel_index(local_x: int, world_y: int, local_z: int, chunk_size: int) -> int:
	return (world_y * chunk_size + local_z) * chunk_size + local_x


static func _count_water_voxels(blocks: PackedInt32Array) -> int:
	var count := 0
	for block in blocks:
		if int(block) == WATER_BLOCK_ID:
			count += 1
	return count


static func _empty_result() -> Dictionary:
	return {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"top_quad_count": 0,
		"quad_count": 0,
		"water_voxel_count": 0,
	}


static func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color) -> void:
	var base := vertices.size()
	vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
	for _index in range(4):
		normals.append(normal); colors.append(color)
	indices.append(base); indices.append(base + 1); indices.append(base + 2)
	indices.append(base); indices.append(base + 2); indices.append(base + 3)
