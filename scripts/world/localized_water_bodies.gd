extends Node3D

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WATER_BUILDER := preload("res://scripts/world/localized_water_mesh_builder.gd")
const WORKER_DATA := preload("res://scripts/world/playable_world_worker_carpathian_data.gd")

const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const WATER_NONE := 0
const MAX_WATER_WORKERS := 2
const WATER_SURFACE_OFFSET := 1.0
const WATER_TOP_COLOR := Color(0.18, 0.50, 0.72, 0.86)
const WATER_SIDE_COLOR := Color(0.12, 0.36, 0.56, 0.86)

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


func _ready() -> void:
	call_deferred("_activate_for_mobile_world")


func _exit_tree() -> void:
	for coord_value: Variant in _water_active_tasks.keys():
		var task_id := int(_water_active_tasks[coord_value])
		WorkerThreadPool.wait_for_task_completion(task_id)
	_water_active_tasks.clear()
	_water_result_mutex.lock()
	_water_completed_results.clear()
	_water_result_mutex.unlock()


func _process(_delta: float) -> void:
	if not _active:
		return
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
		var mesh_instance := _chunks[coord] as MeshInstance3D
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
		_chunks.erase(coord)


func _water_coord_less(a: Vector2i, b: Vector2i) -> bool:
	var a_distance := maxi(absi(a.x - _center.x), absi(a.y - _center.y))
	var b_distance := maxi(absi(b.x - _center.x), absi(b.y - _center.y))
	if a_distance != b_distance:
		return a_distance < b_distance
	return absi(a.x - _center.x) + absi(a.y - _center.y) < absi(b.x - _center.x) + absi(b.y - _center.y)


func _pump_water_tasks() -> void:
	var completed: Array[Vector2i] = []
	for coord_value: Variant in _water_active_tasks.keys():
		var coord: Vector2i = coord_value
		var task_id := int(_water_active_tasks[coord])
		if not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		_water_active_tasks.erase(coord)
		completed.append(coord)

	for coord in completed:
		_water_result_mutex.lock()
		var result: Dictionary = _water_completed_results.get(coord, {})
		_water_completed_results.erase(coord)
		_water_result_mutex.unlock()

		var wanted := maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) <= RENDER_RADIUS
		if not wanted or _chunks.has(coord) or result.is_empty():
			if wanted and not _chunks.has(coord) and result.is_empty():
				_chunks[coord] = null
			continue
		_create_chunk_from_data(coord, result)

	while _water_active_tasks.size() < MAX_WATER_WORKERS and not _water_queue.is_empty():
		var coord := _water_queue.pop_front()
		if maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) > RENDER_RADIUS:
			continue
		if _chunks.has(coord) or _water_active_tasks.has(coord):
			continue
		var task_callable := Callable(get_script(), "_build_water_worker").bind(
			coord, _water_completed_results, _water_result_mutex
		)
		var task_id := WorkerThreadPool.add_task(
			task_callable,
			false,
			"TEKNIK water mesh %s" % coord
		)
		if task_id < 0:
			var fallback_data := WATER_BUILDER.build(_data, coord, CHUNK_SIZE)
			_create_chunk_from_data(coord, fallback_data)
			continue
		_water_active_tasks[coord] = task_id


static func _build_water_worker(coord: Vector2i, result_sink: Dictionary, result_mutex: Mutex) -> void:
	var sampler = WORKER_DATA.new()
	var result := WATER_BUILDER.build(sampler, coord, CHUNK_SIZE)
	result_mutex.lock()
	result_sink[coord] = result
	result_mutex.unlock()


func _create_chunk_from_data(coord: Vector2i, mesh_data: Dictionary) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		_chunks[coord] = null
		return
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
