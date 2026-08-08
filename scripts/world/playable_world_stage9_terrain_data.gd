extends "res://scripts/world/playable_world_stage8_biome_data.gd"

# Stage 9 keeps Stage 8 base ecology immutable and adds an orthogonal terrain
# modifier. No terrain category becomes a new biome ID. The modifier is derived
# entirely from accepted geography fields and is used only by expression rules.
const TERRAIN_MODIFIER_NONE := 0
const TERRAIN_MODIFIER_HILL := 1
const TERRAIN_MODIFIER_PLATEAU := 2
const TERRAIN_MODIFIER_MOUNTAIN := 3
const TERRAIN_MODIFIER_VALLEY := 4
const STAGE9_TERRAIN_MODIFIER_COUNT := 5

# These boundaries deliberately reuse Stage 2's accepted terrain regime edges.
const STAGE9_HILL_STRUCTURE_MIN := STAGE2_PLAINS_END
const STAGE9_PLATEAU_STRUCTURE_MIN := STAGE2_ROLLING_END
const STAGE9_MOUNTAIN_STRUCTURE_MIN := STAGE2_MOUNTAIN_START

# Stage 2's mountain target already contains a ridge-versus-valley term:
# ridge=(1-|continentalness|)^2 and -(1-ridge)*VALLEY_CUT. Reusing that same
# signal makes the Stage 9 valley modifier describe terrain that was physically
# lowered by the terrain generator instead of inventing a second valley system.
const STAGE9_VALLEY_STRENGTH_MIN := 0.22

const STAGE9_HIGH_ROCK_ELEVATION := 48
const STAGE9_TREE_LINE_ELEVATION := 64
const STAGE9_ROCK_SURFACE_SALT := 0x51a9c3d7
const STAGE9_TREE_FILTER_SALT := 0x2d6f83b1


func stage9_valley_strength(continentalness: float, terrain_structure: float) -> float:
	var mountain_strength: float = stage7_mountain_strength(terrain_structure)
	var ridge: float = ridge_strength(continentalness)
	return mountain_strength * (1.0 - ridge)


func stage9_terrain_modifier_from_fields(
	continentalness: float,
	terrain_structure: float,
	water_type: int
) -> int:
	# Wet columns remain hydrology. Stage 11 owns water-aware expression.
	if water_type != WATER_NONE:
		return TERRAIN_MODIFIER_NONE

	if terrain_structure >= STAGE9_MOUNTAIN_STRUCTURE_MIN:
		if stage9_valley_strength(continentalness, terrain_structure) >= STAGE9_VALLEY_STRENGTH_MIN:
			return TERRAIN_MODIFIER_VALLEY
		return TERRAIN_MODIFIER_MOUNTAIN
	if terrain_structure >= STAGE9_PLATEAU_STRUCTURE_MIN:
		return TERRAIN_MODIFIER_PLATEAU
	if terrain_structure >= STAGE9_HILL_STRUCTURE_MIN:
		return TERRAIN_MODIFIER_HILL
	return TERRAIN_MODIFIER_NONE


func stage9_terrain_modifier_at(x: int, z: int) -> int:
	var fields: Vector4 = sample_world_fields(x, z)
	return stage9_terrain_modifier_from_fields(fields.x, fields.y, water_type_at(x, z))


func terrain_modifier_name(modifier: int) -> String:
	match modifier:
		TERRAIN_MODIFIER_NONE:
			return "none"
		TERRAIN_MODIFIER_HILL:
			return "hill"
		TERRAIN_MODIFIER_PLATEAU:
			return "plateau"
		TERRAIN_MODIFIER_MOUNTAIN:
			return "mountain"
		TERRAIN_MODIFIER_VALLEY:
			return "valley"
		_:
			return "unknown"


