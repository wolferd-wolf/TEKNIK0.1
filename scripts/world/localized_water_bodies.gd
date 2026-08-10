extends Node3D

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WATER_BUILDER := preload("res://scripts/world/localized_water_mesh_builder.gd")
const WORKER_DATA := preload("res://scripts/world/playable_world_worker_carpathian_data.gd")
const OVERRIDE_SPATIAL_INDEX := preload("res://scripts/world/playable_world_override_spatial_index.gd")

const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const WATER_NONE := 0
const MAX_WATER_WORKERS := 2

@export var streaming_target_path := NodePath("../../Player")

var _active := false
var _center := Vector2i(2147483647, 2147483647)
var _data = WORLD_DATA.new()
var _material := StandardMaterial3D.new()
var _chunks: Dictionary = {}
var _water_queue: Array[Vector2i] = []
var _water_active_tasks: Dictionary = {}
var _water_completed_results: Dictionary = {}
var _water_result_mutex := Mutex.new()
var _water_build_generation := 0
var _water_revisions: Dictionary = {}
var _water_dirty: Dictionary = {}
var _override_signature := 0
var _override_snapshot: Dictionary = {}
var _override_index = OVERRIDE_SPATIAL_INDEX.new()
var _water_stale_drops := 0
var _water_apply_count := 0
var _water_mesh_build_count := 0
var _water_max_build_usec := 0
var _water_max_apply_usec := 0
var _water_last_face_count := 0
var _water_last_vertex_count := 0
var _water_last_voxel_count := 0


func _ready() -> void:
	add_to_group("water_runtime_manager")
	call_deferred("_activate_for_mobile_world")


func _exit_tree() -> void:
	for coord_value: Variant in _water_active_tasks.keys():
		var task_id := int(_water_active_tasks[coord_value].get("task_id", -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
	_water_active_tasks.clear()
	_water_result_mutex.lock()
	_water_completed_results.clear()
	_water_result_mutex.unlock()


func _process(_delta: float) -> void:
	if not _active:
		return
	_sync_external_edits()
	_pump_water_tasks()
	var target := get_node_or_null(streaming_target_path) as Node3D
	if not is_instance_valid(target):
		return
	var next_center := Vector2i(
		floori(target.global_position.x / float(CHUNK_SIZE)),
		floori(target.global_position.z / float(CHUNK_SIZE))
	)
	if next_center != _center:
		_set_center(next_center)


func _activate_for_mobile_world() -> void:
	var chunk_manager := get_parent()
	if chunk_manager == null or not chunk_manager.has_method("is_playable_world_port_active"):
		set_process(false)
		return
	if not bool(chunk_manager.call("is_playable_world_port_active")):
		set_process(false)
		return

	var runtime := chunk_manager.get_node_or_null("PlayableWorldRuntime")
	if runtime == null:
		call_deferred("_activate_for_mobile_world")
		return
	_data = runtime.data
	_override_snapshot = _data.overrides.duplicate()
	_override_signature = hash(_data.overrides)
	_override_index.rebuild(_data.overrides, CHUNK_SIZE)
	var global_plane := runtime.get_node_or_null("Water")
	if is_instance_valid(global_plane):
		global_plane.queue_free()

	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color.WHITE
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_active = true

	var target := get_node_or_null(streaming_target_path) as Node3D
	if is_instance_valid(target):
		_set_center(Vector2i(
			floori(target.global_position.x / float(CHUNK_SIZE)),
			floori(target.global_position.z / float(CHUNK_SIZE))
		))


func _set_center(next_center: Vector2i) -> void:
	var started_usec := Time.get_ticks_usec()
	_center = next_center
	_water_build_generation += 1
	_water_queue.clear()

	for z in range(_center.y - RENDER_RADIUS, _center.y + RENDER_RADIUS + 1):
		for x in range(_center.x - RENDER_RADIUS, _center.x + RENDER_RADIUS + 1):
			var coord := Vector2i(x, z)
			if _chunks.has(coord) or _water_active_tasks.has(coord):
				continue
			_water_queue.append(coord)
	_water_queue.sort_custom(Callable(self, "_water_coord_less"))

	for coord_value: Variant in _chunks.keys():
		var coord: Vector2i = coord_value
		if maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) <= RENDER_RADIUS + 1:
			continue
		_remove_chunk(coord)

	_record_water_event("WATER_CENTER_BUILD", "center=%s queue=%d elapsed_ms=%.3f" % [_center, _water_queue.size(), (Time.get_ticks_usec() - started_usec) / 1000.0])


func _water_coord_less(a: Vector2i, b: Vector2i) -> bool:
	var a_distance := maxi(absi(a.x - _center.x), absi(a.y - _center.y))
	var b_distance := maxi(absi(b.x - _center.x), absi(b.y - _center.y))
	if a_distance != b_distance:
		return a_distance < b_distance
	return absi(a.x - _center.x) + absi(a.y - _center.y) < absi(b.x - _center.x) + absi(b.y - _center.y)


static func affected_chunks_for_world_cell(cell: Vector3i, chunk_size: int) -> Array[Vector2i]:
	var cells := [
		Vector2i(cell.x, cell.z),
		Vector2i(cell.x + 1, cell.z),
		Vector2i(cell.x - 1, cell.z),
		Vector2i(cell.x, cell.z + 1),
		Vector2i(cell.x, cell.z - 1),
	]
	var result: Array[Vector2i] = []
	for world_cell in cells:
		var coord := Vector2i(floori(float(world_cell.x) / float(chunk_size)), floori(float(world_cell.y) / float(chunk_size)))
		if not result.has(coord):
			result.append(coord)
	return result


static func water_result_is_stale(result_generation: int, current_generation: int, result_revision: int, current_revision: int, wanted: bool) -> bool:
	return result_generation != current_generation or result_revision != current_revision or not wanted


func notify_world_change(cell: Vector3i) -> void:
	var affected := affected_chunks_for_world_cell(cell, CHUNK_SIZE)
	for coord in affected:
		_mark_water_chunk_dirty(coord)
	_record_water_event("WATER_DIRTY", "cell=%s affected_chunks=%s" % [cell, affected])


func mark_water_chunk_dirty(coord: Vector2i) -> void:
	_mark_water_chunk_dirty(coord)
	_record_water_event("WATER_DIRTY", "chunk=%s explicit=1" % coord)


func _mark_water_chunk_dirty(coord: Vector2i) -> void:
	_water_revisions[coord] = int(_water_revisions.get(coord, 0)) + 1
	_water_dirty[coord] = true
	if not _active:
		return
	if maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) > RENDER_RADIUS:
		return
	if not _water_queue.has(coord) and not _water_active_tasks.has(coord):
		_water_queue.push_front(coord)


