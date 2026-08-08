extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage13_data.gd")
const CACHE := preload("res://scripts/world/playable_world_stage13_generation_cache_fast.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20
const SEPARATION_RANGE_MIN := 20.0

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var pattern := _river_pattern(data)
	var determinism := _determinism(data)
	var direct_equivalence := _direct_equivalence(data)
	var seam_checks := _seam_checks(data)
	var benchmark := _benchmark(data)
	if float(pattern["separation_range"]) < SEPARATION_RANGE_MIN:
		_fail(
			"Stage 13 river lanes still read as a periodic translation: separation range %.3f < %.3f"
			% [float(pattern["separation_range"]), SEPARATION_RANGE_MIN]
		)
	if float(pattern["minimum_separation"]) <= float(data.STAGE5_VALLEY_OUTER) * 2.0:
		_fail("Stage 13 adjacent river lanes can collapse into overlapping valley corridors")
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail("Stage 13 shipping generation exceeded 1.0 ms p95: %d usec" % int(benchmark["p95_usec"]))
	var report := {
		"river_pattern": pattern,
		"determinism": determinism,
		"direct_equivalence": direct_equivalence,
		"seam_checks": seam_checks,
		"benchmark": benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE13_RIVER_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE13_RIVER_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _river_pattern(data) -> Dictionary:
	var minimum_separation := INF
	var maximum_separation := 0.0
	var separation_samples := 0
	var lane_motion: Dictionary = {}
	for lane in range(-4, 5):
		lane_motion[lane] = 0.0
		var previous := float(data.stage13_river_center_x(lane, -384.0))
		for z in range(-352, 385, 32):
			var current := float(data.stage13_river_center_x(lane, float(z)))
			lane_motion[lane] = float(lane_motion[lane]) + absf(current - previous)
			previous = current
	for z in range(-384, 385, 32):
		for lane in range(-4, 4):
			var left := float(data.stage13_river_center_x(lane, float(z)))
			var right := float(data.stage13_river_center_x(lane + 1, float(z)))
			var separation := right - left
			minimum_separation = minf(minimum_separation, separation)
			maximum_separation = maxf(maximum_separation, separation)
			separation_samples += 1
	var separation_range := maximum_separation - minimum_separation
	var identical_motion_pairs := 0
	for lane in range(-4, 4):
		if absf(float(lane_motion[lane]) - float(lane_motion[lane + 1])) < 0.001:
			identical_motion_pairs += 1
	if identical_motion_pairs > 0:
		_fail("Stage 13 still contains adjacent river lanes with identical motion signatures")
	return {
		"separation_samples": separation_samples,
		"minimum_separation": minimum_separation,
		"maximum_separation": maximum_separation,
		"separation_range": separation_range,
		"identical_motion_pairs": identical_motion_pairs,
		"theoretical_minimum_separation": data.STAGE13_RIVER_MIN_CENTER_SEPARATION,
	}


func _determinism(data) -> Dictionary:
	var coords := [Vector2i(-11, 7), Vector2i.ZERO, Vector2i(17, -9)]
	var arrays := 0
	for coord in coords:
		var first: Dictionary = CACHE.build(coord, data)
		var second: Dictionary = CACHE.build(coord, data)
		for key in ["world_fields", "heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
			arrays += 1
			if first.get(key) != second.get(key):
				_fail("Stage 13 cache is nondeterministic for %s at %s" % [key, coord])
	return {"chunks": coords.size(), "arrays_compared": arrays}


func _direct_equivalence(data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i(-7, -5), Vector2i(0, 0), Vector2i(11, -9), Vector2i(23, 17)]
	var columns := 0
	var river_columns := 0
	var water_columns := 0
	for coord in coords:
		var cache: Dictionary = CACHE.build(coord, data)
		var heights: PackedInt32Array = cache["heights"]
		var waters: PackedByteArray = cache["stage7_water_types"]
		var origin_x: int = coord.x * CHUNK_SIZE
		var origin_z: int = coord.y * CHUNK_SIZE
		for lz in range(-PADDING, CHUNK_SIZE + PADDING):
			for lx in range(-PADDING, CHUNK_SIZE + PADDING):
				var index := (lz + PADDING) * WIDTH + lx + PADDING
				var wx: int = origin_x + lx
				var wz: int = origin_z + lz
				var direct_height := int(data.terrain_height(wx, wz))
				var direct_water: Vector2i = data.water_info_at(wx, wz)
				if int(heights[index]) != direct_height:
					_fail("Stage 13 cache/direct height mismatch at (%d,%d): cache=%d direct=%d" % [wx, wz, int(heights[index]), direct_height])
				if int(waters[index]) != direct_water.x:
					_fail("Stage 13 cache/direct water mismatch at (%d,%d): cache=%d direct=%d" % [wx, wz, int(waters[index]), direct_water.x])
				if direct_water.x != data.WATER_NONE:
					water_columns += 1
				if direct_water.x == data.WATER_RIVER:
					river_columns += 1
				columns += 1
	if river_columns == 0:
		_fail("Stage 13 direct/cache equivalence fixtures did not exercise a river")
	return {"chunks": coords.size(), "columns": columns, "water_columns": water_columns, "river_columns": river_columns}


func _seam_checks(data) -> Dictionary:
	var pairs := [
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(-8, 5), Vector2i(-7, 5)],
		[Vector2i(12, -9), Vector2i(12, -8)],
		[Vector2i(-15, -4), Vector2i(-15, -3)],
	]
	var compared := 0
	for pair in pairs:
		var a_coord: Vector2i = pair[0]
		var b_coord: Vector2i = pair[1]
		var a: Dictionary = CACHE.build(a_coord, data)
		var b: Dictionary = CACHE.build(b_coord, data)
		var delta := b_coord - a_coord
		if delta.x == 1:
			for z in range(-PADDING, CHUNK_SIZE + PADDING):
				for offset in range(PADDING):
					var world_x := b_coord.x * CHUNK_SIZE + offset
					var a_lx := world_x - a_coord.x * CHUNK_SIZE
					var b_lx := world_x - b_coord.x * CHUNK_SIZE
					_compare_overlap(a, b, a_lx, z, b_lx, z, a_coord, b_coord)
					compared += 1
		elif delta.y == 1:
			for x in range(-PADDING, CHUNK_SIZE + PADDING):
				for offset in range(PADDING):
					var world_z := b_coord.y * CHUNK_SIZE + offset
					var a_lz := world_z - a_coord.y * CHUNK_SIZE
					var b_lz := world_z - b_coord.y * CHUNK_SIZE
					_compare_overlap(a, b, x, a_lz, x, b_lz, a_coord, b_coord)
					compared += 1
	return {"pairs": pairs.size(), "overlap_columns": compared}


func _compare_overlap(a: Dictionary, b: Dictionary, a_lx: int, a_lz: int, b_lx: int, b_lz: int, a_coord: Vector2i, b_coord: Vector2i) -> void:
	var ai := (a_lz + PADDING) * WIDTH + a_lx + PADDING
	var bi := (b_lz + PADDING) * WIDTH + b_lx + PADDING
	for key in ["heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
		if a[key][ai] != b[key][bi]:
			_fail("Stage 13 seam mismatch for %s between %s and %s" % [key, a_coord, b_coord])


func _benchmark(data) -> Dictionary:
	var coords := [Vector2i(-4,-2),Vector2i(-2,1),Vector2i(0,0),Vector2i(1,0),Vector2i(2,-1),Vector2i(4,2),Vector2i(8,-4),Vector2i(11,-3),Vector2i(12,-2),Vector2i(13,-2),Vector2i(14,-1),Vector2i(15,0),Vector2i(16,1),Vector2i(18,-4),Vector2i(20,2),Vector2i(-8,5)]
	for _warmup in range(WARMUPS):
		for coord in coords:
			CACHE.build(coord, data)
	var times: Array[int] = []
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var started := Time.get_ticks_usec()
			CACHE.build(coord, data)
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
		"methodology": "16 padded chunks, 4 warmups, 20 repeats; Stage 13 shipping generation/cache",
	}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
