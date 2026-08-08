extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage7_biome_data.gd")
const STAGE6_CACHE := preload("res://scripts/world/playable_world_stage6_generation_cache_fast.gd")
const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
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
	var equivalence: Dictionary = _validate_equivalence(data, runtime)
	var seams: Dictionary = _validate_seams(runtime)
	var determinism: Dictionary = _validate_determinism(data)
	var benchmark: Dictionary = _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail("Stage 7 generation exceeded the 1.0 ms p95 gate: %d usec" % int(benchmark["p95_usec"]))
	runtime.free()

	var report := {
		"contract": contract,
		"synthetic": synthetic,
		"world_audit": world_audit,
		"equivalence": equivalence,
		"seams": seams,
		"determinism": determinism,
		"benchmark": benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE7_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE7_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _validate_contract(data) -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 7 lost the 150-block legal height")
	var data_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_stage7_biome_data.gd")
	var cache_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_stage7_cache_fast.gd")
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 7 added a new FastNoiseLite stack")
	for retired: String in ["BIOME_BLEND_PATCH", "hash_value", "selector <"]:
		if data_source.contains(retired) or cache_source.contains(retired):
			_fail("Stage 7 still depends on probabilistic patch selection: %s" % retired)
	if not data_source.contains("stage7_classify_with_context"):
		_fail("Stage 7 data does not expose the contextual classifier")
	if not cache_source.contains("stage7_water_types"):
		_fail("Stage 7 cache does not expose hydrology context")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY >= DATA.TERRAIN_SHAPE_HEIGHT_SCALE:
		# The comparison above is intentionally impossible to fail numerically; the
		# real stable-frequency contract is asserted below against the known Stage 1
		# climate frequencies without mutating the accepted samplers.
		_fail("Unexpected climate-frequency contract")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY != 0.0012:
		_fail("Stage 7 changed the accepted slow temperature field")
	if DATA.BIOME_MOISTURE_NOISE_FREQUENCY != 0.0014:
		_fail("Stage 7 changed the accepted slow moisture field")
	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"temperature_frequency": DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY,
		"moisture_frequency": DATA.BIOME_MOISTURE_NOISE_FREQUENCY,
		"prototype_count": 4,
	}


