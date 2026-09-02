extends "res://scripts/world/playable_world_stage10_region_data.gd"

# Stage 11 is expression-only. Physical water remains owned by Stages 4–6;
# Stage 8 base ecology, Stage 9 terrain modifiers and Stage 10 climate-region
# transitions remain unchanged. Dry land immediately touching cached water gets
# one orthogonal hydrology-expression modifier.
const HYDROLOGY_MODIFIER_NONE := 0
const HYDROLOGY_MODIFIER_COAST := 1
const HYDROLOGY_MODIFIER_RIVERBANK := 2
const HYDROLOGY_MODIFIER_LAKESIDE := 3
const HYDROLOGY_MODIFIER_PONDSIDE := 4
const STAGE11_HYDROLOGY_MODIFIER_COUNT := 5
const STAGE11_WATER_MARGIN_RADIUS := 1

# Stage 10 already rendered terrain at sea level + 1 as sand. Stage 11 extends
# the one-cell physical-ocean margin modestly uphill so coast expression is a
# visible new beach band rather than a no-op, while steep coast remains geology.
const STAGE11_COAST_BEACH_MAX_ELEVATION := SEA_LEVEL + 5
const STAGE11_COAST_BEACH_MAX_SLOPE := 2.0
const STAGE11_RIPARIAN_TREE_SALT := 0x6f13b9d1


func hydrology_modifier_name(modifier: int) -> String:
	match modifier:
		HYDROLOGY_MODIFIER_NONE:
			return "none"
		HYDROLOGY_MODIFIER_COAST:
			return "coast"
		HYDROLOGY_MODIFIER_RIVERBANK:
			return "riverbank"
		HYDROLOGY_MODIFIER_LAKESIDE:
			return "lakeside"
		HYDROLOGY_MODIFIER_PONDSIDE:
			return "pondside"
		_:
			return "unknown"


func _stage11_modifier_for_neighbor_water(water_type: int) -> int:
	match water_type:
		WATER_RIVER:
			return HYDROLOGY_MODIFIER_RIVERBANK
		WATER_LAKE:
			return HYDROLOGY_MODIFIER_LAKESIDE
		WATER_POND:
			return HYDROLOGY_MODIFIER_PONDSIDE
		WATER_OCEAN:
			return HYDROLOGY_MODIFIER_COAST
		_:
			return HYDROLOGY_MODIFIER_NONE


func _stage11_modifier_priority(modifier: int) -> int:
	# River mouths should read as riparian where river water is present; enclosed
	# lake/pond margins outrank generic ocean coast when contexts touch.
	match modifier:
		HYDROLOGY_MODIFIER_RIVERBANK:
			return 4
		HYDROLOGY_MODIFIER_LAKESIDE:
			return 3
		HYDROLOGY_MODIFIER_PONDSIDE:
			return 2
		HYDROLOGY_MODIFIER_COAST:
			return 1
		_:
			return 0


