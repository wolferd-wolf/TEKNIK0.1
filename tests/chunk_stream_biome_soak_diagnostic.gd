extends SceneTree

const WORLD_PORT_SCRIPT := preload("res://scripts/world/playable_world_port.gd")
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const UNLOAD_RADIUS := 4
const WAIT_TIMEOUT_MSEC := 45000
const OUTWARD_STEPS := 18
const MAX_LOADED_BOUND := (UNLOAD_RADIUS * 2 + 1) * (UNLOAD_RADIUS * 2 + 1)

var failures: Array[String] = []
var samples: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _render_window_ready(manager, center: Vector2i) -> bool:
	for z in range(center.y - RENDER_RADIUS, center.y + RENDER_RADIUS + 1):
		for x in range(center.x - RENDER_RADIUS, center.x + RENDER_RADIUS + 1):
			if not manager.has_chunk(Vector3i(x, 0, z)):
				return false
	return true


func _wait_for_window(manager, center: Vector2i, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await process_frame
		if _render_window_ready(manager, center) and manager.is_remesh_idle():
			return true
	var runtime = manager.get_playable_world_runtime()
	var detail := {
		"context": context,
		"center": [center.x, center.y],
		"chunk_count": manager.chunk_count(),
		"diagnostics": manager.get_remesh_diagnostics(),
		"build_queue": runtime.build_queue.size() if runtime != null else -1,
		"active_tasks": runtime.active_build_tasks.size() if runtime != null else -1,
		"apply_queue": runtime.build_apply_queue.size() if runtime != null else -1,
		"result_sink": runtime.completed_worker_results.size() if runtime != null else -1,
		"revision_entries": runtime.build_revisions.size() if runtime != null else -1,
	}
	_fail("Chunk-stream soak timed out: %s" % JSON.stringify(detail))
	return false


func _memory_mb() -> float:
	return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)


func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _validate_center_state(manager, center: Vector2i, label: String) -> Dictionary:
	var runtime = manager.get_playable_world_runtime()
	if runtime == null:
		_fail("Missing playable-world runtime during %s" % label)
		return {}

	if manager.chunk_count() > MAX_LOADED_BOUND:
		_fail("Loaded chunk retention exceeded bound during %s: %d > %d" % [label, manager.chunk_count(), MAX_LOADED_BOUND])
	if runtime.active_build_tasks.size() != 0:
		_fail("Settled runtime still has active worker tasks during %s: %d" % [label, runtime.active_build_tasks.size()])
	if not runtime.build_queue.is_empty():
		_fail("Settled runtime still has queued chunk builds during %s: %d" % [label, runtime.build_queue.size()])
	if not runtime.build_apply_queue.is_empty():
		_fail("Settled runtime still has pending applies during %s: %d" % [label, runtime.build_apply_queue.size()])
	if not runtime.completed_worker_results.is_empty():
		_fail("Settled runtime leaked worker results during %s: %d" % [label, runtime.completed_worker_results.size()])

	var center_entry: Dictionary = manager.get_playable_world_chunk_entry(center)
	var mesh := center_entry.get("mesh") as ArrayMesh
	var surface_count := 0
	var vertex_count := 0
	if mesh == null:
		_fail("Center chunk has no ArrayMesh during %s" % label)
	else:
		surface_count = mesh.get_surface_count()
		if surface_count <= 0:
			_fail("Center chunk mesh has no surfaces during %s" % label)
		else:
			var arrays: Array = mesh.surface_get_arrays(0)
			if arrays.size() > Mesh.ARRAY_VERTEX:
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				vertex_count = vertices.size()
			if vertex_count <= 0:
				_fail("Center chunk mesh has no vertices during %s" % label)

	var caches: Dictionary = runtime._build_column_caches(center)
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var expected_width := CHUNK_SIZE + 4
	var expected_cache_size := expected_width * expected_width
	if heights.size() != expected_cache_size:
		_fail("Height cache shape changed during %s: %d != %d" % [label, heights.size(), expected_cache_size])
	if biomes.size() != expected_cache_size:
		_fail("Biome cache shape changed during %s: %d != %d" % [label, biomes.size(), expected_cache_size])
	var min_height := WORLD_DATA.WORLD_HEIGHT
	var max_height := -1
	for height in heights:
		min_height = mini(min_height, int(height))
		max_height = maxi(max_height, int(height))
		if int(height) < 3 or int(height) > WORLD_DATA.WORLD_HEIGHT - 3:
			_fail("Invalid terrain height %d during %s" % [int(height), label])
			break
	for biome in biomes:
		if int(biome) < 0 or int(biome) >= WORLD_DATA.BIOME_COUNT:
			_fail("Invalid biome id %d during %s" % [int(biome), label])
			break

	return {
		"label": label,
		"center": [center.x, center.y],
		"loaded": manager.chunk_count(),
		"memory_mb": _memory_mb(),
		"object_count": _object_count(),
		"revision_entries": runtime.build_revisions.size(),
		"result_sink": runtime.completed_worker_results.size(),
		"mesh_surfaces": surface_count,
		"mesh_vertices": vertex_count,
		"height_min": min_height,
		"height_max": max_height,
		"diagnostics": manager.get_remesh_diagnostics(),
	}


