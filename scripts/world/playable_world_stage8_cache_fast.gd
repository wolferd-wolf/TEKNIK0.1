extends RefCounted

const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
const FIELD_STRIDE := 6


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Reuse the accepted fused Stage 7 terrain/hydrology cache. Stage 8 performs
	# no new noise sampling: it replaces only the ecology byte using climate
	# values and water ownership already present in the padded cache.
	var cache: Dictionary = STAGE7_CACHE.build(coord, sampler)
	var fields: PackedFloat32Array = cache.get("world_fields", PackedFloat32Array())
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	if biomes.is_empty() or water_types.size() != biomes.size():
		return cache

	var plains_t: float = sampler.STAGE8_PLAINS_TARGET.x
	var plains_m: float = sampler.STAGE8_PLAINS_TARGET.y
	var forest_t: float = sampler.STAGE8_FOREST_TARGET.x
	var forest_m: float = sampler.STAGE8_FOREST_TARGET.y
	var dense_t: float = sampler.STAGE8_DENSE_FOREST_TARGET.x
	var dense_m: float = sampler.STAGE8_DENSE_FOREST_TARGET.y
	var desert_t: float = sampler.STAGE8_DESERT_TARGET.x
	var desert_m: float = sampler.STAGE8_DESERT_TARGET.y
	var dry_t: float = sampler.STAGE8_DRY_GRASSLAND_TARGET.x
	var dry_m: float = sampler.STAGE8_DRY_GRASSLAND_TARGET.y
	var cold_t: float = sampler.STAGE8_COLD_FOREST_TARGET.x
	var cold_m: float = sampler.STAGE8_COLD_FOREST_TARGET.y

	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST
	var water_none: int = sampler.WATER_NONE

	for column in range(biomes.size()):
		if int(water_types[column]) != water_none:
			biomes[column] = biome_plains
			continue
		var field: int = column * FIELD_STRIDE
		var temperature: float = fields[field + 4]
		var moisture: float = fields[field + 5]

		var dt: float = temperature - plains_t
		var dm: float = moisture - plains_m
		var best_distance: float = dt * dt + dm * dm
		var biome: int = biome_plains

		dt = temperature - forest_t
		dm = moisture - forest_m
		var distance: float = dt * dt + dm * dm
		if distance < best_distance:
			best_distance = distance
			biome = biome_forest

		dt = temperature - dense_t
		dm = moisture - dense_m
		distance = dt * dt + dm * dm
		if distance < best_distance:
			best_distance = distance
			biome = biome_dense

		dt = temperature - desert_t
		dm = moisture - desert_m
		distance = dt * dt + dm * dm
		if distance < best_distance:
			best_distance = distance
			biome = biome_desert

		dt = temperature - dry_t
		dm = moisture - dry_m
		distance = dt * dt + dm * dm
		if distance < best_distance:
			best_distance = distance
			biome = biome_dry

		dt = temperature - cold_t
		dm = moisture - cold_m
		distance = dt * dt + dm * dm
		if distance < best_distance:
			biome = biome_cold

		biomes[column] = biome

	cache["biomes"] = biomes
	cache["stage8_active_biome_count"] = sampler.STAGE8_ACTIVE_BIOME_COUNT
	return cache
