extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage9_terrain_data.gd")
const STAGE8_CACHE := preload("res://scripts/world/playable_world_stage8_cache_fast.gd")
const STAGE9_CACHE := preload("res://scripts/world/playable_world_stage9_cache_fast.gd")
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
	var contract: Dictionary = _validate_contract()
	var synthetic: Dictionary = _validate_synthetic(data)
	var equivalence: Dictionary = _validate_stage8_equivalence(data, runtime)
	var world_audit: Dictionary = _audit_world(data)
	var seams: Dictionary = _validate_seams(runtime)
	var determinism: Dictionary = _validate_determinism(data)
	var benchmark: Dictionary = _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail(
			"Stage 9 generation exceeded the 1.0 ms p95 gate: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"contract": contract,
		"synthetic": synthetic,
		"stage8_equivalence": equivalence,
		"world_audit": world_audit,
		"seams": seams,
		"determinism": determinism,
		"benchmark": benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE9_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE9_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _validate_contract() -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 9 lost the 150-block legal world height")
	if DATA.STAGE8_ACTIVE_BIOME_COUNT != 6:
		_fail("Stage 9 changed the six accepted Stage 8 base ecologies")
	if DATA.STAGE9_TERRAIN_MODIFIER_COUNT != 5:
		_fail("Stage 9 does not expose exactly five terrain modifier states")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY != 0.0012:
		_fail("Stage 9 changed the accepted slow temperature field")
	if DATA.BIOME_MOISTURE_NOISE_FREQUENCY != 0.0014:
		_fail("Stage 9 changed the accepted slow moisture field")

	var data_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage9_terrain_data.gd"
	)
	var cache_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage9_cache_fast.gd"
	)
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 9 added a new noise stack")
	if cache_source.contains("get_noise_2d"):
		_fail("Stage 9 resamples noise instead of reusing cached Stage 7 fields")
	if not cache_source.contains("STAGE7_CACHE.build"):
		_fail("Stage 9 no longer preserves the accepted fused Stage 7 geography cache")
	if cache_source.contains("STAGE8_CACHE.build"):
		_fail("Stage 9 adds a third cache pass instead of fusing Stage 8 ecology with modifiers")

	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"base_ecology_count": DATA.STAGE8_ACTIVE_BIOME_COUNT,
		"terrain_modifier_count": DATA.STAGE9_TERRAIN_MODIFIER_COUNT,
		"temperature_frequency": DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY,
		"moisture_frequency": DATA.BIOME_MOISTURE_NOISE_FREQUENCY,
		"valley_strength_min": DATA.STAGE9_VALLEY_STRENGTH_MIN,
		"tree_line_elevation": DATA.STAGE9_TREE_LINE_ELEVATION,
	}


func _validate_synthetic(data) -> Dictionary:
	var cases: Array = [
		[0.0, -0.60, DATA.WATER_NONE, DATA.TERRAIN_MODIFIER_NONE],
		[0.0, 0.00, DATA.WATER_NONE, DATA.TERRAIN_MODIFIER_HILL],
		[0.0, 0.28, DATA.WATER_NONE, DATA.TERRAIN_MODIFIER_PLATEAU],
		[0.0, 0.68, DATA.WATER_NONE, DATA.TERRAIN_MODIFIER_MOUNTAIN],
		[0.80, 0.68, DATA.WATER_NONE, DATA.TERRAIN_MODIFIER_VALLEY],
		[0.80, 0.68, DATA.WATER_RIVER, DATA.TERRAIN_MODIFIER_NONE],
	]
	var resolved: Array[int] = []
	for entry in cases:
		var actual: int = data.stage9_terrain_modifier_from_fields(
			float(entry[0]), float(entry[1]), int(entry[2])
		)
		resolved.append(actual)
		if actual != int(entry[3]):
			_fail(
				"Stage 9 synthetic modifier mismatch: expected %s got %s"
				% [data.terrain_modifier_name(int(entry[3])), data.terrain_modifier_name(actual)]
			)

	var dry_flat: int = data.stage8_classify_with_context(
		DATA.STAGE8_DRY_GRASSLAND_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0
	)
	var dry_mountain: int = data.stage8_classify_with_context(
		DATA.STAGE8_DRY_GRASSLAND_TARGET, 1.0, 12.0, 90, DATA.WATER_NONE, 0.0
	)
	if dry_flat != dry_mountain or dry_flat != DATA.BIOME_DRY_GRASSLAND:
		_fail("Stage 9 terrain context changed the Stage 8 base ecology classifier")

	if not data.stage9_surface_exposes_stone(
		12, 12, 55, DATA.TERRAIN_MODIFIER_MOUNTAIN, 3.0
	):
		_fail("Stage 9 steep mountain expression does not expose stone")
	if data.stage9_surface_exposes_stone(
		12, 12, 55, DATA.TERRAIN_MODIFIER_VALLEY, 8.0
	):
		_fail("Stage 9 valley expression incorrectly applies mountain rock treatment")

	return {
		"resolved_modifiers": resolved,
		"base_ecology_invariant": dry_flat == dry_mountain,
		"ridge_valley_strength": data.stage9_valley_strength(0.80, 0.68),
	}


