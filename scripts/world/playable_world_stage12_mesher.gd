extends RefCounted

const STAGE10_MESHER := preload("res://scripts/world/playable_world_stage10_mesher.gd")
const STAGE6_MESHER := preload("res://scripts/world/playable_world_stage6_mesher.gd")
const BASE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const BLOCK_AIR := 0
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6


static func _restore_terrain_under_suppression(
	mesher_overrides: Dictionary,
	user_overrides: Dictionary,
	heights: PackedInt32Array,
	origin: Vector3i,
	cache_width: int,
	cache_padding: int
) -> void:
	# Stage 6's historical tree-suppression helper clears the old trunk/canopy
	# volume with AIR overrides. On a higher neighboring terrain column, part of
	# that volume can be real ground rather than foliage. Stage 12 is the shipping
	# adapter, so protect cached terrain here without changing the frozen Stage 6
	# oracle or overriding real player edits.
	var erase_keys: Array[String] = []
	for key_value: Variant in mesher_overrides.keys():
		var key := String(key_value)
		if user_overrides.has(key_value) or user_overrides.has(key):
			continue
		if int(mesher_overrides.get(key_value, BLOCK_AIR)) != BLOCK_AIR:
			continue
		var parts := key.split(",")
		if parts.size() != 3:
			continue
		var cell := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var terrain_index: int = STAGE10_MESHER._cache_index_for_world(
			cell.x,
			cell.z,
			origin,
			cache_width,
			cache_padding
		)
		if terrain_index < 0 or terrain_index >= heights.size():
			continue
		if cell.y <= int(heights[terrain_index]):
			erase_keys.append(key)
	for key: String in erase_keys:
		mesher_overrides.erase(key)


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
	var height_count: int = heights.size()
	var cache_width: int = roundi(sqrt(float(height_count)))
	if cache_width * cache_width != height_count:
		cache_width = chunk_size + 2
	var cache_padding: int = maxi(floori(float(cache_width - chunk_size) * 0.5), 1)
	var origin := Vector3i(coord.x * chunk_size, 0, coord.y * chunk_size)
	var water_valid: bool = water_types.size() == height_count
	var modifiers_valid: bool = terrain_modifiers.size() == height_count
	var transitions_valid: bool = transition_codes.size() == height_count
	var hydrology_valid: bool = hydrology_codes.size() == height_count
	var water_none: int = sampler.WATER_NONE
	var terrain_none: int = sampler.TERRAIN_MODIFIER_NONE
	var hydro_none: int = sampler.HYDROLOGY_MODIFIER_NONE

	# Stage 11 used a Dictionary as a temporary set for every blocked cache column.
	# Stage 12 keeps the same membership semantics in a compact byte mask. Invalid
	# diagnostic indexes are preserved through a tiny fallback set, but the normal
	# shipping path never allocates hash entries for valid padded-cache columns.
	var blocked_mask := PackedByteArray()
	blocked_mask.resize(height_count)
	var blocked_count: int = 0
	var overflow_blocked: Dictionary = {}
	for value in blocked_tree_columns:
		var blocked_index: int = int(value)
		if blocked_index < 0 or blocked_index >= height_count:
			overflow_blocked[blocked_index] = true
		elif blocked_mask[blocked_index] == 0:
			blocked_mask[blocked_index] = 1
			blocked_count += 1

	# Suppress every legacy/generated origin first. The base mesher can sample a
	# tree origin from the outermost padded-cache ring when deciding whether an
	# interior boundary face is occluded, so the suppression set must cover that
	# same full padded domain. Previously this loop skipped ring 0/width-1, leaving
	# phantom legacy canopies that culled real chunk-edge terrain faces.
	for cache_z in range(cache_width):
		var row: int = cache_z * cache_width
		for cache_x in range(cache_width):
			var index: int = row + cache_x
			var biome: int = int(biomes[index])
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			if STAGE10_MESHER._legacy_tree_origin(
				world_x, world_z, surface, biome, world_height, sea_level, sampler
			):
				if blocked_mask[index] == 0:
					blocked_mask[index] = 1
					blocked_count += 1

	var combined_blocked := PackedInt32Array()
	combined_blocked.resize(blocked_count + overflow_blocked.size())
	var blocked_position: int = 0
	for index in range(height_count):
		if blocked_mask[index] == 0:
			continue
		combined_blocked[blocked_position] = index
		blocked_position += 1
	for index_key in overflow_blocked.keys():
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
	_restore_terrain_under_suppression(
		mesher_overrides,
		overrides,
		heights,
		origin,
		cache_width,
		cache_padding
	)

	var custom_origins: Array[Vector3i] = []
	var custom_biomes: Array[int] = []

	# Stage 11 made two full dry-column passes here: one for three-layer surface
	# expression and another for tree eligibility, recomputing coordinates, slope,
	# modifier and transition/hydrology lookups each time. Stage 12 performs both
	# operations in one pass and reuses the exact same values.
	for cache_z in range(1, cache_width - 1):
		var row: int = cache_z * cache_width
		for cache_x in range(1, cache_width - 1):
			var index: int = row + cache_x
			if water_valid and int(water_types[index]) != water_none:
				continue

			var biome: int = int(biomes[index])
			var world_x: int = origin.x + cache_x - cache_padding
			var world_z: int = origin.z + cache_z - cache_padding
			var surface: int = int(heights[index])
			var terrain_modifier: int = (
				int(terrain_modifiers[index]) if modifiers_valid else terrain_none
			)
			var transition_code: int = int(transition_codes[index]) if transitions_valid else 0
			var hydrology_code: int = (
				int(hydrology_codes[index]) if hydrology_valid else hydro_none
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

			if sampler.stage11_tree_candidate_for_biome(
				world_x,
				world_z,
				surface,
				biome,
				transition_code,
				terrain_modifier,
				slope,
				hydrology_code
			):
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
