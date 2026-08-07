extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const CHUNK_SIZE := 12
const WARMUPS := 4
const REPEATS := 20
const P95_LIMIT_USEC := 1000
const MAP_CENTER := Vector2i(157, -16)
const MAP_HALF_SPAN := 96
const MAP_SAMPLE_STEP := 2

var failures: Array[String] = []


func _init() -> void:
	var data = WORLD_DATA.new()
	_validate_height_contract(data)
	var terrain_report: Dictionary = _measure_terrain_shape(data)
	var benchmark_report: Dictionary = _benchmark_real_chunk_generation_and_meshing(data)
	if failures.is_empty():
		print("WORLD_HEIGHT_60_GATE_JSON=%s" % JSON.stringify({
			"terrain": terrain_report,
			"benchmark": benchmark_report,
		}))
		print("WORLD_HEIGHT_60_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_height_contract(data) -> void:
	if WORLD_DATA.WORLD_HEIGHT != 60:
		_fail("WORLD_HEIGHT must be exactly 60")
	if WORLD_DATA.TERRAIN_SHAPE_HEIGHT_SCALE < 4.5:
		_fail("Terrain-shape contribution was not increased proportionally from the 40-block profile")
	if WORLD_DATA.ROCKY_MOUNTAIN_BASE_RISE < 6.0:
		_fail("Rocky base rise did not scale with the added vertical headroom")
	if WORLD_DATA.ROCKY_MOUNTAIN_RUGGEDNESS < 16.5:
		_fail("Rocky ruggedness did not scale with the added vertical headroom")
	var synthetic_peak: int = data.terrain_height_from_samples(Vector4(1.0, 1.0, -1.0, -1.0))
	if synthetic_peak < 45:
		_fail("Synthetic rocky peak does not use the new 60-block vertical range: %d" % synthetic_peak)
	if synthetic_peak > WORLD_DATA.WORLD_HEIGHT - 3:
		_fail("Synthetic rocky peak clips the world safety margin")


func _measure_terrain_shape(data) -> Dictionary:
	var width: int = int((MAP_HALF_SPAN * 2) / MAP_SAMPLE_STEP) + 1
	var heights := PackedInt32Array()
	var legacy_heights := PackedInt32Array()
	heights.resize(width * width)
	legacy_heights.resize(width * width)
	var minimum: int = WORLD_DATA.WORLD_HEIGHT
	var maximum := 0
	var legacy_maximum := 0
	for row in range(width):
		var z: int = MAP_CENTER.y - MAP_HALF_SPAN + row * MAP_SAMPLE_STEP
		for column in range(width):
			var x: int = MAP_CENTER.x - MAP_HALF_SPAN + column * MAP_SAMPLE_STEP
			var samples: Vector4 = data.sample_column_noise(x, z)
			var height: int = data.terrain_height_from_samples(samples)
			var legacy_height: int = _legacy_40_height(samples)
			var index: int = row * width + column
			heights[index] = height
			legacy_heights[index] = legacy_height
			minimum = mini(minimum, height)
			maximum = maxi(maximum, height)
			legacy_maximum = maxi(legacy_maximum, legacy_height)

	var sorted: Array[int] = []
	for value in heights:
		sorted.append(int(value))
	sorted.sort()
	var median: int = sorted[int(sorted.size() * 0.50)]
	var p95: int = sorted[clampi(ceili(float(sorted.size()) * 0.95) - 1, 0, sorted.size() - 1)]
	var compared_edges := 0
	var shaped_edges := 0
	var ridge_points := 0
	for row in range(1, width - 1):
		for column in range(1, width - 1):
			var index: int = row * width + column
			var center: int = int(heights[index])
			var north: int = int(heights[index - width])
			var south: int = int(heights[index + width])
			var west: int = int(heights[index - 1])
			var east: int = int(heights[index + 1])
			for neighbor in [east, south]:
				compared_edges += 1
				if absi(center - int(neighbor)) >= 2:
					shaped_edges += 1
			if center >= north + 2 and center >= south + 2 and center >= west + 2 and center >= east + 2:
				ridge_points += 1
	var shaped_edge_ratio: float = float(shaped_edges) / float(maxi(compared_edges, 1))
	if maximum - minimum < 18:
		_fail("The real map-scale terrain range is still too flat: %d blocks" % (maximum - minimum))
	if p95 - median < 5:
		_fail("Upper terrain distribution lacks meaningful peaks above its median: median=%d p95=%d" % [median, p95])
	if maximum < legacy_maximum + 8:
		_fail("The 60-block profile does not materially exceed the former 40-block peak: new=%d legacy=%d" % [maximum, legacy_maximum])
	if shaped_edge_ratio < 0.015:
		_fail("Map-scale terrain lacks enough visible slopes/ridges: %.6f" % shaped_edge_ratio)
	if ridge_points < 4:
		_fail("Map-scale terrain contains too few distinct ridge/peak points: %d" % ridge_points)
	return {
		"sample_spacing_blocks": MAP_SAMPLE_STEP,
		"sample_width": width,
		"sample_count": heights.size(),
		"minimum_height": minimum,
		"median_height": median,
		"p95_height": p95,
		"maximum_height": maximum,
		"legacy_40_maximum_height": legacy_maximum,
		"height_range": maximum - minimum,
		"shaped_edge_ratio": shaped_edge_ratio,
		"ridge_points": ridge_points,
	}


func _legacy_40_height(samples: Vector4) -> int:
	var base_height: float = 10.0 + samples.x * 6.4 + samples.y * 3.0
	var cold_t: float = clampf(
		(samples.z - (WORLD_DATA.BIOME_COLD_THRESHOLD - WORLD_DATA.BIOME_BLEND_WIDTH))
		/ (WORLD_DATA.BIOME_BLEND_WIDTH * 2.0),
		0.0,
		1.0
	)
	cold_t = cold_t * cold_t * (3.0 - 2.0 * cold_t)
	var wet_t: float = clampf(
		(samples.w - (WORLD_DATA.BIOME_WET_THRESHOLD - WORLD_DATA.BIOME_BLEND_WIDTH))
		/ (WORLD_DATA.BIOME_BLEND_WIDTH * 2.0),
		0.0,
		1.0
	)
	wet_t = wet_t * wet_t * (3.0 - 2.0 * wet_t)
	var rocky_weight: float = (1.0 - cold_t) * (1.0 - wet_t)
	var land_factor: float = clampf((base_height - 6.0) / 3.0, 0.0, 1.0)
	land_factor = land_factor * land_factor * (3.0 - 2.0 * land_factor)
	var peak_strength: float = clampf((samples.y + 1.0) * 0.5, 0.0, 1.0)
	peak_strength *= peak_strength
	var mountain_rise: float = rocky_weight * land_factor * (4.0 + peak_strength * 11.0)
	return clampi(roundi(base_height + mountain_rise), 3, 37)


func _benchmark_real_chunk_generation_and_meshing(data) -> Dictionary:
	var runtime = WORLD_RUNTIME.new()
	runtime.data = data
	var coords: Array[Vector2i] = [
		Vector2i(-4, -2), Vector2i(-2, 1), Vector2i(0, 0), Vector2i(2, -1),
		Vector2i(4, 2), Vector2i(8, -4), Vector2i(11, -3), Vector2i(12, -2),
		Vector2i(13, -2), Vector2i(14, -1), Vector2i(15, 0), Vector2i(16, 1),
		Vector2i(18, -4), Vector2i(20, 2), Vector2i(-8, 5), Vector2i(6, 7),
	]
	for _warmup in range(WARMUPS):
		for coord in coords:
			_consume_real_chunk(runtime, data, coord)

	var times: Array[int] = []
	var face_checksum := 0
	var vertex_checksum := 0
	var height_checksum := 0
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var start: int = Time.get_ticks_usec()
			var consumed: Dictionary = _consume_real_chunk(runtime, data, coord)
			var elapsed: int = maxi(1, Time.get_ticks_usec() - start)
			times.append(elapsed)
			face_checksum += int(consumed["faces"])
			vertex_checksum += int(consumed["vertices"])
			height_checksum += int(consumed["height_checksum"])
	runtime.free()
	var stats: Dictionary = _stats(times)
	if int(stats["p95_usec"]) >= P95_LIMIT_USEC:
		_fail("Real per-chunk generation+meshing exceeded the committed 1.0 ms p95 threshold: %d usec" % int(stats["p95_usec"]))
	return {
		"methodology": {
			"warmup_repetitions": WARMUPS,
			"measured_repetitions": REPEATS,
			"representative_chunks": coords.size(),
			"measured_chunks": times.size(),
			"chunk_size": CHUNK_SIZE,
			"world_height": WORLD_DATA.WORLD_HEIGHT,
			"included_work": "shipping column-cache generation plus playable_world_mesher.build including block cache, sky light, AO, vertices, colors and indices",
			"excluded_work": ["ArrayMesh upload", "collision generation", "scene-tree mutation", "file I/O"],
			"p95_limit_usec": P95_LIMIT_USEC,
		},
		"stats": stats,
		"face_checksum": face_checksum,
		"vertex_checksum": vertex_checksum,
		"height_checksum": height_checksum,
		"raw_usec": times,
	}


func _consume_real_chunk(runtime, data, coord: Vector2i) -> Dictionary:
	var caches: Dictionary = runtime._build_column_caches(coord)
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh: Dictionary = WORLD_MESHER.build(
		coord,
		heights,
		data.overrides,
		CHUNK_SIZE,
		WORLD_DATA.WORLD_HEIGHT,
		WORLD_DATA.SEA_LEVEL,
		biomes
	)
	var height_checksum := 0
	for height in heights:
		height_checksum += int(height)
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	return {
		"faces": int(mesh.get("face_count", 0)),
		"vertices": vertices.size(),
		"height_checksum": height_checksum,
	}


func _stats(values: Array[int]) -> Dictionary:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count: int = sorted.size()
	var mean: float = float(total) / float(count)
	var middle: int = int(count / 2)
	var median: float = float(sorted[middle])
	if count % 2 == 0:
		median = (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
	var p95_index: int = clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)
	return {
		"sample_count": count,
		"minimum_usec": sorted[0],
		"maximum_usec": sorted[count - 1],
		"mean_usec": mean,
		"median_usec": median,
		"p95_usec": sorted[p95_index],
		"minimum_ms": float(sorted[0]) / 1000.0,
		"maximum_ms": float(sorted[count - 1]) / 1000.0,
		"mean_ms": mean / 1000.0,
		"median_ms": median / 1000.0,
		"p95_ms": float(sorted[p95_index]) / 1000.0,
	}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
