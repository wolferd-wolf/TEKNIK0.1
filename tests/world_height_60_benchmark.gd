extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const WARMUPS := 4
const REPEATS := 20
const GENERATION_P95_LIMIT_USEC := 1000
const MESH_P95_RATIO_LIMIT := 1.65
const LEGACY_WORLD_HEIGHT := 40

var failures: Array[String] = []


func _init() -> void:
	var data = WORLD_DATA.new()
	var runtime = WORLD_RUNTIME.new()
	runtime.data = data
	var coords: Array[Vector2i] = [
		Vector2i(-4, -2), Vector2i(-2, 1), Vector2i(0, 0), Vector2i(2, -1),
		Vector2i(4, 2), Vector2i(8, -4), Vector2i(11, -3), Vector2i(12, -2),
		Vector2i(13, -2), Vector2i(14, -1), Vector2i(15, 0), Vector2i(16, 1),
		Vector2i(18, -4), Vector2i(20, 2), Vector2i(-8, 5), Vector2i(6, 7),
	]
	var generation: Dictionary = _benchmark_generation(runtime, coords)
	var meshing: Dictionary = _benchmark_meshing(runtime, data, coords)
	runtime.free()
	if int(generation["stats"]["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail("Column generation exceeded the existing 1.0 ms p95 threshold: %d usec" % int(generation["stats"]["p95_usec"]))
	if float(meshing["p95_ratio_60_over_40"]) > MESH_P95_RATIO_LIMIT:
		_fail("60-block meshing grew beyond the bounded 1.5x scan-cost expectation: %.4fx" % float(meshing["p95_ratio_60_over_40"]))
	var report := {
		"runner": {
			"os_name": OS.get_name(),
			"processor_name": OS.get_processor_name(),
			"processor_count": OS.get_processor_count(),
			"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		},
		"methodology": {
			"warmup_repetitions": WARMUPS,
			"measured_repetitions": REPEATS,
			"representative_chunks": coords.size(),
			"measured_chunks_per_path": coords.size() * REPEATS,
			"chunk_size": CHUNK_SIZE,
			"cache_padding": CACHE_PADDING,
			"world_height": WORLD_DATA.WORLD_HEIGHT,
			"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
			"mesh_p95_ratio_limit": MESH_P95_RATIO_LIMIT,
		},
		"generation": generation,
		"meshing": meshing,
		"failures": failures,
	}
	print("WORLD_HEIGHT_60_BENCHMARK_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_HEIGHT_60_BENCHMARK_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _benchmark_generation(runtime, coords: Array[Vector2i]) -> Dictionary:
	for _warmup in range(WARMUPS):
		for coord in coords:
			_consume_caches(runtime._build_column_caches(coord))
	var times: Array[int] = []
	var height_checksum := 0
	var biome_checksum := 0
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var start: int = Time.get_ticks_usec()
			var sums: Dictionary = _consume_caches(runtime._build_column_caches(coord))
			times.append(maxi(1, Time.get_ticks_usec() - start))
			height_checksum += int(sums["height"])
			biome_checksum += int(sums["biome"])
	return {
		"included_work": "shipping cache allocation, one four-noise vector per padded column, height calculation, biome weights, deterministic blend selection and cache writes",
		"excluded_work": ["meshing", "rendering", "collision generation", "scene-tree mutation", "file I/O"],
		"stats": _stats(times),
		"height_checksum": height_checksum,
		"biome_checksum": biome_checksum,
		"raw_usec": times,
	}


func _benchmark_meshing(runtime, data, coords: Array[Vector2i]) -> Dictionary:
	var current_caches: Dictionary = {}
	var legacy_caches: Dictionary = {}
	for coord in coords:
		current_caches[coord] = runtime._build_column_caches(coord)
		legacy_caches[coord] = _build_legacy_caches(data, coord)
	for _warmup in range(WARMUPS):
		for coord in coords:
			_consume_mesh(_mesh(data, coord, legacy_caches[coord], LEGACY_WORLD_HEIGHT))
			_consume_mesh(_mesh(data, coord, current_caches[coord], WORLD_DATA.WORLD_HEIGHT))
	var legacy_times: Array[int] = []
	var current_times: Array[int] = []
	var legacy_faces := 0
	var current_faces := 0
	var legacy_vertices := 0
	var current_vertices := 0
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			if (repetition + index) % 2 == 0:
				var legacy: Dictionary = _measure_mesh(data, coord, legacy_caches[coord], LEGACY_WORLD_HEIGHT)
				var current: Dictionary = _measure_mesh(data, coord, current_caches[coord], WORLD_DATA.WORLD_HEIGHT)
				legacy_times.append(int(legacy["usec"]))
				current_times.append(int(current["usec"]))
				legacy_faces += int(legacy["faces"])
				current_faces += int(current["faces"])
				legacy_vertices += int(legacy["vertices"])
				current_vertices += int(current["vertices"])
			else:
				var current: Dictionary = _measure_mesh(data, coord, current_caches[coord], WORLD_DATA.WORLD_HEIGHT)
				var legacy: Dictionary = _measure_mesh(data, coord, legacy_caches[coord], LEGACY_WORLD_HEIGHT)
				current_times.append(int(current["usec"]))
				legacy_times.append(int(legacy["usec"]))
				current_faces += int(current["faces"])
				legacy_faces += int(legacy["faces"])
				current_vertices += int(current["vertices"])
				legacy_vertices += int(legacy["vertices"])
	var legacy_stats: Dictionary = _stats(legacy_times)
	var current_stats: Dictionary = _stats(current_times)
	return {
		"included_work": "playable_world_mesher.build block cache, sky light, ambient occlusion, vertices, colors and indices using prebuilt column caches",
		"excluded_work": ["column generation", "ArrayMesh upload", "collision generation", "scene-tree mutation", "file I/O"],
		"baseline_40": legacy_stats,
		"current_60": current_stats,
		"p95_ratio_60_over_40": float(current_stats["p95_usec"]) / float(legacy_stats["p95_usec"]),
		"mean_ratio_60_over_40": float(current_stats["mean_usec"]) / float(legacy_stats["mean_usec"]),
		"baseline_face_checksum": legacy_faces,
		"current_face_checksum": current_faces,
		"baseline_vertex_checksum": legacy_vertices,
		"current_vertex_checksum": current_vertices,
		"raw_baseline_40_usec": legacy_times,
		"raw_current_60_usec": current_times,
	}


func _build_legacy_caches(data, coord: Vector2i) -> Dictionary:
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(CACHE_WIDTH * CACHE_WIDTH)
	biomes.resize(CACHE_WIDTH * CACHE_WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var samples: Vector4 = data.sample_column_noise(world_x, world_z)
			var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
			heights[index] = _legacy_40_height(samples)
			biomes[index] = data.blended_biome_from_samples(samples, world_x, world_z)
	return {"heights": heights, "biomes": biomes}


func _legacy_40_height(samples: Vector4) -> int:
	var base_height: float = 10.0 + samples.x * 6.4 + samples.y * 3.0
	var cold_t: float = clampf((samples.z - (WORLD_DATA.BIOME_COLD_THRESHOLD - WORLD_DATA.BIOME_BLEND_WIDTH)) / (WORLD_DATA.BIOME_BLEND_WIDTH * 2.0), 0.0, 1.0)
	cold_t = cold_t * cold_t * (3.0 - 2.0 * cold_t)
	var wet_t: float = clampf((samples.w - (WORLD_DATA.BIOME_WET_THRESHOLD - WORLD_DATA.BIOME_BLEND_WIDTH)) / (WORLD_DATA.BIOME_BLEND_WIDTH * 2.0), 0.0, 1.0)
	wet_t = wet_t * wet_t * (3.0 - 2.0 * wet_t)
	var rocky_weight: float = (1.0 - cold_t) * (1.0 - wet_t)
	var land_factor: float = clampf((base_height - 6.0) / 3.0, 0.0, 1.0)
	land_factor = land_factor * land_factor * (3.0 - 2.0 * land_factor)
	var peak_strength: float = clampf((samples.y + 1.0) * 0.5, 0.0, 1.0)
	peak_strength *= peak_strength
	return clampi(roundi(base_height + rocky_weight * land_factor * (4.0 + peak_strength * 11.0)), 3, LEGACY_WORLD_HEIGHT - 3)


func _mesh(data, coord: Vector2i, caches: Dictionary, world_height: int) -> Dictionary:
	return WORLD_MESHER.build(
		coord,
		caches.get("heights", PackedInt32Array()),
		data.overrides,
		CHUNK_SIZE,
		world_height,
		WORLD_DATA.SEA_LEVEL,
		caches.get("biomes", PackedByteArray())
	)


func _measure_mesh(data, coord: Vector2i, caches: Dictionary, world_height: int) -> Dictionary:
	var start := Time.get_ticks_usec()
	var mesh: Dictionary = _mesh(data, coord, caches, world_height)
	var usec := maxi(1, Time.get_ticks_usec() - start)
	var consumed: Dictionary = _consume_mesh(mesh)
	consumed["usec"] = usec
	return consumed


func _consume_caches(caches: Dictionary) -> Dictionary:
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var height_sum := 0
	var biome_sum := 0
	for height in heights:
		height_sum += int(height)
	for biome in biomes:
		biome_sum += int(biome) + 1
	return {"height": height_sum, "biome": biome_sum}


func _consume_mesh(mesh: Dictionary) -> Dictionary:
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	return {"faces": int(mesh.get("face_count", 0)), "vertices": vertices.size()}


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
