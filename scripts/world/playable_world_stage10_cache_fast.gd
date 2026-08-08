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
# Plains/Forest score difference is 0.8 * abs(moisture - 0.18). With the
# Stage 10 score-width of 0.04, the losing prototype can only influence the
# transition metadata within +/-0.05 moisture of the exact boundary.
const PLAINS_FOREST_TRANSITION_LOW := 0.13
const PLAINS_FOREST_TRANSITION_HIGH := 0.23

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


static func _consider_score(
	score: float,
	biome: int,
	best_score: float,
	best_biome: int,
	second_score: float,
	second_biome: int
) -> Array:
	# Direct helper is intentionally not used in the hot loop; this exists only
	# as executable documentation for the ordering rule mirrored below.
	if score > best_score:
		return [score, biome, best_score, best_biome]
	if score > second_score:
		return [best_score, best_biome, score, biome]
	return [best_score, best_biome, second_score, second_biome]


static func build(coord: Vector2i, sampler) -> Dictionary:
	var cache: Dictionary = STAGE7_CACHE.build(coord, sampler)
	var fields: PackedFloat32Array = cache.get("world_fields", PackedFloat32Array())
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	var count: int = biomes.size()
	if count == 0 or water_types.size() != count:
		return cache

	var modifiers := PackedByteArray()
	var transition_codes := PackedByteArray()
	modifiers.resize(count)
	transition_codes.resize(count)

	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST
	var water_none: int = sampler.WATER_NONE
	var transition_width: float = sampler.STAGE10_TRANSITION_SCORE_WIDTH
	var transition_levels: int = sampler.STAGE10_TRANSITION_LEVELS

	var column: int = 0
	var field_index: int = 0
	while column < count:
		var water_type: int = int(water_types[column])
		if water_type != water_none:
			biomes[column] = biome_plains
			modifiers[column] = MODIFIER_NONE
			transition_codes[column] = 0
			column += 1
			field_index += FIELD_STRIDE
			continue

		var structure: float = fields[field_index + 1]
		var temperature: float = fields[field_index + 4]
		var moisture: float = fields[field_index + 5]

		# Exact Stage 8 winning ecology plus the closest climate competitor. The
		# normal path still evaluates four candidates. Plains/Forest are both kept
		# only inside the narrow score-width where their shared boundary can affect
		# transition expression.
		var biome: int
		var best_score: float
		var second_biome: int = -1
		var second_score: float = -1.0e20
		var score: float
		if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
			biome = biome_plains
			best_score = PLAINS_M * moisture + PLAINS_B

			score = DESERT_T * temperature + DESERT_M * moisture + DESERT_B
			if score > best_score:
				second_score = best_score
				second_biome = biome
				best_score = score
				biome = biome_desert
			else:
				second_score = score
				second_biome = biome_desert

			score = DRY_T * temperature + DRY_M * moisture + DRY_B
			if score > best_score:
				second_score = best_score
				second_biome = biome
				best_score = score
				biome = biome_dry
			elif score > second_score:
				second_score = score
				second_biome = biome_dry

			score = COLD_T * temperature + COLD_M * moisture + COLD_B
			if score > best_score:
				second_score = best_score
				second_biome = biome
				best_score = score
				biome = biome_cold
			elif score > second_score:
				second_score = score
				second_biome = biome_cold

			if moisture >= PLAINS_FOREST_TRANSITION_LOW:
				score = FOREST_M * moisture + FOREST_B
				if score > best_score:
					second_score = best_score
					second_biome = biome
					best_score = score
					biome = biome_forest
				elif score > second_score:
					second_score = score
					second_biome = biome_forest
		else:
			biome = biome_forest
			best_score = FOREST_M * moisture + FOREST_B

			score = DENSE_T * temperature + DENSE_M * moisture + DENSE_B
			if score > best_score:
				second_score = best_score
				second_biome = biome
				best_score = score
				biome = biome_dense
			else:
				second_score = score
				second_biome = biome_dense

			score = DRY_T * temperature + DRY_M * moisture + DRY_B
			if score > best_score:
				second_score = best_score
				second_biome = biome
				best_score = score
				biome = biome_dry
			elif score > second_score:
				second_score = score
				second_biome = biome_dry

			score = COLD_T * temperature + COLD_M * moisture + COLD_B
			if score > best_score:
				second_score = best_score
				second_biome = biome
				best_score = score
				biome = biome_cold
			elif score > second_score:
				second_score = score
				second_biome = biome_cold

			if moisture <= PLAINS_FOREST_TRANSITION_HIGH:
				score = PLAINS_M * moisture + PLAINS_B
				if score > best_score:
					second_score = best_score
					second_biome = biome
					best_score = score
					biome = biome_plains
				elif score > second_score:
					second_score = score
					second_biome = biome_plains
		biomes[column] = biome

		var margin: float = best_score - second_score
		if margin < transition_width and second_biome >= 0:
			var level: int = roundi(
				(1.0 - maxf(margin, 0.0) / transition_width)
				* float(transition_levels)
			)
			if level > 0:
				transition_codes[column] = ((second_biome + 1) << 5) | mini(level, transition_levels)

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
	cache["stage10_transition_codes"] = transition_codes
	return cache