func _parse_override_cell(key_value: Variant) -> Variant:
	if key_value is Vector3i:
		return key_value
	var parts := String(key_value).split(",")
	if parts.size() != 3:
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func _sync_external_edits() -> void:
	var current: Dictionary = _data.overrides
	var current_signature := hash(current)
	if current_signature == _override_signature:
		return
	var changed_cells: Array[Vector3i] = []
	for key_value: Variant in current.keys():
		if not _override_snapshot.has(key_value) or int(current[key_value]) != int(_override_snapshot[key_value]):
			var parsed := _parse_override_cell(key_value)
			if parsed is Vector3i:
				changed_cells.append(parsed)
	for key_value: Variant in _override_snapshot.keys():
		if not current.has(key_value):
			var parsed := _parse_override_cell(key_value)
			if parsed is Vector3i:
				changed_cells.append(parsed)
	_override_snapshot = current.duplicate()
	_override_signature = current_signature
	_override_index.rebuild(current, CHUNK_SIZE)
	for cell in changed_cells:
		notify_world_change(cell)


func diagnostics() -> Dictionary:
	return {
		"water_active": _active,
		"water_center": _center,
		"water_active_tasks": _water_active_tasks.size(),
		"water_queue": _water_queue.size(),
		"water_dirty_chunks": _water_dirty.size(),
		"water_stale_drops": _water_stale_drops,
		"water_mesh_builds": _water_mesh_build_count,
		"water_applies": _water_apply_count,
		"water_max_build_ms": _water_max_build_usec / 1000.0,
		"water_max_apply_ms": _water_max_apply_usec / 1000.0,
		"water_last_faces": _water_last_face_count,
		"water_last_vertices": _water_last_vertex_count,
		"water_last_voxels": _water_last_voxel_count,
	}


func _pump_water_tasks() -> void:
	var completed: Array[Vector2i] = []
	for coord_value: Variant in _water_active_tasks.keys():
		var coord: Vector2i = coord_value
		var task_data: Dictionary = _water_active_tasks[coord]
		var task_id := int(task_data.get("task_id", -1))
		if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		_water_active_tasks.erase(coord)
		completed.append(coord)

	for coord in completed:
		_water_result_mutex.lock()
		var result: Dictionary = _water_completed_results.get(coord, {})
		_water_completed_results.erase(coord)
		_water_result_mutex.unlock()

		var expected_generation := int(result.get("generation", -1))
		var expected_revision := int(result.get("revision", -1))
		var current_revision := int(_water_revisions.get(coord, 0))
		var wanted := maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) <= RENDER_RADIUS
		if result.is_empty() or water_result_is_stale(expected_generation, _water_build_generation, expected_revision, current_revision, wanted):
			_water_stale_drops += 1
			_record_water_event("WATER_STALE_DROP", "chunk=%s result_generation=%d current_generation=%d result_revision=%d current_revision=%d wanted=%s" % [coord, expected_generation, _water_build_generation, expected_revision, current_revision, wanted])
			if wanted and _water_dirty.get(coord, false) and not _water_queue.has(coord):
				_water_queue.push_front(coord)
			continue

		_water_dirty.erase(coord)
		_water_mesh_build_count += 1
		_water_max_build_usec = maxi(_water_max_build_usec, int(result.get("build_usec", 0)))
		_water_last_face_count = int(result.get("face_count", 0))
		_water_last_vertex_count = int(result.get("vertex_count", 0))
		_water_last_voxel_count = int(result.get("water_voxel_count", 0))
		_record_water_event("WATER_MESH_BUILD", "chunk=%s build_ms=%.3f faces=%d vertices=%d quads=%d water_voxels=%d" % [coord, int(result.get("build_usec", 0)) / 1000.0, _water_last_face_count, _water_last_vertex_count, int(result.get("quad_count", 0)), _water_last_voxel_count])
		_create_chunk_from_data(coord, result)

	while _water_active_tasks.size() < MAX_WATER_WORKERS and not _water_queue.is_empty():
		var coord := _water_queue.pop_front()
		if maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) > RENDER_RADIUS:
			continue
		if _water_active_tasks.has(coord):
			continue
		_dispatch_water_task(coord)


