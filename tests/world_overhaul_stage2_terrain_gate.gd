extends SceneTree

const DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")

const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const GENERATION_P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	_validate_contract(data)
	var synthetic := _validate_synthetic_landforms(data)
	var climate_independence := _validate_climate_independence(data)
	var world_stats := _audit_world(data)
	var halo := _validate_halo(runtime)
	var deterministic := _validate_determinism(runtime)
	var benchmark := _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 2 generation exceeded the 1.0 ms p95 threshold: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()
	var report := {
		"world_height_limit": DATA.OVERHAUL_WORLD_HEIGHT,
		"safe_terrain_top": DATA.STAGE2_SAFE_TERRAIN_TOP,
		"synthetic_landforms": synthetic,
		"climate_independence": climate_independence,
		"world_audit": world_stats,
		"halo": halo,
		"determinism": deterministic,
		"benchmark": benchmark,
		"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE2_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE2_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_contract(data) -> void:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 2 lost the 150-block world-height contract")
	if DATA.STAGE2_SAFE_TERRAIN_TOP >= DATA.OVERHAUL_WORLD_HEIGHT - 4:
		_fail("Stage 2 terrain leaves insufficient headroom below the build ceiling")

	# Later stages deliberately subclass the accepted Stage 2 terrain
	# implementation. Validate Stage 2 where it lives instead of requiring those
	# symbols to be duplicated physically into every later-stage wrapper.
	var stage2_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage2_generation_data.gd"
	)
	for required in [
		"continental_base_elevation",
		"terrain_regime_weights",
		"ridge_strength",
		"STAGE2_MOUNTAIN_RIDGE_RISE",
		"STAGE2_VALLEY_CUT",
		"func build_provisional_terrain",
	]:
		if not stage2_source.contains(required):
			_fail("Preserved Stage 2 terrain base is missing %s" % required)

	var stage3_runtime_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage3_generation_runtime.gd"
	)
	if not stage3_runtime_source.contains("_stage2_build_column_caches_for_sampler"):
		_fail("Later-stage shipping runtime lost the Stage 2 cache compatibility path")
	if not stage3_runtime_source.contains("sampler.build_provisional_terrain(terrain_fields)"):
		_fail("Shipping cache bypasses the accepted Stage 2 terrain formula")

	# Stage 4 is allowed to reshape the accepted Stage 2 provisional land in the
	# ocean/coast band. The public height must therefore compose Stage 2 through
	# the later water/finalization stages, rather than equal provisional height.
	for point in [Vector2i.ZERO, Vector2i(31, -47), Vector2i(-96, 73)]:
		var fields: Vector4 = data.sample_world_fields(point.x, point.y)
		var provisional: int = data.build_provisional_terrain(fields)
		var water_shaped: int = data.apply_water_topology(
			fields,
			provisional,
			point.x,
			point.y
		)
		var expected: int = data.finalize_height(water_shaped)
		if data.terrain_height(point.x, point.y) != expected:
			_fail("Public terrain_height bypasses the staged terrain pipeline at %s" % point)


func _validate_synthetic_landforms(data) -> Dictionary:
	var plain: int = data.build_provisional_terrain(Vector4(0.0, -0.65, 0.0, 0.0))
	var rolling: int = data.build_provisional_terrain(Vector4(0.35, -0.05, 0.0, 0.0))
	var upland: int = data.build_provisional_terrain(Vector4(0.1, 0.30, 0.0, 0.0))
	var ridge: int = data.build_provisional_terrain(Vector4(0.0, 0.82, 0.0, 0.0))
	var valley: int = data.build_provisional_terrain(Vector4(0.88, 0.82, 0.0, 0.0))
	if rolling <= plain:
		_fail("Rolling regime does not rise above synthetic plains")
	if upland <= plain + 5:
		_fail("Upland/plateau regime is not materially above plains")
	if ridge <= upland + 20:
		_fail("Ridged mountain spine is not materially above uplands")
	if ridge <= valley + 15:
		_fail("Mountain ridge/valley separation is too weak")
	if ridge >= DATA.STAGE2_SAFE_TERRAIN_TOP:
		_fail("Synthetic mountain clips the safe terrain ceiling")
	return {
		"plain": plain,
		"rolling": rolling,
		"upland": upland,
		"mountain_ridge": ridge,
		"mountain_valley": valley,
	}


