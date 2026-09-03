extends "res://scripts/world/playable_world_stage7_biome_data.gd"

# Stage 8 establishes the first ecology set that can be read immediately with
# TEKNIK's current block palette. Mountain/valley/plateau remain terrain context;
# Stage 8 does not reintroduce them as ecology IDs.
#
# BIOME_ROCKY (3) remains reserved for historical compatibility but is no longer
# emitted by the shipping classifier. New active ecology IDs begin after it.
const BIOME_DENSE_FOREST := 4
const BIOME_DRY_GRASSLAND := 5
const BIOME_COLD_FOREST := 6
const STAGE8_ACTIVE_BIOME_COUNT := 6
const STAGE8_MAX_BIOME_ID := BIOME_COLD_FOREST

const STAGE8_PLAINS_TARGET := Vector2(0.00, -0.02)
const STAGE8_FOREST_TARGET := Vector2(0.00, 0.38)
const STAGE8_DENSE_FOREST_TARGET := Vector2(0.12, 0.72)
const STAGE8_DESERT_TARGET := Vector2(0.66, -0.60)
const STAGE8_DRY_GRASSLAND_TARGET := Vector2(0.40, -0.24)
const STAGE8_COLD_FOREST_TARGET := Vector2(-0.52, 0.34)

const STAGE8_DENSE_TREE_SPACING := 4
const STAGE8_DENSE_TREE_OFFSET := 1
const STAGE8_DRY_TREE_SPACING := 11
const STAGE8_DRY_TREE_OFFSET := 5
const STAGE8_COLD_TREE_SPACING := 5
const STAGE8_COLD_TREE_OFFSET := 3
# Plains previously reused the shared baseline grid (spacing 7, 75% accept),
# which is the same density Forest falls back to outside its own tighter
# grid. That made "open plains" read as densely treed as forest edges.
# Plains now gets its own much wider, sparser grid.
const STAGE8_PLAINS_TREE_SPACING := 27
const STAGE8_PLAINS_TREE_OFFSET := 11

const STAGE8_DRY_SURFACE_SALT := 0x13579bdf
const STAGE8_COLD_SURFACE_SALT := 0x2468ace1


func _stage8_distance_sq(climate: Vector2, target: Vector2) -> float:
	var dx: float = climate.x - target.x
	var dy: float = climate.y - target.y
	return dx * dx + dy * dy


func stage8_classify_climate(climate: Vector2, water_type: int, allow_plains: bool = true) -> int:
	# Water remains geography, not a biome. Until Stage 11 adds water-aware
	# expression, physical water columns retain neutral Plains as base ecology.
	if water_type != WATER_NONE:
		return BIOME_PLAINS

	var best_biome: int = BIOME_FOREST
	var best_distance: float = INF
	if allow_plains:
		best_biome = BIOME_PLAINS
		best_distance = _stage8_distance_sq(climate, STAGE8_PLAINS_TARGET)

	var distance: float = _stage8_distance_sq(climate, STAGE8_FOREST_TARGET)
	if distance < best_distance:
		best_distance = distance
		best_biome = BIOME_FOREST

	distance = _stage8_distance_sq(climate, STAGE8_DENSE_FOREST_TARGET)
	if distance < best_distance:
		best_distance = distance
		best_biome = BIOME_DENSE_FOREST

	distance = _stage8_distance_sq(climate, STAGE8_DESERT_TARGET)
	if distance < best_distance:
		best_distance = distance
		best_biome = BIOME_DESERT

	distance = _stage8_distance_sq(climate, STAGE8_DRY_GRASSLAND_TARGET)
	if distance < best_distance:
		best_distance = distance
		best_biome = BIOME_DRY_GRASSLAND

	distance = _stage8_distance_sq(climate, STAGE8_COLD_FOREST_TARGET)
	if distance < best_distance:
		best_biome = BIOME_COLD_FOREST

	return best_biome


func stage8_classify_with_context(
	climate: Vector2,
	_mountain_strength: float,
	_slope: float,
	_height: int,
	water_type: int,
	_coast_proximity: float
) -> int:
	# Terrain context is intentionally accepted but does not choose base ecology.
	# Stage 9 owns terrain modifiers such as mountain/cold/exposed-stone treatment.
	return stage8_classify_climate(climate, water_type)


func classify_biome(climate: Vector2, x: int, z: int) -> int:
	return stage8_classify_climate(climate, water_type_at(x, z))