func stage11_hydrology_modifier_at(x: int, z: int) -> int:
	if water_type_at(x, z) != WATER_NONE:
		return HYDROLOGY_MODIFIER_NONE
	var best_modifier: int = HYDROLOGY_MODIFIER_NONE
	var best_priority: int = 0
	for dz in range(-STAGE11_WATER_MARGIN_RADIUS, STAGE11_WATER_MARGIN_RADIUS + 1):
		for dx in range(-STAGE11_WATER_MARGIN_RADIUS, STAGE11_WATER_MARGIN_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue
			var modifier: int = _stage11_modifier_for_neighbor_water(
				water_type_at(x + dx, z + dz)
			)
			var priority: int = _stage11_modifier_priority(modifier)
			if priority > best_priority:
				best_priority = priority
				best_modifier = modifier
	return best_modifier


func stage11_is_wet_margin(hydrology_modifier: int) -> bool:
	return (
		hydrology_modifier == HYDROLOGY_MODIFIER_RIVERBANK
		or hydrology_modifier == HYDROLOGY_MODIFIER_LAKESIDE
		or hydrology_modifier == HYDROLOGY_MODIFIER_PONDSIDE
	)


func stage11_surface_block(
	cell: Vector3i,
	height: int,
	biome: int,
	transition_code: int,
	terrain_modifier: int,
	slope: float,
	hydrology_modifier: int
) -> int:
	# Geological cliffs remain authoritative over shoreline decoration.
	if stage9_surface_exposes_stone(cell.x, cell.z, height, terrain_modifier, slope):
		return stage9_surface_block(cell, height, biome, terrain_modifier, slope)

	# A gentle low ocean edge is a physical beach. Keep the treatment narrow and
	# deterministic instead of turning all low continental land into sand.
	if (
		hydrology_modifier == HYDROLOGY_MODIFIER_COAST
		and height <= STAGE11_COAST_BEACH_MAX_ELEVATION
		and slope <= STAGE11_COAST_BEACH_MAX_SLOPE
		and cell.y >= height - 2
	):
		return BLOCK_SAND

	# Immediate river/lake/pond margins are hydrated ground. This is what turns a
	# dry ecology beside real water into a narrow green riparian/lakeside corridor
	# without changing the underlying biome ID.
	if stage11_is_wet_margin(hydrology_modifier) and cell.y >= height - 2:
		return BLOCK_GRASS if cell.y == height else BLOCK_DIRT

	return stage10_surface_block(
		cell,
		height,
		biome,
		transition_code,
		terrain_modifier,
		slope
	)


func _stage11_modifier_allows_tree(
	x: int,
	z: int,
	surface: int,
	terrain_modifier: int,
	slope: float
) -> bool:
	if stage9_surface_exposes_stone(x, z, surface, terrain_modifier, slope):
		return false
	var hash_value: int = absi(_stage8_hash(x, z, STAGE9_TREE_FILTER_SALT))
	match terrain_modifier:
		TERRAIN_MODIFIER_MOUNTAIN:
			if slope >= 3.0 or surface >= STAGE9_TREE_LINE_ELEVATION:
				return false
			return hash_value % 2 == 0
		TERRAIN_MODIFIER_PLATEAU:
			return hash_value % 3 != 0
		TERRAIN_MODIFIER_HILL:
			return hash_value % 5 != 0
		_:
			return true


func _stage11_boost_tree_biome(biome: int, hydrology_modifier: int) -> int:
	match hydrology_modifier:
		HYDROLOGY_MODIFIER_RIVERBANK:
			match biome:
				BIOME_DESERT, BIOME_DRY_GRASSLAND, BIOME_PLAINS:
					return BIOME_FOREST
				BIOME_FOREST:
					return BIOME_DENSE_FOREST
		HYDROLOGY_MODIFIER_LAKESIDE:
			match biome:
				BIOME_DESERT, BIOME_DRY_GRASSLAND:
					return BIOME_PLAINS
				BIOME_PLAINS:
					return BIOME_FOREST
				BIOME_FOREST:
					return BIOME_DENSE_FOREST
		HYDROLOGY_MODIFIER_PONDSIDE:
			match biome:
				BIOME_DESERT, BIOME_DRY_GRASSLAND:
					return BIOME_PLAINS
				BIOME_PLAINS:
					return BIOME_FOREST
	return biome


func stage11_tree_candidate_for_biome(
	x: int,
	z: int,
	surface: int,
	biome: int,
	transition_code: int,
	terrain_modifier: int,
	slope: float,
	hydrology_modifier: int
) -> bool:
	if hydrology_modifier == HYDROLOGY_MODIFIER_NONE:
		return stage10_tree_candidate_for_biome(
			x, z, surface, biome, transition_code, terrain_modifier, slope
		)

	# Beaches stay open; higher/steeper coast keeps the accepted Stage 10 ecology.
	if hydrology_modifier == HYDROLOGY_MODIFIER_COAST:
		if stage11_surface_block(
			Vector3i(x, surface, z),
			surface,
			biome,
			transition_code,
			terrain_modifier,
			slope,
			hydrology_modifier
		) != BLOCK_GRASS:
			return false
		return stage10_tree_candidate_for_biome(
			x, z, surface, biome, transition_code, terrain_modifier, slope
		)

	# Preserve every Stage 10 tree that remains valid on hydrated ground.
	if stage10_tree_candidate_for_biome(
		x, z, surface, biome, transition_code, terrain_modifier, slope
	):
		return true

	if not stage11_is_wet_margin(hydrology_modifier):
		return false
	if stage11_surface_block(
		Vector3i(x, surface, z),
		surface,
		biome,
		transition_code,
		terrain_modifier,
		slope,
		hydrology_modifier
	) != BLOCK_GRASS:
		return false
	if not _stage11_modifier_allows_tree(x, z, surface, terrain_modifier, slope):
		return false

	var boost_biome: int = _stage11_boost_tree_biome(biome, hydrology_modifier)
	if boost_biome == biome:
		return false
	if not stage8_tree_candidate_for_biome(x, z, surface, boost_biome):
		return false

	var boost_hash: int = absi(_stage8_hash(x, z, STAGE11_RIPARIAN_TREE_SALT))
	match hydrology_modifier:
		HYDROLOGY_MODIFIER_RIVERBANK:
			return boost_hash % 3 != 0
		HYDROLOGY_MODIFIER_LAKESIDE:
			return boost_hash % 2 == 0
		HYDROLOGY_MODIFIER_PONDSIDE:
			return boost_hash % 3 == 0
		_:
			return false


func is_tree_origin_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	var transition_code: int = stage10_transition_code_at(x, z)
	var terrain_modifier: int = stage9_terrain_modifier_at(x, z)
	var hydrology_modifier: int = stage11_hydrology_modifier_at(x, z)
	var slope: float = stage7_surface_slope_at(x, z, surface)
	return stage11_tree_candidate_for_biome(
		x,
		z,
		surface,
		biome,
		transition_code,
		terrain_modifier,
		slope,
		hydrology_modifier
	)


func generated_tree_block(cell: Vector3i) -> int:
	# Stage 11 changes eligibility, not the six accepted Stage 8 silhouettes.
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


func stage11_water_context_at(x: int, z: int) -> Dictionary:
	var context: Dictionary = stage10_region_context_at(x, z)
	var hydrology_modifier: int = stage11_hydrology_modifier_at(x, z)
	context["hydrology_modifier"] = hydrology_modifier
	context["hydrology_modifier_name"] = hydrology_modifier_name(hydrology_modifier)
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
	var biome: int = classify_biome(climate, cell.x, cell.z)
	if cell.y <= height:
		if cell.y < height - 2:
			return stage8_surface_block(cell, height, biome)
		var terrain_modifier: int = stage9_terrain_modifier_from_fields(
			fields.x, fields.y, water_type
		)
		var slope: float = stage7_surface_slope_at(cell.x, cell.z, height)
		var transition_code: int = stage10_transition_code_for_climate(climate, water_type)
		var hydrology_modifier: int = stage11_hydrology_modifier_at(cell.x, cell.z)
		return stage11_surface_block(
			cell,
			height,
			biome,
			transition_code,
			terrain_modifier,
			slope,
			hydrology_modifier
		)
	return generated_tree_block(cell)