func _dispatch_water_task(coord: Vector2i) -> void:
	var generation := _water_build_generation
	var revision := int(_water_revisions.get(coord, 0))
	var override_snapshot := _override_index.snapshot_for_chunk(coord, CHUNK_SIZE, 1)
	var task_callable := Callable(get_script(), "_build_water_worker").bind(coord, generation, revision, override_snapshot, _water_completed_results, _water_result_mutex)
	var task_id := WorkerThreadPool.add_task(task_callable, false, "TEKNIK water mesh %s r%d" % [coord, revision])
	if task_id < 0:
		_water_queue.push_back(coord)
		_record_water_event("WATER_WORKER_SUBMIT_FAILURE", "chunk=%s error=%d" % [coord, task_id])
		return
	_water_active_tasks[coord] = {"task_id": task_id, "generation": generation, "revision": revision}


static func _build_water_worker(coord: Vector2i, generation: int, revision: int, override_snapshot: Dictionary, result_sink: Dictionary, result_mutex: Mutex) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = WORKER_DATA.new()
	sampler.overrides = override_snapshot
	var mesh_data := WATER_BUILDER.build(sampler, coord, CHUNK_SIZE)
	var result := {
		"coord": coord,
		"generation": generation,
		"revision": revision,
		"build_usec": Time.get_ticks_usec() - started_usec,
		"vertices": mesh_data.get("vertices", PackedVector3Array()),
		"normals": mesh_data.get("normals", PackedVector3Array()),
		"colors": mesh_data.get("colors", PackedColorArray()),
		"indices": mesh_data.get("indices", PackedInt32Array()),
		"face_count": int(mesh_data.get("indices", PackedInt32Array()).size() / 3),
		"vertex_count": int(mesh_data.get("vertices", PackedVector3Array()).size()),
		"quad_count": int(mesh_data.get("quad_count", 0)),
		"water_voxel_count": int(mesh_data.get("water_voxel_count", 0)),
	}
	result_mutex.lock()
	result_sink[coord] = result
	result_mutex.unlock()


func _create_chunk_from_data(coord: Vector2i, mesh_data: Dictionary) -> void:
	var started_usec := Time.get_ticks_usec()
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		_remove_chunk(coord)
		_water_apply_count += 1
		_water_max_apply_usec = maxi(_water_max_apply_usec, Time.get_ticks_usec() - started_usec)
		_record_water_event("WATER_APPLY", "chunk=%s empty=1 apply_ms=%.3f" % [coord, (Time.get_ticks_usec() - started_usec) / 1000.0])
		return

	_remove_chunk(coord)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Water_%d_%d" % [coord.x, coord.y]
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)
	mesh_instance.mesh = mesh
	mesh.surface_set_material(0, _material)
	add_child(mesh_instance)
	_chunks[coord] = mesh_instance
	_water_apply_count += 1
	_water_max_apply_usec = maxi(_water_max_apply_usec, Time.get_ticks_usec() - started_usec)
	_record_water_event("WATER_APPLY", "chunk=%s apply_ms=%.3f faces=%d vertices=%d" % [coord, (Time.get_ticks_usec() - started_usec) / 1000.0, int(mesh_data.get("face_count", 0)), vertices.size()])


func _remove_chunk(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	var old_mesh := _chunks[coord] as MeshInstance3D
	if is_instance_valid(old_mesh):
		old_mesh.queue_free()
	_chunks.erase(coord)


func _record_water_event(event_name: String, detail: String) -> void:
	var capture := get_node_or_null("/root/DiagnosticLogCapture")
	if capture != null and capture.has_method("record_event"):
		capture.record_event(event_name, detail)


static func water_info(data, x: int, z: int) -> Vector2i:
	return WATER_BUILDER.water_info(data, x, z)


static func is_water_column(data, x: int, z: int) -> bool:
	return water_info(data, x, z).x != WATER_NONE


static func build_water_mesh(data, coord: Vector2i, chunk_size: int) -> ArrayMesh:
	var mesh_data := WATER_BUILDER.build(data, coord, chunk_size)
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
