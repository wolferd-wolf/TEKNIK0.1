extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage8_biome_data.gd")
const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
const STAGE8_CACHE := preload("res://scripts/world/playable_world_stage8_cache_fast.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const FIELD_STRIDE := 6
const P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var contract: Dictionary = _validate_contract(data)
	var synthetic: Dictionary = _validate_synthetic_classifier(data)
	var world_audit: Dictionary = _audit_world(data)
	var expression: Dictionary = _validate_expression_contract(data, world_audit)
	var equivalence: Dictionary = _validate_equivalence(data, runtime)
	var seams: Dictionary = _validate_seams(runtime)
	var determinism: Dictionary = _validate_determinism(data)
	var benchmark: Dictionary = _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail(
			"Stage 8 generation exceeded the 1.0 ms p95 gate: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"contract": contract,
		"synthetic": synthetic,
		"world_audit": world_audit,
		"expression": expression,
		"equivalence": equivalence,
		"seams": seams,
		"determinism": determinism,
		"benchmark": benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE8_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE8_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _active_biomes() -> Array[int]:
	return [
		DATA.BIOME_PLAINS,
		DATA.BIOME_FOREST,
		DATA.BIOME_DENSE_FOREST,
		DATA.BIOME_DESERT,
		DATA.BIOME_DRY_GRASSLAND,
		DATA.BIOME_COLD_FOREST,
	]


func _validate_contract(_data) -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 8 lost the 150-block legal height")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY != 0.0012:
		_fail("Stage 8 changed the accepted slow temperature field")
	if DATA.BIOME_MOISTURE_NOISE_FREQUENCY != 0.0014:
		_fail("Stage 8 changed the accepted slow moisture field")
	if DATA.STAGE8_ACTIVE_BIOME_COUNT != 6:
		_fail("Stage 8 did not admit exactly six readable land ecologies")
	if _active_biomes().has(DATA.BIOME_ROCKY):
		_fail("Stage 8 still treats Rocky as a base ecology")
	var data_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage8_biome_data.gd"
	)
	var cache_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage8_cache_fast.gd"
	)
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 8 added a new noise stack")
	if cache_source.contains("get_noise_2d"):
		_fail("Stage 8 ecology pass resamples noise instead of reusing Stage 7 fields")
	if not cache_source.contains("STAGE7_CACHE.build"):
		_fail("Stage 8 no longer preserves the accepted Stage 7 geography cache")
	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"temperature_frequency": DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY,
		"moisture_frequency": DATA.BIOME_MOISTURE_NOISE_FREQUENCY,
		"active_biome_count": DATA.STAGE8_ACTIVE_BIOME_COUNT,
		"reserved_rocky_id": DATA.BIOME_ROCKY,
	}


