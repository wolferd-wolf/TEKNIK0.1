extends "res://scripts/world/playable_world_stage6_tree_consistent_data.gd"

# Stage 7 replaces the legacy probabilistic patch selector with a deterministic
# nearest-prototype classifier. It deliberately keeps the existing four biome
# identities; Stage 8 is responsible for expanding the visible biome set.
#
# Classification uses slow temperature/moisture climate fields first, then
# terrain and hydrology context to decide which profiles are eligible. This
# removes salt-and-pepper patch selection while guaranteeing a fallback biome.
const STAGE7_PLAINS_TARGET := Vector2(0.00, 0.00)
const STAGE7_FOREST_TARGET := Vector2(-0.02, 0.48)
const STAGE7_DESERT_TARGET := Vector2(0.52, -0.46)
const STAGE7_ROCKY_TARGET := Vector2(-0.42, -0.30)

const STAGE7_ROCKY_STRUCTURE_MIN := 0.30
const STAGE7_ROCKY_ELEVATION_MIN := 42
const STAGE7_COAST_HEIGHT_MARGIN := 2


func _stage7_distance_sq(climate: Vector2, target: Vector2) -> float:
	var delta := climate - target
	return delta.x * delta.x + delta.y * delta.y


func _stage7_choose_land_biome(
	climate: Vector2,
	terrain_structure: float,
	height: int
) -> int:
	var best_biome := BIOME_PLAINS
	var best_distance := _stage7_distance_sq(climate, STAGE7_PLAINS_TARGET)

	var forest_distance := _stage7_distance_sq(climate, STAGE7_FOREST_TARGET)
	if forest_distance < best_distance:
		best_biome = BIOME_FOREST
		best_distance = forest_distance

	var desert_distance := _stage7_distance_sq(climate, STAGE7_DESERT_TARGET)
	if desert_distance < best_distance:
		best_biome = BIOME_DESERT
		best_distance = desert_distance

	# Rocky is an ecological choice only where the physical terrain supports it.
	# This prevents cold/dry climate alone from painting flat lowlands as rocky.
	if (
		terrain_structure >= STAGE7_ROCKY_STRUCTURE_MIN
		or height >= STAGE7_ROCKY_ELEVATION_MIN
	):
		var rocky_distance := _stage7_distance_sq(climate, STAGE7_ROCKY_TARGET)
		if rocky_distance < best_distance:
			best_biome = BIOME_ROCKY

	return best_biome


func stage7_classify_with_context(
	climate: Vector2,
	terrain_structure: float,
	height: int,
	water_type: int
) -> int:
	# Hydrology is physical geography, not a fifth ecology. Existing Stage 4-6
	# water remains authoritative. Wet columns use a neutral land ecology so an
	# ocean/lake/river can never become Forest or Rocky merely from climate.
	if water_type != WATER_NONE:
		return BIOME_PLAINS

	# Very low coastal land also stays neutral. Stage 11 will express dedicated
	# water-aware coast/riparian modifiers after the base ecology is established.
	if height <= SEA_LEVEL + STAGE7_COAST_HEIGHT_MARGIN:
		return BIOME_PLAINS

	return _stage7_choose_land_biome(climate, terrain_structure, height)


func classify_biome(climate: Vector2, x: int, z: int) -> int:
	var height := terrain_height(x, z)
	var structure := stage3_terrain_structure(x, z)
	var water_type := water_type_at(x, z)
	return stage7_classify_with_context(climate, structure, height, water_type)