func _validate_climate_independence(data) -> Dictionary:
	var comparisons := 0
	for continentalness in [-0.75, -0.25, 0.0, 0.35, 0.75]:
		for structure in [-0.6, -0.1, 0.25, 0.52, 0.82]:
			var cold_wet: int = data.build_provisional_terrain(
				Vector4(continentalness, structure, -1.0, 1.0)
			)
			var hot_dry: int = data.build_provisional_terrain(
				Vector4(continentalness, structure, 1.0, -1.0)
			)
			if cold_wet != hot_dry:
				_fail("Terrain height became climate-coupled")
			comparisons += 1
	return {"comparisons": comparisons}


func _audit_world(data) -> Dictionary:
	var minimum_height := 999999
	var maximum_height := -999999
	var height_total := 0
	var sample_count := 0
	var regime_counts := [0, 0, 0, 0]
	var flat_samples := 0
	var steep_samples := 0
	var mountain_adjacencies := 0
	var previous_row: Array[bool] = []
	var spacing := 6
	var start := -384
	var finish := 384
	var row_width := int((finish - start) / spacing) + 1
	previous_row.resize(row_width)
	var row_index := 0
	for z in range(start, finish + 1, spacing):
		var current_row: Array[bool] = []
		current_row.resize(row_width)
		var column_index := 0
		var previous_mountain := false
		for x in range(start, finish + 1, spacing):
			var fields: Vector4 = data.sample_world_fields(x, z)
			var height: int = data.build_provisional_terrain(fields)
			minimum_height = mini(minimum_height, height)
			maximum_height = maxi(maximum_height, height)
			height_total += height
			sample_count += 1
			var regime := _dominant_regime(data.terrain_regime_weights(fields.y))
			regime_counts[regime] += 1
			var is_mountain := regime == 3
			current_row[column_index] = is_mountain
			if is_mountain and previous_mountain:
				mountain_adjacencies += 1
			if is_mountain and row_index > 0 and previous_row[column_index]:
				mountain_adjacencies += 1
			previous_mountain = is_mountain
			# Keep this Stage 2 audit scoped to provisional terrain. Stage 4 owns
			# coastal/ocean relief after this layer.
			var east_fields: Vector4 = data.sample_world_fields(x + spacing, z)
			var south_fields: Vector4 = data.sample_world_fields(x, z + spacing)
			var east_height: int = data.build_provisional_terrain(east_fields)
			var south_height: int = data.build_provisional_terrain(south_fields)
			var local_delta := maxi(absi(east_height - height), absi(south_height - height))
			if regime == 0 and local_delta <= 3:
				flat_samples += 1
			if regime == 3 and local_delta >= 4:
				steep_samples += 1
			column_index += 1
		previous_row = current_row
		row_index += 1
	var height_range := maximum_height - minimum_height
	if maximum_height < 55 or height_range < 35:
		_fail("Stage 2 terrain scale regressed")
	if maximum_height > DATA.STAGE2_SAFE_TERRAIN_TOP:
		_fail("Sampled terrain exceeded the safe terrain top")
	if flat_samples < 40:
		_fail("Sampled world lacks enough recognizably flat plains")
	if steep_samples < 20:
		_fail("Sampled mountain areas lack steep relief")
	if mountain_adjacencies < 30:
		_fail("Mountain samples are too isolated to read as ranges")
	for regime_index in range(4):
		if int(regime_counts[regime_index]) < 20:
			_fail("Terrain regime %d is effectively absent" % regime_index)
	return {
		"sample_count": sample_count,
		"minimum_height": minimum_height,
		"maximum_height": maximum_height,
		"height_range": height_range,
		"mean_height": float(height_total) / float(sample_count),
		"regime_counts": regime_counts,
		"flat_plains_samples": flat_samples,
		"steep_mountain_samples": steep_samples,
		"mountain_adjacencies": mountain_adjacencies,
	}


