extends RefCounted

const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
const FIELD_STRIDE := 6

# Stage 8's exact nearest-prototype linear scores. Stage 9 calls Stage 7 once and
# performs Stage 8 ecology + Stage 9 terrain modifier classification together in
# one hot pass so the modifier layer does not add another 256-column traversal.
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
const PLAINS_FOREST_MOISTURE_BOUNDARY := 0.18

# Accepted Stage 2/9 regime constants are fixed literals in this stage-specific
# cache. Keeping them local avoids dynamic sampler property reads in every build.
const HILL_START := -0.28
const PLATEAU_START := 0.22
const MOUNTAIN_START := 0.34
const MOUNTAIN_FULL := 0.68
const MOUNTAIN_RANGE_RECIPROCAL := 2.9411764705882353
const VALLEY_MIN := 0.22

const MODIFIER_NONE := 0
const MODIFIER_HILL := 1
const MODIFIER_PLATEAU := 2
const MODIFIER_MOUNTAIN := 3
const MODIFIER_VALLEY := 4


static func build(coord: Vector2i, sampler) -> Dictionary:
	var cache: Dictionary = STAGE7_CACHE.build(coord, sampler)
	var fields: PackedFloat32Array = cache.get("world_fields", PackedFloat32Array())
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	var count: int = biomes.size()
	if count == 0 or water_types.size() != count:
		return cache

	var modifiers := PackedByteArray()
	modifiers.resize(count)

	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST
	var water_none: int = sampler.WATER_NONE

	var column: int = 0
	var field_index: int = 0
	while column < count:
		var water_type: int = int(water_types[column])
		if water_type != water_none:
			biomes[column] = biome_plains
			modifiers[column] = MODIFIER_NONE
			column += 1
			field_index += FIELD_STRIDE
			continue

		# Structure, temperature and moisture are needed for every land column.
		# Continentalness is read only for mountain-regime columns, where the
		# accepted Stage 2 ridge-versus-valley term actually needs it.
		var structure: float = fields[field_index + 1]
		var temperature: float = fields[field_index + 4]
		var moisture: float = fields[field_index + 5]

		# Exact Stage 8 base ecology decision.
		var biome: int
		var best_score: float
		var score: float
		if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
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

		# Orthogonal Stage 9 terrain regime. FastNoiseLite's accepted field range is
		# already [-1,1], so no clamp is required for continentalness. Mountain
		# strength is saturated by the branch rather than a general clampf call.
		var modifier: int = MODIFIER_NONE
		if structure >= MOUNTAIN_START:
			var mountain_strength: float = 1.0
			if structure < MOUNTAIN_FULL:
				var mountain_t: float = (structure - MOUNTAIN_START) * MOUNTAIN_RANGE_RECIPROCAL
				mountain_strength = mountain_t * mountain_t * (3.0 - 2.0 * mountain_t)
			var continentalness: float = fields[field_index]
			var ridge_base: float = 1.0 - absf(continentalness)
			var ridge: float = ridge_base * ridge_base
			var valley_strength: float = mountain_strength * (1.0 - ridge)
			modifier = MODIFIER_VALLEY if valley_strength >= VALLEY_MIN else MODIFIER_MOUNTAIN
		elif structure >= PLATEAU_START:
			modifier = MODIFIER_PLATEAU
		elif structure >= HILL_START:
			modifier = MODIFIER_HILL
		modifiers[column] = modifier

		column += 1
		field_index += FIELD_STRIDE

	cache["biomes"] = biomes
	cache["stage8_active_biome_count"] = sampler.STAGE8_ACTIVE_BIOME_COUNT
	cache["stage9_terrain_modifiers"] = modifiers
	cache["stage9_terrain_modifier_count"] = sampler.STAGE9_TERRAIN_MODIFIER_COUNT
	return cache
