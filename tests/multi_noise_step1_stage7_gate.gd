extends "res://tests/multi_noise_step1_stage3_gate.gd"

# Stage 7 runs the full historical multi-noise transaction against the modern
# Stage 6 hydrology contract. The old parent scan assumes every water column is
# below the single global sea level, which became invalid when Stage 6 added
# contained inland lakes and ponds with local water surfaces above sea level.
# Keep the same scan and gameplay assertions, but validate water against the
# shipping topology itself: every classified water surface must clear its
# generated terrain basin floor.
func _scan_static_integration() -> Dictionary:
	var water_columns := 0
	var dry_columns := 0
	var tree_origins := 0
	var plains_trees := 0
	var forest_trees := 0
	var verified_canopies := 0
	var water_fixture := INVALID_FIXTURE
	var dry_fixture := INVALID_FIXTURE
	var tree_fixture := INVALID_FIXTURE
	var tree_access := Vector2i.ZERO

	for z in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var surface: int = data.terrain_height(x, z)
			var biome: int = data.biome_at(x, z)
			var water_info: Vector2i = LOCALIZED_WATER.water_info(data, x, z)
			var water := water_info.x != 0
			if water:
				water_columns += 1
				if water_fixture == INVALID_FIXTURE:
					water_fixture = Vector2i(x, z)
				if water_info.y <= surface:
					_fail(
						"Water surface failed to clear its terrain basin at (%d, %d): surface=%d water_level=%d type=%d"
						% [x, z, surface, water_info.y, water_info.x]
					)
			elif surface >= WORLD_DATA.SEA_LEVEL + 2:
				dry_columns += 1
				if dry_fixture == INVALID_FIXTURE:
					dry_fixture = Vector2i(x, z)

			if not data.is_tree_origin_for_biome(x, z, surface, biome):
				continue
			tree_origins += 1
			if biome == WORLD_DATA.BIOME_PLAINS:
				plains_trees += 1
			elif biome == WORLD_DATA.BIOME_FOREST:
				forest_trees += 1
			else:
				_fail("A tree origin appeared in %s at (%d, %d)" % [data.biome_name(biome), x, z])
			if data.get_block(Vector3i(x, surface, z)) != BLOCK_GRASS:
				_fail("A generated tree is not rooted on grass at (%d, %d)" % [x, z])
			if data.get_block(Vector3i(x, surface + 1, z)) != BLOCK_LOG:
				_fail("A generated tree has no mineable base log at (%d, %d)" % [x, z])
			if _count_canopy_leaves(Vector2i(x, z), surface) > 0:
				verified_canopies += 1
			else:
				_fail("A generated tree has no canopy leaves at (%d, %d)" % [x, z])
			if tree_fixture == INVALID_FIXTURE:
				var access: Vector2i = _find_tree_access(Vector2i(x, z), surface)
				if access != Vector2i.ZERO:
					tree_fixture = Vector2i(x, z)
					tree_access = access

	if water_columns <= 0 or water_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no localized water body")
	if dry_columns <= 0 or dry_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no dry terrain")
	if tree_origins <= 0 or plains_trees <= 0 or forest_trees <= 0:
		_fail("Step 5 scan did not retain both plains and forest trees")
	if verified_canopies != tree_origins:
		_fail("Not every generated tree retained a canopy")
	if tree_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no side-accessible base log")

	var placement_fixture := INVALID_FIXTURE
	if tree_fixture != INVALID_FIXTURE:
		placement_fixture = _find_placement_fixture(tree_fixture)
	if placement_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no placement fixture near the generated tree")

	var water_mesh: Dictionary = _validate_water_mesh(water_fixture)
	var dry_chunk: Dictionary = _find_dry_chunk()
	return {
		"scan_radius": SCAN_RADIUS,
		"water_columns": water_columns,
		"dry_columns": dry_columns,
		"tree_origins": tree_origins,
		"plains_trees": plains_trees,
		"forest_trees": forest_trees,
		"verified_canopies": verified_canopies,
		"water_fixture": [water_fixture.x, water_fixture.y],
		"dry_fixture": [dry_fixture.x, dry_fixture.y],
		"tree_fixture": [tree_fixture.x, tree_fixture.y],
		"tree_access": [tree_access.x, tree_access.y],
		"placement_fixture": [placement_fixture.x, placement_fixture.y],
		"water_mesh": water_mesh,
		"dry_chunk": dry_chunk,
	}
