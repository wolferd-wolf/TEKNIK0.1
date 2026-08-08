extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage7_biome_data.gd")
const STAGE6_CACHE := preload("res://scripts/world/playable_world_stage6_generation_cache_fast.gd")
const STAGE7_CACHE := preload("res://scripts/world/playable_world_stage7_cache_fast.gd")
const RUNTIME := preload("res://scripts/world/playable_world_stage7_frozen_runtime.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var synthetic := _synthetic(data)
	var equivalence := _equivalence(data, runtime)
	var seams := _seams(runtime)
	var determinism := _determinism(data)
	var benchmark := _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail("Frozen Stage 7 generation exceeded 1.0 ms p95: %d usec" % int(benchmark["p95_usec"]))
	runtime.free()
	var report := {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"prototype_count": 4,
		"temperature_frequency": DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY,
		"moisture_frequency": DATA.BIOME_MOISTURE_NOISE_FREQUENCY,
		"synthetic": synthetic,
		"equivalence": equivalence,
		"seams": seams,
		"determinism": determinism,
		"benchmark": benchmark,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE7_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE7_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _synthetic(data) -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Frozen Stage 7 lost 150-block height")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY != 0.0012 or DATA.BIOME_MOISTURE_NOISE_FREQUENCY != 0.0014:
		_fail("Frozen Stage 7 climate frequencies changed")
	var plains := data.stage7_classify_with_context(DATA.STAGE7_PLAINS_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	var forest := data.stage7_classify_with_context(DATA.STAGE7_FOREST_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	var desert := data.stage7_classify_with_context(DATA.STAGE7_DESERT_TARGET, 0.0, 0.0, 18, DATA.WATER_NONE, 0.0)
	var rocky := data.stage7_classify_with_context(DATA.STAGE7_ROCKY_TARGET, 1.0, 6.0, 18, DATA.WATER_NONE, 0.0)
	if plains != DATA.BIOME_PLAINS or forest != DATA.BIOME_FOREST or desert != DATA.BIOME_DESERT or rocky != DATA.BIOME_ROCKY:
		_fail("Frozen Stage 7 prototype selection changed")
	var flat_rocky := data.stage7_classify_with_context(DATA.STAGE7_ROCKY_TARGET, 0.0, 0.0, 80, DATA.WATER_NONE, 0.0)
	if flat_rocky == DATA.BIOME_ROCKY:
		_fail("Frozen Stage 7 Rocky regained flat-elevation eligibility")
	var water_forest := data.stage7_classify_with_context(DATA.STAGE7_FOREST_TARGET, 0.0, 0.0, 5, DATA.WATER_OCEAN, 1.0)
	if water_forest != DATA.BIOME_PLAINS:
		_fail("Frozen Stage 7 physical water selected Forest")
	return {"plains": plains, "forest": forest, "desert": desert, "rocky": rocky, "flat_rocky": flat_rocky, "water_forest": water_forest}


func _equivalence(data, runtime) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(4, -3), Vector2i(-7, 6), Vector2i(15, 12)]
	var compared := 0
	for coord in coords:
		var stage6: Dictionary = STAGE6_CACHE.build(coord, data)
		var stage7: Dictionary = runtime._build_column_caches(coord)
		if stage6.get("heights") != stage7.get("heights"):
			_fail("Frozen Stage 7 changed Stage 6 heights in %s" % coord)
		var biomes: PackedByteArray = stage7.get("biomes", PackedByteArray())
		for lz in range(CHUNK_SIZE):
			for lx in range(CHUNK_SIZE):
				var index := (lz + PADDING) * WIDTH + lx + PADDING
				var wx := coord.x * CHUNK_SIZE + lx
				var wz := coord.y * CHUNK_SIZE + lz
				if int(biomes[index]) != data.biome_at(wx, wz):
					_fail("Frozen Stage 7 cache/public biome mismatch at (%d,%d)" % [wx, wz])
				compared += 1
	return {"chunks": coords.size(), "columns": compared}


func _index(coord: Vector2i, wx: int, wz: int) -> int:
	return (wz - (coord.y * CHUNK_SIZE - PADDING)) * WIDTH + wx - (coord.x * CHUNK_SIZE - PADDING)


func _seams(runtime) -> Dictionary:
	var pairs := [[Vector2i.ZERO, Vector2i(1, 0)], [Vector2i.ZERO, Vector2i(0, 1)]]
	var compared := 0
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var ca: Dictionary = runtime._build_column_caches(a)
		var cb: Dictionary = runtime._build_column_caches(b)
		var ba: PackedByteArray = ca.get("biomes", PackedByteArray())
		var bb: PackedByteArray = cb.get("biomes", PackedByteArray())
		var ha: PackedInt32Array = ca.get("heights", PackedInt32Array())
		var hb: PackedInt32Array = cb.get("heights", PackedInt32Array())
		var min_ax := a.x * CHUNK_SIZE - PADDING
		var min_az := a.y * CHUNK_SIZE - PADDING
		var max_ax := min_ax + WIDTH - 1
		var max_az := min_az + WIDTH - 1
		var min_bx := b.x * CHUNK_SIZE - PADDING
		var min_bz := b.y * CHUNK_SIZE - PADDING
		var max_bx := min_bx + WIDTH - 1
		var max_bz := min_bz + WIDTH - 1
		for wz in range(maxi(min_az, min_bz), mini(max_az, max_bz) + 1):
			for wx in range(maxi(min_ax, min_bx), mini(max_ax, max_bx) + 1):
				var ia := _index(a, wx, wz)
				var ib := _index(b, wx, wz)
				if ba[ia] != bb[ib] or ha[ia] != hb[ib]:
					_fail("Frozen Stage 7 seam mismatch at (%d,%d)" % [wx, wz])
				compared += 1
	return {"overlap_columns": compared}


func _determinism(data) -> Dictionary:
	var coords := [Vector2i.ZERO, Vector2i(9, -11), Vector2i(-17, 5)]
	for coord in coords:
		var a := STAGE7_CACHE.build(coord, data)
		var b := STAGE7_CACHE.build(coord, data)
		if a.get("heights") != b.get("heights") or a.get("biomes") != b.get("biomes"):
			_fail("Frozen Stage 7 cache is nondeterministic in %s" % coord)
	return {"chunks": coords.size()}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			coords.append(Vector2i(x, z))
	for _w in range(WARMUPS):
		for coord in coords:
			runtime._build_column_caches(coord)
	var values: Array[int] = []
	for _r in range(REPEATS):
		for coord in coords:
			var started := Time.get_ticks_usec()
			runtime._build_column_caches(coord)
			values.append(maxi(1, Time.get_ticks_usec() - started))
	values.sort()
	var total := 0
	for value in values:
		total += value
	var p95_index := clampi(ceili(float(values.size()) * 0.95) - 1, 0, values.size() - 1)
	return {"sample_count": values.size(), "minimum_usec": values[0], "mean_usec": float(total) / float(values.size()), "p95_usec": values[p95_index], "p95_ms": float(values[p95_index]) / 1000.0, "maximum_usec": values[values.size() - 1]}
