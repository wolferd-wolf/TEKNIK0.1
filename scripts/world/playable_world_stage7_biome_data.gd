extends "res://scripts/world/playable_world_stage6_tree_consistent_data.gd"

# Stage 7 replaces probabilistic patch selection with a deterministic
# nearest-prototype climate classifier. Stage 8 owns biome-set expansion.
const STAGE7_PLAINS_TARGET := Vector2(0.02, -0.02)
const STAGE7_FOREST_TARGET := Vector2(-0.05, 0.58)
const STAGE7_DESERT_TARGET := Vector2(0.68, -0.62)
const STAGE7_ROCKY_TARGET := Vector2(-0.34, -0.24)

# Stage-7 tuning checkpoint: widen neutral plains and make rugged/cold-dry
# terrain genuinely reachable without letting Rocky paint flat lowlands.
const STAGE7_ROCKY_STRUCTURE_MIN := 0.20
const STAGE7_ROCKY_ELEVATION_MIN := 38
const STAGE7_COAST_HEIGHT_MARGIN := 2

func _stage7_distance_sq(climate: Vector2, target: Vector2) -> float:
	var delta := climate - target
	return delta.x * delta.x + delta.y * delta.y

func _stage7_choose_land_biome(climate: Vector2, terrain_structure: float, height: int) -> int:
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
	if terrain_structure >= STAGE7_ROCKY_STRUCTURE_MIN or height >= STAGE7_ROCKY_ELEVATION_MIN:
		var rocky_distance := _stage7_distance_sq(climate, STAGE7_ROCKY_TARGET)
		if rocky_distance < best_distance:
			best_biome = BIOME_ROCKY
	return best_biome

func stage7_classify_with_context(climate: Vector2, terrain_structure: float, height: int, water_type: int) -> int:
	if water_type != WATER_NONE:
		return BIOME_PLAINS
	if height <= SEA_LEVEL + STAGE7_COAST_HEIGHT_MARGIN:
		return BIOME_PLAINS
	return _stage7_choose_land_biome(climate, terrain_structure, height)

func classify_biome(climate: Vector2, x: int, z: int) -> int:
	var height := terrain_height(x, z)
	var structure := stage3_terrain_structure(x, z)
	var water_type := water_type_at(x, z)
	return stage7_classify_with_context(climate, structure, height, water_type)
