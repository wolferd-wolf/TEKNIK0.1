extends RefCounted

const STAGE6_MESHER := preload("res://scripts/world/playable_world_stage6_mesher.gd")
const BASE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6


static func _legacy_tree_origin(
	x: int,
	z: int,
	surface: int,
	biome: int,
	world_height: int,
	sea_level: int,
	sampler
) -> bool:
	if biome == sampler.BIOME_DESERT or biome == sampler.BIOME_ROCKY:
		return false
	if surface <= sea_level + 1 or surface + sampler.TREE_TRUNK_HEIGHT + 1 >= world_height:
		return false
	var baseline_grid: bool = (
		posmod(x, sampler.TREE_SPACING) == sampler.TREE_OFFSET
		and posmod(z, sampler.TREE_SPACING) == sampler.TREE_OFFSET
	)
	var forest_grid: bool = (
		biome == sampler.BIOME_FOREST
		and posmod(x, sampler.FOREST_TREE_SPACING) == sampler.FOREST_TREE_OFFSET
		and posmod(z, sampler.FOREST_TREE_SPACING) == sampler.FOREST_TREE_OFFSET
	)
	if not baseline_grid and not forest_grid:
		return false
	var hash_value: int = absi((x * 73856093) ^ (z * 19349663) ^ sampler.WORLD_SEED)
	if forest_grid and not baseline_grid:
		return hash_value % 3 != 0
	return hash_value % 4 != 0


static func _cache_index_for_world(
	x: int,
	z: int,
	origin: Vector3i,
	cache_width: int,
	cache_padding: int
) -> int:
	var cache_x: int = x - origin.x + cache_padding
	var cache_z: int = z - origin.z + cache_padding
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return -1
	return cache_z * cache_width + cache_x


static func _plain_or_forest_trunk_at(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	biomes: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	sampler
) -> bool:
	var index: int = _cache_index_for_world(
		cell.x, cell.z, origin, cache_width, cache_padding
	)
	if index < 0:
		return false
	var biome: int = int(biomes[index])
	if biome != sampler.BIOME_PLAINS and biome != sampler.BIOME_FOREST:
		return false
	var surface: int = int(heights[index])
	if not _legacy_tree_origin(
		cell.x, cell.z, surface, biome, world_height, sea_level, sampler
	):
		return false
	return cell.y > surface and cell.y <= surface + sampler.TREE_TRUNK_HEIGHT