func biome_name(biome: int) -> String:
	match biome:
		BIOME_PLAINS:
			return "plains"
		BIOME_FOREST:
			return "forest"
		BIOME_DESERT:
			return "desert"
		BIOME_ROCKY:
			return "rocky_legacy"
		BIOME_DENSE_FOREST:
			return "dense_forest"
		BIOME_DRY_GRASSLAND:
			return "dry_grassland"
		BIOME_COLD_FOREST:
			return "cold_forest"
		_:
			return "unknown"


func _stage8_hash(x: int, z: int, salt: int = 0) -> int:
	var value: int = (x * 73856093) ^ (z * 19349663) ^ (WORLD_SEED * 83492791) ^ salt
	value = (value ^ (value >> 13)) * 1274126177
	return value ^ (value >> 16)


func stage8_dry_surface_is_sand(x: int, z: int) -> bool:
	# Broad grass remains dominant; deterministic shallow sand breaks give the
	# region a dry ground texture without requiring a new material asset.
	return posmod(_stage8_hash(x, z, STAGE8_DRY_SURFACE_SALT), 5) == 0


func stage8_cold_surface_is_stone(x: int, z: int) -> bool:
	# Sparse exposed stone is the third visual cue for the cold forest while
	# snow/ice assets do not yet exist.
	return posmod(_stage8_hash(x, z, STAGE8_COLD_SURFACE_SALT), 7) == 0


func stage8_surface_block(cell: Vector3i, height: int, biome: int) -> int:
	if cell.y == height:
		if height <= SEA_LEVEL + 1 or biome == BIOME_DESERT:
			return BLOCK_SAND
		if biome == BIOME_DRY_GRASSLAND and stage8_dry_surface_is_sand(cell.x, cell.z):
			return BLOCK_SAND
		if biome == BIOME_COLD_FOREST and stage8_cold_surface_is_stone(cell.x, cell.z):
			return BLOCK_STONE
		return BLOCK_GRASS
	if cell.y >= height - 3:
		if height <= SEA_LEVEL + 1 or biome == BIOME_DESERT:
			return BLOCK_SAND
		return BLOCK_DIRT
	return BLOCK_STONE


func decorate_surface(y: int, height: int, biome: int) -> int:
	# Coordinate-free compatibility path. Shipping direct block queries call the
	# coordinate-aware Stage 8 surface helper below.
	return terrain_block(y, height, biome)


func stage8_tree_trunk_height(biome: int) -> int:
	match biome:
		BIOME_DENSE_FOREST, BIOME_COLD_FOREST:
			return 5
		BIOME_DRY_GRASSLAND:
			return 3
		_:
			return TREE_TRUNK_HEIGHT