func _validate_synthetic_classifier(data) -> Dictionary:
	var targets: Array = [
		[DATA.STAGE8_PLAINS_TARGET, DATA.BIOME_PLAINS],
		[DATA.STAGE8_FOREST_TARGET, DATA.BIOME_FOREST],
		[DATA.STAGE8_DENSE_FOREST_TARGET, DATA.BIOME_DENSE_FOREST],
		[DATA.STAGE8_DESERT_TARGET, DATA.BIOME_DESERT],
		[DATA.STAGE8_DRY_GRASSLAND_TARGET, DATA.BIOME_DRY_GRASSLAND],
		[DATA.STAGE8_COLD_FOREST_TARGET, DATA.BIOME_COLD_FOREST],
	]
	var resolved: Array[int] = []
	for entry in targets:
		var climate: Vector2 = entry[0]
		var expected: int = int(entry[1])
		var actual: int = data.stage8_classify_with_context(
			climate, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0
		)
		resolved.append(actual)
		if actual != expected:
			_fail(
				"Stage 8 prototype %s selected %s instead of itself"
				% [data.biome_name(expected), data.biome_name(actual)]
			)

	var water_dense: int = data.stage8_classify_with_context(
		DATA.STAGE8_DENSE_FOREST_TARGET,
		1.0,
		8.0,
		50,
		DATA.WATER_LAKE,
		0.0
	)
	if water_dense != DATA.BIOME_PLAINS:
		_fail("Physical water was allowed to select a non-neutral Stage 8 ecology")

	var dry_flat: int = data.stage8_classify_with_context(
		DATA.STAGE8_DRY_GRASSLAND_TARGET, 0.0, 0.0, 15, DATA.WATER_NONE, 0.0
	)
	var dry_mountain: int = data.stage8_classify_with_context(
		DATA.STAGE8_DRY_GRASSLAND_TARGET, 1.0, 12.0, 90, DATA.WATER_NONE, 0.0
	)
	if dry_flat != dry_mountain:
		_fail("Stage 8 base ecology changes when only terrain context changes")
	if resolved.has(DATA.BIOME_ROCKY) or dry_mountain == DATA.BIOME_ROCKY:
		_fail("Stage 8 classifier still emits the legacy Rocky ecology")

	return {
		"resolved_targets": resolved,
		"water_dense_forest": water_dense,
		"terrain_context_invariant": dry_flat == dry_mountain,
	}


