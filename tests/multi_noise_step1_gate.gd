extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const WARMUP_REPETITIONS := 4
const MEASURED_REPETITIONS := 20

var failures: Array[String] = []


class LegacyTwoNoiseSampler:
	extends RefCounted

	const LEGACY_WORLD_SEED := 734921
	const LEGACY_WORLD_HEIGHT := 30

	var height_noise := FastNoiseLite.new()
	var region_noise := FastNoiseLite.new()

	func _init() -> void:
		height_noise.seed = LEGACY_WORLD_SEED
		height_noise.frequency = 0.011
		height_noise.fractal_octaves = 4
		height_noise.fractal_gain = 0.48
		height_noise.fractal_lacunarity = 2.05
		region_noise.seed = LEGACY_WORLD_SEED ^ 0x5f3759df
		region_noise.frequency = 0.0035
		region_noise.fractal_octaves = 2

	func terrain_height(x: int, z: int) -> int:
		var continental := height_noise.get_noise_2d(float(x), float(z))
		var region := region_noise.get_noise_2d(float(x), float(z))
		return clampi(roundi(10.0 + continental * 6.4 + region * 3.0), 3, LEGACY_WORLD_HEIGHT - 3)


func _init() -> void:
	var data = WORLD_DATA.new()
	var legacy := LegacyTwoNoiseSampler.new()

	_validate_source_contract(data)
	_validate_determinism_and_legacy_equivalence(data, legacy)
	_validate_world_coordinate_continuity(data)
	_validate_height_bounds(data)
	var benchmark := _run_benchmark(data, legacy)

	if failures.is_empty():
		print("MULTI_NOISE_STEP1_BENCHMARK_JSON=%s" % JSON.stringify(benchmark))
		print("MULTI_NOISE_STEP1_GATE_PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_source_contract(data) -> void:
	if int(WORLD_DATA.NOISE_SAMPLES_PER_COLUMN) != 4:
		_fail("NOISE_SAMPLES_PER_COLUMN must be exactly 4")

	var source := FileAccess.get_file_as_string("res://scripts/world/playable_world_data.gd")
	var sample_start := source.find("func sample_column_noise")
	var height_start := source.find("func terrain_height", sample_start)
	var block_start := source.find("func get_block", height_start)
	if sample_start < 0 or height_start < 0 or block_start < 0:
		_fail("Unable to isolate multi-noise source functions")
		return

	var sample_body := source.substr(sample_start, height_start - sample_start)
	var height_body := source.substr(height_start, block_start - height_start)
	if _count_occurrences(sample_body, ".get_noise_2d(") != 4:
		_fail("sample_column_noise must contain exactly four FastNoiseLite samples")
	if _count_occurrences(height_body, "sample_column_noise(") != 1:
		_fail("terrain_height must call sample_column_noise exactly once per column")
	if _count_occurrences(height_body, ".get_noise_2d(") != 0:
		_fail("terrain_height contains an out-of-contract direct noise sample")

	var points: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(11, 11),
		Vector2i(12, 0),
		Vector2i(-1, -1),
		Vector2i(-12, 7),
		Vector2i(4096, -2048),
	]
	for point in points:
		var actual: Vector4 = data.sample_column_noise(point.x, point.y)
		var expected := Vector4(
			data.continentalness_noise.get_noise_2d(float(point.x), float(point.y)),
			data.terrain_shape_noise.get_noise_2d(float(point.x), float(point.y)),
			data.temperature_noise.get_noise_2d(float(point.x), float(point.y)),
			data.moisture_noise.get_noise_2d(float(point.x), float(point.y))
		)
		if not actual.is_equal_approx(expected):
			_fail("Noise layer ordering or world-coordinate sampling mismatch at %s" % point)


func _validate_determinism_and_legacy_equivalence(data, legacy: LegacyTwoNoiseSampler) -> void:
	for z in range(-48, 49, 7):
		for x in range(-48, 49, 5):
			var first_samples: Vector4 = data.sample_column_noise(x, z)
			var second_samples: Vector4 = data.sample_column_noise(x, z)
			if not first_samples.is_equal_approx(second_samples):
				_fail("Four-noise samples were not deterministic at (%d,%d)" % [x, z])
			var first_height: int = data.terrain_height(x, z)
			var second_height: int = data.terrain_height(x, z)
			if first_height != second_height:
				_fail("Terrain height was not deterministic at (%d,%d)" % [x, z])
			var legacy_height: int = legacy.terrain_height(x, z)
			if first_height != legacy_height:
				_fail("Step 1 changed terrain height at (%d,%d): legacy=%d four-noise=%d" % [
					x, z, legacy_height, first_height
				])


