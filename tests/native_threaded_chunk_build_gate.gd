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


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


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

	var runtime := SHIPPING_RUNTIME.new()
	var entry_apply_ms: Array[float] = []
	var collision_attach_ms: Array[float] = []
	var resource_ms: Array[float] = []
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

		var prepared_mesh := result.get("prepared_mesh") as ArrayMesh
		var prepared_shape := result.get("prepared_collision_shape") as ConcavePolygonShape3D
		if prepared_mesh == null or prepared_mesh.get_surface_count() != 1:
			_fail("Worker result %s has no prepared ArrayMesh" % key)
			continue
		if prepared_shape == null:
			_fail("Worker result %s has no prepared collision shape" % key)
			continue
		if prepared_mesh.get_meta(SHIPPING_RUNTIME.PREPARED_COLLISION_META, null) != prepared_shape:
			_fail("Worker result %s did not bind prepared collision shape to mesh" % key)
		resource_ms.append(float(int(result.get("resource_usec", 0))) / 1000.0)

		var apply_mesh_data := mesh_data.duplicate(false)
		apply_mesh_data["_prepared_mesh"] = prepared_mesh
		var apply_started := Time.get_ticks_usec()
		var entry: Dictionary = runtime._create_entry(COORDS[index], apply_mesh_data, false)
		entry_apply_ms.append(float(Time.get_ticks_usec() - apply_started) / 1000.0)
		if entry.is_empty() or entry.get("mesh") != prepared_mesh:
			_fail("Main-thread entry %s rebuilt or lost the prepared mesh" % key)
		else:
			var root := entry.get("root") as Node3D
			if is_instance_valid(root):
				root.free()

		var collision_started := Time.get_ticks_usec()
		var collision := runtime._create_collision(prepared_mesh)
		collision_attach_ms.append(float(Time.get_ticks_usec() - collision_started) / 1000.0)
		if collision == null:
			_fail("Prepared collision %s could not attach" % key)
		else:
			var shape_node := collision.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if shape_node == null or shape_node.shape != prepared_shape:
				_fail("Collision %s rebuilt or lost the prepared shape" % key)
			collision.free()

	entry_apply_ms.sort()
	collision_attach_ms.sort()
	resource_ms.sort()
	print("NATIVE_THREADED_CHUNK_BUILD_JSON=%s" % JSON.stringify({
		"tasks_submitted": task_ids.size(),
		"results": result_sink.size(),
		"wall_ms": float(elapsed_usec) / 1000.0,
		"resource_prepare_p95_ms": _percentile(resource_ms, 0.95),
		"main_entry_attach_p95_ms": _percentile(entry_apply_ms, 0.95),
		"main_collision_attach_p95_ms": _percentile(collision_attach_ms, 0.95),
		"failures": failures,
	}))
	if failures.is_empty() and result_sink.size() == COORDS.size():
		print("NATIVE_THREADED_CHUNK_BUILD_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