func stage9_surface_exposes_stone(
	x: int,
	z: int,
	height: int,
	modifier: int,
	slope: float
) -> bool:
	var hash_value: int = absi(_stage8_hash(x, z, STAGE9_ROCK_SURFACE_SALT))
	match modifier:
		TERRAIN_MODIFIER_MOUNTAIN:
			# Cliffs stay geological, while lower/gentler mountain shoulders keep
			# enough ecology surface for recognisable forested and grassy mountains.
			if slope >= 3.0:
				return true
			if slope >= 2.0:
				return hash_value % 2 == 0
			if height >= STAGE9_HIGH_ROCK_ELEVATION:
				return hash_value % 2 == 0
			return hash_value % 7 == 0
		TERRAIN_MODIFIER_PLATEAU:
			if slope >= 3.0:
				return true
			return height >= STAGE9_HIGH_ROCK_ELEVATION and hash_value % 11 == 0
		TERRAIN_MODIFIER_HILL:
			return slope >= 4.0 and hash_value % 2 == 0
		_:
			# Valleys intentionally retain their base ecology surface. Their visual
			# contrast comes from being less rocky/less tree-suppressed than slopes.
			return false


func stage9_surface_block(
	cell: Vector3i,
	height: int,
	biome: int,
	modifier: int,
	slope: float
) -> int:
	var exposed_stone: bool = stage9_surface_exposes_stone(
		cell.x, cell.z, height, modifier, slope
	)
	if exposed_stone and cell.y == height:
		return BLOCK_STONE
	if (
		exposed_stone
		and modifier == TERRAIN_MODIFIER_MOUNTAIN
		and cell.y == height - 1
		and (slope >= 3.0 or height >= STAGE9_HIGH_ROCK_ELEVATION)
	):
		return BLOCK_STONE
	return stage8_surface_block(cell, height, biome)


func stage9_tree_candidate_for_biome(
	x: int,
	z: int,
	surface: int,
	biome: int,
	modifier: int,
	slope: float
) -> bool:
	if not stage8_tree_candidate_for_biome(x, z, surface, biome):
		return false
	if stage9_surface_exposes_stone(x, z, surface, modifier, slope):
		return false

	var hash_value: int = absi(_stage8_hash(x, z, STAGE9_TREE_FILTER_SALT))
	match modifier:
		TERRAIN_MODIFIER_MOUNTAIN:
			# Cliffs and terrain above the tree line remain open. Lower gentle
			# mountains retain a sparse subset of the selected base ecology trees.
			if slope >= 3.0 or surface >= STAGE9_TREE_LINE_ELEVATION:
				return false
			return hash_value % 2 == 0
		TERRAIN_MODIFIER_PLATEAU:
			return hash_value % 3 != 0
		TERRAIN_MODIFIER_HILL:
			return hash_value % 5 != 0
		TERRAIN_MODIFIER_VALLEY:
			# Valley floors retain the full Stage 8 ecology density. Relative to the
			# surrounding filtered slopes this naturally reads as sheltered terrain.
			return true
		_:
			return true


func is_tree_origin_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	var modifier: int = stage9_terrain_modifier_at(x, z)
	var slope: float = stage7_surface_slope_at(x, z, surface)
	return stage9_tree_candidate_for_biome(x, z, surface, biome, modifier, slope)


func generated_tree_block(cell: Vector3i) -> int:
	# Stage 9 changes tree eligibility, not the six accepted Stage 8 silhouettes.
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


func stage9_expression_context_at(x: int, z: int) -> Dictionary:
	var context: Dictionary = stage7_context_at(x, z)
	var fields: Vector4 = sample_world_fields(x, z)
	var modifier: int = stage9_terrain_modifier_from_fields(
		fields.x,
		fields.y,
		int(context.get("water_type", WATER_NONE))
	)
	context["base_biome"] = biome_at(x, z)
	context["terrain_modifier"] = modifier
	context["terrain_modifier_name"] = terrain_modifier_name(modifier)
	context["valley_strength"] = stage9_valley_strength(fields.x, fields.y)
	return context


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
	var water_type: int = water_type_at(cell.x, cell.z)
	var climate: Vector2 = sample_biome_climate(cell.x, cell.z)
	var biome: int = stage8_classify_climate(climate, water_type)
	if cell.y <= height:
		if cell.y < height - 1:
			return stage8_surface_block(cell, height, biome)
		var modifier: int = stage9_terrain_modifier_from_fields(
			fields.x, fields.y, water_type
		)
		var slope: float = stage7_surface_slope_at(cell.x, cell.z, height)
		return stage9_surface_block(cell, height, biome, modifier, slope)
	return generated_tree_block(cell)