func _validate_world_coordinate_continuity(data) -> void:
	var origin_cache := _build_four_noise_cache(data, Vector2i.ZERO)
	var east_cache := _build_four_noise_cache(data, Vector2i(1, 0))
	var south_cache := _build_four_noise_cache(data, Vector2i(0, 1))
	var negative_cache := _build_four_noise_cache(data, Vector2i(-1, -1))

	for local_z in range(CHUNK_SIZE):
		var from_origin: int = _cache_value(origin_cache, CHUNK_SIZE, local_z)
		var from_east: int = _cache_value(east_cache, 0, local_z)
		var direct: int = data.terrain_height(CHUNK_SIZE, local_z)
		if from_origin != from_east or from_east != direct:
			_fail("East chunk boundary restarted or misaligned at z=%d" % local_z)

	for local_x in range(CHUNK_SIZE):
		var from_origin: int = _cache_value(origin_cache, local_x, CHUNK_SIZE)
		var from_south: int = _cache_value(south_cache, local_x, 0)
		var direct: int = data.terrain_height(local_x, CHUNK_SIZE)
		if from_origin != from_south or from_south != direct:
			_fail("South chunk boundary restarted or misaligned at x=%d" % local_x)

	for local_z in range(CHUNK_SIZE):
		var cached: int = _cache_value(negative_cache, 0, local_z)
		var direct: int = data.terrain_height(-CHUNK_SIZE, -CHUNK_SIZE + local_z)
		if cached != direct:
			_fail("Negative chunk world-coordinate mismatch at local z=%d" % local_z)

	if data.sample_column_noise(0, 0).is_equal_approx(data.sample_column_noise(CHUNK_SIZE, 0)):
		_fail("Adjacent chunks appear to restart noise at local origin")


func _validate_height_bounds(data) -> void:
	for chunk_z in range(-4, 5):
		for chunk_x in range(-4, 5):
			var cache := _build_four_noise_cache(data, Vector2i(chunk_x, chunk_z))
			if cache.size() != CACHE_WIDTH * CACHE_WIDTH:
				_fail("Unexpected cache size for chunk (%d,%d)" % [chunk_x, chunk_z])
				continue
			for height in cache:
				if height < 3 or height > WORLD_DATA.WORLD_HEIGHT - 3:
					_fail("Height %d escaped valid bounds in chunk (%d,%d)" % [height, chunk_x, chunk_z])
					return


