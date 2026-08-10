extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WATER_NONE := 0
const WATER_SURFACE_OFFSET := 1.0
const WATER_TOP_COLOR := Color(0.18, 0.50, 0.72, 0.86)
const WATER_SIDE_COLOR := Color(0.12, 0.36, 0.56, 0.86)


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

	for local_z in range(chunk_size):
		var cache_z := local_z + 1
		for local_x in range(chunk_size):
			var cache_x := local_x + 1
			var index := cache_z * cache_width + cache_x
			if int(water_types[index]) == WATER_NONE:
				continue
			var floor_y := int(terrain_heights[index])
			var surface_y := int(water_surfaces[index])
			if surface_y <= floor_y:
				continue

			var top_y := float(surface_y) + WATER_SURFACE_OFFSET
			_append_quad(vertices, normals, colors, indices,
				Vector3(local_x, top_y, local_z),
				Vector3(local_x, top_y, local_z + 1),
				Vector3(local_x + 1, top_y, local_z + 1),
				Vector3(local_x + 1, top_y, local_z),
				Vector3.UP, WATER_TOP_COLOR)

			_append_exposed_side_stack(vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x + 1, cache_z, Vector3.RIGHT)
			_append_exposed_side_stack(vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x - 1, cache_z, Vector3.LEFT)
			_append_exposed_side_stack(vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x, cache_z + 1, Vector3.BACK)
			_append_exposed_side_stack(vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x, cache_z - 1, Vector3.FORWARD)

	return {"vertices": vertices, "normals": normals, "colors": colors, "indices": indices}


static func water_info(data, x: int, z: int) -> Vector2i:
	if data.has_method("water_info_at"):
		return data.water_info_at(x, z)
	if data.has_method("is_ocean_column"):
		if bool(data.is_ocean_column(x, z)):
			return Vector2i(1, WORLD_DATA.SEA_LEVEL)
		return Vector2i(WATER_NONE, -1)
	if data.terrain_height(x, z) >= WORLD_DATA.SEA_LEVEL:
		return Vector2i(WATER_NONE, -1)
	var connected_neighbors := 0
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if data.terrain_height(x + offset.x, z + offset.z) < WORLD_DATA.SEA_LEVEL:
			connected_neighbors += 1
	if connected_neighbors >= 2:
		return Vector2i(1, WORLD_DATA.SEA_LEVEL)
	return Vector2i(WATER_NONE, -1)


static func _append_exposed_side_stack(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, local_x: int, local_z: int, floor_y: int, surface_y: int, terrain_heights: PackedInt32Array, water_types: PackedByteArray, water_surfaces: PackedInt32Array, cache_width: int, neighbor_cache_x: int, neighbor_cache_z: int, normal: Vector3) -> void:
	var neighbor_index := neighbor_cache_z * cache_width + neighbor_cache_x
	var neighbor_floor := int(terrain_heights[neighbor_index])
	var neighbor_water_type := int(water_types[neighbor_index])
	var neighbor_surface := int(water_surfaces[neighbor_index])
	for block_y in range(floor_y + 1, surface_y + 1):
		if _column_occupies_y(neighbor_floor, neighbor_water_type, neighbor_surface, block_y):
			continue
		var bottom := float(block_y)
		var top := float(block_y + 1)
		if normal == Vector3.RIGHT:
			_append_quad(vertices, normals, colors, indices, Vector3(local_x + 1, bottom, local_z), Vector3(local_x + 1, top, local_z), Vector3(local_x + 1, top, local_z + 1), Vector3(local_x + 1, bottom, local_z + 1), normal, WATER_SIDE_COLOR)
		elif normal == Vector3.LEFT:
			_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z), Vector3(local_x, bottom, local_z + 1), Vector3(local_x, top, local_z + 1), Vector3(local_x, top, local_z), normal, WATER_SIDE_COLOR)
		elif normal == Vector3.BACK:
			_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z + 1), Vector3(local_x + 1, bottom, local_z + 1), Vector3(local_x + 1, top, local_z + 1), Vector3(local_x, top, local_z + 1), normal, WATER_SIDE_COLOR)
		else:
			_append_quad(vertices, normals, colors, indices, Vector3(local_x, bottom, local_z), Vector3(local_x, top, local_z), Vector3(local_x + 1, top, local_z), Vector3(local_x + 1, bottom, local_z), normal, WATER_SIDE_COLOR)


static func _column_occupies_y(terrain_height: int, water_type: int, water_surface: int, y: int) -> bool:
	if y <= terrain_height:
		return true
	return water_type != WATER_NONE and y <= water_surface


static func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color) -> void:
	var base := vertices.size()
	vertices.append(v0)
	vertices.append(v1)
	vertices.append(v2)
	vertices.append(v3)
	for _index in range(4):
		normals.append(normal)
		colors.append(color)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)