func _validate_stage8_equivalence(data, runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(4, -3),
		Vector2i(-7, 6),
		Vector2i(15, 12),
	]
	var height_columns: int = 0
	var biome_columns: int = 0
	var modifier_columns: int = 0
	for coord: Vector2i in coords:
		var stage8: Dictionary = STAGE8_CACHE.build(coord, data)
		var stage9: Dictionary = runtime._build_column_caches(coord)
		var heights8: PackedInt32Array = stage8.get("heights", PackedInt32Array())
		var heights9: PackedInt32Array = stage9.get("heights", PackedInt32Array())
		var biomes8: PackedByteArray = stage8.get("biomes", PackedByteArray())
		var biomes9: PackedByteArray = stage9.get("biomes", PackedByteArray())
		var water8: PackedByteArray = stage8.get("stage7_water_types", PackedByteArray())
		var water9: PackedByteArray = stage9.get("stage7_water_types", PackedByteArray())
		var modifiers: PackedByteArray = stage9.get("stage9_terrain_modifiers", PackedByteArray())
		if heights8 != heights9:
			_fail("Stage 9 changed Stage 8 terrain/hydrology heights in chunk %s" % coord)
		if biomes8 != biomes9:
			_fail("Stage 9 changed Stage 8 base ecology IDs in chunk %s" % coord)
		if water8 != water9:
			_fail("Stage 9 changed Stage 8 water ownership in chunk %s" % coord)
		if modifiers.size() != WIDTH * WIDTH:
			_fail("Stage 9 modifier cache has the wrong padded size in chunk %s" % coord)
			continue

		var origin_x: int = coord.x * CHUNK_SIZE
		var origin_z: int = coord.y * CHUNK_SIZE
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				var cache_x: int = local_x + PADDING
				var cache_z: int = local_z + PADDING
				var index: int = cache_z * WIDTH + cache_x
				var world_x: int = origin_x + local_x
				var world_z: int = origin_z + local_z
				var expected_modifier: int = data.stage9_terrain_modifier_at(world_x, world_z)
				if int(modifiers[index]) != expected_modifier:
					_fail("Stage 9 cache/public modifier mismatch at (%d,%d)" % [world_x, world_z])
				height_columns += 1
				biome_columns += 1
				modifier_columns += 1
	return {
		"chunks": coords.size(),
		"height_columns": height_columns,
		"biome_columns": biome_columns,
		"modifier_columns": modifier_columns,
	}


func _cached_slope(cache_x: int, cache_z: int, heights: PackedInt32Array) -> float:
	var index: int = cache_z * WIDTH + cache_x
	var center: int = int(heights[index])
	var slope: int = 0
	slope = maxi(slope, absi(int(heights[index - 1]) - center))
	slope = maxi(slope, absi(int(heights[index + 1]) - center))
	slope = maxi(slope, absi(int(heights[index - WIDTH]) - center))
	slope = maxi(slope, absi(int(heights[index + WIDTH]) - center))
	return float(slope)


