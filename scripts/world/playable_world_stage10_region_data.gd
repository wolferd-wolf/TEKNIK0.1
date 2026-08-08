extends "res://scripts/world/playable_world_stage9_terrain_data.gd"

# Stage 10 keeps the Stage 8 base ecology IDs and Stage 9 terrain modifier IDs
# unchanged. Region transitions are expression metadata only: the winning biome
# remains a single deterministic climate Voronoi region, while the runner-up
# ecology can gradually influence vegetation/ground cues near the boundary.
const STAGE10_TRANSITION_SCORE_WIDTH := 0.04
const STAGE10_TRANSITION_LEVELS := 31
const STAGE10_TRANSITION_HASH_RANGE := STAGE10_TRANSITION_LEVELS * 2
const STAGE10_TREE_BLEND_SALT := 0x61c88647
const STAGE10_GROUND_BLEND_SALT := 0x35a1d7c3

# Exact Stage 8 nearest-prototype linear scores. Maximizing these is equivalent
# to minimizing squared Euclidean distance because the shared climate length
# term cancels for every prototype.
const STAGE10_PLAINS_M := -0.04
const STAGE10_PLAINS_B := -0.0004
const STAGE10_FOREST_M := 0.76
const STAGE10_FOREST_B := -0.1444
const STAGE10_DENSE_T := 0.24
const STAGE10_DENSE_M := 1.44
const STAGE10_DENSE_B := -0.5328
const STAGE10_DESERT_T := 1.32
const STAGE10_DESERT_M := -1.20
const STAGE10_DESERT_B := -0.7956
const STAGE10_DRY_T := 0.80
const STAGE10_DRY_M := -0.48
const STAGE10_DRY_B := -0.2176
const STAGE10_COLD_T := -1.04
const STAGE10_COLD_M := 0.68
const STAGE10_COLD_B := -0.386


func stage10_transition_partner(code: int) -> int:
	if code <= 0:
		return -1
	return (code >> 5) - 1


func stage10_transition_level(code: int) -> int:
	return code & STAGE10_TRANSITION_LEVELS


func stage10_transition_strength(code: int) -> float:
	return float(stage10_transition_level(code)) / float(STAGE10_TRANSITION_LEVELS)


func stage10_pack_transition(partner_biome: int, level: int) -> int:
	if partner_biome < 0 or level <= 0:
		return 0
	return ((partner_biome + 1) << 5) | clampi(level, 1, STAGE10_TRANSITION_LEVELS)


func stage10_transition_code_for_climate(climate: Vector2, water_type: int) -> int:
	if water_type != WATER_NONE:
		return 0

	var temperature: float = climate.x
	var moisture: float = climate.y
	var best_biome: int = BIOME_PLAINS
	var best_score: float = STAGE10_PLAINS_M * moisture + STAGE10_PLAINS_B
	var second_biome: int = -1
	var second_score: float = -1.0e20
	var score: float

	score = STAGE10_FOREST_M * moisture + STAGE10_FOREST_B
	if score > best_score:
		second_score = best_score
		second_biome = best_biome
		best_score = score
		best_biome = BIOME_FOREST
	else:
		second_score = score
		second_biome = BIOME_FOREST

	score = STAGE10_DENSE_T * temperature + STAGE10_DENSE_M * moisture + STAGE10_DENSE_B
	if score > best_score:
		second_score = best_score
		second_biome = best_biome
		best_score = score
		best_biome = BIOME_DENSE_FOREST
	elif score > second_score:
		second_score = score
		second_biome = BIOME_DENSE_FOREST

	score = STAGE10_DESERT_T * temperature + STAGE10_DESERT_M * moisture + STAGE10_DESERT_B
	if score > best_score:
		second_score = best_score
		second_biome = best_biome
		best_score = score
		best_biome = BIOME_DESERT
	elif score > second_score:
		second_score = score
		second_biome = BIOME_DESERT

	score = STAGE10_DRY_T * temperature + STAGE10_DRY_M * moisture + STAGE10_DRY_B
	if score > best_score:
		second_score = best_score
		second_biome = best_biome
		best_score = score
		best_biome = BIOME_DRY_GRASSLAND
	elif score > second_score:
		second_score = score
		second_biome = BIOME_DRY_GRASSLAND

	score = STAGE10_COLD_T * temperature + STAGE10_COLD_M * moisture + STAGE10_COLD_B
	if score > best_score:
		second_score = best_score
		second_biome = best_biome
		best_score = score
		best_biome = BIOME_COLD_FOREST
	elif score > second_score:
		second_score = score
		second_biome = BIOME_COLD_FOREST

	var margin: float = best_score - second_score
	if margin >= STAGE10_TRANSITION_SCORE_WIDTH:
		return 0
	var level: int = roundi(
		(1.0 - maxf(margin, 0.0) / STAGE10_TRANSITION_SCORE_WIDTH)
		* float(STAGE10_TRANSITION_LEVELS)
	)
	return stage10_pack_transition(second_biome, level)


