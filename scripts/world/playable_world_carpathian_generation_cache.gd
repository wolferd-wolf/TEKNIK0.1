extends RefCounted

const STAGE13_CACHE := preload("res://scripts/world/playable_world_stage13_generation_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_STRIDE := 6
const MODIFIER_NONE := 0


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Without the native extension this wrapper is byte-for-byte the accepted
	# Stage 13 path. That keeps all historical/headless gates meaningful.
	var cache: Dictionary = STAGE13_CACHE.build(coord, sampler)
	if not sampler.has_method("carpathian_enabled") or not sampler.carpathian_enabled():
		return cache

	var width: int = CHUNK_SIZE + PADDING * 2
	var count: int = width * width
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	var max_x: int = min_x + width - 1
	var max_z: int = min_z + width - 1
	var fields: PackedFloat32Array = cache.get("world_fields", PackedFloat32Array())
	if fields.size() != count * FIELD_STRIDE:
		push_error("Carpathian cache adapter received invalid Stage 13 field cache")
		return {}

	var heights: PackedInt32Array = sampler.carpathian_generate_grid(
		min_x, min_z, width, width, 1
	)
	if heights.size() != count:
		push_error("Native Carpathian grid size mismatch")
		return {}

	var biomes := PackedByteArray()
	var water_types := PackedByteArray()
	var modifiers := PackedByteArray()
	biomes.resize(count)
	water_types.resize(count)
	modifiers.resize(count)

	# Apply the already-accepted Stage 4 ocean/coast and Stage 5 river topology
	# to the new Carpathian base height. Ecology and terrain-modifier rules remain
	# unchanged in this test integration.
	for cz in range(width):
		var world_z: int = min_z + cz
		var row: int = cz * width
		for cx in range(width):
			var world_x: int = min_x + cx
			var column: int = row + cx
			var field: int = column * FIELD_STRIDE
			var column_fields := Vector4(
				fields[field],
				fields[field + 1],
				fields[field + 2],
				fields[field + 3]
			)
			var stage4_height: int = sampler._carpathian_stage4_height(
				column_fields, heights[column]
			)
			var water_type: int = sampler.WATER_NONE
			var stage5_height: int = stage4_height
			if column_fields.x <= sampler.STAGE4_OCEAN_WATER_START:
				stage5_height = sampler.finalize_height(stage4_height)
				water_type = sampler.water_type_from_fields(column_fields, stage5_height)
			else:
				var river_value: float = sampler.stage5_river_signal(world_x, world_z)
				var strengths: Vector2 = sampler.stage5_river_strengths_from_signal(
					column_fields.x, river_value
				)
				stage5_height = sampler.finalize_height(
					sampler.stage5_shape_height_from_signal(
						column_fields.x, stage4_height, river_value
					)
				)
				if strengths.x >= sampler.STAGE5_CHANNEL_WATER_CUTOFF:
					water_type = sampler.WATER_RIVER
			heights[column] = stage5_height
			water_types[column] = water_type
			var climate := Vector2(fields[field + 2], fields[field + 3])
			biomes[column] = sampler.stage8_classify_climate(climate, water_type)
			modifiers[column] = sampler.stage9_terrain_modifier_from_fields(
				column_fields.x, column_fields.y, water_type
			)

	# Re-evaluate sparse Stage 6 features against Carpathian terrain, then apply
	# them to the cache once. This prevents lake/pond water levels from being
	# inherited from the old Stage 13 terrain underneath the new mesh.
	var features: Array[Dictionary] = sampler.stage6_collect_features_for_bounds(
		min_x, min_z, max_x, max_z
	)
	for feature: Dictionary in features:
		var center_x: int = int(feature["center_x"])
		var center_z: int = int(feature["center_z"])
		var radius_x: float = float(feature["radius_x"])
		var radius_z: float = float(feature["radius_z"])
		var feature_min_x: int = maxi(min_x, floori(float(center_x) - radius_x))
		var feature_max_x: int = mini(max_x, ceili(float(center_x) + radius_x))
		var feature_min_z: int = maxi(min_z, floori(float(center_z) - radius_z))
		var feature_max_z: int = mini(max_z, ceili(float(center_z) + radius_z))
		var water_radius: float = float(feature["water_radius"])
		var water_radius_squared: float = water_radius * water_radius
		for world_z in range(feature_min_z, feature_max_z + 1):
			var row: int = (world_z - min_z) * width
			for world_x in range(feature_min_x, feature_max_x + 1):
				var distance_squared: float = sampler.stage6_feature_distance_squared(
					world_x, world_z, feature
				)
				if distance_squared >= 1.0:
					continue
				var index: int = row + world_x - min_x
				heights[index] = sampler.stage6_shape_height_for_feature(
					heights[index], world_x, world_z, feature
				)
				if distance_squared <= water_radius_squared:
					water_types[index] = int(feature["type"])
					biomes[index] = sampler.BIOME_PLAINS
					modifiers[index] = MODIFIER_NONE

	return {
		"world_fields": fields,
		"heights": heights,
		"biomes": biomes,
		"stage7_water_types": water_types,
		"stage6_features": features,
		"stage8_active_biome_count": sampler.STAGE8_ACTIVE_BIOME_COUNT,
		"stage9_terrain_modifiers": modifiers,
		"stage9_terrain_modifier_count": sampler.STAGE9_TERRAIN_MODIFIER_COUNT,
	}