func _audit_world(data) -> Dictionary:
	var chunk_axis: Array[int] = [-128, -96, -64, -32, 0, 32, 64, 96, 128]
	var modifier_counts := PackedInt32Array()
	modifier_counts.resize(DATA.STAGE9_TERRAIN_MODIFIER_COUNT)
	var stage8_tree_candidates := PackedInt32Array()
	stage8_tree_candidates.resize(DATA.STAGE9_TERRAIN_MODIFIER_COUNT)
	var stage9_tree_candidates := PackedInt32Array()
	stage9_tree_candidates.resize(DATA.STAGE9_TERRAIN_MODIFIER_COUNT)
	var stone_surface_counts := PackedInt32Array()
	stone_surface_counts.resize(DATA.STAGE9_TERRAIN_MODIFIER_COUNT)
	var biome_masks := PackedInt32Array()
	biome_masks.resize(DATA.STAGE9_TERRAIN_MODIFIER_COUNT)
	var water_columns: int = 0
	var total_land: int = 0
	var fixtures: Dictionary = {}

	for chunk_z: int in chunk_axis:
		for chunk_x: int in chunk_axis:
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = STAGE9_CACHE.build(coord, data)
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
			var modifiers: PackedByteArray = cache.get("stage9_terrain_modifiers", PackedByteArray())
			if (
				heights.size() != WIDTH * WIDTH
				or biomes.size() != WIDTH * WIDTH
				or water_types.size() != WIDTH * WIDTH
				or modifiers.size() != WIDTH * WIDTH
			):
				_fail("Stage 9 broad audit encountered malformed cache arrays")
				continue

			var origin_x: int = coord.x * CHUNK_SIZE
			var origin_z: int = coord.y * CHUNK_SIZE
			for cache_z in range(PADDING, PADDING + CHUNK_SIZE):
				for cache_x in range(PADDING, PADDING + CHUNK_SIZE):
					var index: int = cache_z * WIDTH + cache_x
					var water_type: int = int(water_types[index])
					var modifier: int = int(modifiers[index])
					if modifier < 0 or modifier >= DATA.STAGE9_TERRAIN_MODIFIER_COUNT:
						_fail("Stage 9 emitted an invalid terrain modifier ID")
						continue
					if water_type != DATA.WATER_NONE:
						water_columns += 1
						if modifier != DATA.TERRAIN_MODIFIER_NONE:
							_fail("Stage 9 applied a terrain modifier to a physical-water column")
						continue

					total_land += 1
					modifier_counts[modifier] += 1
					var biome: int = int(biomes[index])
					if biome >= 0 and biome <= DATA.STAGE8_MAX_BIOME_ID:
						biome_masks[modifier] = int(biome_masks[modifier]) | (1 << biome)
					var world_x: int = origin_x + cache_x - PADDING
					var world_z: int = origin_z + cache_z - PADDING
					var surface: int = int(heights[index])
					var slope: float = _cached_slope(cache_x, cache_z, heights)
					var exposed: bool = data.stage9_surface_exposes_stone(
						world_x, world_z, surface, modifier, slope
					)
					if exposed:
						stone_surface_counts[modifier] += 1
						var rock_key: String = "rock_%d" % modifier
						if not fixtures.has(rock_key):
							fixtures[rock_key] = [world_x, world_z, surface, biome, slope]
					if modifier == DATA.TERRAIN_MODIFIER_VALLEY and exposed:
						_fail("Stage 9 valley surface unexpectedly received mountain rock treatment")

					var stage8_candidate: bool = data.stage8_tree_candidate_for_biome(
						world_x, world_z, surface, biome
					)
					if stage8_candidate:
						stage8_tree_candidates[modifier] += 1
					var stage9_candidate: bool = data.stage9_tree_candidate_for_biome(
						world_x, world_z, surface, biome, modifier, slope
					)
					if stage9_candidate:
						stage9_tree_candidates[modifier] += 1
						if exposed:
							_fail("Stage 9 placed a generated tree candidate on exposed stone")
					var modifier_key: String = "modifier_%d" % modifier
					if not fixtures.has(modifier_key):
						fixtures[modifier_key] = [world_x, world_z, surface, biome, slope]

	for modifier in range(DATA.STAGE9_TERRAIN_MODIFIER_COUNT):
		if modifier_counts[modifier] < 24:
			_fail(
				"Stage 9 broad audit did not form a readable %s terrain region"
				% data.terrain_modifier_name(modifier)
			)
	if water_columns <= 0:
		_fail("Stage 9 broad audit did not exercise physical water")
	if stone_surface_counts[DATA.TERRAIN_MODIFIER_MOUNTAIN] <= 0:
		_fail("Stage 9 mountains never produced exposed-stone expression")
	if stone_surface_counts[DATA.TERRAIN_MODIFIER_PLATEAU] <= 0:
		_fail("Stage 9 plateaus never produced any exposed-stone expression")

	for modifier in [
		DATA.TERRAIN_MODIFIER_HILL,
		DATA.TERRAIN_MODIFIER_PLATEAU,
		DATA.TERRAIN_MODIFIER_MOUNTAIN,
	]:
		if stage8_tree_candidates[modifier] <= 0:
			_fail("Stage 9 audit found no Stage 8 tree candidates in %s terrain" % data.terrain_modifier_name(modifier))
		elif stage9_tree_candidates[modifier] >= stage8_tree_candidates[modifier]:
			_fail("Stage 9 %s terrain did not reduce normal tree density" % data.terrain_modifier_name(modifier))
	if stage8_tree_candidates[DATA.TERRAIN_MODIFIER_MOUNTAIN] > 0 and stage9_tree_candidates[DATA.TERRAIN_MODIFIER_MOUNTAIN] <= 0:
		_fail("Stage 9 removed all possible forested lower-mountain trees")
	if stage9_tree_candidates[DATA.TERRAIN_MODIFIER_VALLEY] != stage8_tree_candidates[DATA.TERRAIN_MODIFIER_VALLEY]:
		_fail("Stage 9 valley floors do not retain full Stage 8 ecology tree density")

	var ecology_counts_per_modifier: Array[int] = []
	for modifier in range(DATA.STAGE9_TERRAIN_MODIFIER_COUNT):
		var mask: int = int(biome_masks[modifier])
		var count: int = 0
		for biome in range(DATA.STAGE8_MAX_BIOME_ID + 1):
			if (mask & (1 << biome)) != 0:
				count += 1
		ecology_counts_per_modifier.append(count)
	if ecology_counts_per_modifier[DATA.TERRAIN_MODIFIER_MOUNTAIN] < 3:
		_fail("Stage 9 mountain terrain does not cross enough base ecologies")
	if ecology_counts_per_modifier[DATA.TERRAIN_MODIFIER_PLATEAU] < 3:
		_fail("Stage 9 plateau terrain does not cross enough base ecologies")
	if ecology_counts_per_modifier[DATA.TERRAIN_MODIFIER_VALLEY] < 2:
		_fail("Stage 9 valley terrain does not cross enough base ecologies")

	var count_report: Array[int] = []
	var stage8_tree_report: Array[int] = []
	var stage9_tree_report: Array[int] = []
	var stone_report: Array[int] = []
	for modifier in range(DATA.STAGE9_TERRAIN_MODIFIER_COUNT):
		count_report.append(int(modifier_counts[modifier]))
		stage8_tree_report.append(int(stage8_tree_candidates[modifier]))
		stage9_tree_report.append(int(stage9_tree_candidates[modifier]))
		stone_report.append(int(stone_surface_counts[modifier]))

	return {
		"land_columns": total_land,
		"water_columns": water_columns,
		"modifier_counts": count_report,
		"modifier_names": ["none", "hill", "plateau", "mountain", "valley"],
		"ecology_counts_per_modifier": ecology_counts_per_modifier,
		"stage8_tree_candidates": stage8_tree_report,
		"stage9_tree_candidates": stage9_tree_report,
		"stone_surface_counts": stone_report,
		"fixtures": fixtures,
	}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	return (world_z - min_z) * WIDTH + world_x - min_x