func stage10_transition_code_at(x: int, z: int) -> int:
	return stage10_transition_code_for_climate(
		sample_biome_climate(x, z),
		water_type_at(x, z)
	)


func stage10_uses_partner(x: int, z: int, code: int, salt: int) -> bool:
	var level: int = stage10_transition_level(code)
	if level <= 0:
		return false
	# At the exact climate boundary, each side converges on a 50/50 expression
	# mix while the underlying biome identity remains unchanged.
	return posmod(_stage8_hash(x, z, salt), STAGE10_TRANSITION_HASH_RANGE) < level


func stage10_surface_block(
	cell: Vector3i,
	height: int,
	biome: int,
	transition_code: int,
	modifier: int,
	slope: float
) -> int:
	# Geological terrain expression always wins over climate decoration.
	if stage9_surface_exposes_stone(cell.x, cell.z, height, modifier, slope):
		return stage9_surface_block(cell, height, biome, modifier, slope)
	if cell.y != height:
		return stage8_surface_block(cell, height, biome)
	if height <= SEA_LEVEL + 1 or biome == BIOME_DESERT:
		return BLOCK_SAND

	var selected_biome: int = biome
	var partner: int = stage10_transition_partner(transition_code)
	if (
		partner >= 0
		and partner != BIOME_DESERT
		and stage10_uses_partner(cell.x, cell.z, transition_code, STAGE10_GROUND_BLEND_SALT)
	):
		selected_biome = partner

	if selected_biome == BIOME_DRY_GRASSLAND and stage8_dry_surface_is_sand(cell.x, cell.z):
		return BLOCK_SAND
	if selected_biome == BIOME_COLD_FOREST and stage8_cold_surface_is_stone(cell.x, cell.z):
		return BLOCK_STONE
	return BLOCK_GRASS


func stage10_tree_candidate_for_biome(
	x: int,
	z: int,
	surface: int,
	biome: int,
	transition_code: int,
	modifier: int,
	slope: float
) -> bool:
	var candidate: bool = stage8_tree_candidate_for_biome(x, z, surface, biome)
	var partner: int = stage10_transition_partner(transition_code)
	if partner >= 0:
		var partner_candidate: bool = stage8_tree_candidate_for_biome(x, z, surface, partner)
		if (
			candidate != partner_candidate
			and stage10_uses_partner(x, z, transition_code, STAGE10_TREE_BLEND_SALT)
		):
			candidate = partner_candidate
	if not candidate:
		return false

	# Never put a transitioned tree onto the final visible sand/stone cue.
	if stage10_surface_block(
		Vector3i(x, surface, z), surface, biome, transition_code, modifier, slope
	) != BLOCK_GRASS:
		return false

	var hash_value: int = absi(_stage8_hash(x, z, STAGE9_TREE_FILTER_SALT))
	match modifier:
		TERRAIN_MODIFIER_MOUNTAIN:
			if slope >= 3.0 or surface >= STAGE9_TREE_LINE_ELEVATION:
				return false
			return hash_value % 2 == 0
		TERRAIN_MODIFIER_PLATEAU:
			return hash_value % 3 != 0
		TERRAIN_MODIFIER_HILL:
			return hash_value % 5 != 0
		TERRAIN_MODIFIER_VALLEY, TERRAIN_MODIFIER_NONE:
			return true
		_:
			return true


func is_tree_origin_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	var transition_code: int = stage10_transition_code_at(x, z)
	var modifier: int = stage9_terrain_modifier_at(x, z)
	var slope: float = stage7_surface_slope_at(x, z, surface)
	return stage10_tree_candidate_for_biome(
		x, z, surface, biome, transition_code, modifier, slope
	)


func generated_tree_block(cell: Vector3i) -> int:
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


func stage10_region_context_at(x: int, z: int) -> Dictionary:
	var context: Dictionary = stage9_expression_context_at(x, z)
	var code: int = stage10_transition_code_at(x, z)
	context["transition_code"] = code
	context["transition_partner"] = stage10_transition_partner(code)
	context["transition_strength"] = stage10_transition_strength(code)
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
		var transition_code: int = stage10_transition_code_for_climate(climate, water_type)
		return stage10_surface_block(
			cell, height, biome, transition_code, modifier, slope
		)
	return generated_tree_block(cell)
