extends RefCounted

const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
const FIELD_STRIDE := 6

# For Euclidean nearest-prototype selection, the shared climate length term can
# be removed from every squared distance. Maximizing
#   2 * climate.dot(target) - target.length_squared()
# gives exactly the same Voronoi regions as minimizing squared distance.
const PLAINS_M := -0.04
const PLAINS_B := -0.0004
const FOREST_M := 0.76
const FOREST_B := -0.1444
const DENSE_T := 0.24
const DENSE_M := 1.44
const DENSE_B := -0.5328
const DESERT_T := 1.32
const DESERT_M := -1.20
const DESERT_B := -0.7956
const DRY_T := 0.80
const DRY_M := -0.48
const DRY_B := -0.2176
const COLD_T := -1.04
const COLD_M := 0.68
const COLD_B := -0.386

# At moisture <= 0.18, Plains always beats Forest and Forest always beats Dense
# Forest throughout FastNoiseLite's [-1, 1] temperature range, so Forest and
# Dense Forest cannot be nearest. Above 0.18, Forest always beats Plains and
# Dry Grassland always beats Desert, so Plains and Desert cannot be nearest.
# Pruning those impossible candidates preserves the exact nearest-prototype
# Voronoi result while reducing the hot pass from six candidates to four.
const PLAINS_FOREST_MOISTURE_BOUNDARY := 0.18


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Reuse the accepted fused Stage 7 terrain/hydrology cache. Stage 8 performs
	# no new noise sampling: it replaces only the ecology byte using climate
	# values and water ownership already present in the padded cache.
	var cache: Dictionary = STAGE7_CACHE.build(coord, sampler)
	var fields: PackedFloat32Array = cache.get("world_fields", PackedFloat32Array())
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	var count: int = biomes.size()
	if count == 0 or water_types.size() != count:
		return cache

	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST
	var water_none: int = sampler.WATER_NONE

	var column: int = 0
	var climate_field: int = 4
	while column < count:
		if int(water_types[column]) != water_none:
			biomes[column] = biome_plains
			column += 1
			climate_field += FIELD_STRIDE
			continue

		var temperature: float = fields[climate_field]
		var moisture: float = fields[climate_field + 1]
		var biome: int
		var best_score: float
		var score: float

		if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
			# Exact candidate set: Plains, Desert, Dry Grassland, Cold Forest.
			biome = biome_plains
			best_score = PLAINS_M * moisture + PLAINS_B

			score = DESERT_T * temperature + DESERT_M * moisture + DESERT_B
			if score > best_score:
				best_score = score
				biome = biome_desert

			score = DRY_T * temperature + DRY_M * moisture + DRY_B
			if score > best_score:
				best_score = score
				biome = biome_dry

			score = COLD_T * temperature + COLD_M * moisture + COLD_B
			if score > best_score:
				biome = biome_cold
		else:
			# Exact candidate set: Forest, Dense Forest, Dry Grassland, Cold Forest.
			biome = biome_forest
			best_score = FOREST_M * moisture + FOREST_B

			score = DENSE_T * temperature + DENSE_M * moisture + DENSE_B
			if score > best_score:
				best_score = score
				biome = biome_dense

			score = DRY_T * temperature + DRY_M * moisture + DRY_B
			if score > best_score:
				best_score = score
				biome = biome_dry

			score = COLD_T * temperature + COLD_M * moisture + COLD_B
			if score > best_score:
				biome = biome_cold

		biomes[column] = biome
		column += 1
		climate_field += FIELD_STRIDE

	cache["biomes"] = biomes
	cache["stage8_active_biome_count"] = sampler.STAGE8_ACTIVE_BIOME_COUNT
	return cache
