extends RefCounted

const WATER_BLOCK_ID := 7
const WATER_NONE := 0
const WORLD_HEIGHT := 60
const WATER_TOP_COLOR := Color(0.18, 0.50, 0.72, 0.86)
const WATER_SIDE_COLOR := Color(0.12, 0.36, 0.56, 0.86)

# Dedicated fluid mesher.
# The world owns water as voxel/fluid state. The procedural water source is the
# same water_info_at() state used by the world data to materialize BLOCK_WATER
# in get_block(). The mesher consumes that compact column state rather than
# calling get_block() for every voxel in the 60-block column.
#
# Rendering rules:
# - only exposed water tops are emitted;
# - adjacent water cells never emit internal faces;
# - shoreline side faces are emitted only against air/open space;
# - equal-height adjacent tops are greedily merged;
# - a one-column cache border provides chunk-boundary correctness;
# - explicit block overrides remain authoritative over generated fluid state.
static func build(data, coord: Vector2i, chunk_size: int) -> Dictionary:
	if not data.has_method("terrain_height"):
		return _empty_result()

	var cache_width := chunk_size + 2
	var cache_count := cache_width * cache_width
	var terrain_heights := PackedInt32Array()
	var water_types := PackedByteArray()
	var water_surfaces := PackedInt32Array()
	terrain_heights.resize(cache_count)
	water_types.resize(cache_count)
	water_surfaces.resize(cache_count)

	var origin_x := coord.x * chunk_size
	var origin_z := coord.y * chunk_size
	for cache_z in range(cache_width):
		var world_z := origin_z + cache_z - 1
		var row := cache_z * cache_width
		for cache_x in range(cache_width):
			var world_x := origin_x + cache_x - 1
			var index := row + cache_x
			terrain_heights[index] = int(data.terrain_height(world_x, world_z))
			var info := water_info(data, world_x, world_z)
			water_types[index] = clampi(info.x, 0, 255)
			water_surfaces[index] = info.y

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var top_visited := PackedByteArray()
	top_visited.resize(chunk_size * chunk_size)
	var top_quad_count := 0
	var water_voxel_count := 0

	# The column source is converted into the same full water-voxel range used by
	# gameplay: floor+1 through water_surface inclusive.
	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var cache_x := local_x + 1
			var cache_z := local_z + 1
			var index := cache_z * cache_width + cache_x
			var floor_y := int(terrain_heights[index])
			var surface_y := int(water_surfaces[index])
			var water_type := int(water_types[index])
			if water_type == WATER_NONE or surface_y <= floor_y:
				continue

			for world_y in range(floor_y + 1, surface_y + 1):
				if _is_water_cell(data, origin_x + local_x, world_y, origin_z + local_z, floor_y, surface_y, water_type):
					water_voxel_count += 1

			var top_local_index := local_z * chunk_size + local_x
			if top_visited[top_local_index] != 0:
				continue
			if not _is_water_cell(data, origin_x + local_x, surface_y, origin_z + local_z, floor_y, surface_y, water_type):
				continue

			var width := 1
			while local_x + width < chunk_size:
				var candidate_local_index := local_z * chunk_size + local_x + width
				var candidate_cache := cache_z * cache_width + (local_x + width + 1)
				if top_visited[candidate_local_index] != 0:
					break
				if int(water_types[candidate_cache]) != water_type or int(water_surfaces[candidate_cache]) != surface_y:
					break
				var candidate_floor := int(terrain_heights[candidate_cache])
				if not _is_water_cell(data, origin_x + local_x + width, surface_y, origin_z + local_z, candidate_floor, surface_y, water_type):
					break
				width += 1

			var depth := 1
			while local_z + depth < chunk_size:
				var row_compatible := true
				for span_x in range(width):
					var candidate_local_index := (local_z + depth) * chunk_size + local_x + span_x
					var candidate_cache := (local_z + depth + 1) * cache_width + (local_x + span_x + 1)
					if top_visited[candidate_local_index] != 0:
						row_compatible = false
						break
					if int(water_types[candidate_cache]) != water_type or int(water_surfaces[candidate_cache]) != surface_y:
						row_compatible = false
						break
					var candidate_floor := int(terrain_heights[candidate_cache])
					if not _is_water_cell(data, origin_x + local_x + span_x, surface_y, origin_z + local_z + depth, candidate_floor, surface_y, water_type):
						row_compatible = false
						break
				if not row_compatible:
					break
				depth += 1

			for mark_z in range(depth):
				for mark_x in range(width):
					top_visited[(local_z + mark_z) * chunk_size + local_x + mark_x] = 1

			var top_y := float(surface_y + 1)
			_append_quad(vertices, normals, colors, indices,
				Vector3(local_x, top_y, local_z),
				Vector3(local_x, top_y, local_z + depth),
				Vector3(local_x + width, top_y, local_z + depth),
				Vector3(local_x + width, top_y, local_z),
				Vector3.UP, WATER_TOP_COLOR)
			top_quad_count += 1

	# Emit only exposed vertical parts of each water stack. Neighbor water at the
	# same y occupies the interface, so water/water faces are suppressed.
	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var cache_x := local_x + 1
			var cache_z := local_z + 1
			var index := cache_z * cache_width + cache_x
			var floor_y := int(terrain_heights[index])
			var surface_y := int(water_surfaces[index])
			var water_type := int(water_types[index])
			if water_type == WATER_NONE or surface_y <= floor_y:
				continue

			_append_exposed_side_stack(vertices, normals, colors, indices,
				data, local_x, local_z, origin_x + local_x, origin_z + local_z,
				floor_y, surface_y, water_type,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x + 1, cache_z, Vector3.RIGHT)
			_append_exposed_side_stack(vertices, normals, colors, indices,
				data, local_x, local_z, origin_x + local_x, origin_z + local_z,
				floor_y, surface_y, water_type,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x - 1, cache_z, Vector3.LEFT)
			_append_exposed_side_stack(vertices, normals, colors, indices,
				data, local_x, local_z, origin_x + local_x, origin_z + local_z,
				floor_y, surface_y, water_type,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x, cache_z + 1, Vector3.BACK)
			_append_exposed_side_stack(vertices, normals, colors, indices,
				data, local_x, local_z, origin_x + local_x, origin_z + local_z,
				floor_y, surface_y, water_type,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x, cache_z - 1, Vector3.FORWARD)

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"top_quad_count": top_quad_count,
		"quad_count": vertices.size() / 4,
		"water_voxel_count": water_voxel_count,
	}


