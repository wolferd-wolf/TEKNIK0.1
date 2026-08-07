extends SceneTree

const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const CHUNK_SIZE := 12
const WORLD_HEIGHT := 60
const SEA_LEVEL := 7
const CACHE_PADDING := 2
const TASK_COUNT := 24


func _init() -> void:
	var failures := PackedStringArray()
	_assert_threaded_source_contract(failures)
	_assert_lookup_equivalence(failures)

	var expected_signature := _build_signature()
	_expect(expected_signature != 0, "Reference mesh signature must be non-zero", failures)
	_run_concurrent_builds(expected_signature, failures)

	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return

	print("ANDROID_THREADED_MESHER_SHARED_ARRAY_ACCESS_REMOVED_PASS")
	print("ANDROID_THREADED_MESHER_TABLE_EQUIVALENCE_PASS")
	print("ANDROID_THREADED_MESHER_CONCURRENCY_PASS tasks=%d signature=%d" % [TASK_COUNT, expected_signature])
	print("ANDROID_THREADED_MESHER_GATE_PASS")
	quit(0)


func _assert_threaded_source_contract(failures: PackedStringArray) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/world/playable_world_mesher.gd")
	_expect(not source.is_empty(), "Mesher source must be readable", failures)
	for forbidden: String in [
		"FACE_DIRECTIONS[",
		"FACE_NORMALS[",
		"FACE_VERTICES[",
		"FACE_TANGENT_AXES[",
		"AO_BRIGHTNESS[",
	]:
		_expect(
			not source.contains(forbidden),
			"Threaded mesher must not index shared Array table %s" % forbidden,
			failures
		)
	_expect(
		source.contains("_vertex_ao_level_cached_with_basis"),
		"Threaded AO path must receive face basis by value",
		failures
	)
	_expect(
		source.contains("_vertex_sky_factor_with_basis"),
		"Threaded skylight path must receive face basis by value",
		failures
	)


func _assert_lookup_equivalence(failures: PackedStringArray) -> void:
	for face_index in range(6):
		_expect(
			WORLD_MESHER._face_direction(face_index) == WORLD_MESHER.FACE_DIRECTIONS[face_index],
			"Face direction %d changed" % face_index,
			failures
		)
		_expect(
			WORLD_MESHER._face_normal(face_index) == WORLD_MESHER.FACE_NORMALS[face_index],
			"Face normal %d changed" % face_index,
			failures
		)
		_expect(
			WORLD_MESHER._face_tangent_axes(face_index) == WORLD_MESHER.FACE_TANGENT_AXES[face_index],
			"Face tangent axes %d changed" % face_index,
			failures
		)
		for vertex_index in range(4):
			var expected_vertex: Vector3 = WORLD_MESHER.FACE_VERTICES[face_index][vertex_index]
			_expect(
				WORLD_MESHER._face_vertex(face_index, vertex_index) == expected_vertex,
				"Face %d vertex %d changed" % [face_index, vertex_index],
				failures
			)
	for ao_level in range(4):
		_expect(
			is_equal_approx(WORLD_MESHER._ao_brightness(ao_level), WORLD_MESHER.AO_BRIGHTNESS[ao_level]),
			"AO brightness %d changed" % ao_level,
			failures
		)
	var diagonal_levels: Array[int] = [3, 0, 3, 0]
	_expect(
		WORLD_MESHER._should_flip_ao_diagonal(diagonal_levels)
		== WORLD_MESHER._should_flip_ao_diagonal_values(3, 0, 3, 0),
		"AO diagonal selection changed",
		failures
	)


func _run_concurrent_builds(expected_signature: int, failures: PackedStringArray) -> void:
	var sink: Dictionary = {}
	var sink_mutex := Mutex.new()
	var task_ids: Array[int] = []
	for task_index in range(TASK_COUNT):
		var task_id := WorkerThreadPool.add_task(
			Callable(get_script(), "_worker_build").bind(task_index, sink, sink_mutex),
			false,
			"TEKNIK Android mesher race gate %d" % task_index
		)
		_expect(task_id >= 0, "Worker task %d failed to submit" % task_index, failures)
		if task_id >= 0:
			task_ids.append(task_id)

	for task_id: int in task_ids:
		var wait_error := WorkerThreadPool.wait_for_task_completion(task_id)
		_expect(wait_error == OK, "Worker task %d wait failed: %d" % [task_id, wait_error], failures)

	_expect(sink.size() == task_ids.size(), "Every worker must publish a result", failures)
	for task_index in range(TASK_COUNT):
		if not sink.has(task_index):
			_expect(false, "Worker %d published no signature" % task_index, failures)
			continue
		var signature := int(sink[task_index])
		_expect(
			signature == expected_signature,
			"Worker %d mesh signature changed: expected %d got %d"
			% [task_index, expected_signature, signature],
			failures
		)


static func _worker_build(task_index: int, sink: Dictionary, sink_mutex: Mutex) -> void:
	var signature := _build_signature()
	sink_mutex.lock()
	sink[task_index] = signature
	sink_mutex.unlock()


static func _build_signature() -> int:
	var width := CHUNK_SIZE + CACHE_PADDING * 2
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(width * width)
	biomes.resize(width * width)
	for z in range(width):
		for x in range(width):
			var index := z * width + x
			heights[index] = 9 + ((x * 3 + z * 5) % 9)
			biomes[index] = (x + z * 2) % 4
	var overrides: Dictionary = {
		"2,18,2": WORLD_MESHER.BLOCK_LOG,
		"3,18,2": WORLD_MESHER.BLOCK_LEAVES,
		"4,18,2": WORLD_MESHER.BLOCK_AIR,
	}
	var mesh_data: Dictionary = WORLD_MESHER.build(
		Vector2i.ZERO,
		heights,
		overrides,
		CHUNK_SIZE,
		WORLD_HEIGHT,
		SEA_LEVEL,
		biomes
	)
	return _mesh_signature(mesh_data)


static func _mesh_signature(mesh_data: Dictionary) -> int:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var signature := int(mesh_data.get("face_count", 0)) * 1000003
	signature += vertices.size() * 1009
	signature += normals.size() * 1013
	signature += colors.size() * 1019
	signature += indices.size() * 1021
	for vertex: Vector3 in vertices:
		signature = _mix(signature, roundi(vertex.x * 16.0))
		signature = _mix(signature, roundi(vertex.y * 16.0))
		signature = _mix(signature, roundi(vertex.z * 16.0))
	for normal: Vector3 in normals:
		signature = _mix(signature, roundi(normal.x * 16.0))
		signature = _mix(signature, roundi(normal.y * 16.0))
		signature = _mix(signature, roundi(normal.z * 16.0))
	for color: Color in colors:
		signature = _mix(signature, roundi(color.r * 4096.0))
		signature = _mix(signature, roundi(color.g * 4096.0))
		signature = _mix(signature, roundi(color.b * 4096.0))
	for mesh_index: int in indices:
		signature = _mix(signature, mesh_index)
	return signature


static func _mix(current: int, value: int) -> int:
	return posmod(current * 31 + value + 17, 2147483647)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