func _audit_world(data) -> Dictionary:
	# Broad fixed geography is required because accepted climate fields are slow.
	var chunk_axis: Array[int] = [-128, -96, -64, -32, 0, 32, 64, 96, 128]
	var counts := PackedInt32Array()
	counts.resize(DATA.STAGE8_MAX_BIOME_ID + 1)
	var land_counts := PackedInt32Array()
	land_counts.resize(DATA.STAGE8_MAX_BIOME_ID + 1)
	var tree_counts := PackedInt32Array()
	tree_counts.resize(DATA.STAGE8_MAX_BIOME_ID + 1)
	var water_columns := 0
	var rocky_columns := 0
	var dry_sand_columns := 0
	var cold_stone_columns := 0
	var total_columns := 0
	var fixtures: Dictionary = {}

	for chunk_z: int in chunk_axis:
		for chunk_x: int in chunk_axis:
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = STAGE8_CACHE.build(coord, data)
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			if (
				biomes.size() != WIDTH * WIDTH
				or water_types.size() != WIDTH * WIDTH
				or heights.size() != WIDTH * WIDTH
			):
				_fail("Stage 8 cache arrays have the wrong padded size")
				continue
			var origin_x: int = coord.x * CHUNK_SIZE
			var origin_z: int = coord.y * CHUNK_SIZE
			for local_z in range(PADDING, PADDING + CHUNK_SIZE):
				for local_x in range(PADDING, PADDING + CHUNK_SIZE):
					var index: int = local_z * WIDTH + local_x
					var biome: int = int(biomes[index])
					if biome < 0 or biome > DATA.STAGE8_MAX_BIOME_ID:
						_fail("Stage 8 produced an invalid biome ID")
						continue
					counts[biome] += 1
					total_columns += 1
					if biome == DATA.BIOME_ROCKY:
						rocky_columns += 1
					var water_type: int = int(water_types[index])
					if water_type != DATA.WATER_NONE:
						water_columns += 1
						if biome != DATA.BIOME_PLAINS:
							_fail("Physical water selected a non-neutral Stage 8 ecology")
						continue

					land_counts[biome] += 1
					var world_x: int = origin_x + local_x - PADDING
					var world_z: int = origin_z + local_z - PADDING
					var surface: int = int(heights[index])
					if data.stage8_tree_candidate_for_biome(world_x, world_z, surface, biome):
						tree_counts[biome] += 1
						var tree_key: String = "%d_tree" % biome
						if not fixtures.has(tree_key):
							fixtures[tree_key] = [world_x, world_z, surface]
					if biome == DATA.BIOME_DRY_GRASSLAND and data.stage8_dry_surface_is_sand(world_x, world_z):
						dry_sand_columns += 1
						if not fixtures.has("dry_sand"):
							fixtures["dry_sand"] = [world_x, world_z, surface]
					if biome == DATA.BIOME_COLD_FOREST and data.stage8_cold_surface_is_stone(world_x, world_z):
						cold_stone_columns += 1
						if not fixtures.has("cold_stone"):
							fixtures["cold_stone"] = [world_x, world_z, surface]

	for biome_id: int in _active_biomes():
		if land_counts[biome_id] < 24:
			_fail(
				"Stage 8 broad world audit did not form a readable %s region"
				% data.biome_name(biome_id)
			)
	if rocky_columns != 0:
		_fail("Legacy Rocky still appears in Stage 8 shipping output")
	if water_columns <= 0:
		_fail("Stage 8 broad audit did not exercise physical water")
	if dry_sand_columns <= 0:
		_fail("Dry Grassland never produced its sand ground cue")
	if cold_stone_columns <= 0:
		_fail("Cold Forest never produced its exposed-stone ground cue")
	if tree_counts[DATA.BIOME_DESERT] != 0:
		_fail("Desert produced generated trees")

	var density: Dictionary = {}
	for biome_id: int in _active_biomes():
		var land: int = int(land_counts[biome_id])
		density[data.biome_name(biome_id)] = (
			float(tree_counts[biome_id]) / float(land) if land > 0 else 0.0
		)
	var plains_density: float = float(density.get("plains", 0.0))
	var forest_density: float = float(density.get("forest", 0.0))
	var dense_density: float = float(density.get("dense_forest", 0.0))
	var dry_density: float = float(density.get("dry_grassland", 0.0))
	var cold_density: float = float(density.get("cold_forest", 0.0))
	if not (dense_density > forest_density and forest_density > plains_density):
		_fail("Stage 8 forest density hierarchy is not Dense > Forest > Plains")
	if dry_density >= plains_density:
		_fail("Dry Grassland is not more open than Plains")
	if cold_density <= plains_density:
		_fail("Cold Forest is not visibly more wooded than Plains")

	var count_report: Array[int] = []
	var land_report: Array[int] = []
	var tree_report: Array[int] = []
	for biome_id in range(DATA.STAGE8_MAX_BIOME_ID + 1):
		count_report.append(int(counts[biome_id]))
		land_report.append(int(land_counts[biome_id]))
		tree_report.append(int(tree_counts[biome_id]))
	return {
		"columns": total_columns,
		"counts_by_id": count_report,
		"land_counts_by_id": land_report,
		"tree_counts_by_id": tree_report,
		"tree_density": density,
		"water_columns": water_columns,
		"rocky_columns": rocky_columns,
		"dry_sand_columns": dry_sand_columns,
		"cold_stone_columns": cold_stone_columns,
		"fixtures": fixtures,
	}