static func build(
	coord: Vector2i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	chunk_size: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray,
	water_types: PackedByteArray,
	sampler,
	blocked_tree_columns: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var cache_width: int = roundi(sqrt(float(heights.size())))
	if cache_width * cache_width != heights.size():
		cache_width = chunk_size + 2
	var cache_padding: int = maxi(floori(float(cache_width - chunk_size) * 0.5), 1)
	var origin := Vector3i(coord.x * chunk_size, 0, coord.y * chunk_size)

	# Stage 6's base mesher would treat unknown ecology IDs as Plains and generate
	# its baseline trees. Suppress those generated baseline trees only in the three
	# new Stage 8 ecologies; Stage 8 then injects the intended silhouettes below.
	var blocked_lookup: Dictionary = {}
	for value in blocked_tree_columns:
		blocked_lookup[int(value)] = true
	for cache_z in range(cache_width):
		for cache_x in range(cache_width):
			var index: int = cache_z * cache_width + cache_x
			var biome: int = int(biomes[index])
			if (
				biome != sampler.BIOME_DENSE_FOREST
				and biome != sampler.BIOME_DRY_GRASSLAND
				and biome != sampler.BIOME_COLD_FOREST
			):
				continue
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			if _legacy_tree_origin(
				world_x, world_z, surface, biome, world_height, sea_level, sampler
			):
				blocked_lookup[index] = true

	var combined_blocked := PackedInt32Array()
	combined_blocked.resize(blocked_lookup.size())
	var blocked_position := 0
	for index in blocked_lookup.keys():
		combined_blocked[blocked_position] = int(index)
		blocked_position += 1

	var mesher_overrides: Dictionary = STAGE6_MESHER._suppression_overrides(
		coord,
		heights,
		biomes,
		overrides,
		chunk_size,
		world_height,
		sea_level,
		combined_blocked
	)

	# Ground cues use only existing TEKNIK blocks. User edits always win.
	for cache_z in range(cache_width):
		for cache_x in range(cache_width):
			var index: int = cache_z * cache_width + cache_x
			var biome: int = int(biomes[index])
			if biome != sampler.BIOME_DRY_GRASSLAND and biome != sampler.BIOME_COLD_FOREST:
				continue
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			var cell := Vector3i(world_x, surface, world_z)
			var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
			if overrides.has(key):
				continue
			if biome == sampler.BIOME_DRY_GRASSLAND and sampler.stage8_dry_surface_is_sand(world_x, world_z):
				mesher_overrides[key] = BLOCK_SAND
			elif biome == sampler.BIOME_COLD_FOREST and sampler.stage8_cold_surface_is_stone(world_x, world_z):
				mesher_overrides[key] = BLOCK_STONE

	# Collect the exact custom origins once. Water ownership comes directly from
	# the Stage 8/Stage 7 padded cache, so no extra hydrology lookup is needed.
	var custom_origins: Array[Vector3i] = []
	var custom_biomes: Array[int] = []
	for cache_z in range(cache_width):
		for cache_x in range(cache_width):
			var index: int = cache_z * cache_width + cache_x
			var biome: int = int(biomes[index])
			if (
				biome != sampler.BIOME_DENSE_FOREST
				and biome != sampler.BIOME_DRY_GRASSLAND
				and biome != sampler.BIOME_COLD_FOREST
			):
				continue
			if water_types.size() == heights.size() and int(water_types[index]) != sampler.WATER_NONE:
				continue
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			if not sampler.stage8_tree_candidate_for_biome(world_x, world_z, surface, biome):
				continue
			custom_origins.append(Vector3i(world_x, surface, world_z))
			custom_biomes.append(biome)

	# Trunks first so an overlapping canopy can never hide a mineable log.
	for tree_index in range(custom_origins.size()):
		var tree: Vector3i = custom_origins[tree_index]
		var biome: int = custom_biomes[tree_index]
		var trunk_top: int = tree.y + sampler.stage8_tree_trunk_height(biome)
		for y in range(tree.y + 1, trunk_top + 1):
			var cell := Vector3i(tree.x, y, tree.z)
			var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
			if not overrides.has(key):
				mesher_overrides[key] = BLOCK_LOG

	# Then apply the biome-specific canopy silhouette. Unlike an arbitrary block
	# override, generated foliage must never replace terrain on a neighboring
	# slope. Clip every leaf against that column's cached surface first.
	for tree_index in range(custom_origins.size()):
		var tree: Vector3i = custom_origins[tree_index]
		var biome: int = custom_biomes[tree_index]
		var trunk_top: int = tree.y + sampler.stage8_tree_trunk_height(biome)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for dy in range(-2, 3):
					if not sampler.stage8_tree_canopy_contains(dx, dz, dy, biome):
						continue
					var cell := Vector3i(tree.x + dx, trunk_top + dy, tree.z + dz)
					if cell.y < 0 or cell.y >= world_height:
						continue
					var terrain_index: int = _cache_index_for_world(
						cell.x, cell.z, origin, cache_width, cache_padding
					)
					if terrain_index < 0 or cell.y <= int(heights[terrain_index]):
						continue
					var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
					if overrides.has(key):
						continue
					if int(mesher_overrides.get(key, BLOCK_AIR)) == BLOCK_LOG:
						continue
					if _plain_or_forest_trunk_at(
						cell,
						origin,
						heights,
						biomes,
						cache_width,
						cache_padding,
						world_height,
						sea_level,
						sampler
					):
						continue
					mesher_overrides[key] = BLOCK_LEAVES

	return BASE_MESHER.build(
		coord,
		heights,
		mesher_overrides,
		chunk_size,
		world_height,
		sea_level,
		biomes
	)