static func water_info(data, x: int, z: int) -> Vector2i:
	if data.has_method("water_info_at"):
		return data.water_info_at(x, z)
	if data.has_method("is_ocean_column"):
		if bool(data.is_ocean_column(x, z)):
			return Vector2i(1, 7)
		return Vector2i(WATER_NONE, -1)
	return Vector2i(WATER_NONE, -1)


static func _is_water_cell(data, x: int, y: int, z: int, floor_y: int, surface_y: int, water_type: int) -> bool:
	var override_value := _override_value(data, Vector3i(x, y, z))
	if override_value.x:
		return override_value.y == WATER_BLOCK_ID
	return water_type != WATER_NONE and y > floor_y and y <= surface_y


static func _column_occupies_y(
	data,
	x: int,
	y: int,
	z: int,
	terrain_height: int,
	water_type: int,
	water_surface: int
) -> bool:
	var override_value := _override_value(data, Vector3i(x, y, z))
	if override_value.x:
		return override_value.y != 0
	if y <= terrain_height:
		return true
	return water_type != WATER_NONE and y <= water_surface


static func _append_exposed_side_stack(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	data,
	local_x: int,
	local_z: int,
	world_x: int,
	world_z: int,
	floor_y: int,
	surface_y: int,
	water_type: int,
	terrain_heights: PackedInt32Array,
	water_types: PackedByteArray,
	water_surfaces: PackedInt32Array,
	cache_width: int,
	neighbor_cache_x: int,
	neighbor_cache_z: int,
	normal: Vector3
) -> void:
	if neighbor_cache_x < 0 or neighbor_cache_x >= cache_width or neighbor_cache_z < 0 or neighbor_cache_z >= cache_width:
		return
	var neighbor_index := neighbor_cache_z * cache_width + neighbor_cache_x
	var neighbor_x := world_x + int(normal.x)
	var neighbor_z := world_z + int(normal.z)
	var neighbor_floor := int(terrain_heights[neighbor_index])
	var neighbor_water_type := int(water_types[neighbor_index])
	var neighbor_surface := int(water_surfaces[neighbor_index])

	var run_start := -1
	for block_y in range(floor_y + 1, surface_y + 1):
		var source_active := _is_water_cell(data, world_x, block_y, world_z, floor_y, surface_y, water_type)
		var exposed := source_active and not _column_occupies_y(
			data, neighbor_x, block_y, neighbor_z,
			neighbor_floor, neighbor_water_type, neighbor_surface
		)
		if exposed and run_start < 0:
			run_start = block_y
		elif not exposed and run_start >= 0:
			_append_vertical_side_quad(vertices, normals, colors, indices, local_x, local_z, run_start, block_y, normal)
			run_start = -1
	if run_start >= 0:
		_append_vertical_side_quad(vertices, normals, colors, indices, local_x, local_z, run_start, surface_y + 1, normal)


static func _append_vertical_side_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	local_x: int,
	local_z: int,
	bottom_y: int,
	top_y: int,
	normal: Vector3
) -> void:
	var x := float(local_x)
	var z := float(local_z)
	if normal == Vector3.RIGHT:
		_append_quad(vertices, normals, colors, indices, Vector3(x + 1.0, bottom_y, z), Vector3(x + 1.0, top_y, z), Vector3(x + 1.0, top_y, z + 1.0), Vector3(x + 1.0, bottom_y, z + 1.0), normal, WATER_SIDE_COLOR)
	elif normal == Vector3.LEFT:
		_append_quad(vertices, normals, colors, indices, Vector3(x, bottom_y, z), Vector3(x, bottom_y, z + 1.0), Vector3(x, top_y, z + 1.0), Vector3(x, top_y, z), normal, WATER_SIDE_COLOR)
	elif normal == Vector3.BACK:
		_append_quad(vertices, normals, colors, indices, Vector3(x, bottom_y, z + 1.0), Vector3(x + 1.0, bottom_y, z + 1.0), Vector3(x + 1.0, top_y, z + 1.0), Vector3(x, top_y, z + 1.0), normal, WATER_SIDE_COLOR)
	else:
		_append_quad(vertices, normals, colors, indices, Vector3(x, bottom_y, z), Vector3(x, top_y, z), Vector3(x + 1.0, top_y, z), Vector3(x + 1.0, bottom_y, z), normal, WATER_SIDE_COLOR)


static func _override_value(data, cell: Vector3i) -> Vector2i:
	var overrides = data.get("overrides")
	if not overrides is Dictionary:
		return Vector2i(0, 0)
	var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
	if not overrides.has(key):
		return Vector2i(0, 0)
	return Vector2i(1, int(overrides[key]))


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
