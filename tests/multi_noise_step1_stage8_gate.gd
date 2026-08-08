extends "res://tests/multi_noise_step1_stage7_gate.gd"

# Stage 8 expands the canonical tree-supporting ecology set and introduces
# biome-specific trunk/canopy heights. Keep the historical shipping transaction,
# but discover fixtures against the Stage 8 ecology/expression contract.
func _scan_static_integration() -> Dictionary:
	var water_columns := 0
	var dry_columns := 0
	var tree_origins := 0
	var verified_canopies := 0
	var tree_counts: Dictionary = {}
	var water_fixture := INVALID_FIXTURE
	var dry_fixture := INVALID_FIXTURE
	var tree_fixture := INVALID_FIXTURE
	var tree_access := Vector2i.ZERO
	var tree_biomes: Array[int] = [
		data.BIOME_PLAINS,
		data.BIOME_FOREST,
		data.BIOME_DENSE_FOREST,
		data.BIOME_DRY_GRASSLAND,
		data.BIOME_COLD_FOREST,
	]

	for z in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var surface: int = data.terrain_height(x, z)
			var biome: int = data.biome_at(x, z)
			var water_info: Vector2i = LOCALIZED_WATER.water_info(data, x, z)
			var water: bool = water_info.x != 0
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

			if not bool(data.is_tree_origin(x, z)):
				continue
			tree_origins += 1
			tree_counts[data.biome_name(biome)] = int(tree_counts.get(data.biome_name(biome), 0)) + 1
			if not tree_biomes.has(biome):
				_fail(
					"A canonical tree origin appeared in non-tree Stage 8 ecology %s at (%d, %d)"
					% [data.biome_name(biome), x, z]
				)
			if data.get_block(Vector3i(x, surface, z)) != BLOCK_GRASS:
				_fail("A Stage 8 generated tree is not rooted on grass at (%d, %d)" % [x, z])
			if data.get_block(Vector3i(x, surface + 1, z)) != BLOCK_LOG:
				_fail("A Stage 8 generated tree has no mineable base log at (%d, %d)" % [x, z])
			if _count_canopy_leaves(Vector2i(x, z), surface) > 0:
				verified_canopies += 1
			else:
				_fail("A Stage 8 generated tree has no canopy leaves at (%d, %d)" % [x, z])
			if tree_fixture == INVALID_FIXTURE:
				var access: Vector2i = _find_tree_access(Vector2i(x, z), surface)
				if access != Vector2i.ZERO:
					tree_fixture = Vector2i(x, z)
					tree_access = access

	if water_columns <= 0 or water_fixture == INVALID_FIXTURE:
		_fail("Stage 8 shipping scan found no physical water body")
	if dry_columns <= 0 or dry_fixture == INVALID_FIXTURE:
		_fail("Stage 8 shipping scan found no dry terrain")
	if tree_origins <= 0:
		_fail("Stage 8 shipping scan found no canonical generated tree")
	if verified_canopies != tree_origins:
		_fail("Not every Stage 8 generated tree retained a canopy")
	if tree_fixture == INVALID_FIXTURE:
		_fail("Stage 8 shipping scan found no side-accessible base log")

	var placement_fixture := INVALID_FIXTURE
	if tree_fixture != INVALID_FIXTURE:
		placement_fixture = _find_placement_fixture(tree_fixture)
	if placement_fixture == INVALID_FIXTURE:
		_fail("Stage 8 shipping scan found no placement fixture near the generated tree")

	var water_mesh: Dictionary = _validate_water_mesh(water_fixture)
	var dry_chunk: Dictionary = _find_dry_chunk()
	return {
		"scan_radius": SCAN_RADIUS,
		"water_columns": water_columns,
		"dry_columns": dry_columns,
		"tree_origins": tree_origins,
		"tree_counts": tree_counts,
		"verified_canopies": verified_canopies,
		"tree_distribution_note": "Stage 8 accepts every admitted tree-supporting ecology",
		"water_fixture": [water_fixture.x, water_fixture.y],
		"dry_fixture": [dry_fixture.x, dry_fixture.y],
		"tree_fixture": [tree_fixture.x, tree_fixture.y],
		"tree_access": [tree_access.x, tree_access.y],
		"placement_fixture": [placement_fixture.x, placement_fixture.y],
		"water_mesh": water_mesh,
		"dry_chunk": dry_chunk,
	}


func _count_canopy_leaves(origin: Vector2i, surface: int) -> int:
	var biome: int = data.biome_at(origin.x, origin.y)
	var trunk_top: int = surface + data.stage8_tree_trunk_height(biome)
	var count := 0
	for z_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			for y_offset in range(-2, 3):
				if data.get_block(Vector3i(
					origin.x + x_offset,
					trunk_top + y_offset,
					origin.y + z_offset
				)) == BLOCK_LEAVES:
					count += 1
	return count
