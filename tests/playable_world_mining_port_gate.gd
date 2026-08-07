extends SceneTree

const WORLD_PORT_SCRIPT := preload("res://scripts/world/playable_world_port.gd")
const WORLD_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SOURCE_PATH := "res://scripts/world/playable_world_port.gd"
const FRAME_LIMIT := 600
const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const BLOCK_AIR := 0
const BLOCK_STONE := 3

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_for_collision_ring(manager) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if manager.is_playable_world_collision_ring_ready():
			return true
	_fail("Standalone playable-world collision ring did not become ready")
	return false


func _wait_for_atomic_swap(manager, previous_swap_count: int, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		var diagnostics: Dictionary = manager.get_remesh_diagnostics()
		if int(diagnostics.get("atomic_swaps", 0)) > previous_swap_count:
			return true
	_fail("Standalone playable-world atomic swap did not complete during %s" % context)
	return false


func _wait_for_render_window(manager, center: Vector2i, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if _render_window_ready(manager, center) and manager.is_remesh_idle():
			return true
	_fail("Standalone playable-world render window did not become ready during %s" % context)
	return false


func _render_window_ready(manager, center: Vector2i) -> bool:
	for z in range(center.y - RENDER_RADIUS, center.y + RENDER_RADIUS + 1):
		for x in range(center.x - RENDER_RADIUS, center.x + RENDER_RADIUS + 1):
			if not manager.has_chunk(Vector3i(x, 0, z)):
				return false
	return true


func _validate_standalone_source() -> void:
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	if source.is_empty():
		_fail("Could not read standalone adapter source")
		return
	for forbidden in ["chunk_manager.gd", "super.", "OS.has_feature", "force_playable_world_port"]:
		if source.contains(forbidden):
			_fail("Standalone adapter still contains forbidden fallback dependency: %s" % forbidden)


func _run_gate() -> void:
	_validate_standalone_source()
	if not failures.is_empty():
		_finish()
		return

	var test_root := Node3D.new()
	test_root.name = "PlayableWorldStandaloneGate"
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
	if not manager.is_playable_world_port_active():
		_fail("Standalone playable-world adapter did not report active")
		_finish()
		return
	if manager.expected_chunk_count() != 49:
		_fail("Standalone world no longer targets the 7x7 visual radius")

	if not await _wait_for_collision_ring(manager):
		_finish()
		return
	if manager.chunk_count() < 9:
		_fail("Standalone startup loaded fewer than nine collision-ring chunks")

	var height_samples: Dictionary = {}
	for sample in [Vector2i(2, 2), Vector2i(28, 7), Vector2i(-19, 31), Vector2i(47, -23)]:
		height_samples[manager.get_playable_world_height(sample.x, sample.y)] = true
	if height_samples.size() < 2:
		_fail("Standalone deterministic terrain did not produce varied heights")

	var edit_y: int = manager.get_playable_world_height(2, 2) + 2
	var edit_coord := Vector3i(2, edit_y, 2)
	if manager.get_block_world(edit_coord) != BLOCK_AIR:
		var clear_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
		if not manager.set_block_world(edit_coord, BLOCK_AIR):
			_fail("Could not clear standalone edit fixture")
		elif not await _wait_for_atomic_swap(manager, clear_swaps, "fixture clear"):
			_finish()
			return

	var chunk_coord := Vector2i(0, 0)
	var entry_before: Dictionary = manager.get_playable_world_chunk_entry(chunk_coord)
	var root_before := entry_before.get("root") as Node3D
	var place_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.place_block_world(edit_coord, BLOCK_STONE):
		_fail("Standalone placement rejected a valid air cell")
		_finish()
		return
	if not await _wait_for_atomic_swap(manager, place_swaps, "placement"):
		_finish()
		return
	if manager.get_block_world(edit_coord) != BLOCK_STONE:
		_fail("Standalone placement did not update block data")
	var entry_after_place: Dictionary = manager.get_playable_world_chunk_entry(chunk_coord)
	var root_after_place := entry_after_place.get("root") as Node3D
	if not is_instance_valid(root_after_place) or root_after_place == root_before:
		_fail("Standalone placement did not atomically replace the chunk root")
	if not is_instance_valid(entry_after_place.get("collision")):
		_fail("Standalone placement replacement lost collision")

	var mine_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.mine_block_world(edit_coord):
		_fail("Standalone mining rejected the placed block")
		_finish()
		return
	if manager.get_block_world(edit_coord) != BLOCK_AIR:
		_fail("Standalone mining did not update block data immediately")
	if not await _wait_for_atomic_swap(manager, mine_swaps, "mining"):
		_finish()
		return
	var entry_after_mine: Dictionary = manager.get_playable_world_chunk_entry(chunk_coord)
	var root_after_mine := entry_after_mine.get("root") as Node3D
	if not is_instance_valid(root_after_mine) or root_after_mine == root_after_place:
		_fail("Standalone mining did not atomically replace the chunk root")
	if not is_instance_valid(entry_after_mine.get("collision")):
		_fail("Standalone mining replacement lost collision")

	var packed_main := load(MAIN_SCENE) as PackedScene
	if packed_main == null:
		_fail("Main scene failed to load with standalone adapter")
		_finish()
		return
	var main := packed_main.instantiate()
	root.add_child(main)
	for _frame in range(32):
		await process_frame
	var scene_manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	if scene_manager == null or player == null:
		_fail("Main scene is missing standalone manager or player")
	elif not scene_manager.is_playable_world_port_active():
		_fail("Main scene did not activate standalone playable world on desktop")
	elif player.get("_chunk_manager") != scene_manager:
		_fail("Player did not bind to the standalone world contract")

	if not await _wait_for_render_window(manager, Vector2i.ZERO, "chunk-stream diagnosis baseline"):
		_finish()
		return
	var stream_report: Dictionary = await _measure_chunk_streaming(manager, target)
	if stream_report.is_empty():
		_finish()
		return

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	if int(diagnostics.get("atomic_swap_failures", 0)) != 0:
		_fail("Standalone adapter reported an atomic swap failure")

	if failures.is_empty():
		print("PLAYABLE_WORLD_STANDALONE_GATE_PASS")
		print("STANDALONE_INHERITANCE=Node3D only; no legacy fallback")
		print("STANDALONE_STARTUP_CHUNKS=%d" % manager.chunk_count())
		print("STANDALONE_PLACE_MINE=%s -> stone -> air" % edit_coord)
		print("STANDALONE_MAIN_SCENE_BINDING=player uses ChunkManager node contract")
		print("CHUNK_STREAM_DIAG_JSON=%s" % JSON.stringify(stream_report))

	_finish()


func _measure_chunk_streaming(manager, target: Node3D) -> Dictionary:
	var runtime = manager.get_playable_world_runtime()
	if runtime == null:
		_fail("Chunk-stream diagnosis could not resolve the shipping runtime")
		return {}
	var initial_diagnostics: Dictionary = manager.get_remesh_diagnostics()
	var architecture := {
		"background_compute_ms": float(initial_diagnostics.get("max_background_compute_ms", -1.0)),
		"build_budget_usec": int(WORLD_RUNTIME.BUILD_BUDGET_USEC),
		"world_height": int(WORLD_DATA.WORLD_HEIGHT),
		"chunk_size": CHUNK_SIZE,
		"render_radius": RENDER_RADIUS,
	}

	var shifts: Array[Dictionary] = []
	var first_forward_coords: Array[Vector2i] = []
	for next_center in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0)]:
		var shift: Dictionary = await _measure_live_shift(manager, target, next_center)
		if shift.is_empty():
			return {}
		shifts.append(shift)
		if next_center == Vector2i(1, 0) and first_forward_coords.is_empty():
			for coord_value: Variant in shift.get("requested_missing_coords", []):
				var coord: Vector2i = coord_value
				first_forward_coords.append(coord)

	if first_forward_coords.size() != 7:
		_fail("Expected seven first-boundary incoming chunks, measured %d" % first_forward_coords.size())
		return {}
	var backtrack_missing: int = int(shifts[4].get("requested_missing_count", -1))
	if backtrack_missing != 7:
		_fail("Expected seven regenerated chunks after two-chunk backtrack, measured %d" % backtrack_missing)
		return {}

	var phase_samples: Array[Dictionary] = []
	for coord in first_forward_coords:
		phase_samples.append(_measure_chunk_phases(runtime, coord))
	var cache_ms: Array[float] = []
	var mesh_ms: Array[float] = []
	var commit_ms: Array[float] = []
	var collision_ms: Array[float] = []
	for sample in phase_samples:
		cache_ms.append(float(sample.get("column_cache_ms", 0.0)))
		mesh_ms.append(float(sample.get("mesh_data_ms", 0.0)))
		commit_ms.append(float(sample.get("arraymesh_entry_ms", 0.0)))
		collision_ms.append(float(sample.get("collision_ms", 0.0)))

	return {
		"measurement_scope": "shipping initial chunk stream path; no mining/placement remesh",
		"proxy": "Godot 4.3 hosted Linux headless runtime",
		"architecture": architecture,
		"live_shifts": shifts,
		"phase_samples": phase_samples,
		"phase_stats_ms": {
			"column_cache": _stats(cache_ms),
			"mesh_data": _stats(mesh_ms),
			"arraymesh_entry": _stats(commit_ms),
			"collision": _stats(collision_ms),
		},
		"backtrack_regenerated_chunks": backtrack_missing,
	}