func _validate_synthetic_classifier(data) -> Dictionary:
	var dry_context := [0.0, 0, DATA.WATER_NONE, 0.0]
	var plains: int = data.stage7_classify_with_context(DATA.STAGE7_PLAINS_TARGET, 0.0, dry_context[0], 18, dry_context[2], dry_context[3])
	var forest: int = data.stage7_classify_with_context(DATA.STAGE7_FOREST_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	var desert: int = data.stage7_classify_with_context(DATA.STAGE7_DESERT_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	var rocky: int = data.stage7_classify_with_context(DATA.STAGE7_ROCKY_TARGET, 1.0, 5.0, 50, DATA.WATER_NONE, 0.0)
	if plains != DATA.BIOME_PLAINS:
		_fail("Plains prototype does not select Plains")
	if forest != DATA.BIOME_FOREST:
		_fail("Forest prototype does not select Forest")
	if desert != DATA.BIOME_DESERT:
		_fail("Desert prototype does not select Desert")
	if rocky != DATA.BIOME_ROCKY:
		_fail("Eligible Rocky prototype does not select Rocky")
	var flat_rocky: int = data.stage7_classify_with_context(DATA.STAGE7_ROCKY_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	if flat_rocky == DATA.BIOME_ROCKY:
		_fail("Rocky still paints ordinary flat lowlands")
	var wet_forest: int = data.stage7_classify_with_context(DATA.STAGE7_FOREST_TARGET, 0.0, 0.0, 5, DATA.WATER_OCEAN, 1.0)
	if wet_forest != DATA.BIOME_PLAINS:
		_fail("Physical water was allowed to classify as Forest")
	var coast_rocky: int = data.stage7_classify_with_context(DATA.STAGE7_ROCKY_TARGET, 1.0, 5.0, 50, DATA.WATER_NONE, 0.9)
	if coast_rocky == DATA.BIOME_ROCKY:
		_fail("Rocky ignores coastal eligibility")
	var fallback: int = data.stage7_classify_with_context(Vector2(99.0, -99.0), 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	if fallback < 0 or fallback >= DATA.BIOME_COUNT:
		_fail("Nearest-prototype classifier produced an invalid fallback")
	return {
		"plains": plains,
		"forest": forest,
		"desert": desert,
		"rocky": rocky,
		"flat_rocky": flat_rocky,
		"water_forest": wet_forest,
		"coast_rocky": coast_rocky,
		"fallback": fallback,
	}


func _audit_world(data) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in [-32, -16, 0, 16, 32]:
		for x in [-32, -16, 0, 16, 32]:
			coords.append(Vector2i(x, z))
	var counts := PackedInt32Array()
	counts.resize(DATA.BIOME_COUNT)
	var water_columns := 0
	var rocky_columns := 0
	var context_columns := 0
	var max_slope := 0.0
	for coord: Vector2i in coords:
		var cache: Dictionary = STAGE7_CACHE.build(coord, data)
		var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
		var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
		var slopes: PackedFloat32Array = cache.get("stage7_slopes", PackedFloat32Array())
		var mountain: PackedFloat32Array = cache.get("stage7_mountain_strengths", PackedFloat32Array())
		var coast: PackedFloat32Array = cache.get("stage7_coast_proximity", PackedFloat32Array())
		var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
		if biomes.size() != WIDTH * WIDTH or water_types.size() != WIDTH * WIDTH:
			_fail("Stage 7 context arrays have the wrong padded-cache size")
			continue
		for local_z in range(PADDING, PADDING + CHUNK_SIZE):
			for local_x in range(PADDING, PADDING + CHUNK_SIZE):
				var index: int = local_z * WIDTH + local_x
				var biome: int = int(biomes[index])
				if biome < 0 or biome >= DATA.BIOME_COUNT:
					_fail("Stage 7 produced an invalid world biome ID")
					continue
				counts[biome] += 1
				context_columns += 1
				max_slope = maxf(max_slope, float(slopes[index]))
				if int(water_types[index]) != DATA.WATER_NONE:
					water_columns += 1
					if biome != DATA.BIOME_PLAINS:
						_fail("A physical water column selected a non-neutral land ecology")
				if biome == DATA.BIOME_ROCKY:
					rocky_columns += 1
					if (
						float(coast[index]) > DATA.STAGE7_ROCKY_COAST_PROXIMITY_MAX
						or (
							float(mountain[index]) < DATA.STAGE7_ROCKY_MOUNTAIN_STRENGTH_MIN
							and int(heights[index]) < DATA.STAGE7_ROCKY_ELEVATION_MIN
						)
					):
						_fail("Rocky appeared outside its terrain eligibility")
	for biome_id in [DATA.BIOME_PLAINS, DATA.BIOME_FOREST, DATA.BIOME_DESERT]:
		if counts[biome_id] <= 0:
			_fail("Stage 7 fixed world audit did not reach %s" % data.biome_name(biome_id))
	if rocky_columns <= 0:
		_fail("Stage 7 fixed world audit did not reach an eligible Rocky ecology")
	if water_columns <= 0:
		_fail("Stage 7 fixed world audit did not exercise water eligibility")
	return {
		"columns": context_columns,
		"counts": Array(counts),
		"water_columns": water_columns,
		"rocky_columns": rocky_columns,
		"maximum_slope": max_slope,
	}


func _validate_equivalence(data, runtime) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(4, -3), Vector2i(-7, 6), Vector2i(15, 12)]
	var compared_heights := 0
	var compared_biomes := 0
	for coord: Vector2i in coords:
		var stage6: Dictionary = STAGE6_CACHE.build(coord, data)
		var stage7: Dictionary = runtime._build_column_caches(coord)
		var heights6: PackedInt32Array = stage6.get("heights", PackedInt32Array())
		var heights7: PackedInt32Array = stage7.get("heights", PackedInt32Array())
		var biomes7: PackedByteArray = stage7.get("biomes", PackedByteArray())
		if heights6 != heights7:
			_fail("Stage 7 changed Stage 6 terrain/hydrology heights in chunk %s" % coord)
		var origin_x: int = coord.x * CHUNK_SIZE
		var origin_z: int = coord.y * CHUNK_SIZE
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				var index: int = (local_z + PADDING) * WIDTH + local_x + PADDING
				var world_x: int = origin_x + local_x
				var world_z: int = origin_z + local_z
				var expected: int = data.biome_at(world_x, world_z)
				if int(biomes7[index]) != expected:
					_fail("Stage 7 cache/public biome mismatch at (%d,%d)" % [world_x, world_z])
				compared_biomes += 1
				compared_heights += 1
	return {"height_columns": compared_heights, "biome_columns": compared_biomes, "chunks": coords.size()}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	return (world_z - min_z) * WIDTH + (world_x - min_x)


func _validate_seams(runtime) -> Dictionary:
	var comparisons := 0
	for pair in [
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
		[Vector2i(-4, 3), Vector2i(-3, 3)],
		[Vector2i(5, -7), Vector2i(5, -6)],
	]:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var cache_a: Dictionary = runtime._build_column_caches(a)
		var cache_b: Dictionary = runtime._build_column_caches(b)
		var biomes_a: PackedByteArray = cache_a["biomes"]
		var biomes_b: PackedByteArray = cache_b["biomes"]
		var min_ax: int = a.x * CHUNK_SIZE - PADDING
		var min_az: int = a.y * CHUNK_SIZE - PADDING
		var max_ax: int = min_ax + WIDTH - 1
		var max_az: int = min_az + WIDTH - 1
		var min_bx: int = b.x * CHUNK_SIZE - PADDING
		var min_bz: int = b.y * CHUNK_SIZE - PADDING
		var max_bx: int = min_bx + WIDTH - 1
		var max_bz: int = min_bz + WIDTH - 1
		for world_z in range(maxi(min_az, min_bz), mini(max_az, max_bz) + 1):
			for world_x in range(maxi(min_ax, min_bx), mini(max_ax, max_bx) + 1):
				if biomes_a[_cache_index(a, world_x, world_z)] != biomes_b[_cache_index(b, world_x, world_z)]:
					_fail("Stage 7 biome seam at (%d,%d)" % [world_x, world_z])
				comparisons += 1
	if comparisons < 192:
		_fail("Stage 7 seam gate exercised too few overlap columns")
	return {"overlap_columns": comparisons}


func _validate_determinism(data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(11, -9), Vector2i(-13, 4)]
	var checks := 0
	for coord: Vector2i in coords:
		var first: Dictionary = STAGE7_CACHE.build(coord, data)
		var second: Dictionary = STAGE7_CACHE.build(coord, data)
		for key: String in ["heights", "biomes", "stage7_water_types", "stage7_slopes", "stage7_mountain_strengths", "stage7_coast_proximity"]:
			if first.get(key) != second.get(key):
				_fail("Stage 7 cache is non-deterministic for %s in %s" % [key, coord])
		checks += 1
	return {"chunks": checks}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			coords.append(Vector2i(x * 7, z * 7))
	for _warmup in range(WARMUPS):
		for coord: Vector2i in coords:
			runtime._build_column_caches(coord)
	var samples: Array[int] = []
	for _repeat in range(REPEATS):
		for coord: Vector2i in coords:
			var started: int = Time.get_ticks_usec()
			runtime._build_column_caches(coord)
			samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	var total := 0
	for sample: int in samples:
		total += sample
	var p95_index: int = mini(samples.size() - 1, ceili(float(samples.size()) * 0.95) - 1)
	return {
		"sample_count": samples.size(),
		"minimum_usec": samples[0],
		"mean_usec": float(total) / float(samples.size()),
		"p95_usec": samples[p95_index],
		"p95_ms": float(samples[p95_index]) / 1000.0,
		"maximum_usec": samples[samples.size() - 1],
		"methodology": "16 padded chunks, 4 warmups, 20 repeats; same 320-sample hard gate",
	}