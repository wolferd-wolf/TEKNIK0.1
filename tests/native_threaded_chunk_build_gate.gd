extends SceneTree

const SHIPPING_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const NATIVE_CLASS := &"TeknikVoxelMesher"
const COORDS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(-2, 7), Vector2i(-1, 8), Vector2i(-1, -2), Vector2i(0, -2),
]

var result_sink: Dictionary = {}
var result_mutex := Mutex.new()
var failures: Array[String] = []


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _init() -> void:
	if not ClassDB.class_exists(NATIVE_CLASS):
		_fail("TeknikVoxelMesher native class is not loaded")

	var task_ids: Array[int] = []
	var keys: Array[String] = []
	var started_usec := Time.get_ticks_usec()
	for index in range(COORDS.size()):
		var coord := COORDS[index]
		var revision := index + 1
		var key := "%d:%d:%d" % [coord.x, coord.y, revision]
		keys.append(key)
		var callable := Callable(SHIPPING_RUNTIME, "_stage3_worker_build_chunk").bind(
			coord,
			{},
			revision,
			result_sink,
			result_mutex,
			key
		)
		var task_id := WorkerThreadPool.add_task(
			callable,
			false,
			"TEKNIK native threaded chunk %s" % coord
		)
		if task_id < 0:
			_fail("WorkerThreadPool rejected %s" % coord)
			continue
		task_ids.append(task_id)

	for task_id in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	var elapsed_usec := Time.get_ticks_usec() - started_usec

	for index in range(keys.size()):
		var key := keys[index]
		if not result_sink.has(key):
			_fail("Missing worker result %s" % key)
			continue
		var result: Dictionary = result_sink[key]
		var mesh_data: Dictionary = result.get("mesh_data", {})
		var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
		var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
		if int(mesh_data.get("face_count", 0)) <= 0:
			_fail("Worker result %s has no faces" % key)
		if vertices.is_empty() or indices.is_empty():
			_fail("Worker result %s has empty mesh arrays" % key)
		if indices.size() % 3 != 0:
			_fail("Worker result %s has non-triangle index count" % key)

	print("NATIVE_THREADED_CHUNK_BUILD_JSON=%s" % JSON.stringify({
		"tasks_submitted": task_ids.size(),
		"results": result_sink.size(),
		"wall_ms": float(elapsed_usec) / 1000.0,
		"failures": failures,
	}))
	if failures.is_empty() and result_sink.size() == COORDS.size():
		print("NATIVE_THREADED_CHUNK_BUILD_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