func _measure_live_shift(manager, target: Node3D, next_center: Vector2i) -> Dictionary:
	var runtime = manager.get_playable_world_runtime()
	var missing: Array[Vector2i] = []
	for z in range(next_center.y - RENDER_RADIUS, next_center.y + RENDER_RADIUS + 1):
		for x in range(next_center.x - RENDER_RADIUS, next_center.x + RENDER_RADIUS + 1):
			var coord := Vector2i(x, z)
			if not runtime.loaded.has(coord):
				missing.append(coord)
	var pending: Dictionary = {}
	for coord in missing:
		pending[coord] = true
	var build_ms: Array[float] = []
	var frame_ms: Array[float] = []
	var collision_ms: Array[float] = []
	var loaded_per_frame: Array[int] = []
	var start_usec := Time.get_ticks_usec()
	target.global_position = Vector3(
		next_center.x * CHUNK_SIZE + 0.5,
		target.global_position.y,
		next_center.y * CHUNK_SIZE + 0.5
	)
	for _frame in range(FRAME_LIMIT):
		if pending.is_empty() and _render_window_ready(manager, next_center) and manager.is_remesh_idle():
			break
		var frame_start := Time.get_ticks_usec()
		await process_frame
		frame_ms.append((Time.get_ticks_usec() - frame_start) / 1000.0)
		var newly_loaded: Array[Vector2i] = []
		for coord_value: Variant in pending.keys():
			var coord: Vector2i = coord_value
			if runtime.loaded.has(coord):
				newly_loaded.append(coord)
		for coord in newly_loaded:
			pending.erase(coord)
		loaded_per_frame.append(newly_loaded.size())
		if not newly_loaded.is_empty():
			var diag: Dictionary = manager.get_remesh_diagnostics()
			if newly_loaded.size() == 1:
				build_ms.append(float(diag.get("max_queue_ms", 0.0)))
			collision_ms.append(float(diag.get("max_apply_ms", 0.0)))
	if not pending.is_empty() or not _render_window_ready(manager, next_center):
		_fail("Chunk-stream shift to %s did not finish within the frame limit" % next_center)
		return {}
	var total_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	var missing_json: Array[Array] = []
	for coord in missing:
		missing_json.append([coord.x, coord.y])
	return {
		"center": [next_center.x, next_center.y],
		"requested_missing_count": missing.size(),
		"requested_missing_coords": missing,
		"requested_missing_coords_json": missing_json,
		"stream_total_ms": total_ms,
		"observed_single_chunk_build_ms": _stats(build_ms),
		"frame_wall_ms": _stats(frame_ms),
		"collision_build_ms": _stats(collision_ms),
		"max_new_chunks_in_one_frame": _max_int(loaded_per_frame),
	}


