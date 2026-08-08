extends RefCounted

const STAGE10_MESHER := preload("res://scripts/world/playable_world_stage10_mesher.gd")
const STAGE6_MESHER := preload("res://scripts/world/playable_world_stage6_mesher.gd")
const BASE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const BLOCK_AIR := 0
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6


static func build(
	coord: Vector2i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	chunk_size: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray,
	water_types: PackedByteArray,
	terrain_modifiers: PackedByteArray,
	transition_codes: PackedByteArray,
	hydrology_codes: PackedByteArray,
	sampler,
	blocked_tree_columns: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var cache_width: int = roundi(sqrt(float(heights.size())))
	if cache_width * cache_width != heights.size():
		cache_width = chunk_size + 2
	var cache_padding: int = maxi(floori(float(cache_width - chunk_size) * 0.5), 1)
	var origin := Vector3i(coord.x * chunk_size, 0, coord.y * chunk_size)
	var modifiers_valid: bool = terrain_modifiers.size() == heights.size()
	var transitions_valid: bool = transition_codes.size() == heights.size()
	var hydrology_valid: bool = hydrology_codes.size() == heights.size()

	# Suppress every legacy/generated origin first. Stage 11 then re-injects the
	# accepted Stage 8 silhouettes using Stage 10 climate/terrain eligibility plus
	# the new water-margin rules.
	var blocked_lookup: Dictionary = {}
	for value in blocked_tree_columns:
		blocked_lookup[int(value)] = true
	for cache_z in range(1, cache_width - 1):
		for cache_x in range(1, cache_width - 1):
			var index: int = cache_z * cache_width + cache_x
			var biome: int = int(biomes[index])
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			if STAGE10_MESHER._legacy_tree_origin(
				world_x, world_z, surface, biome, world_height, sea_level, sampler
			):
				blocked_lookup[index] = true

	var combined_blocked := PackedInt32Array()
	combined_blocked.resize(blocked_lookup.size())
	var blocked_position: int = 0
	for index_key in blocked_lookup.keys():
		combined_blocked[blocked_position] = int(index_key)
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

	# Surface expression is applied only to dry land. Three top layers are visited
	# so coast sand and hydrated desert soil exactly match direct get_block().
	for cache_z in range(1, cache_width - 1):
		for cache_x in range(1, cache_width - 1):
			var index: int = cache_z * cache_width + cache_x
			var water_type: int = (
				int(water_types[index]) if water_types.size() == heights.size() else sampler.WATER_NONE
			)
			if water_type != sampler.WATER_NONE:
				continue
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			var biome: int = int(biomes[index])
			var terrain_modifier: int = (
				int(terrain_modifiers[index]) if modifiers_valid else sampler.TERRAIN_MODIFIER_NONE
			)
			var transition_code: int = int(transition_codes[index]) if transitions_valid else 0
			var hydrology_code: int = (
				int(hydrology_codes[index]) if hydrology_valid else sampler.HYDROLOGY_MODIFIER_NONE
			)
			var slope: float = STAGE10_MESHER._cached_slope(
				cache_x, cache_z, heights, cache_width
			)
			for y in range(maxi(0, surface - 2), surface + 1):
				var cell := Vector3i(world_x, y, world_z)
				var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
				if overrides.has(key):
					continue
				var desired: int = sampler.stage11_surface_block(
					cell,
					surface,
					biome,
					transition_code,
					terrain_modifier,
					slope,
					hydrology_code
				)
				var baseline: int = BASE_MESHER._terrain_block(y, surface, sea_level, biome)
				if desired != baseline:
					mesher_overrides[key] = desired

	var custom_origins: Array[Vector3i] = []
	var custom_biomes: Array[int] = []
	for cache_z in range(1, cache_width - 1):
		for cache_x in range(1, cache_width - 1):
			var index: int = cache_z * cache_width + cache_x
			if water_types.size() == heights.size() and int(water_types[index]) != sampler.WATER_NONE:
				continue
			var biome: int = int(biomes[index])
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			var terrain_modifier: int = (
				int(terrain_modifiers[index]) if modifiers_valid else sampler.TERRAIN_MODIFIER_NONE
			)
			var transition_code: int = int(transition_codes[index]) if transitions_valid else 0
			var hydrology_code: int = (
				int(hydrology_codes[index]) if hydrology_valid else sampler.HYDROLOGY_MODIFIER_NONE
			)
			var slope: float = STAGE10_MESHER._cached_slope(
				cache_x, cache_z, heights, cache_width
			)
			if not sampler.stage11_tree_candidate_for_biome(
				world_x,
				world_z,
				surface,
				biome,
				transition_code,
				terrain_modifier,
				slope,
				hydrology_code
			):
				continue
			custom_origins.append(Vector3i(world_x, surface, world_z))
			custom_biomes.append(biome)

	for tree_index in range(custom_origins.size()):
		var tree: Vector3i = custom_origins[tree_index]
		var biome: int = custom_biomes[tree_index]
		var trunk_top: int = tree.y + sampler.stage8_tree_trunk_height(biome)
		for y in range(tree.y + 1, trunk_top + 1):
			var cell := Vector3i(tree.x, y, tree.z)
			var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
			if not overrides.has(key):
				mesher_overrides[key] = BLOCK_LOG

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
					var terrain_index: int = STAGE10_MESHER._cache_index_for_world(
						cell.x, cell.z, origin, cache_width, cache_padding
					)
					if terrain_index < 0 or cell.y <= int(heights[terrain_index]):
						continue
					var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
					if overrides.has(key):
						continue
					if int(mesher_overrides.get(key, BLOCK_AIR)) == BLOCK_LOG:
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
