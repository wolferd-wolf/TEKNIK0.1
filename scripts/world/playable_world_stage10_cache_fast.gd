extends RefCounted

const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
const FIELD_STRIDE := 6

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
const PLAINS_FOREST_TRANSITION_LOW := 0.13
const PLAINS_FOREST_TRANSITION_HIGH := 0.23

# Exact Stage 8 Voronoi envelope breakpoints. These are intersections of the
# accepted linear prototype scores; they do not change any climate target.
const DENSE_FOREST_ENVELOPE_START := 0.348326996197719
const FOREST_ENVELOPE_END := 0.671395348837208

# Accepted Stage 9 terrain-modifier constants.
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
	# Stage 7 already owns the fused terrain/hydrology/lake pass. Stage 10 replaces
	# only the obsolete Stage 7 four-biome result with the exact Stage 8 ecology
	# and Stage 9 modifier in one lightweight pass. The decision tree below is the
	# upper envelope of the same Stage 8 linear Voronoi scores, so it preserves the
	# accepted regions while avoiding four full score evaluations per land column.
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

	var field_index: int = 0
	for column in range(count):
		if int(water_types[column]) != water_none:
			biomes[column] = biome_plains
			modifiers[column] = MODIFIER_NONE
			field_index += FIELD_STRIDE
			continue

		var structure: float = fields[field_index + 1]
		var temperature: float = fields[field_index + 4]
		var moisture: float = fields[field_index + 5]
		var biome: int

		if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
			# Exact upper envelope: Cold -> Plains -> Dry Grassland -> Desert.
			if 1.04 * temperature < 0.72 * moisture - 0.3856:
				biome = biome_cold
			elif 0.80 * temperature <= 0.44 * moisture + 0.2172:
				biome = biome_plains
			elif 0.52 * temperature >= 0.72 * moisture + 0.578:
				biome = biome_desert
			else:
				biome = biome_dry
		elif moisture < DENSE_FOREST_ENVELOPE_START:
			# Dense Forest is below the Forest/Dry envelope in this moisture band.
			if 1.04 * temperature < -0.08 * moisture - 0.2416:
				biome = biome_cold
			elif 0.80 * temperature > 1.24 * moisture + 0.0732:
				biome = biome_dry
			else:
				biome = biome_forest
		elif moisture <= FOREST_ENVELOPE_END:
			# Exact upper envelope: Cold -> Forest -> Dense Forest -> Dry Grassland.
			if 1.04 * temperature < -0.08 * moisture - 0.2416:
				biome = biome_cold
			elif 0.24 * temperature <= 0.3884 - 0.68 * moisture:
				biome = biome_forest
			elif 0.56 * temperature > 1.92 * moisture - 0.3152:
				biome = biome_dry
			else:
				biome = biome_dense
		else:
			# Forest is below the Cold/Dense envelope at high moisture.
			if 1.28 * temperature + 0.76 * moisture - 0.1468 < 0.0:
				biome = biome_cold
			elif 0.56 * temperature > 1.92 * moisture - 0.3152:
				biome = biome_dry
			else:
				biome = biome_dense
		biomes[column] = biome

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
		field_index += FIELD_STRIDE

	cache["biomes"] = biomes
	cache["stage8_active_biome_count"] = sampler.STAGE8_ACTIVE_BIOME_COUNT
	cache["stage9_terrain_modifiers"] = modifiers
	cache["stage9_terrain_modifier_count"] = sampler.STAGE9_TERRAIN_MODIFIER_COUNT
	return cache


static func build_transition_codes(cache: Dictionary, sampler) -> PackedByteArray:
	var fields: PackedFloat32Array = cache.get("world_fields", PackedFloat32Array())
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	var count: int = biomes.size()
	var codes := PackedByteArray()
	codes.resize(count)
	if count == 0 or water_types.size() != count or fields.size() < count * FIELD_STRIDE:
		return codes

	var water_none: int = sampler.WATER_NONE
	var transition_width: float = sampler.STAGE10_TRANSITION_SCORE_WIDTH
	var transition_levels: int = sampler.STAGE10_TRANSITION_LEVELS
	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST

	var field_index: int = 0
	for column in range(count):
		if int(water_types[column]) != water_none:
			field_index += FIELD_STRIDE
			continue
		var temperature: float = fields[field_index + 4]
		var moisture: float = fields[field_index + 5]
		var biome: int = int(biomes[column])

		var best_score: float
		match biome:
			biome_plains:
				best_score = PLAINS_M * moisture + PLAINS_B
			biome_forest:
				best_score = FOREST_M * moisture + FOREST_B
			biome_dense:
				best_score = DENSE_T * temperature + DENSE_M * moisture + DENSE_B
			biome_desert:
				best_score = DESERT_T * temperature + DESERT_M * moisture + DESERT_B
			biome_dry:
				best_score = DRY_T * temperature + DRY_M * moisture + DRY_B
			biome_cold:
				best_score = COLD_T * temperature + COLD_M * moisture + COLD_B
			_:
				best_score = -1.0e20

		var second_score: float = -1.0e20
		var second_biome: int = -1
		var score: float
		if biome != biome_plains and moisture <= PLAINS_FOREST_TRANSITION_HIGH:
			score = PLAINS_M * moisture + PLAINS_B
			if score > second_score:
				second_score = score
				second_biome = biome_plains
		if biome != biome_forest and moisture >= PLAINS_FOREST_TRANSITION_LOW:
			score = FOREST_M * moisture + FOREST_B
			if score > second_score:
				second_score = score
				second_biome = biome_forest
		if biome != biome_dense and moisture > PLAINS_FOREST_MOISTURE_BOUNDARY:
			score = DENSE_T * temperature + DENSE_M * moisture + DENSE_B
			if score > second_score:
				second_score = score
				second_biome = biome_dense
		if biome != biome_desert and moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
			score = DESERT_T * temperature + DESERT_M * moisture + DESERT_B
			if score > second_score:
				second_score = score
				second_biome = biome_desert
		if biome != biome_dry:
			score = DRY_T * temperature + DRY_M * moisture + DRY_B
			if score > second_score:
				second_score = score
				second_biome = biome_dry
		if biome != biome_cold:
			score = COLD_T * temperature + COLD_M * moisture + COLD_B
			if score > second_score:
				second_score = score
				second_biome = biome_cold

		var margin: float = best_score - second_score
		if second_biome >= 0 and margin < transition_width:
			var level: int = roundi(
				(1.0 - maxf(margin, 0.0) / transition_width)
				* float(transition_levels)
			)
			if level > 0:
				codes[column] = ((second_biome + 1) << 5) | mini(level, transition_levels)
		field_index += FIELD_STRIDE
	return codes