func stage8_tree_candidate_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if biome == BIOME_DESERT or biome == BIOME_ROCKY:
		return false
	var trunk_height: int = stage8_tree_trunk_height(biome)
	if surface <= SEA_LEVEL + 1 or surface + trunk_height + 2 >= OVERHAUL_WORLD_HEIGHT:
		return false

	var hash_value: int = absi((x * 73856093) ^ (z * 19349663) ^ WORLD_SEED)
	var baseline_grid: bool = (
		posmod(x, TREE_SPACING) == TREE_OFFSET
		and posmod(z, TREE_SPACING) == TREE_OFFSET
	)

	match biome:
		BIOME_PLAINS:
			var plains_grid: bool = (
				posmod(x, STAGE8_PLAINS_TREE_SPACING) == STAGE8_PLAINS_TREE_OFFSET
				and posmod(z, STAGE8_PLAINS_TREE_SPACING) == STAGE8_PLAINS_TREE_OFFSET
			)
			return plains_grid and hash_value % 4 == 0
		BIOME_FOREST:
			var forest_grid: bool = (
				posmod(x, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
				and posmod(z, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
			)
			if forest_grid and not baseline_grid:
				return hash_value % 3 != 0
			return baseline_grid and hash_value % 4 != 0
		BIOME_DENSE_FOREST:
			var dense_grid: bool = (
				posmod(x, STAGE8_DENSE_TREE_SPACING) == STAGE8_DENSE_TREE_OFFSET
				and posmod(z, STAGE8_DENSE_TREE_SPACING) == STAGE8_DENSE_TREE_OFFSET
			)
			if dense_grid:
				return hash_value % 5 != 0
			return baseline_grid and hash_value % 4 != 0
		BIOME_DRY_GRASSLAND:
			if stage8_dry_surface_is_sand(x, z):
				return false
			return (
				posmod(x, STAGE8_DRY_TREE_SPACING) == STAGE8_DRY_TREE_OFFSET
				and posmod(z, STAGE8_DRY_TREE_SPACING) == STAGE8_DRY_TREE_OFFSET
				and hash_value % 2 == 0
			)
		BIOME_COLD_FOREST:
			if stage8_cold_surface_is_stone(x, z):
				return false
			return (
				posmod(x, STAGE8_COLD_TREE_SPACING) == STAGE8_COLD_TREE_OFFSET
				and posmod(z, STAGE8_COLD_TREE_SPACING) == STAGE8_COLD_TREE_OFFSET
				and hash_value % 4 != 0
			)
		_:
			return false


func is_tree_origin_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	# Keep the cheap deterministic candidate test before hydrology lookup.
	if not stage8_tree_candidate_for_biome(x, z, surface, biome):
		return false
	return water_type_at(x, z) == WATER_NONE


func is_tree_origin(x: int, z: int) -> bool:
	var surface: int = terrain_height(x, z)
	var biome: int = biome_at(x, z)
	return is_tree_origin_for_biome(x, z, surface, biome)


func stage8_tree_canopy_contains(
	dx: int,
	dz: int,
	dy_from_trunk_top: int,
	biome: int
) -> bool:
	if absi(dx) > 1 or absi(dz) > 1:
		return false
	match biome:
		BIOME_DENSE_FOREST:
			if dy_from_trunk_top >= -2 and dy_from_trunk_top <= 1:
				return true
			return dy_from_trunk_top == 2 and dx == 0 and dz == 0
		BIOME_DRY_GRASSLAND:
			if dy_from_trunk_top == 0:
				return true
			return dy_from_trunk_top == 1 and dx == 0 and dz == 0
		BIOME_COLD_FOREST:
			if dy_from_trunk_top == -2 or dy_from_trunk_top == -1:
				return true
			if dy_from_trunk_top == 0:
				return absi(dx) + absi(dz) <= 1
			return dy_from_trunk_top == 1 and dx == 0 and dz == 0
		_:
			return dy_from_trunk_top >= -1 and dy_from_trunk_top <= 1


func stage8_tree_block_for_origin(
	cell: Vector3i,
	tree_x: int,
	tree_z: int,
	surface: int,
	biome: int
) -> int:
	var trunk_top: int = surface + stage8_tree_trunk_height(biome)
	if cell.x == tree_x and cell.z == tree_z and cell.y > surface and cell.y <= trunk_top:
		return BLOCK_LOG
	if stage8_tree_canopy_contains(
		cell.x - tree_x,
		cell.z - tree_z,
		cell.y - trunk_top,
		biome
	):
		return BLOCK_LEAVES
	return BLOCK_AIR


func generated_tree_block(cell: Vector3i) -> int:
	# Rooted trunks win over overlapping canopies, matching the historical rule.
	var own_surface: int = terrain_height(cell.x, cell.z)
	var own_biome: int = biome_at(cell.x, cell.z)
	if is_tree_origin_for_biome(cell.x, cell.z, own_surface, own_biome):
		var own_block: int = stage8_tree_block_for_origin(
			cell, cell.x, cell.z, own_surface, own_biome
		)
		if own_block == BLOCK_LOG:
			return BLOCK_LOG

	for tree_z in range(cell.z - 1, cell.z + 2):
		for tree_x in range(cell.x - 1, cell.x + 2):
			var surface: int = terrain_height(tree_x, tree_z)
			var biome: int = biome_at(tree_x, tree_z)
			if not is_tree_origin_for_biome(tree_x, tree_z, surface, biome):
				continue
			var block: int = stage8_tree_block_for_origin(
				cell, tree_x, tree_z, surface, biome
			)
			if block != BLOCK_AIR:
				return block
	return BLOCK_AIR


func get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= OVERHAUL_WORLD_HEIGHT:
		return BLOCK_AIR
	var key := cell_key(cell)
	if overrides.has(key):
		return int(overrides[key])
	var fields: Vector4 = sample_world_fields(cell.x, cell.z)
	var provisional_height: int = build_provisional_terrain(fields)
	var water_shaped_height: int = apply_water_topology(
		fields, provisional_height, cell.x, cell.z
	)
	var height: int = finalize_height(water_shaped_height)
	var climate: Vector2 = sample_biome_climate(cell.x, cell.z)
	var biome: int = stage8_classify_climate(climate, water_type_at(cell.x, cell.z))
	if cell.y <= height:
		return stage8_surface_block(cell, height, biome)
	return generated_tree_block(cell)