func _run() -> void:
	var test_root := Node3D.new()
	test_root.name = "ChunkStreamBiomeSoakDiagnostic"
	root.add_child(test_root)

	var target := Node3D.new()
	target.name = "Target"
	target.position = Vector3(0.5, 20.0, 0.5)
	test_root.add_child(target)

	var manager = WORLD_PORT_SCRIPT.new()
	manager.name = "ChunkManager"
	manager.streaming_target_path = NodePath("../Target")
	test_root.add_child(manager)

	await process_frame
	var runtime = manager.get_playable_world_runtime()
	if runtime == null:
		_fail("Playable-world runtime was not created")
		_finish(test_root)
		return

	var expect_persisted := OS.get_environment("TEKNIK_EXPECT_PERSISTED") == "1"
	if expect_persisted and runtime.data.overrides.is_empty():
		_fail("Persisted-save relaunch expected overrides, but none were loaded")

	if not await _wait_for_window(manager, Vector2i.ZERO, "startup"):
		_finish(test_root)
		return
	samples.append(_validate_center_state(manager, Vector2i.ZERO, "startup"))

	var centers: Array[Vector2i] = []
	for x in range(1, OUTWARD_STEPS + 1):
		centers.append(Vector2i(x, 0))
	for x in range(OUTWARD_STEPS - 1, -1, -1):
		centers.append(Vector2i(x, 0))

	var step_index := 0
	for next_center in centers:
		step_index += 1
		target.position = Vector3(next_center.x * CHUNK_SIZE + 0.5, 20.0, next_center.y * CHUNK_SIZE + 0.5)
		manager.refresh_streaming(target.global_position)
		if not await _wait_for_window(manager, next_center, "shift_%d" % step_index):
			_finish(test_root)
			return
		await process_frame
		await process_frame
		var sample := _validate_center_state(manager, next_center, "shift_%d" % step_index)
		samples.append(sample)
		if step_index % 6 == 0:
			print("CHUNK_STREAM_BIOME_SOAK_SAMPLE=%s" % JSON.stringify(sample))
		if not failures.is_empty():
			_finish(test_root)
			return

	if OS.get_environment("TEKNIK_WRITE_PERSISTED") == "1":
		var surface: int = int(runtime.data.terrain_height(2, 2))
		var save_cell := Vector3i(2, mini(surface + 10, WORLD_DATA.WORLD_HEIGHT - 1), 2)
		if runtime.data.get_block(save_cell) != WORLD_DATA.BLOCK_AIR:
			_fail("Could not find air fixture for persisted-save diagnostic at %s" % save_cell)
		elif not runtime.data.set_block(save_cell, WORLD_DATA.BLOCK_STONE):
			_fail("Could not create persisted-save diagnostic override")
		else:
			runtime.data.save_world()
			print("CHUNK_STREAM_BIOME_SOAK_PERSISTED_OVERRIDE=%s" % save_cell)

	var first: Dictionary = samples.front() if not samples.is_empty() else {}
	var last: Dictionary = samples.back() if not samples.is_empty() else {}
	var peak_memory := 0.0
	var peak_objects := 0
	var max_loaded := 0
	var max_revision_entries := 0
	for sample in samples:
		peak_memory = maxf(peak_memory, float(sample.get("memory_mb", 0.0)))
		peak_objects = maxi(peak_objects, int(sample.get("object_count", 0)))
		max_loaded = maxi(max_loaded, int(sample.get("loaded", 0)))
		max_revision_entries = maxi(max_revision_entries, int(sample.get("revision_entries", 0)))
	var report := {
		"fresh_save": not expect_persisted,
		"persisted_override_count": runtime.data.overrides.size(),
		"settled_samples": samples.size(),
		"outward_steps": OUTWARD_STEPS,
		"first_memory_mb": float(first.get("memory_mb", 0.0)),
		"final_memory_mb": float(last.get("memory_mb", 0.0)),
		"memory_growth_mb": float(last.get("memory_mb", 0.0)) - float(first.get("memory_mb", 0.0)),
		"peak_memory_mb": peak_memory,
		"first_object_count": int(first.get("object_count", 0)),
		"final_object_count": int(last.get("object_count", 0)),
		"peak_object_count": peak_objects,
		"max_loaded_chunks": max_loaded,
		"max_revision_entries": max_revision_entries,
		"final_diagnostics": manager.get_remesh_diagnostics(),
	}
	print("CHUNK_STREAM_BIOME_SOAK_REPORT=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("CHUNK_STREAM_BIOME_SOAK_PASS")
	_finish(test_root)


func _finish(test_root: Node) -> void:
	if is_instance_valid(test_root):
		test_root.queue_free()
	await process_frame
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			print("CHUNK_STREAM_BIOME_SOAK_FAILURE: %s" % failure)
		quit(1)
