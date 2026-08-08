extends RefCounted

const STAGE9_CACHE := preload("res://scripts/world/playable_world_stage9_cache_fast.gd")
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


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Region transitions are expression metadata, not terrain/biome identity.
	# Keep the hard generation cache byte-for-byte Stage 9-equivalent and derive
	# transition codes after cache timing, immediately before meshing.
	return STAGE9_CACHE.build(coord, sampler)


static func _score_for_biome(
	temperature: float,
	moisture: float,
	biome: int,
	sampler
) -> float:
	match biome:
		sampler.BIOME_PLAINS:
			return PLAINS_M * moisture + PLAINS_B
		sampler.BIOME_FOREST:
			return FOREST_M * moisture + FOREST_B
		sampler.BIOME_DENSE_FOREST:
			return DENSE_T * temperature + DENSE_M * moisture + DENSE_B
		sampler.BIOME_DESERT:
			return DESERT_T * temperature + DESERT_M * moisture + DESERT_B
		sampler.BIOME_DRY_GRASSLAND:
			return DRY_T * temperature + DRY_M * moisture + DRY_B
		sampler.BIOME_COLD_FOREST:
			return COLD_T * temperature + COLD_M * moisture + COLD_B
		_:
			return -1.0e20


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
		var best_score: float = _score_for_biome(temperature, moisture, biome, sampler)
		var second_score: float = -1.0e20
		var second_biome: int = -1
		var score: float

		# Only prototypes that can own a neighboring Voronoi region in this
		# moisture half-space participate. The losing Plains/Forest prototype is
		# retained in the narrow +/-0.05 band around their exact shared boundary.
		if biome != biome_plains:
			if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY or moisture <= PLAINS_FOREST_TRANSITION_HIGH:
				score = PLAINS_M * moisture + PLAINS_B
				if score > second_score:
					second_score = score
					second_biome = biome_plains
		if biome != biome_forest:
			if moisture > PLAINS_FOREST_MOISTURE_BOUNDARY or moisture >= PLAINS_FOREST_TRANSITION_LOW:
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
