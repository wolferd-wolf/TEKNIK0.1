extends "res://tests/multi_noise_step1_stage3_gate.gd"

# Stage 7 deliberately replaces the old small probabilistic biome patches with
# slow deterministic climate regions. The historical Step 5 integration still
# provides useful water/tree/mining/placement coverage, but two distribution-era
# assumptions are no longer valid:
#   * every water surface is the global sea level;
#   * a 257x257 near-spawn scan must contain trees from both Plains and Forest.
#
# The pre-overhaul Step 4 performance benchmark is also intentionally not used
# as the shipping performance authority here. It times the retired
# playable_world_data.gd blend implementation (640 measurements per path), not
# the current staged generator. Stage 7 has its own 320-sample <1.0 ms gate on
# the actual shipping cache. We keep the historical Step 4 correctness and
# distribution assertions below, then execute the full modern shipping
# transaction.
func _run_gate() -> void:
	data = WORLD_DATA.new()
	STEP4_CONTRACT.run(data, failures)
	step4_distribution = STEP4_DISTRIBUTION.run(data, failures)
	STEP4_INTEGRATION.run(data, failures)
	if not failures.is_empty():
		_finish()
		return

	data = SHIPPING_DATA.new()
	var report: Dictionary = _scan_static_integration()
	if not failures.is_empty():
		_finish()
		return

	await _run_shipping_scene_transaction(report)
	if not failures.is_empty():
		_finish()
		return

	var distribution_report: Dictionary = step4_distribution.duplicate(true)
	distribution_report.erase("fixtures")
	print("MULTI_NOISE_STEP4_DISTRIBUTION_JSON=%s" % JSON.stringify(distribution_report))
	print(
		"MULTI_NOISE_STEP4_BENCHMARK_JSON=%s"
		% JSON.stringify({
			"compatibility": "legacy pre-overhaul performance oracle not used as Stage 7 shipping gate",
			"shipping_gate": "WORLD_OVERHAUL_STAGE7_BIOME_GATE",
			"shipping_p95_limit_usec": 1000,
		})
	)
	print("MULTI_NOISE_STEP4_GATE_PASS")
	print("MULTI_NOISE_STEP5_INTEGRATION_JSON=%s" % JSON.stringify(report))
	print("MULTI_NOISE_STEP5_GATE_PASS")
	print(
		"MULTI_NOISE_STEP1_BENCHMARK_JSON=%s"
		% JSON.stringify({
			"compatibility": "stage7-full-shipping-integration",
			"shipping_performance_gate": "WORLD_OVERHAUL_STAGE7_BIOME_GATE",
		})
	)
	print("MULTI_NOISE_STEP1_GATE_PASS")
	_finish()


# This wrapper keeps the full shipping transaction while validating the modern
# contracts: local water containment, at least one canonical generated tree,
# tree origins only in tree-supporting ecologies, and intact canopies.
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
			else:
				if surface >= WORLD_DATA.SEA_LEVEL + 2:
					dry_columns += 1
					if dry_fixture == INVALID_FIXTURE:
						dry_fixture = Vector2i(x, z)

			# Use the canonical shipping predicate. Stage 6+ intentionally suppresses
			# otherwise-valid tree hashes in physical water columns.
			if not bool(data.is_tree_origin(x, z)):
				continue
			tree_origins += 1
			if biome == WORLD_DATA.BIOME_PLAINS:
				plains_trees += 1
			elif biome == WORLD_DATA.BIOME_FOREST:
				forest_trees += 1
			else:
				_fail(
					"A canonical tree origin appeared in non-tree ecology %s at (%d, %d)"
					% [data.biome_name(biome), x, z]
				)
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
		_fail("Stage 7 shipping scan found no physical water body")
	if dry_columns <= 0 or dry_fixture == INVALID_FIXTURE:
		_fail("Stage 7 shipping scan found no dry terrain")
	if tree_origins <= 0:
		_fail("Stage 7 shipping scan found no canonical generated tree")
	if verified_canopies != tree_origins:
		_fail("Not every generated tree retained a canopy")
	if tree_fixture == INVALID_FIXTURE:
		_fail("Stage 7 shipping scan found no side-accessible base log")

	var placement_fixture := INVALID_FIXTURE
	if tree_fixture != INVALID_FIXTURE:
		placement_fixture = _find_placement_fixture(tree_fixture)
	if placement_fixture == INVALID_FIXTURE:
		_fail("Stage 7 shipping scan found no placement fixture near the generated tree")

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
		"tree_distribution_note": "Stage 7 slow climate regions do not require both tree ecologies near spawn",
		"water_fixture": [water_fixture.x, water_fixture.y],
		"dry_fixture": [dry_fixture.x, dry_fixture.y],
		"tree_fixture": [tree_fixture.x, tree_fixture.y],
		"tree_access": [tree_access.x, tree_access.y],
		"placement_fixture": [placement_fixture.x, placement_fixture.y],
		"water_mesh": water_mesh,
		"dry_chunk": dry_chunk,
	}