extends "res://scripts/world/playable_world_stage6_tree_consistent_data.gd"

# Stage 7 replaces the historical probabilistic biome-patch selector with a
# deterministic nearest-prototype climate classifier. Stage 8 owns expansion to
# the final 6–8 strong ecology set; Stage 7 deliberately keeps the existing four
# biome IDs so this stage changes classifier architecture rather than assets.
#
# Classification order is now explicit:
#   1. physical terrain/hydrology context establishes eligibility,
#   2. temperature × moisture chooses the nearest eligible climate prototype,
#   3. Plains is the guaranteed fallback.
#
# Slope is exposed in the context contract now, even though the transitional
# four-biome set does not need it to distinguish an ecology. Stage 9 terrain
# modifiers can consume it without changing this classifier API.
const STAGE7_PLAINS_TARGET := Vector2(0.02, -0.02)
const STAGE7_FOREST_TARGET := Vector2(-0.05, 0.58)
const STAGE7_DESERT_TARGET := Vector2(0.68, -0.62)
const STAGE7_ROCKY_TARGET := Vector2(-0.34, -0.24)

# Rocky remains only as a compatibility ecology until Stage 8. It is no longer
# allowed to *create* mountains or paint ordinary flat lowlands. Rugged terrain
# is generated first by Stages 2–6; only then can cold/dry climate select Rocky.
const STAGE7_ROCKY_MOUNTAIN_STRENGTH_MIN := 0.24
const STAGE7_ROCKY_ELEVATION_MIN := 38
const STAGE7_ROCKY_COAST_PROXIMITY_MAX := 0.55


func _stage7_distance_sq(climate: Vector2, target: Vector2) -> float:
	var dx: float = climate.x - target.x
	var dy: float = climate.y - target.y
	return dx * dx + dy * dy


func stage7_mountain_strength(terrain_structure: float) -> float:
	return _stage3_smooth01(
		(terrain_structure - STAGE2_MOUNTAIN_START)
		/ (STAGE2_MOUNTAIN_FULL - STAGE2_MOUNTAIN_START)
	)


func stage7_coast_proximity_from_continentalness(continentalness: float) -> float:
	# 1.0 at the ocean edge, fading smoothly to 0.0 at established inland terrain.
	if continentalness <= STAGE4_OCEAN_WATER_START:
		return 1.0
	if continentalness >= STAGE4_COAST_INLAND_END:
		return 0.0
	return 1.0 - _stage3_smooth01(
		(continentalness - STAGE4_OCEAN_WATER_START)
		/ (STAGE4_COAST_INLAND_END - STAGE4_OCEAN_WATER_START)
	)


func stage7_rocky_eligible(
	mountain_strength: float,
	height: int,
	coast_proximity: float
) -> bool:
	if coast_proximity > STAGE7_ROCKY_COAST_PROXIMITY_MAX:
		return false
	return (
		mountain_strength >= STAGE7_ROCKY_MOUNTAIN_STRENGTH_MIN
		or height >= STAGE7_ROCKY_ELEVATION_MIN
	)


func stage7_classify_with_context(
	climate: Vector2,
	mountain_strength: float,
	_slope: float,
	height: int,
	water_type: int,
	coast_proximity: float
) -> int:
	# Stage 7 selects a base ecology, not a water biome. Physical water already
	# exists independently, so wet columns use the neutral base ecology until
	# Stage 11 adds water-aware biome expression.
	if water_type != WATER_NONE:
		return BIOME_PLAINS

	var best_biome: int = BIOME_PLAINS
	var best_distance: float = _stage7_distance_sq(climate, STAGE7_PLAINS_TARGET)

	var forest_distance: float = _stage7_distance_sq(climate, STAGE7_FOREST_TARGET)
	if forest_distance < best_distance:
		best_biome = BIOME_FOREST
		best_distance = forest_distance

	var desert_distance: float = _stage7_distance_sq(climate, STAGE7_DESERT_TARGET)
	if desert_distance < best_distance:
		best_biome = BIOME_DESERT
		best_distance = desert_distance

	if stage7_rocky_eligible(mountain_strength, height, coast_proximity):
		var rocky_distance: float = _stage7_distance_sq(climate, STAGE7_ROCKY_TARGET)
		if rocky_distance < best_distance:
			best_biome = BIOME_ROCKY

	return best_biome


func stage7_surface_slope_at(x: int, z: int, center_height: int = -1) -> float:
	var center: int = center_height
	if center < 0:
		center = terrain_height(x, z)
	var slope: int = 0
	slope = maxi(slope, absi(terrain_height(x - 1, z) - center))
	slope = maxi(slope, absi(terrain_height(x + 1, z) - center))
	slope = maxi(slope, absi(terrain_height(x, z - 1) - center))
	slope = maxi(slope, absi(terrain_height(x, z + 1) - center))
	return float(slope)


func stage7_context_at(x: int, z: int) -> Dictionary:
	var fields: Vector4 = sample_world_fields(x, z)
	var height: int = terrain_height(x, z)
	return {
		"height": height,
		"mountain_strength": stage7_mountain_strength(fields.y),
		"slope": stage7_surface_slope_at(x, z, height),
		"water_type": water_type_at(x, z),
		"coast_proximity": stage7_coast_proximity_from_continentalness(fields.x),
		"temperature": sample_biome_climate(x, z).x,
		"moisture": sample_biome_climate(x, z).y,
	}


func classify_biome(climate: Vector2, x: int, z: int) -> int:
	var fields: Vector4 = sample_world_fields(x, z)
	var height: int = terrain_height(x, z)
	var mountain_strength: float = stage7_mountain_strength(fields.y)
	var coast_proximity: float = stage7_coast_proximity_from_continentalness(fields.x)
	var water_type: int = water_type_at(x, z)
	# Slope is part of the Stage 7 context API but is intentionally not an ecology
	# discriminator in the transitional four-biome set. Avoid four extra terrain
	# queries on every direct biome lookup until Stage 9 needs that modifier.
	return stage7_classify_with_context(
		climate,
		mountain_strength,
		0.0,
		height,
		water_type,
		coast_proximity
	)