extends RefCounted

const STAGE5_CACHE := preload("res://scripts/world/playable_world_stage5_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_STRIDE := 6


static func _base_tree_candidate(
	x: int,
	z: int,
	surface: int,
	biome: int,
	sampler
) -> bool:
	if biome == sampler.BIOME_DESERT or biome == sampler.BIOME_ROCKY:
		return false
	if (
		surface <= sampler.SEA_LEVEL + 1
		or surface + sampler.TREE_TRUNK_HEIGHT + 1 >= sampler.OVERHAUL_WORLD_HEIGHT
	):
		return false
	var baseline_grid := (
		posmod(x, sampler.TREE_SPACING) == sampler.TREE_OFFSET
		and posmod(z, sampler.TREE_SPACING) == sampler.TREE_OFFSET
	)
	var forest_grid := (
		biome == sampler.BIOME_FOREST
		and posmod(x, sampler.FOREST_TREE_SPACING) == sampler.FOREST_TREE_OFFSET
		and posmod(z, sampler.FOREST_TREE_SPACING) == sampler.FOREST_TREE_OFFSET
	)
	if not baseline_grid and not forest_grid:
		return false
	var hash_value := absi((x * 73856093) ^ (z * 19349663) ^ sampler.WORLD_SEED)
	if forest_grid and not baseline_grid:
		return hash_value % 3 != 0
	return hash_value % 4 != 0


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Stage 5 remains the dense hot path. Stage 6 is intentionally sparse: first
	# build the accepted Stage 5 cache, then touch only columns inside accepted
	# lake/pond feature bounds. When a basin center is already in that cache, the
	# sampler reuses its fields/height instead of resampling the center.
	var result: Dictionary = STAGE5_CACHE.build(coord, sampler)
	var heights: PackedInt32Array = result.get("heights", PackedInt32Array())
	if heights.is_empty():
		return result
	var world_fields: PackedFloat32Array = result.get("world_fields", PackedFloat32Array())
	var biomes: PackedByteArray = result.get("biomes", PackedByteArray())
	var blocked_tree_columns := PackedInt32Array()

	var width := CHUNK_SIZE + PADDING * 2
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var min_x := origin_x - PADDING
	var min_z := origin_z - PADDING
	var max_x := origin_x + CHUNK_SIZE + PADDING - 1
	var max_z := origin_z + CHUNK_SIZE + PADDING - 1

	# Stage 5 water already exists in the base cache. Only evaluate river status
	# for columns that the mesher would otherwise consider tree origins; this is
	# sparse (grid/hash gated) and avoids a second dense river pass.
	for cache_z in range(width):
		var world_z := min_z + cache_z
		var row := cache_z * width
		for cache_x in range(width):
			var index := row + cache_x
			var surface := heights[index]
			var biome := int(biomes[index]) if index < biomes.size() else sampler.BIOME_PLAINS
			var world_x := min_x + cache_x
			if not _base_tree_candidate(world_x, world_z, surface, biome, sampler):
				continue
			var field_index := index * FIELD_STRIDE
			if field_index >= world_fields.size():
				continue
			var continentalness := float(world_fields[field_index])
			if continentalness <= sampler.STAGE4_OCEAN_WATER_START:
				blocked_tree_columns.append(index)
				continue
			var river_value := sampler.stage5_river_signal(world_x, world_z)
			var strengths := sampler.stage5_river_strengths_from_signal(
				continentalness,
				river_value
			)
			if strengths.x >= sampler.STAGE5_CHANNEL_WATER_CUTOFF:
				blocked_tree_columns.append(index)

	var features: Array[Dictionary] = sampler.stage6_collect_features_for_cached_bounds(
		min_x,
		min_z,
		max_x,
		max_z,
		width,
		world_fields,
		heights
	)
	if features.is_empty():
		result["blocked_tree_columns"] = blocked_tree_columns
		return result

	for feature: Dictionary in features:
		var center_x := int(feature["center_x"])
		var center_z := int(feature["center_z"])
		var radius_x := float(feature["radius_x"])
		var radius_z := float(feature["radius_z"])
		var reciprocal_radius_x := 1.0 / radius_x
		var reciprocal_radius_z := 1.0 / radius_z
		var water_radius := float(feature["water_radius"])
		var water_radius_squared := water_radius * water_radius
		var hard_rim_radius := float(feature["hard_rim_radius"])
		var hard_rim_squared := hard_rim_radius * hard_rim_radius
		var inverse_outer_rim_range := 1.0 / (1.0 - hard_rim_squared)
		var water_level := int(feature["water_level"])
		var water_level_plus_one := water_level + 1
		var depth := int(feature["depth"])
		var safe_top: int = sampler.STAGE2_SAFE_TERRAIN_TOP
		var feature_min_x := maxi(min_x, floori(float(center_x) - radius_x))
		var feature_max_x := mini(max_x, ceili(float(center_x) + radius_x))
		var feature_min_z := maxi(min_z, floori(float(center_z) - radius_z))
		var feature_max_z := mini(max_z, ceili(float(center_z) + radius_z))
		for world_z in range(feature_min_z, feature_max_z + 1):
			var normalized_z := float(world_z - center_z) * reciprocal_radius_z
			var normalized_z_squared := normalized_z * normalized_z
			var cache_z := world_z - min_z
			var row := cache_z * width
			for world_x in range(feature_min_x, feature_max_x + 1):
				var normalized_x := float(world_x - center_x) * reciprocal_radius_x
				var distance_squared := normalized_x * normalized_x + normalized_z_squared
				if distance_squared >= 1.0:
					continue
				var cache_x := world_x - min_x
				var index := row + cache_x
				var stage5_height := heights[index]
				if distance_squared <= water_radius_squared:
					var core_t := clampf(
						distance_squared / water_radius_squared,
						0.0,
						1.0
					)
					core_t = core_t * core_t * (3.0 - 2.0 * core_t)
					var floor_height := (
						water_level
						- 1
						- roundi(float(depth) * (1.0 - core_t))
					)
					heights[index] = clampi(
						mini(stage5_height, floor_height),
						3,
						safe_top
					)
					var biome := int(biomes[index]) if index < biomes.size() else sampler.BIOME_PLAINS
					if _base_tree_candidate(world_x, world_z, heights[index], biome, sampler):
						blocked_tree_columns.append(index)
					continue
				if distance_squared <= hard_rim_squared:
					heights[index] = clampi(
						maxi(stage5_height, water_level_plus_one),
						3,
						safe_top
					)
					continue
				if stage5_height >= water_level_plus_one:
					continue
				var rim_t := clampf(
					(distance_squared - hard_rim_squared) * inverse_outer_rim_range,
					0.0,
					1.0
				)
				rim_t = rim_t * rim_t * (3.0 - 2.0 * rim_t)
				var blended_rim := roundi(lerpf(
					float(water_level_plus_one),
					float(stage5_height),
					rim_t
				))
				heights[index] = clampi(
					maxi(stage5_height, blended_rim),
					3,
					safe_top
				)

	result["heights"] = heights
	result["blocked_tree_columns"] = blocked_tree_columns
	return result