func _validate_seams(runtime) -> Dictionary:
	var pairs: Array = [
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
		[Vector2i(-4, 3), Vector2i(-3, 3)],
		[Vector2i(7, -6), Vector2i(7, -5)],
	]
	var comparisons: int = 0
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var cache_a: Dictionary = runtime._build_column_caches(a)
		var cache_b: Dictionary = runtime._build_column_caches(b)
		var heights_a: PackedInt32Array = cache_a.get("heights", PackedInt32Array())
		var heights_b: PackedInt32Array = cache_b.get("heights", PackedInt32Array())
		var biomes_a: PackedByteArray = cache_a.get("biomes", PackedByteArray())
		var biomes_b: PackedByteArray = cache_b.get("biomes", PackedByteArray())
		var modifiers_a: PackedByteArray = cache_a.get("stage9_terrain_modifiers", PackedByteArray())
		var modifiers_b: PackedByteArray = cache_b.get("stage9_terrain_modifiers", PackedByteArray())
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
				if int(heights_a[ia]) != int(heights_b[ib]):
					_fail("Stage 9 height seam mismatch at (%d,%d)" % [x, z])
				if int(biomes_a[ia]) != int(biomes_b[ib]):
					_fail("Stage 9 base ecology seam mismatch at (%d,%d)" % [x, z])
				if int(modifiers_a[ia]) != int(modifiers_b[ib]):
					_fail("Stage 9 terrain modifier seam mismatch at (%d,%d)" % [x, z])
				comparisons += 1
	return {"overlap_columns": comparisons}


func _validate_determinism(data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(9, -11), Vector2i(-17, 5)]
	for coord: Vector2i in coords:
		var first: Dictionary = STAGE9_CACHE.build(coord, data)
		var second: Dictionary = STAGE9_CACHE.build(coord, data)
		if first.get("heights") != second.get("heights"):
			_fail("Stage 9 height cache is nondeterministic in %s" % coord)
		if first.get("biomes") != second.get("biomes"):
			_fail("Stage 9 base ecology cache is nondeterministic in %s" % coord)
		if first.get("stage9_terrain_modifiers") != second.get("stage9_terrain_modifiers"):
			_fail("Stage 9 terrain modifier cache is nondeterministic in %s" % coord)
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
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var modifiers: PackedByteArray = cache.get("stage9_terrain_modifiers", PackedByteArray())
			var checksum: int = 0
			if not heights.is_empty():
				checksum += int(heights[0]) + int(heights[heights.size() - 1])
			if not biomes.is_empty():
				checksum += int(biomes[0]) + int(biomes[biomes.size() - 1])
			if not modifiers.is_empty():
				checksum += int(modifiers[0]) + int(modifiers[modifiers.size() - 1])
			if checksum == -2147483648:
				_fail("Impossible Stage 9 benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	values.sort()
	var total: int = 0
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