func _run_benchmark(data, legacy: LegacyTwoNoiseSampler) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-4, 4):
			coords.append(Vector2i(x, z))

	for _warmup in range(WARMUP_REPETITIONS):
		for coord in coords:
			_consume_cache(_build_legacy_cache(legacy, coord))
			_consume_cache(_build_four_noise_cache(data, coord))

	var legacy_usec: Array[int] = []
	var four_noise_usec: Array[int] = []
	var legacy_checksum := 0
	var four_noise_checksum := 0

	for repetition in range(MEASURED_REPETITIONS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[index]
			if (repetition + index) % 2 == 0:
				var legacy_first := _measure_legacy_cache(legacy, coord)
				legacy_usec.append(int(legacy_first["usec"]))
				legacy_checksum += int(legacy_first["checksum"])
				var four_second := _measure_four_noise_cache(data, coord)
				four_noise_usec.append(int(four_second["usec"]))
				four_noise_checksum += int(four_second["checksum"])
			else:
				var four_first := _measure_four_noise_cache(data, coord)
				four_noise_usec.append(int(four_first["usec"]))
				four_noise_checksum += int(four_first["checksum"])
				var legacy_second := _measure_legacy_cache(legacy, coord)
				legacy_usec.append(int(legacy_second["usec"]))
				legacy_checksum += int(legacy_second["checksum"])

	if legacy_checksum != four_noise_checksum:
		_fail("Benchmark paths produced different height checksums")

	var legacy_stats := _stats(legacy_usec)
	var four_stats := _stats(four_noise_usec)
	var legacy_mean := float(legacy_stats["mean_usec"])
	var four_mean := float(four_stats["mean_usec"])
	var slowdown := 0.0
	if legacy_mean > 0.0:
		slowdown = ((four_mean / legacy_mean) - 1.0) * 100.0

	return {
		"runner": {
			"os_name": OS.get_name(),
			"processor_name": OS.get_processor_name(),
			"processor_count": OS.get_processor_count(),
			"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		},
		"benchmark_contract": {
			"chunk_size": CHUNK_SIZE,
			"logical_columns_per_chunk": CHUNK_SIZE * CHUNK_SIZE,
			"cache_padding": CACHE_PADDING,
			"sampled_columns_per_chunk": CACHE_WIDTH * CACHE_WIDTH,
			"warmup_repetitions": WARMUP_REPETITIONS,
			"measured_repetitions": MEASURED_REPETITIONS,
			"unique_chunk_coordinates": coords.size(),
			"measured_chunks_per_path": coords.size() * MEASURED_REPETITIONS,
			"legacy_noise_samples_per_column": 2,
			"four_noise_samples_per_column": WORLD_DATA.NOISE_SAMPLES_PER_COLUMN,
			"included_work": "height-cache allocation, world-coordinate loop, noise sampling, height calculation and writes",
			"excluded_work": ["meshing", "rendering", "scene-tree mutation", "collision generation", "file I/O", "world-save loading"],
		},
		"legacy_actual_two_noise_baseline": legacy_stats,
		"four_noise_gdscript": four_stats,
		"relative_slowdown_percent": slowdown,
		"legacy_checksum": legacy_checksum,
		"four_noise_checksum": four_noise_checksum,
		"raw_legacy_usec": legacy_usec,
		"raw_four_noise_usec": four_noise_usec,
	}


func _measure_legacy_cache(legacy: LegacyTwoNoiseSampler, coord: Vector2i) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var cache := _build_legacy_cache(legacy, coord)
	var elapsed_usec := maxi(1, Time.get_ticks_usec() - start_usec)
	return {"usec": elapsed_usec, "checksum": _consume_cache(cache)}


func _measure_four_noise_cache(data, coord: Vector2i) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var cache := _build_four_noise_cache(data, coord)
	var elapsed_usec := maxi(1, Time.get_ticks_usec() - start_usec)
	return {"usec": elapsed_usec, "checksum": _consume_cache(cache)}


func _build_legacy_cache(legacy: LegacyTwoNoiseSampler, coord: Vector2i) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(CACHE_WIDTH * CACHE_WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
			heights[index] = legacy.terrain_height(origin_x + local_x, origin_z + local_z)
	return heights


func _build_four_noise_cache(data, coord: Vector2i) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(CACHE_WIDTH * CACHE_WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
			heights[index] = data.terrain_height(origin_x + local_x, origin_z + local_z)
	return heights


func _cache_value(cache: PackedInt32Array, local_x: int, local_z: int) -> int:
	var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
	return cache[index]


func _consume_cache(cache: PackedInt32Array) -> int:
	var checksum := 0
	for height in cache:
		checksum += height
	return checksum


func _stats(values: Array[int]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var count := sorted.size()
	var total := 0
	for value in sorted:
		total += value
	var mean_usec := float(total) / float(count)
	var middle := int(count / 2)
	var median_usec := float(sorted[middle])
	if count % 2 == 0:
		median_usec = (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
	var p95_index := clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)
	return {
		"sample_count": count,
		"minimum_usec": sorted[0],
		"maximum_usec": sorted[count - 1],
		"mean_usec": mean_usec,
		"median_usec": median_usec,
		"p95_usec": sorted[p95_index],
		"total_usec": total,
		"minimum_ms": float(sorted[0]) / 1000.0,
		"maximum_ms": float(sorted[count - 1]) / 1000.0,
		"mean_ms": mean_usec / 1000.0,
		"median_ms": median_usec / 1000.0,
		"p95_ms": float(sorted[p95_index]) / 1000.0,
		"total_ms": float(total) / 1000.0,
	}


func _count_occurrences(text: String, needle: String) -> int:
	var count := 0
	var offset := 0
	var found := text.find(needle, offset)
	while found >= 0:
		count += 1
		offset = found + needle.length()
		found = text.find(needle, offset)
	return count


func _fail(message: String) -> void:
	failures.append(message)