func _validate_expression_contract(data, world_audit: Dictionary) -> Dictionary:
	if data.stage8_tree_trunk_height(DATA.BIOME_DENSE_FOREST) <= data.stage8_tree_trunk_height(DATA.BIOME_FOREST):
		_fail("Dense Forest trees are not taller than ordinary Forest trees")
	if data.stage8_tree_trunk_height(DATA.BIOME_COLD_FOREST) <= data.stage8_tree_trunk_height(DATA.BIOME_FOREST):
		_fail("Cold Forest trees are not taller than ordinary Forest trees")
	if data.stage8_tree_trunk_height(DATA.BIOME_DRY_GRASSLAND) >= data.stage8_tree_trunk_height(DATA.BIOME_PLAINS):
		_fail("Dry Grassland trees are not shorter than Plains trees")
	if not data.stage8_tree_canopy_contains(1, 1, -2, DATA.BIOME_DENSE_FOREST):
		_fail("Dense Forest is missing its deep canopy cue")
	if data.stage8_tree_canopy_contains(1, 1, -1, DATA.BIOME_DRY_GRASSLAND):
		_fail("Dry Grassland canopy is not visibly flat")
	if data.stage8_tree_canopy_contains(1, 1, 0, DATA.BIOME_COLD_FOREST):
		_fail("Cold Forest top canopy is not narrow/conifer-like")
	if not data.stage8_tree_canopy_contains(0, 0, 1, DATA.BIOME_COLD_FOREST):
		_fail("Cold Forest is missing its conifer tip")

	var fixtures: Dictionary = world_audit.get("fixtures", {})
	for entry in [
		["dry_sand", DATA.BIOME_DRY_GRASSLAND, DATA.BLOCK_SAND],
		["cold_stone", DATA.BIOME_COLD_FOREST, DATA.BLOCK_STONE],
	]:
		var key: String = entry[0]
		if not fixtures.has(key):
			continue
		var values: Array = fixtures[key]
		var cell := Vector3i(int(values[0]), int(values[2]), int(values[1]))
		var actual: int = data.stage8_surface_block(cell, cell.y, int(entry[1]))
		if actual != int(entry[2]):
			_fail("Stage 8 ground cue helper disagrees with its fixture: %s" % key)

	for biome_id in [DATA.BIOME_DENSE_FOREST, DATA.BIOME_DRY_GRASSLAND, DATA.BIOME_COLD_FOREST]:
		var key: String = "%d_tree" % biome_id
		if not fixtures.has(key):
			_fail("Stage 8 found no generated tree fixture for %s" % data.biome_name(biome_id))
			continue
		var values: Array = fixtures[key]
		var x: int = int(values[0])
		var z: int = int(values[1])
		var surface: int = int(values[2])
		if data.get_block(Vector3i(x, surface, z)) != DATA.BLOCK_GRASS:
			_fail("Stage 8 generated tree is not rooted on grass in %s" % data.biome_name(biome_id))
		if data.get_block(Vector3i(x, surface + 1, z)) != DATA.BLOCK_LOG:
			_fail("Stage 8 generated tree has no mineable base log in %s" % data.biome_name(biome_id))

	return {
		"dense_trunk_height": data.stage8_tree_trunk_height(DATA.BIOME_DENSE_FOREST),
		"dry_trunk_height": data.stage8_tree_trunk_height(DATA.BIOME_DRY_GRASSLAND),
		"cold_trunk_height": data.stage8_tree_trunk_height(DATA.BIOME_COLD_FOREST),
		"fixtures_checked": fixtures.size(),
	}


func _validate_equivalence(data, runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(4, -3),
		Vector2i(-7, 6),
		Vector2i(15, 12),
	]
	var height_columns := 0
	var biome_columns := 0
	for coord: Vector2i in coords:
		var stage7: Dictionary = STAGE7_CACHE.build(coord, data)
		var stage8: Dictionary = runtime._build_column_caches(coord)
		var heights7: PackedInt32Array = stage7.get("heights", PackedInt32Array())
		var heights8: PackedInt32Array = stage8.get("heights", PackedInt32Array())
		if heights7 != heights8:
			_fail("Stage 8 changed Stage 7 terrain/hydrology heights in chunk %s" % coord)
		var biomes8: PackedByteArray = stage8.get("biomes", PackedByteArray())
		var origin_x: int = coord.x * CHUNK_SIZE
		var origin_z: int = coord.y * CHUNK_SIZE
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				var index: int = (local_z + PADDING) * WIDTH + local_x + PADDING
				var world_x: int = origin_x + local_x
				var world_z: int = origin_z + local_z
				var expected: int = data.biome_at(world_x, world_z)
				if int(biomes8[index]) != expected:
					_fail("Stage 8 cache/public biome mismatch at (%d,%d)" % [world_x, world_z])
				biome_columns += 1
				height_columns += 1
	return {
		"chunks": coords.size(),
		"height_columns": height_columns,
		"biome_columns": biome_columns,
	}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	return (world_z - min_z) * WIDTH + (world_x - min_x)