func _measure_chunk_phases(runtime, coord: Vector2i) -> Dictionary:
	var cache_start := Time.get_ticks_usec()
	var caches: Dictionary = runtime._build_column_caches(coord)
	var cache_usec := Time.get_ticks_usec() - cache_start
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh_start := Time.get_ticks_usec()
	var mesh_data: Dictionary = WORLD_MESHER.build(
		coord,
		heights,
		runtime.data.overrides,
		CHUNK_SIZE,
		WORLD_DATA.WORLD_HEIGHT,
		WORLD_DATA.SEA_LEVEL,
		biomes
	)
	var mesh_usec := Time.get_ticks_usec() - mesh_start
	var entry_start := Time.get_ticks_usec()
	var entry: Dictionary = runtime._create_entry(coord, mesh_data, false)
	var entry_usec := Time.get_ticks_usec() - entry_start
	var collision_usec := 0
	var mesh := entry.get("mesh") as ArrayMesh
	if mesh != null:
		var collision_start := Time.get_ticks_usec()
		var collision: StaticBody3D = runtime._create_collision(mesh)
		collision_usec = Time.get_ticks_usec() - collision_start
		if is_instance_valid(collision):
			collision.free()
	var entry_root := entry.get("root") as Node3D
	if is_instance_valid(entry_root):
		entry_root.free()
	return {
		"coord": [coord.x, coord.y],
		"column_cache_ms": cache_usec / 1000.0,
		"mesh_data_ms": mesh_usec / 1000.0,
		"arraymesh_entry_ms": entry_usec / 1000.0,
		"collision_ms": collision_usec / 1000.0,
		"faces": int(mesh_data.get("face_count", 0)),
	}


func _stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {
		"count": sorted.size(),
		"mean": total / float(sorted.size()),
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"max": sorted[sorted.size() - 1],
	}


func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	var index := clampi(ceili(fraction * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _max_int(values: Array[int]) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result


func _finish() -> void:
	quit(1 if not failures.is_empty() else 0)
