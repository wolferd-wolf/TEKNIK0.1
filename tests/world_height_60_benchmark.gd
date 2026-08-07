extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const CHUNK_SIZE := 12
const WARMUPS := 4
const REPEATS := 20
const P95_LIMIT_USEC := 1000


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
	for _warmup in range(WARMUPS):
		for coord in coords:
			_consume(runtime, data, coord)
	var times: Array[int] = []
	var faces := 0
	var vertices := 0
	var height_checksum := 0
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var start: int = Time.get_ticks_usec()
			var result: Dictionary = _consume(runtime, data, coord)
			times.append(maxi(1, Time.get_ticks_usec() - start))
			faces += int(result["faces"])
			vertices += int(result["vertices"])
			height_checksum += int(result["height_checksum"])
	runtime.free()
	var stats: Dictionary = _stats(times)
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
			"measured_chunks": times.size(),
			"chunk_size": CHUNK_SIZE,
			"world_height": WORLD_DATA.WORLD_HEIGHT,
			"included_work": "shipping _build_column_caches plus playable_world_mesher.build including block cache, sky light, AO, vertices, colors and indices",
			"excluded_work": ["ArrayMesh upload", "collision generation", "scene-tree mutation", "file I/O"],
			"p95_limit_usec": P95_LIMIT_USEC,
		},
		"stats": stats,
		"face_checksum": faces,
		"vertex_checksum": vertices,
		"height_checksum": height_checksum,
		"raw_usec": times,
	}
	print("WORLD_HEIGHT_60_BENCHMARK_JSON=%s" % JSON.stringify(report))
	if int(stats["p95_usec"]) >= P95_LIMIT_USEC:
		push_error("WORLD_HEIGHT_60_BENCHMARK_FAIL p95=%d usec threshold=%d usec" % [int(stats["p95_usec"]), P95_LIMIT_USEC])
		quit(1)
		return
	print("WORLD_HEIGHT_60_BENCHMARK_PASS")
	quit(0)


func _consume(runtime, data, coord: Vector2i) -> Dictionary:
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
	var checksum := 0
	for height in heights:
		checksum += int(height)
	var mesh_vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	return {
		"faces": int(mesh.get("face_count", 0)),
		"vertices": mesh_vertices.size(),
		"height_checksum": checksum,
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