func _validate_seams(runtime) -> Dictionary:
	var pairs: Array = [
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
		[Vector2i(-4, 3), Vector2i(-3, 3)],
		[Vector2i(7, -6), Vector2i(7, -5)],
	]
	var comparisons := 0
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var cache_a: Dictionary = runtime._build_column_caches(a)
		var cache_b: Dictionary = runtime._build_column_caches(b)
		var biomes_a: PackedByteArray = cache_a.get("biomes", PackedByteArray())
		var biomes_b: PackedByteArray = cache_b.get("biomes", PackedByteArray())
		var heights_a: PackedInt32Array = cache_a.get("heights", PackedInt32Array())
		var heights_b: PackedInt32Array = cache_b.get("heights", PackedInt32Array())
		var min_ax: int = a.x * CHUNK_SIZE - PADDING
		var min_az: int = a.y * CHUNK_SIZE - PADDING
		var max_ax: int = min_ax + WIDTH - 1
		var max_az: int = min_az + WIDTH - 1
		var min_bx: int = b.x * CHUNK_SIZE - PADDING
		var min_bz: int = b.y * CHUNK_SIZE - PADDING
		var max_bx: int = min_bx + WIDTH - 1
		var max_bz: int = min_bz + WIDTH - 1
		for z in range(maxi(min_az, min_bz), mini(max_az, max_bz) + 1):
			for x in range(maxi(min_ax, min_bx), mini(max_ax, max_bx) + 1):
				var ia: int = _cache_index(a, x, z)
				var ib: int = _cache_index(b, x, z)
				if int(biomes_a[ia]) != int(biomes_b[ib]):
					_fail("Stage 8 biome seam mismatch at (%d,%d)" % [x, z])
				if int(heights_a[ia]) != int(heights_b[ib]):
					_fail("Stage 8 height seam mismatch at (%d,%d)" % [x, z])
				comparisons += 1
	return {"overlap_columns": comparisons}


func _validate_determinism(data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(9, -11), Vector2i(-17, 5)]
	for coord: Vector2i in coords:
		var first: Dictionary = STAGE8_CACHE.build(coord, data)
		var second: Dictionary = STAGE8_CACHE.build(coord, data)
		if first.get("heights") != second.get("heights"):
			_fail("Stage 8 height cache is nondeterministic in %s" % coord)
		if first.get("biomes") != second.get("biomes"):
			_fail("Stage 8 biome cache is nondeterministic in %s" % coord)
		if first.get("stage7_water_types") != second.get("stage7_water_types"):
			_fail("Stage 8 water ownership is nondeterministic in %s" % coord)
	return {"chunks": coords.size()}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			coords.append(Vector2i(x, z))
	for _warmup in range(WARMUPS):
		for coord: Vector2i in coords:
			runtime._build_column_caches(coord)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for coord: Vector2i in coords:
			var started: int = Time.get_ticks_usec()
			var cache: Dictionary = runtime._build_column_caches(coord)
			# Consume output so the benchmark includes completed cache writes.
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var checksum: int = 0
			if not heights.is_empty():
				checksum += int(heights[0]) + int(heights[heights.size() - 1])
			if not biomes.is_empty():
				checksum += int(biomes[0]) + int(biomes[biomes.size() - 1])
			if checksum == -2147483648:
				_fail("Impossible Stage 8 benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	values.sort()
	var total := 0
	for value: int in values:
		total += value
	var p95_index: int = clampi(ceili(float(values.size()) * 0.95) - 1, 0, values.size() - 1)
	return {
		"sample_count": values.size(),
		"minimum_usec": values[0],
		"mean_usec": float(total) / float(values.size()),
		"p95_usec": values[p95_index],
		"p95_ms": float(values[p95_index]) / 1000.0,
		"maximum_usec": values[values.size() - 1],
		"methodology": "16 padded chunks, 4 warmups, 20 repeats; same 320-sample hard gate",
	}
