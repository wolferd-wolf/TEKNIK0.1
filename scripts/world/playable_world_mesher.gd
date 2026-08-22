extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const BLOCK_COAL_ORE := 10
const BLOCK_IRON_ORE := 11
const BLOCK_COPPER_ORE := 12
const BLOCK_FURNACE := 13
const BLOCK_IRON_INGOT := 14
const BLOCK_COPPER_INGOT := 15
const BLOCK_COAL := 16
const BLOCK_GLASS := 17
const BLOCK_CHARCOAL := 18
const WORLD_SEED := 734921
const TREE_SPACING := 7
const TREE_OFFSET := 3
const FOREST_TREE_SPACING := 5
const FOREST_TREE_OFFSET := 1
const TREE_TRUNK_HEIGHT := 4
const TREE_CANOPY_RADIUS := 1
const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2
const BIOME_ROCKY := 3
const MAX_SKY_LIGHT := 15
const MIN_SKY_BRIGHTNESS := 0.35

# Compatibility tables are kept for existing validation code only. The threaded
# meshing path below never reads these shared Array containers.
const FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
const FACE_NORMALS: Array[Vector3] = [
	Vector3.UP,
	Vector3.DOWN,
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.BACK,
	Vector3.FORWARD,
]
const FACE_VERTICES: Array = [
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const FACE_TANGENT_AXES: Array[Vector2i] = [
	Vector2i(0, 2),
	Vector2i(0, 2),
	Vector2i(1, 2),
	Vector2i(1, 2),
	Vector2i(0, 1),
	Vector2i(0, 1),
]
const AO_BRIGHTNESS: Array[float] = [0.55, 0.70, 0.85, 1.0]


static func build(
	coord: Vector2i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	chunk_size: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var face_count := 0
	var origin := Vector3i(coord.x * chunk_size, 0, coord.y * chunk_size)
	var cache_width := roundi(sqrt(float(heights.size())))
	if cache_width * cache_width != heights.size():
		cache_width = chunk_size + 2
	var cache_padding := maxi(floori(float(cache_width - chunk_size) * 0.5), 1)
	var block_cache := _build_block_cache(
		origin,
		heights,
		overrides,
		cache_width,
		cache_padding,
		world_height,
		sea_level,
		biomes
	)
	var sky_light := _build_sky_light_from_blocks(block_cache, cache_width, world_height)

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			for y in range(world_height):
				var cell := Vector3i(origin.x + local_x, y, origin.z + local_z)
				var block := _cached_block(
					cell,
					origin,
					block_cache,
					cache_width,
					cache_padding,
					world_height
				)
				if block == BLOCK_AIR:
					continue
				for face_index in range(6):
					var face_direction := _face_direction(face_index)
					var face_normal := _face_normal(face_index)
					var tangent_axes := _face_tangent_axes(face_index)
					var neighbor := cell + face_direction
					if _cached_block(
						neighbor,
						origin,
						block_cache,
						cache_width,
						cache_padding,
						world_height
					) != BLOCK_AIR:
						continue
					var base_index := vertices.size()
					var local_cell := Vector3(local_x, y, local_z)
					var ao_0 := 0
					var ao_1 := 0
					var ao_2 := 0
					var ao_3 := 0
					for vertex_index in range(4):
						var vertex := _face_vertex(face_index, vertex_index)
						var ao_level := _vertex_ao_level_cached_with_basis(
							cell,
							vertex,
							face_direction,
							tangent_axes,
							origin,
							block_cache,
							cache_width,
							cache_padding,
							world_height
						)
						match vertex_index:
							0:
								ao_0 = ao_level
							1:
								ao_1 = ao_level
							2:
								ao_2 = ao_level
							_:
								ao_3 = ao_level
						var sky_factor := _vertex_sky_factor_with_basis(
							cell,
							vertex,
							face_direction,
							tangent_axes,
							origin,
							sky_light,
							cache_width,
							cache_padding,
							world_height
						)
						var light_factor := _face_shade(face_index) * _ao_brightness(ao_level) * sky_factor
						vertices.append(local_cell + vertex)
						normals.append(face_normal)
						colors.append(_block_color(block, cell, face_index, light_factor))
					_append_face_indices(indices, base_index, ao_0, ao_1, ao_2, ao_3)
					face_count += 1

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"face_count": face_count,
	}


static func _face_direction(face_index: int) -> Vector3i:
	match face_index:
		0:
			return Vector3i.UP
		1:
			return Vector3i.DOWN
		2:
			return Vector3i.RIGHT
		3:
			return Vector3i.LEFT
		4:
			return Vector3i(0, 0, 1)
		_:
			return Vector3i(0, 0, -1)


static func _face_normal(face_index: int) -> Vector3:
	match face_index:
		0:
			return Vector3.UP
		1:
			return Vector3.DOWN
		2:
			return Vector3.RIGHT
		3:
			return Vector3.LEFT
		4:
			return Vector3.BACK
		_:
			return Vector3.FORWARD


static func _face_vertex(face_index: int, vertex_index: int) -> Vector3:
	match face_index:
		0:
			match vertex_index:
				0:
					return Vector3(0, 1, 0)
				1:
					return Vector3(0, 1, 1)
				2:
					return Vector3(1, 1, 1)
				_:
					return Vector3(1, 1, 0)
		1:
			match vertex_index:
				0:
					return Vector3(0, 0, 0)
				1:
					return Vector3(1, 0, 0)
				2:
					return Vector3(1, 0, 1)
				_:
					return Vector3(0, 0, 1)
		2:
			match vertex_index:
				0:
					return Vector3(1, 0, 0)
				1:
					return Vector3(1, 1, 0)
				2:
					return Vector3(1, 1, 1)
				_:
					return Vector3(1, 0, 1)
		3:
			match vertex_index:
				0:
					return Vector3(0, 0, 0)
				1:
					return Vector3(0, 0, 1)
				2:
					return Vector3(0, 1, 1)
				_:
					return Vector3(0, 1, 0)
		4:
			match vertex_index:
				0:
					return Vector3(0, 0, 1)
				1:
					return Vector3(1, 0, 1)
				2:
					return Vector3(1, 1, 1)
				_:
					return Vector3(0, 1, 1)
		_:
			match vertex_index:
				0:
					return Vector3(0, 0, 0)
				1:
					return Vector3(0, 1, 0)
				2:
					return Vector3(1, 1, 0)
				_:
					return Vector3(1, 0, 0)


static func _face_tangent_axes(face_index: int) -> Vector2i:
	match face_index:
		0, 1:
			return Vector2i(0, 2)
		2, 3:
			return Vector2i(1, 2)
		_:
			return Vector2i(0, 1)


static func _ao_brightness(ao_level: int) -> float:
	match ao_level:
		0:
			return 0.55
		1:
			return 0.70
		2:
			return 0.85
		_:
			return 1.0


static func _build_block_cache(
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var blocks := PackedByteArray()
	blocks.resize(cache_width * cache_width * world_height)
	for cache_z in range(cache_width):
		for cache_x in range(cache_width):
			var world_x := origin.x + cache_x - cache_padding
			var world_z := origin.z + cache_z - cache_padding
			for y in range(world_height):
				var block := _get_block(
					Vector3i(world_x, y, world_z),
					origin,
					heights,
					overrides,
					cache_width,
					cache_padding,
					world_height,
					sea_level,
					biomes
				)
				blocks[_volume_index(cache_x, y, cache_z, cache_width, world_height)] = block
	return blocks


static func _cached_block(
	cell: Vector3i,
	origin: Vector3i,
	blocks: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int
) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= world_height:
		return BLOCK_AIR
	var cache_x := cell.x - origin.x + cache_padding
	var cache_z := cell.z - origin.z + cache_padding
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return BLOCK_AIR
	return int(blocks[_volume_index(cache_x, cell.y, cache_z, cache_width, world_height)])


static func _cached_biome(
	x: int,
	z: int,
	origin: Vector3i,
	biomes: PackedByteArray,
	cache_width: int,
	cache_padding: int
) -> int:
	if biomes.size() != cache_width * cache_width:
		return BIOME_PLAINS
	var cache_x := x - origin.x + cache_padding
	var cache_z := z - origin.z + cache_padding
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return BIOME_PLAINS
	return int(biomes[cache_z * cache_width + cache_x])


static func _get_block(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray()
) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= world_height:
		return BLOCK_AIR
	var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
	if overrides.has(key):
		return int(overrides[key])
	var cache_x := cell.x - origin.x + cache_padding
	var cache_z := cell.z - origin.z + cache_padding
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return BLOCK_AIR
	var height := heights[cache_z * cache_width + cache_x]
	var biome := _cached_biome(cell.x, cell.z, origin, biomes, cache_width, cache_padding)
	if cell.y <= height:
		return _terrain_block(cell.y, height, sea_level, biome)
	return _generated_tree_block(
		cell,
		origin,
		heights,
		cache_width,
		cache_padding,
		world_height,
		sea_level,
		biomes
	)


static func _terrain_block(y: int, height: int, sea_level: int, biome: int = BIOME_PLAINS) -> int:
	if y == height:
		if height <= sea_level + 1 or biome == BIOME_DESERT:
			return BLOCK_SAND
		if biome == BIOME_ROCKY:
			return BLOCK_STONE
		return BLOCK_GRASS
	if y >= height - 3:
		if height <= sea_level + 1 or biome == BIOME_DESERT:
			return BLOCK_SAND
		if biome == BIOME_ROCKY:
			return BLOCK_STONE
		return BLOCK_DIRT
	return BLOCK_STONE


static func _generated_tree_block(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray()
) -> int:
	for tree_z in range(cell.z - TREE_CANOPY_RADIUS, cell.z + TREE_CANOPY_RADIUS + 1):
		for tree_x in range(cell.x - TREE_CANOPY_RADIUS, cell.x + TREE_CANOPY_RADIUS + 1):
			var cache_x := tree_x - origin.x + cache_padding
			var cache_z := tree_z - origin.z + cache_padding
			if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
				continue
			var surface := heights[cache_z * cache_width + cache_x]
			var biome := _cached_biome(tree_x, tree_z, origin, biomes, cache_width, cache_padding)
			if not _is_tree_origin(tree_x, tree_z, surface, world_height, sea_level, biome):
				continue
			var trunk_top := surface + TREE_TRUNK_HEIGHT
			if cell.x == tree_x and cell.z == tree_z and cell.y > surface and cell.y <= trunk_top:
				return BLOCK_LOG
			if cell.y >= trunk_top - 1 and cell.y <= trunk_top + 1:
				return BLOCK_LEAVES
	return BLOCK_AIR


static func _is_tree_origin(
	x: int,
	z: int,
	surface: int,
	world_height: int,
	sea_level: int,
	biome: int = BIOME_PLAINS
) -> bool:
	if biome == BIOME_DESERT or biome == BIOME_ROCKY:
		return false
	if surface <= sea_level + 1 or surface + TREE_TRUNK_HEIGHT + 1 >= world_height:
		return false
	var baseline_grid := (
		posmod(x, TREE_SPACING) == TREE_OFFSET
		and posmod(z, TREE_SPACING) == TREE_OFFSET
	)
	var forest_grid := (
		biome == BIOME_FOREST
		and posmod(x, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
		and posmod(z, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
	)
	if not baseline_grid and not forest_grid:
		return false
	var hash_value := absi((x * 73856093) ^ (z * 19349663) ^ WORLD_SEED)
	if forest_grid and not baseline_grid:
		return hash_value % 3 != 0
	return hash_value % 4 != 0


static func _build_sky_light(
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var blocks := _build_block_cache(
		origin,
		heights,
		overrides,
		cache_width,
		cache_padding,
		world_height,
		sea_level,
		biomes
	)
	return _build_sky_light_from_blocks(blocks, cache_width, world_height)


static func _build_sky_light_from_blocks(
	blocks: PackedByteArray,
	cache_width: int,
	world_height: int
) -> PackedByteArray:
	var sky_light := PackedByteArray()
	sky_light.resize(cache_width * cache_width * world_height)
	for cache_z in range(cache_width):
		for cache_x in range(cache_width):
			var light_level := MAX_SKY_LIGHT
			for y in range(world_height - 1, -1, -1):
				var index := _volume_index(cache_x, y, cache_z, cache_width, world_height)
				var block := int(blocks[index])
				if block == BLOCK_LEAVES:
					light_level = maxi(light_level - 1, 0)
				elif block != BLOCK_AIR:
					light_level = 0
				sky_light[index] = light_level
	return sky_light


static func _vertex_ao_level(
	cell: Vector3i,
	face_index: int,
	vertex: Vector3,
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray()
) -> int:
	var blocks := _build_block_cache(
		origin,
		heights,
		overrides,
		cache_width,
		cache_padding,
		world_height,
		sea_level,
		biomes
	)
	return _vertex_ao_level_cached(
		cell,
		face_index,
		vertex,
		origin,
		blocks,
		cache_width,
		cache_padding,
		world_height
	)


static func _vertex_ao_level_cached(
	cell: Vector3i,
	face_index: int,
	vertex: Vector3,
	origin: Vector3i,
	blocks: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int
) -> int:
	return _vertex_ao_level_cached_with_basis(
		cell,
		vertex,
		_face_direction(face_index),
		_face_tangent_axes(face_index),
		origin,
		blocks,
		cache_width,
		cache_padding,
		world_height
	)


static func _vertex_ao_level_cached_with_basis(
	cell: Vector3i,
	vertex: Vector3,
	normal: Vector3i,
	tangent_axes: Vector2i,
	origin: Vector3i,
	blocks: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int
) -> int:
	var side_a_direction := _axis_direction(tangent_axes.x, _axis_component(vertex, tangent_axes.x) > 0.5)
	var side_b_direction := _axis_direction(tangent_axes.y, _axis_component(vertex, tangent_axes.y) > 0.5)
	var sample_origin := cell + normal
	var side_a := _occludes_ambient(_cached_block(
		sample_origin + side_a_direction,
		origin,
		blocks,
		cache_width,
		cache_padding,
		world_height
	))
	var side_b := _occludes_ambient(_cached_block(
		sample_origin + side_b_direction,
		origin,
		blocks,
		cache_width,
		cache_padding,
		world_height
	))
	var corner := _occludes_ambient(_cached_block(
		sample_origin + side_a_direction + side_b_direction,
		origin,
		blocks,
		cache_width,
		cache_padding,
		world_height
	))
	if side_a and side_b:
		return 0
	return 3 - int(side_a) - int(side_b) - int(corner)


static func _vertex_sky_factor(
	cell: Vector3i,
	face_index: int,
	vertex: Vector3,
	origin: Vector3i,
	sky_light: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int
) -> float:
	return _vertex_sky_factor_with_basis(
		cell,
		vertex,
		_face_direction(face_index),
		_face_tangent_axes(face_index),
		origin,
		sky_light,
		cache_width,
		cache_padding,
		world_height
	)


static func _vertex_sky_factor_with_basis(
	cell: Vector3i,
	vertex: Vector3,
	normal: Vector3i,
	tangent_axes: Vector2i,
	origin: Vector3i,
	sky_light: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int
) -> float:
	var side_a_direction := _axis_direction(tangent_axes.x, _axis_component(vertex, tangent_axes.x) > 0.5)
	var side_b_direction := _axis_direction(tangent_axes.y, _axis_component(vertex, tangent_axes.y) > 0.5)
	var sample_origin := cell + normal
	var total_light := 0
	total_light += _sky_light_at(sample_origin, origin, sky_light, cache_width, cache_padding, world_height)
	total_light += _sky_light_at(sample_origin + side_a_direction, origin, sky_light, cache_width, cache_padding, world_height)
	total_light += _sky_light_at(sample_origin + side_b_direction, origin, sky_light, cache_width, cache_padding, world_height)
	total_light += _sky_light_at(
		sample_origin + side_a_direction + side_b_direction,
		origin,
		sky_light,
		cache_width,
		cache_padding,
		world_height
	)
	var normalized_light := float(total_light) / float(MAX_SKY_LIGHT * 4)
	return lerpf(MIN_SKY_BRIGHTNESS, 1.0, normalized_light)


static func _sky_light_at(
	cell: Vector3i,
	origin: Vector3i,
	sky_light: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int
) -> int:
	if cell.y >= world_height:
		return MAX_SKY_LIGHT
	if cell.y < 0:
		return 0
	var cache_x := cell.x - origin.x + cache_padding
	var cache_z := cell.z - origin.z + cache_padding
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return MAX_SKY_LIGHT
	return int(sky_light[_volume_index(cache_x, cell.y, cache_z, cache_width, world_height)])


static func _volume_index(x: int, y: int, z: int, width: int, world_height: int) -> int:
	return (z * width + x) * world_height + y


static func _sky_index(x: int, y: int, z: int, width: int, world_height: int) -> int:
	return _volume_index(x, y, z, width, world_height)


static func _occludes_ambient(block: int) -> bool:
	return block != BLOCK_AIR


static func _axis_component(vertex: Vector3, axis: int) -> float:
	match axis:
		0:
			return vertex.x
		1:
			return vertex.y
		_:
			return vertex.z


static func _axis_direction(axis: int, positive: bool) -> Vector3i:
	var amount := 1 if positive else -1
	match axis:
		0:
			return Vector3i(amount, 0, 0)
		1:
			return Vector3i(0, amount, 0)
		_:
			return Vector3i(0, 0, amount)


static func _append_face_indices(
	indices: PackedInt32Array,
	base_index: int,
	ao_0: int,
	ao_1: int,
	ao_2: int,
	ao_3: int
) -> void:
	if _should_flip_ao_diagonal_values(ao_0, ao_1, ao_2, ao_3):
		indices.append(base_index)
		indices.append(base_index + 3)
		indices.append(base_index + 1)
		indices.append(base_index + 1)
		indices.append(base_index + 3)
		indices.append(base_index + 2)
		return
	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


static func _should_flip_ao_diagonal(ao_levels: Array[int]) -> bool:
	return ao_levels[0] + ao_levels[2] > ao_levels[1] + ao_levels[3]


static func _should_flip_ao_diagonal_values(ao_0: int, ao_1: int, ao_2: int, ao_3: int) -> bool:
	return ao_0 + ao_2 > ao_1 + ao_3


static func _block_color(block: int, cell: Vector3i, face_index: int, light_factor: float) -> Color:
	var base_color: Color
	match block:
		BLOCK_GRASS:
			base_color = Color(0.34, 0.68, 0.25) if face_index == 0 else Color(0.38, 0.48, 0.23)
		BLOCK_DIRT:
			base_color = Color(0.50, 0.34, 0.20)
		BLOCK_STONE:
			base_color = Color(0.56, 0.58, 0.60)
		BLOCK_SAND:
			base_color = Color(0.82, 0.75, 0.54)
		BLOCK_LOG:
			base_color = Color(0.48, 0.30, 0.14)
		BLOCK_LEAVES:
			base_color = Color(0.22, 0.52, 0.18)
		BLOCK_COAL_ORE:
			base_color = Color(0.30, 0.30, 0.32)
		BLOCK_IRON_ORE:
			base_color = Color(0.72, 0.58, 0.45)
		BLOCK_COPPER_ORE:
			base_color = Color(0.44, 0.72, 0.60)
		BLOCK_FURNACE:
			base_color = Color(0.38, 0.34, 0.31)
		BLOCK_IRON_INGOT:
			base_color = Color(0.78, 0.78, 0.80)
		BLOCK_COPPER_INGOT:
			base_color = Color(0.80, 0.48, 0.26)
		BLOCK_COAL:
			base_color = Color(0.12, 0.12, 0.13)
		BLOCK_GLASS:
			base_color = Color(0.78, 0.88, 0.92)
		BLOCK_CHARCOAL:
			base_color = Color(0.20, 0.19, 0.18)
		_:
			base_color = Color.WHITE
	var hash_value := absi((cell.x * 73856093) ^ (cell.y * 83492791) ^ (cell.z * 19349663))
	var variation := 0.97 + float(hash_value % 7) * 0.01
	var factor := light_factor * variation
	return Color(
		clampf(base_color.r * factor, 0.0, 1.0),
		clampf(base_color.g * factor, 0.0, 1.0),
		clampf(base_color.b * factor, 0.0, 1.0),
		1.0
	)


static func _face_shade(face_index: int) -> float:
	match face_index:
		0:
			return 1.0
		1:
			return 0.5
		2, 3:
			return 0.6
		_:
			return 0.8
