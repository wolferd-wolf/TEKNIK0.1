extends SceneTree

const SHIPPING_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const COORDS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(4, -3), Vector2i(4, 0), Vector2i(4, 2), Vector2i(-2, 7),
]
const REPEATS := 4

var failures: Array[String] = []


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _array_mesh_from_data(mesh_data: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_result(coord: Vector2i, revision: int) -> Dictionary:
	var sink: Dictionary = {}
	var mutex := Mutex.new()
	var key := "%d:%d:%d" % [coord.x, coord.y, revision]
	SHIPPING_RUNTIME._stage3_worker_build_chunk(coord, {}, revision, sink, mutex, key)
	return sink.get(key, {})


func _init() -> void:
	var runtime := SHIPPING_RUNTIME.new()
	var render_upload_ms: Array[float] = []
	var old_collision_ms: Array[float] = []
	var new_collision_ms: Array[float] = []
	var split_frame_peak_ms: Array[float] = []
	var old_same_frame_ms: Array[float] = []
	var collision_data_ms: Array[float] = []
	var samples := 0

	# Warm the shipping path before timing engine resource construction.
	var warm := _build_result(COORDS[0], 1)
	if warm.is_empty():
		_fail("warmup shipping result is empty")

	for repeat in range(REPEATS):
		for coord_index in range(COORDS.size()):
			var coord := COORDS[coord_index]
			var result := _build_result(coord, 100 + repeat * COORDS.size() + coord_index)
			if result.is_empty():
				_fail("shipping result missing for %s" % coord)
				continue
			var mesh_data: Dictionary = result.get("mesh_data", {})
			var faces: PackedVector3Array = mesh_data.get(
				SHIPPING_RUNTIME.COLLISION_FACES_KEY,
				PackedVector3Array()
			)
			var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
			if faces.is_empty() or faces.size() != indices.size() or faces.size() % 3 != 0:
				_fail("invalid worker collision faces for %s" % coord)
				continue
			collision_data_ms.append(float(int(result.get("collision_data_usec", 0))) / 1000.0)

			var render_started := Time.get_ticks_usec()
			var mesh := _array_mesh_from_data(mesh_data)
			var render_ms := float(Time.get_ticks_usec() - render_started) / 1000.0
			if mesh.get_surface_count() != 1:
				_fail("render mesh missing surface for %s" % coord)
				continue

			var old_started := Time.get_ticks_usec()
			var old_shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
			var old_ms := float(Time.get_ticks_usec() - old_started) / 1000.0
			if old_shape == null:
				_fail("legacy collision shape failed for %s" % coord)
				continue
			old_shape.backface_collision = true

			var new_started := Time.get_ticks_usec()
			var collision := runtime._create_collision_from_faces(faces)
			var new_ms := float(Time.get_ticks_usec() - new_started) / 1000.0
			if collision == null:
				_fail("precomputed-face collision failed for %s" % coord)
				continue
			var shape_node: CollisionShape3D = null
			if collision.get_child_count() == 1:
				shape_node = collision.get_child(0) as CollisionShape3D
			var new_shape := shape_node.shape as ConcavePolygonShape3D if shape_node != null else null
			if new_shape == null:
				_fail("precomputed-face collision shape missing for %s" % coord)
				collision.free()
				continue
			if new_shape.get_faces() != faces:
				_fail("precomputed collision faces changed for %s" % coord)
			if old_shape.get_faces().size() != faces.size():
				_fail("legacy/new triangle count differs for %s" % coord)

			render_upload_ms.append(render_ms)
			old_collision_ms.append(old_ms)
			new_collision_ms.append(new_ms)
			old_same_frame_ms.append(render_ms + old_ms)
			split_frame_peak_ms.append(maxf(render_ms, new_ms))
			samples += 1
			collision.free()

	var render_p95 := _percentile(render_upload_ms, 0.95)
	var old_collision_p95 := _percentile(old_collision_ms, 0.95)
	var new_collision_p95 := _percentile(new_collision_ms, 0.95)
	var old_same_frame_p95 := _percentile(old_same_frame_ms, 0.95)
	var split_peak_p95 := _percentile(split_frame_peak_ms, 0.95)
	var improvement := 0.0
	if old_same_frame_p95 > 0.0:
		improvement = 1.0 - split_peak_p95 / old_same_frame_p95

	if samples != COORDS.size() * REPEATS:
		_fail("expected %d samples, got %d" % [COORDS.size() * REPEATS, samples])
	if new_collision_p95 > old_collision_p95 * 1.10:
		_fail("precomputed collision p95 regressed: new=%.3f old=%.3f" % [new_collision_p95, old_collision_p95])
	if split_peak_p95 >= old_same_frame_p95:
		_fail("split frame peak did not improve: split=%.3f old_same_frame=%.3f" % [split_peak_p95, old_same_frame_p95])

	print("CHUNK_APPLY_HITCH_GATE_JSON=%s" % JSON.stringify({
		"samples": samples,
		"render_upload_p95_ms": render_p95,
		"legacy_collision_p95_ms": old_collision_p95,
		"precomputed_collision_p95_ms": new_collision_p95,
		"legacy_same_frame_p95_ms": old_same_frame_p95,
		"split_frame_peak_p95_ms": split_peak_p95,
		"split_peak_reduction": improvement,
		"collision_data_p95_ms": _percentile(collision_data_ms, 0.95),
		"failures": failures,
	}))
	if failures.is_empty():
		print("CHUNK_APPLY_HITCH_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
