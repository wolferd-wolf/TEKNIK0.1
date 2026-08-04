extends Node3D
class_name ChunkManager

const VOXEL_CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const BIOME_PROBE_SCRIPT := preload("res://scripts/world/biome_probe.gd")
const CHUNK_MESHER_SCRIPT := preload("res://scripts/world/chunk_mesher.gd")
const THREADED_CHUNK_MESHER_SCRIPT := preload("res://scripts/world/threaded_chunk_mesher.gd")
const CHUNK_SIZE := 16
const CHUNK_DIMENSIONS := Vector3i(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
const BLOCK_AIR := 0
const MIN_PLACEABLE_BLOCK := 1
const MAX_PLACEABLE_BLOCK := 4
const TERRAIN_SEED := 1701
const BIOME_SEED := 2718
const TERRAIN_BASE_HEIGHT := 8
const TERRAIN_HEIGHT_AMPLITUDE := 6
const MAX_REMESH_TIMING_SAMPLES := 512
const MAX_REMESH_APPLIES_PER_PHYSICS_FRAME := 2
const NEIGHBOR_DIRECTIONS := [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

@export_range(1, 8, 1) var render_radius: int = 2
@export var streaming_target_path: NodePath

var chunks: Dictionary = {}
var last_center_chunk: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var _streaming_target: Node3D
var _elevation_noise := FastNoiseLite.new()
var _biome_noise := FastNoiseLite.new()
var _remesh_timing_samples: Array[Dictionary] = []
var _remesh_revisions: Dictionary = {}
var _active_remesh_tasks: Dictionary = {}
var _remesh_apply_queue: Array[Dictionary] = []
var _completed_worker_results: Dictionary = {}
var _worker_result_mutex := Mutex.new()
var _remesh_tasks_started := 0
var _remesh_results_applied := 0
var _remesh_stale_results_discarded := 0
var _remesh_coalesced_requests := 0
var _max_remesh_queue_usec := 0
var _max_remesh_apply_usec := 0
var _max_remesh_background_usec := 0
var _max_remesh_pump_usec := 0


func _ready() -> void:
	_configure_elevation_noise()
	_configure_biome_noise()
	_streaming_target = get_node_or_null(streaming_target_path) as Node3D
	if _streaming_target != null:
		refresh_streaming(_streaming_target.global_position)


func _process(_delta: float) -> void:
	if _streaming_target == null:
		return

	var center_chunk := world_to_chunk_coord(_streaming_target.global_position)
	if center_chunk != last_center_chunk:
		refresh_streaming(_streaming_target.global_position)


func _physics_process(_delta: float) -> void:
	var started_usec := Time.get_ticks_usec()
	_collect_completed_remesh_tasks()
	_apply_completed_remeshes(MAX_REMESH_APPLIES_PER_PHYSICS_FRAME)
	_max_remesh_pump_usec = maxi(
		_max_remesh_pump_usec,
		Time.get_ticks_usec() - started_usec
	)


func _exit_tree() -> void:
	for task_data in _active_remesh_tasks.values():
		var task_id := int(task_data.get("task_id", -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
	_active_remesh_tasks.clear()
	_remesh_apply_queue.clear()


func _configure_elevation_noise() -> void:
	_elevation_noise.seed = TERRAIN_SEED
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elevation_noise.frequency = 0.015
	_elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elevation_noise.fractal_octaves = 4
	_elevation_noise.fractal_lacunarity = 2.0
	_elevation_noise.fractal_gain = 0.5


func _configure_biome_noise() -> void:
	_biome_noise.seed = BIOME_SEED
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_noise.frequency = 0.0035
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_biome_noise.fractal_octaves = 3
	_biome_noise.fractal_lacunarity = 2.0
	_biome_noise.fractal_gain = 0.5


static func world_to_chunk_coord(world_position: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_position.x / float(CHUNK_SIZE)),
		floori(world_position.y / float(CHUNK_SIZE)),
		floori(world_position.z / float(CHUNK_SIZE))
	)


static func chunk_coord_to_world_origin(chunk_coord: Vector3i) -> Vector3:
	return Vector3(
		chunk_coord.x * CHUNK_SIZE,
		chunk_coord.y * CHUNK_SIZE,
		chunk_coord.z * CHUNK_SIZE
	)


func world_to_local_coord(world_block_coord: Vector3i) -> Vector3i:
	return Vector3i(
		posmod(world_block_coord.x, CHUNK_SIZE),
		posmod(world_block_coord.y, CHUNK_SIZE),
		posmod(world_block_coord.z, CHUNK_SIZE)
	)


func get_block_world(world_block_coord: Vector3i) -> int:
	var chunk_coord := Vector3i(
		floori(world_block_coord.x / float(CHUNK_SIZE)),
		floori(world_block_coord.y / float(CHUNK_SIZE)),
		floori(world_block_coord.z / float(CHUNK_SIZE))
	)
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return BLOCK_AIR
	return chunk.get_block(world_to_local_coord(world_block_coord))


func set_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	var chunk_coord := Vector3i(
		floori(world_block_coord.x / float(CHUNK_SIZE)),
		floori(world_block_coord.y / float(CHUNK_SIZE)),
		floori(world_block_coord.z / float(CHUNK_SIZE))
	)
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return false

	var local_coord := world_to_local_coord(world_block_coord)
	var previous_block_id: int = chunk.get_block(local_coord)
	if previous_block_id == block_id:
		return false

	chunk.set_block(local_coord, block_id)
	var operation_started_usec := Time.get_ticks_usec()
	var primary_duration_usec := _rebuild_chunk(chunk_coord)
	var boundary_result := _rebuild_boundary_neighbors(chunk_coord, local_coord)
	var total_duration_usec := Time.get_ticks_usec() - operation_started_usec
	_record_remesh_timing(
		world_block_coord,
		local_coord,
		previous_block_id,
		block_id,
		primary_duration_usec,
		int(boundary_result["duration_usec"]),
		int(boundary_result["chunk_count"]),
		total_duration_usec
	)
	return true


func mine_block_world(world_block_coord: Vector3i) -> bool:
	if get_block_world(world_block_coord) == BLOCK_AIR:
		return false
	return set_block_world(world_block_coord, BLOCK_AIR)


func place_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if block_id < MIN_PLACEABLE_BLOCK or block_id > MAX_PLACEABLE_BLOCK:
		return false
	if get_block_world(world_block_coord) != BLOCK_AIR:
		return false
	return set_block_world(world_block_coord, block_id)


func _rebuild_boundary_neighbors(chunk_coord: Vector3i, local_coord: Vector3i) -> Dictionary:
	var boundary_directions := _boundary_directions(local_coord)
	var rebuilt_chunk_count := 0
	var total_duration_usec := 0
	for direction in boundary_directions:
		var duration_usec := _rebuild_chunk(chunk_coord + direction)
		if duration_usec < 0:
			continue
		rebuilt_chunk_count += 1
		total_duration_usec += duration_usec
	return {
		"chunk_count": rebuilt_chunk_count,
		"duration_usec": total_duration_usec,
	}


func _boundary_directions(local_coord: Vector3i) -> Array[Vector3i]:
	var boundary_directions: Array[Vector3i] = []
	if local_coord.x == 0:
		boundary_directions.append(Vector3i.LEFT)
	elif local_coord.x == CHUNK_SIZE - 1:
		boundary_directions.append(Vector3i.RIGHT)

	if local_coord.y == 0:
		boundary_directions.append(Vector3i.DOWN)
	elif local_coord.y == CHUNK_SIZE - 1:
		boundary_directions.append(Vector3i.UP)

	if local_coord.z == 0:
		boundary_directions.append(Vector3i.FORWARD)
	elif local_coord.z == CHUNK_SIZE - 1:
		boundary_directions.append(Vector3i.BACK)
	return boundary_directions


func _record_remesh_timing(
	world_block_coord: Vector3i,
	local_coord: Vector3i,
	previous_block_id: int,
	new_block_id: int,
	primary_duration_usec: int,
	neighbor_duration_usec: int,
	neighbor_chunk_count: int,
	total_duration_usec: int
) -> void:
	var mutation := "replace"
	if new_block_id == BLOCK_AIR:
		mutation = "mine"
	elif previous_block_id == BLOCK_AIR:
		mutation = "place"

	var primary_chunk_count := 1 if primary_duration_usec >= 0 else 0
	var rebuilt_chunk_count := primary_chunk_count + neighbor_chunk_count
	var sample := {
		"mutation": mutation,
		"world_block_coord": world_block_coord,
		"local_coord": local_coord,
		"rebuilt_chunk_count": rebuilt_chunk_count,
		"primary_ms": max(primary_duration_usec, 0) / 1000.0,
		"neighbor_ms": neighbor_duration_usec / 1000.0,
		"total_ms": total_duration_usec / 1000.0,
		"main_thread_queue_ms": total_duration_usec / 1000.0,
	}
	_max_remesh_queue_usec = maxi(_max_remesh_queue_usec, total_duration_usec)
	if _remesh_timing_samples.size() >= MAX_REMESH_TIMING_SAMPLES:
		_remesh_timing_samples.pop_front()
	_remesh_timing_samples.append(sample)
	print(
		"REMESH_QUEUE_TIMING mutation=%s chunks=%d primary_ms=%.3f neighbor_ms=%.3f main_thread_ms=%.3f world=%s local=%s"
		% [
			mutation,
			rebuilt_chunk_count,
			float(sample["primary_ms"]),
			float(sample["neighbor_ms"]),
			float(sample["main_thread_queue_ms"]),
			world_block_coord,
			local_coord,
		]
	)


func get_remesh_timing_samples() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for sample in _remesh_timing_samples:
		snapshot.append(sample.duplicate(true))
	return snapshot


func clear_remesh_timing_samples() -> void:
	_remesh_timing_samples.clear()


func get_remesh_diagnostics() -> Dictionary:
	return {
		"tasks_started": _remesh_tasks_started,
		"results_applied": _remesh_results_applied,
		"stale_results_discarded": _remesh_stale_results_discarded,
		"coalesced_requests": _remesh_coalesced_requests,
		"active_tasks": _active_remesh_tasks.size(),
		"pending_applies": _remesh_apply_queue.size(),
		"max_queue_ms": _max_remesh_queue_usec / 1000.0,
		"max_apply_ms": _max_remesh_apply_usec / 1000.0,
		"max_background_compute_ms": _max_remesh_background_usec / 1000.0,
		"max_pump_ms": _max_remesh_pump_usec / 1000.0,
	}


func reset_remesh_diagnostics() -> bool:
	if not is_remesh_idle():
		return false
	_remesh_tasks_started = 0
	_remesh_results_applied = 0
	_remesh_stale_results_discarded = 0
	_remesh_coalesced_requests = 0
	_max_remesh_queue_usec = 0
	_max_remesh_apply_usec = 0
	_max_remesh_background_usec = 0
	_max_remesh_pump_usec = 0
	clear_remesh_timing_samples()
	return true


func is_remesh_idle() -> bool:
	return _active_remesh_tasks.is_empty() and _remesh_apply_queue.is_empty()


func refresh_streaming(world_position: Vector3) -> void:
	var center_chunk := world_to_chunk_coord(world_position)
	var desired_chunks: Dictionary = {}
	var added_chunks: Array[Vector3i] = []
	var affected_chunks: Dictionary = {}
	var radius_squared := render_radius * render_radius

	for offset_x in range(-render_radius, render_radius + 1):
		for offset_y in range(-render_radius, render_radius + 1):
			for offset_z in range(-render_radius, render_radius + 1):
				var offset := Vector3i(offset_x, offset_y, offset_z)
				if offset.length_squared() > radius_squared:
					continue

				var chunk_coord := center_chunk + offset
				desired_chunks[chunk_coord] = true
				if not chunks.has(chunk_coord):
					create_empty_chunk(chunk_coord, false)
					added_chunks.append(chunk_coord)

	var loaded_coords := chunks.keys()
	for loaded_coord_variant in loaded_coords:
		var loaded_coord: Vector3i = loaded_coord_variant
		if desired_chunks.has(loaded_coord):
			continue
		for direction in NEIGHBOR_DIRECTIONS:
			var neighbor_coord: Vector3i = loaded_coord + direction
			if desired_chunks.has(neighbor_coord) and has_chunk(neighbor_coord):
				affected_chunks[neighbor_coord] = true
		remove_chunk(loaded_coord, false)

	for added_coord in added_chunks:
		affected_chunks[added_coord] = true
		for direction in NEIGHBOR_DIRECTIONS:
			var neighbor_coord: Vector3i = added_coord + direction
			if has_chunk(neighbor_coord):
				affected_chunks[neighbor_coord] = true

	for affected_coord in affected_chunks.keys():
		_rebuild_chunk(affected_coord)

	last_center_chunk = center_chunk


func expected_chunk_count() -> int:
	var count := 0
	var radius_squared := render_radius * render_radius
	for offset_x in range(-render_radius, render_radius + 1):
		for offset_y in range(-render_radius, render_radius + 1):
			for offset_z in range(-render_radius, render_radius + 1):
				var offset := Vector3i(offset_x, offset_y, offset_z)
				if offset.length_squared() <= radius_squared:
					count += 1
	return count


func has_chunk(chunk_coord: Vector3i) -> bool:
	return chunks.has(chunk_coord)


func get_chunk(chunk_coord: Vector3i) -> Node3D:
	return chunks.get(chunk_coord) as Node3D


func register_chunk(chunk_coord: Vector3i, chunk: Node3D) -> bool:
	if chunk == null or chunks.has(chunk_coord):
		return false

	chunks[chunk_coord] = chunk
	if chunk.get_parent() == null:
		add_child(chunk)
	return true


func create_empty_chunk(chunk_coord: Vector3i, queue_remesh: bool = true) -> Node3D:
	var existing_chunk := get_chunk(chunk_coord)
	if is_instance_valid(existing_chunk):
		return existing_chunk

	var chunk := VOXEL_CHUNK_SCRIPT.new()
	chunk.configure(chunk_coord)
	chunk.generate_terrain(
		_elevation_noise,
		_biome_noise,
		TERRAIN_BASE_HEIGHT,
		TERRAIN_HEIGHT_AMPLITUDE
	)
	BIOME_PROBE_SCRIPT.run(chunk)
	register_chunk(chunk_coord, chunk)
	if queue_remesh:
		_rebuild_chunk_and_neighbors(chunk_coord)
	return chunk


func remove_chunk(chunk_coord: Vector3i, queue_neighbors: bool = true) -> bool:
	if not chunks.has(chunk_coord):
		return false

	var chunk := get_chunk(chunk_coord)
	chunks.erase(chunk_coord)
	_cancel_remesh(chunk_coord)
	if is_instance_valid(chunk):
		chunk.queue_free()
	if queue_neighbors:
		for direction in NEIGHBOR_DIRECTIONS:
			_rebuild_chunk(chunk_coord + direction)
	return true


func _rebuild_chunk_and_neighbors(chunk_coord: Vector3i) -> void:
	_rebuild_chunk(chunk_coord)
	for direction in NEIGHBOR_DIRECTIONS:
		_rebuild_chunk(chunk_coord + direction)


func _rebuild_chunk(chunk_coord: Vector3i) -> int:
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return -1
	var started_usec := Time.get_ticks_usec()
	_queue_remesh(chunk_coord)
	return Time.get_ticks_usec() - started_usec


func _queue_remesh(chunk_coord: Vector3i) -> bool:
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return false

	var revision := int(_remesh_revisions.get(chunk_coord, 0)) + 1
	_remesh_revisions[chunk_coord] = revision
	if _active_remesh_tasks.has(chunk_coord):
		_remesh_coalesced_requests += 1
		return true

	_start_remesh_task(chunk_coord, revision)
	return true


func _cancel_remesh(chunk_coord: Vector3i) -> void:
	_remesh_revisions[chunk_coord] = int(_remesh_revisions.get(chunk_coord, 0)) + 1


func _start_remesh_task(chunk_coord: Vector3i, revision: int) -> void:
	var snapshot := _capture_chunk_snapshot(chunk_coord)
	if snapshot.is_empty():
		return

	var result_key := _result_key(chunk_coord, revision)
	var task_callable := Callable(
		THREADED_CHUNK_MESHER_SCRIPT,
		"build_mesh_data"
	).bind(snapshot, _completed_worker_results, _worker_result_mutex, result_key)
	var task_id := WorkerThreadPool.add_task(
		task_callable,
		false,
		"TEKNIK remesh %s r%d" % [chunk_coord, revision]
	)
	if task_id < 0:
		push_error("Failed to submit remesh task for %s revision %d" % [chunk_coord, revision])
		return

	_active_remesh_tasks[chunk_coord] = {
		"task_id": task_id,
		"revision": revision,
		"result_key": result_key,
		"queued_at_usec": Time.get_ticks_usec(),
	}
	_remesh_tasks_started += 1


func _capture_chunk_snapshot(chunk_coord: Vector3i) -> Dictionary:
	var chunk := get_chunk(chunk_coord)
	if not is_instance_valid(chunk):
		return {}

	var neighbors: Dictionary = {}
	for direction in NEIGHBOR_DIRECTIONS:
		var neighbor_chunk := get_chunk(chunk_coord + direction)
		if is_instance_valid(neighbor_chunk):
			neighbors[direction] = neighbor_chunk.blocks.duplicate()
		else:
			neighbors[direction] = PackedByteArray()
	return {
		"chunk_coord": chunk_coord,
		"blocks": chunk.blocks.duplicate(),
		"neighbors": neighbors,
	}


func _collect_completed_remesh_tasks() -> void:
	var active_coords := _active_remesh_tasks.keys()
	for chunk_coord_variant in active_coords:
		var chunk_coord: Vector3i = chunk_coord_variant
		var task_data: Dictionary = _active_remesh_tasks.get(chunk_coord, {})
		if task_data.is_empty():
			continue
		var task_id := int(task_data.get("task_id", -1))
		if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
			continue

		WorkerThreadPool.wait_for_task_completion(task_id)
		var result_key := String(task_data.get("result_key", ""))
		var result := _take_worker_result(result_key)
		var completed_revision := int(task_data.get("revision", 0))
		var latest_revision := int(_remesh_revisions.get(chunk_coord, 0))
		_active_remesh_tasks.erase(chunk_coord)

		if not result.is_empty():
			_max_remesh_background_usec = maxi(
				_max_remesh_background_usec,
				int(result.get("compute_usec", 0))
			)

		if (
			result.is_empty()
			or not has_chunk(chunk_coord)
			or completed_revision != latest_revision
		):
			_remesh_stale_results_discarded += 1
		else:
			_remesh_apply_queue.append({
				"chunk_coord": chunk_coord,
				"revision": completed_revision,
				"queued_at_usec": int(task_data.get("queued_at_usec", 0)),
				"result": result,
			})

		if has_chunk(chunk_coord) and latest_revision > completed_revision:
			_start_remesh_task(chunk_coord, latest_revision)


func _take_worker_result(result_key: String) -> Dictionary:
	var result: Dictionary = {}
	_worker_result_mutex.lock()
	if _completed_worker_results.has(result_key):
		result = _completed_worker_results[result_key]
		_completed_worker_results.erase(result_key)
	_worker_result_mutex.unlock()
	return result


func _apply_completed_remeshes(max_applies: int) -> void:
	var applied_this_frame := 0
	while applied_this_frame < max_applies and not _remesh_apply_queue.is_empty():
		var apply_data: Dictionary = _remesh_apply_queue.pop_front()
		var chunk_coord: Vector3i = apply_data.get("chunk_coord", Vector3i.ZERO)
		var revision := int(apply_data.get("revision", 0))
		if (
			not has_chunk(chunk_coord)
			or revision != int(_remesh_revisions.get(chunk_coord, 0))
		):
			_remesh_stale_results_discarded += 1
			continue

		var chunk := get_chunk(chunk_coord)
		if not is_instance_valid(chunk):
			_remesh_stale_results_discarded += 1
			continue

		var result: Dictionary = apply_data.get("result", {})
		var apply_started_usec := Time.get_ticks_usec()
		_apply_mesh_data(chunk, result)
		var apply_usec := Time.get_ticks_usec() - apply_started_usec
		var background_usec := int(result.get("compute_usec", 0))
		var queued_at_usec := int(apply_data.get("queued_at_usec", 0))
		var latency_usec := Time.get_ticks_usec() - queued_at_usec
		_max_remesh_apply_usec = maxi(_max_remesh_apply_usec, apply_usec)
		_remesh_results_applied += 1
		applied_this_frame += 1
		print(
			"THREADED_REMESH_COMPLETE coord=%s revision=%d background_ms=%.3f apply_ms=%.3f latency_ms=%.3f"
			% [
				chunk_coord,
				revision,
				background_usec / 1000.0,
				apply_usec / 1000.0,
				latency_usec / 1000.0,
			]
		)


func _apply_mesh_data(chunk, result: Dictionary) -> void:
	var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		if is_instance_valid(chunk.mesh_instance):
			chunk.mesh_instance.visible = false
		if is_instance_valid(chunk.collision_shape):
			chunk.collision_shape.shape = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = result.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = result.get("colors", PackedColorArray())
	var chunk_mesh := ArrayMesh.new()
	chunk_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var chunk_collision := chunk_mesh.create_trimesh_shape()
	_ensure_chunk_render_nodes(chunk, chunk_mesh, chunk_collision)
	chunk.mesh_instance.mesh = chunk_mesh
	chunk.mesh_instance.visible = true
	chunk.collision_shape.shape = chunk_collision


func _ensure_chunk_render_nodes(
	chunk,
	initial_mesh: ArrayMesh,
	initial_collision: Shape3D
) -> void:
	if not is_instance_valid(chunk.mesh_instance):
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.name = "ChunkMesh"
		chunk.mesh_instance.mesh = initial_mesh
		chunk.mesh_instance.material_override = CHUNK_MESHER_SCRIPT.create_material()
		chunk.mesh_instance.visible = true
		chunk.add_child(chunk.mesh_instance)
	elif chunk.mesh_instance.material_override == null:
		chunk.mesh_instance.material_override = CHUNK_MESHER_SCRIPT.create_material()

	if not is_instance_valid(chunk.collision_body):
		chunk.collision_body = StaticBody3D.new()
		chunk.collision_body.name = "ChunkCollision"
		chunk.add_child(chunk.collision_body)

	if not is_instance_valid(chunk.collision_shape):
		chunk.collision_shape = CollisionShape3D.new()
		chunk.collision_shape.name = "CollisionShape3D"
		chunk.collision_shape.shape = initial_collision
		chunk.collision_body.add_child(chunk.collision_shape)


func _result_key(chunk_coord: Vector3i, revision: int) -> String:
	return "%d:%d:%d:%d" % [chunk_coord.x, chunk_coord.y, chunk_coord.z, revision]


func clear_chunks() -> void:
	for chunk_coord_variant in chunks.keys():
		var chunk_coord: Vector3i = chunk_coord_variant
		_cancel_remesh(chunk_coord)
		var chunk := get_chunk(chunk_coord)
		if is_instance_valid(chunk):
			chunk.queue_free()
	chunks.clear()


func chunk_count() -> int:
	return chunks.size()
