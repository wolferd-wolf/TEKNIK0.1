extends SceneTree

const SHIPPING_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")

const SAMPLE_COORDS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, -1),
	Vector2i(-2, 1),
	Vector2i(2, -2),
	Vector2i(-4, 7),
	Vector2i(-1, -2),
]
const WARMUPS := 1
const REPEATS := 4

var failures: Array[String] = []


func _p95(values: Array[int]) -> int:
	var ordered := values.duplicate()
	ordered.sort()
	var index := clampi(ceili(float(ordered.size()) * 0.95) - 1, 0, ordered.size() - 1)
	return int(ordered[index])


func _mean(values: Array[int]) -> float:
	var total := 0
	for value in values:
		total += value
	return float(total) / float(values.size())


func _sample(coord: Vector2i, revision: int) -> Dictionary:
	var sink: Dictionary = {}
	var mutex := Mutex.new()
	var key := "%d:%d:%d" % [coord.x, coord.y, revision]
	SHIPPING_RUNTIME._stage3_worker_build_chunk(
		coord,
		{},
		revision,
		sink,
		mutex,
		key
	)
	if not sink.has(key):
		failures.append("Worker produced no result for %s" % coord)
		return {}
	return sink[key]


func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		failures.append("TeknikCarpathianSampler native extension is not loaded")

	for warmup in range(WARMUPS):
		for coord in SAMPLE_COORDS:
			_sample(coord, -100 - warmup)

	var cache_values: Array[int] = []
	var mesh_values: Array[int] = []
	var compute_values: Array[int] = []
	var face_counts: Array[int] = []
	var mesh_heights: Array[int] = []
	for repeat in range(REPEATS):
		for coord in SAMPLE_COORDS:
			var result := _sample(coord, repeat + 1)
			if result.is_empty():
				continue
			var mesh_data: Dictionary = result.get("mesh_data", {})
			var faces := int(mesh_data.get("face_count", 0))
			if faces <= 0:
				failures.append("Chunk %s produced no mesh faces" % coord)
			cache_values.append(int(result.get("cache_usec", 0)))
			mesh_values.append(int(result.get("mesh_usec", 0)))
			compute_values.append(int(result.get("compute_usec", 0)))
			face_counts.append(faces)
			mesh_heights.append(int(result.get("mesh_height", 0)))

	if cache_values.is_empty() or mesh_values.is_empty():
		failures.append("No performance samples were collected")
	else:
		var report := {
			"methodology": "%d warmup x %d coords; %d repeats = %d measured shipping worker builds" % [
				WARMUPS, SAMPLE_COORDS.size(), REPEATS, mesh_values.size()
			],
			"cache": {
				"mean_ms": _mean(cache_values) / 1000.0,
				"p95_ms": float(_p95(cache_values)) / 1000.0,
				"max_ms": float(cache_values.max()) / 1000.0,
			},
			"mesh": {
				"mean_ms": _mean(mesh_values) / 1000.0,
				"p95_ms": float(_p95(mesh_values)) / 1000.0,
				"max_ms": float(mesh_values.max()) / 1000.0,
			},
			"compute": {
				"mean_ms": _mean(compute_values) / 1000.0,
				"p95_ms": float(_p95(compute_values)) / 1000.0,
				"max_ms": float(compute_values.max()) / 1000.0,
			},
			"face_count_min": face_counts.min(),
			"face_count_max": face_counts.max(),
			"mesh_height_min": mesh_heights.min(),
			"mesh_height_max": mesh_heights.max(),
			"mesh_to_cache_p95_ratio": float(_p95(mesh_values)) / maxf(float(_p95(cache_values)), 1.0),
		}
		print("CHUNK_GENERATION_PERF_BASELINE_JSON=%s" % JSON.stringify(report))

	if failures.is_empty():
		print("CHUNK_GENERATION_PERF_BASELINE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
