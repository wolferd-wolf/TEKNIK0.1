extends RefCounted

const WATER_NONE := 0
const WATER_SURFACE_OFFSET := 1.0
const WATER_TOP_COLOR := Color(0.18, 0.50, 0.72, 0.86)
const WATER_SIDE_COLOR := Color(0.12, 0.36, 0.56, 0.86)

# Dedicated fluid mesher. Water remains world data, but only explicit water
# state is rendered. Continuous equal-height surfaces are greedily merged.
# IMPORTANT: terrain/ocean classification is not a water source. A dug hole on
# dry land must stay dry, just like Minecraft. The authoritative sampler must
# explicitly say that a column contains water.
static func build(data, coord: Vector2i, chunk_size: int) -> Dictionary:
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

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var local_index := local_z * chunk_size + local_x
			if top_visited[local_index] != 0:
				continue
			var cache_index := (local_z + 1) * cache_width + local_x + 1
			if not _has_visible_water(terrain_heights, water_types, water_surfaces, cache_index):
				top_visited[local_index] = 1
				continue

			var surface_y := int(water_surfaces[cache_index])
			var width := 1
			while local_x + width < chunk_size:
				var next_local_index := local_z * chunk_size + local_x + width
				var next_cache_index := (local_z + 1) * cache_width + local_x + width + 1
				if top_visited[next_local_index] != 0 or not _has_visible_water(terrain_heights, water_types, water_surfaces, next_cache_index):
					break
				if int(water_surfaces[next_cache_index]) != surface_y:
					break
				width += 1

			var height := 1
			while local_z + height < chunk_size:
				var row_compatible := true
				for span_x in range(width):
					var check_local_index := (local_z + height) * chunk_size + local_x + span_x
					var check_cache_index := (local_z + height + 1) * cache_width + local_x + span_x + 1
					if top_visited[check_local_index] != 0 or not _has_visible_water(terrain_heights, water_types, water_surfaces, check_cache_index) or int(water_surfaces[check_cache_index]) != surface_y:
						row_compatible = false
						break
				if not row_compatible:
					break
				height += 1

			for mark_z in range(height):
				for mark_x in range(width):
					top_visited[(local_z + mark_z) * chunk_size + local_x + mark_x] = 1

			var top_y := float(surface_y) + WATER_SURFACE_OFFSET
			_append_quad(vertices, normals, colors, indices,
				Vector3(local_x, top_y, local_z), Vector3(local_x, top_y, local_z + height),
				Vector3(local_x + width, top_y, local_z + height), Vector3(local_x + width, top_y, local_z),
				Vector3.UP, WATER_TOP_COLOR)

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var cache_x := local_x + 1
			var cache_z := local_z + 1
			var index := cache_z * cache_width + cache_x
			if not _has_visible_water(terrain_heights, water_types, water_surfaces, index):
				continue
			var floor_y := int(terrain_heights[index])
			var surface_y := int(water_surfaces[index])
			_append_exposed_side(vertices, normals, colors, indices, local_x, local_z, floor_y, surface_y, terrain_heights, water_types, water_surfaces, cache_width, cache_x + 1, cache_z, Vector3.RIGHT)
			_append_exposed_side(vertices, normals, colors, indices, local_x, local_z, floor_y, surface_y, terrain_heights, water_types, water_surfaces, cache_width, cache_x - 1, cache_z, Vector3.LEFT)
			_append_exposed_side(vertices, normals, colors, indices, local_x, local_z, floor_y, surface_y, terrain_heights, water_types, water_surfaces, cache_width, cache_x, cache_z + 1, Vector3.BACK)
			_append_exposed_side(vertices, normals, colors, indices, local_x, local_z, floor_y, surface_y, terrain_heights, water_types, water_surfaces, cache_width, cache_x, cache_z - 1, Vector3.FORWARD)

	return {"vertices": vertices, "normals": normals, "colors": colors, "indices": indices, "top_quad_count": indices.size() / 6, "quad_count": vertices.size() / 4}


static func water_info(data, x: int, z: int) -> Vector2i:
	# Explicit water state is the only valid source. In particular, do NOT use
	# is_ocean_column()/sea level as a fallback: that creates an artificial
	# infinite plane and makes digging into dry terrain reveal water.
	if data.has_method("water_info_at"):
		var info: Vector2i = data.water_info_at(x, z)
		if info.x != WATER_NONE and info.y >= 0:
			return info
	return Vector2i(WATER_NONE, -1)


static func _has_visible_water(terrain_heights: PackedInt32Array, water_types: PackedByteArray, water_surfaces: PackedInt32Array, index: int) -> bool:
	return int(water_types[index]) != WATER_NONE and int(water_surfaces[index]) > int(terrain_heights[index])


static func _append_exposed_side(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, local_x: int, local_z: int, floor_y: int, surface_y: int, terrain_heights: PackedInt32Array, water_types: PackedByteArray, water_surfaces: PackedInt32Array, cache_width: int, neighbor_cache_x: int, neighbor_cache_z: int, normal: Vector3) -> void:
	var neighbor_index := neighbor_cache_z * cache_width + neighbor_cache_x
	var neighbor_floor := int(terrain_heights[neighbor_index])
	var neighbor_water_type := int(water_types[neighbor_index])
	var neighbor_surface := int(water_surfaces[neighbor_index])
	var neighbor_top := neighbor_floor
	if neighbor_water_type != WATER_NONE:
		neighbor_top = maxi(neighbor_top, neighbor_surface)
	var bottom_y := maxi(floor_y, neighbor_top) + 1
	if bottom_y > surface_y:
		return
	var bottom := float(bottom_y)
	var top := float(surface_y + 1)
	if normal == Vector3.RIGHT:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x + 1, bottom, local_z), Vector3(local_x + 1, top, local_z), Vector3(local_x + 1, top, local_z + 1), Vector3(local_x + 1, bottom, local_z + 1), normal, WATER_SIDE_COLOR)
	elif normal == Vector3.LEFT:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z), Vector3(local_x, bottom, local_z + 1), Vector3(local_x, top, local_z + 1), Vector3(local_x, top, local_z), normal, WATER_SIDE_COLOR)
	elif normal == Vector3.BACK:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z + 1), Vector3(local_x + 1, bottom, local_z + 1), Vector3(local_x + 1, top, local_z + 1), Vector3(local_x, top, local_z + 1), normal, WATER_SIDE_COLOR)
	else:
		_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z), Vector3(local_x, top, local_z), Vector3(local_x + 1, top, local_z), Vector3(local_x + 1, bottom, local_z), normal, WATER_SIDE_COLOR)


static func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color) -> void:
	var base := vertices.size()
	vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
	for _index in range(4):
		normals.append(normal); colors.append(color)
	indices.append(base); indices.append(base + 1); indices.append(base + 2)
	indices.append(base); indices.append(base + 2); indices.append(base + 3)