func _dominant_regime(weights: Vector4) -> int:
	var result := 0
	var strongest := weights.x
	if weights.y > strongest:
		result = 1
		strongest = weights.y
	if weights.z > strongest:
		result = 2
		strongest = weights.z
	if weights.w > strongest:
		result = 3
	return result


func _validate_halo(runtime) -> Dictionary:
	var compared_columns := 0
	for pair in [
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
		[Vector2i(-4, 3), Vector2i(-3, 3)],
	]:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var cache_a: Dictionary = runtime._build_column_caches(a)
		var cache_b: Dictionary = runtime._build_column_caches(b)
		var heights_a: PackedInt32Array = cache_a["heights"]
		var heights_b: PackedInt32Array = cache_b["heights"]
		var min_x := maxi(a.x * CHUNK_SIZE - CACHE_PADDING, b.x * CHUNK_SIZE - CACHE_PADDING)
		var max_x := mini(
			a.x * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1,
			b.x * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1
		)
		var min_z := maxi(a.y * CHUNK_SIZE - CACHE_PADDING, b.y * CHUNK_SIZE - CACHE_PADDING)
		var max_z := mini(
			a.y * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1,
			b.y * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1
		)
		for world_z in range(min_z, max_z + 1):
			for world_x in range(min_x, max_x + 1):
				var index_a := _cache_index(a, world_x, world_z)
				var index_b := _cache_index(b, world_x, world_z)
				if heights_a[index_a] != heights_b[index_b]:
					_fail("Stage 2 terrain halo seam at (%d,%d)" % [world_x, world_z])
				compared_columns += 1
	return {"compared_overlap_columns": compared_columns}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	return (world_z - origin_z + CACHE_PADDING) * CACHE_WIDTH + world_x - origin_x + CACHE_PADDING


func _validate_determinism(runtime) -> Dictionary:
	var compared_chunks := 0
	for coord in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), Vector2i(11, 9)]:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["heights"] != second["heights"]:
			_fail("Stage 2 height generation is nondeterministic at %s" % coord)
		if first["biomes"] != second["biomes"]:
			_fail("Stage 2 biome cache became nondeterministic at %s" % coord)
		compared_chunks += 1
	return {"compared_chunks": compared_chunks}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i(-4, -2), Vector2i(-2, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(4, 2), Vector2i(8, -4), Vector2i(11, -3),
		Vector2i(12, -2), Vector2i(13, -2), Vector2i(14, -1), Vector2i(15, 0),
		Vector2i(16, 1), Vector2i(18, -4), Vector2i(20, 2), Vector2i(-8, 5),
	]
	for _warmup in range(WARMUPS):
		for coord in coords:
			runtime._build_column_caches(coord)
	var times: Array[int] = []
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var started := Time.get_ticks_usec()
			runtime._build_column_caches(coord)
			times.append(maxi(1, Time.get_ticks_usec() - started))
	times.sort()
	var total := 0
	for value in times:
		total += value
	var p95_index := clampi(ceili(float(times.size()) * 0.95) - 1, 0, times.size() - 1)
	return {
		"sample_count": times.size(),
		"minimum_usec": times[0],
		"maximum_usec": times[times.size() - 1],
		"mean_usec": float(total) / float(times.size()),
		"p95_usec": times[p95_index],
		"p95_ms": float(times[p95_index]) / 1000.0,
		"methodology": "same 16 representative padded chunks, 4 warmups, 20 repeats; generation/cache only",
	}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)