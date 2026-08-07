extends SceneTree

const WORLD_PORT_SCRIPT := preload("res://scripts/world/playable_world_port.gd")
const WORLD_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SOURCE_PATH := "res://scripts/world/playable_world_port.gd"
const WAIT_TIMEOUT_MSEC := 30000
const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const STALE_TEST_CENTER := Vector2i(5, 0)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_for_collision_ring(manager) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await process_frame
		if manager.is_playable_world_collision_ring_ready():
			return true
	_fail("Standalone playable-world collision ring did not become ready")
	return false


func _wait_for_atomic_swap(manager, previous_swap_count: int, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await process_frame
		var diagnostics: Dictionary = manager.get_remesh_diagnostics()
		if int(diagnostics.get("atomic_swaps", 0)) > previous_swap_count:
			return true
	_fail("Standalone playable-world atomic swap did not complete during %s" % context)
	return false


func _wait_for_render_window(manager, center: Vector2i, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
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

	# Remove the second shipping-world fixture before timing so its background
	# workers cannot contaminate the Step-1 frame-time measurement.
	main.queue_free()
	await process_frame
	await process_frame

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
		print("CHUNK_STREAM_THREADING_STEP1_GATE_PASS")
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
		"max_active_build_tasks": int(WORLD_RUNTIME.MAX_ACTIVE_BUILD_TASKS),
		"max_build_applies_per_frame": int(WORLD_RUNTIME.MAX_BUILD_APPLIES_PER_FRAME),
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
	var sync_main_thread_ms: Array[float] = []
	for sample in phase_samples:
		var cache_value := float(sample.get("column_cache_ms", 0.0))
		var mesh_value := float(sample.get("mesh_data_ms", 0.0))
		var commit_value := float(sample.get("arraymesh_entry_ms", 0.0))
		cache_ms.append(cache_value)
		mesh_ms.append(mesh_value)
		commit_ms.append(commit_value)
		collision_ms.append(float(sample.get("collision_ms", 0.0)))
		sync_main_thread_ms.append(cache_value + mesh_value + commit_value)

	var before_stats := _stats(sync_main_thread_ms)
	var after_frame_p95_max := 0.0
	var after_frame_max := 0.0
	var queue_max := 0.0
	var apply_max := 0.0
	var pump_max := 0.0
	var background_max := 0.0
	for shift in shifts:
		if int(shift.get("requested_missing_count", 0)) <= 0:
			continue
		var frame_stats: Dictionary = shift.get("frame_wall_ms", {})
		after_frame_p95_max = maxf(after_frame_p95_max, float(frame_stats.get("p95", 0.0)))
		after_frame_max = maxf(after_frame_max, float(frame_stats.get("max", 0.0)))
		var shift_diag: Dictionary = shift.get("diagnostics", {})
		queue_max = maxf(queue_max, float(shift_diag.get("max_queue_ms", 0.0)))
		apply_max = maxf(apply_max, float(shift_diag.get("max_apply_ms", 0.0)))
		pump_max = maxf(pump_max, float(shift_diag.get("max_pump_ms", 0.0)))
		background_max = maxf(background_max, float(shift_diag.get("max_background_compute_ms", 0.0)))

	var baseline_p95 := float(before_stats.get("p95", 0.0))
	if background_max <= 0.0:
		_fail("Step 1 did not report any background chunk computation")
	if baseline_p95 <= 0.0:
		_fail("Step 1 synchronous baseline did not produce a measurable p95")
	elif pump_max >= baseline_p95 * 0.25:
		_fail("Threaded main-thread pump %.3f ms did not improve enough over %.3f ms synchronous p95" % [pump_max, baseline_p95])
	if baseline_p95 > 0.0 and after_frame_p95_max >= baseline_p95 * 0.50:
		_fail("Threaded stream frame p95 %.3f ms remained too close to %.3f ms synchronous p95" % [after_frame_p95_max, baseline_p95])

	var stale_report: Dictionary = await _measure_stale_rejection(manager)
	if stale_report.is_empty():
		return {}

	return {
		"measurement_scope": "Step 1 initial chunk streaming before/after; no directional lookahead or LRU cache",
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
		"before_after_main_thread_ms": {
			"before_sync_chunk_build": before_stats,
			"after_stream_frame_p95_max": after_frame_p95_max,
			"after_stream_frame_max": after_frame_max,
			"after_queue_max": queue_max,
			"after_apply_max": apply_max,
			"after_pump_max": pump_max,
			"background_compute_max": background_max,
		},
		"stale_result_gate": stale_report,
		"backtrack_regenerated_chunks": backtrack_missing,
	}


func _measure_live_shift(manager, target: Node3D, next_center: Vector2i) -> Dictionary:
	if not manager.reset_remesh_diagnostics():
		_fail("Could not reset chunk-stream diagnostics before shift to %s" % next_center)
		return {}
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
	while Time.get_ticks_usec() - start_usec < WAIT_TIMEOUT_MSEC * 1000:
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
			collision_ms.append(float(diag.get("max_collision_ms", 0.0)))
	if not pending.is_empty() or not _render_window_ready(manager, next_center):
		_fail("Chunk-stream shift to %s did not finish within %d ms" % [next_center, WAIT_TIMEOUT_MSEC])
		return {}
	var total_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	var missing_json: Array[Array] = []
	for coord in missing:
		missing_json.append([coord.x, coord.y])
	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	if not missing.is_empty() and float(diagnostics.get("max_background_compute_ms", 0.0)) <= 0.0:
		_fail("Shift to %s completed without background compute evidence" % next_center)
	return {
		"center": [next_center.x, next_center.y],
		"requested_missing_count": missing.size(),
		"requested_missing_coords": missing,
		"requested_missing_coords_json": missing_json,
		"stream_total_ms": total_ms,
		"observed_single_chunk_build_ms": _stats(build_ms),
		"main_thread_queue_ms": _stats(build_ms),
		"frame_wall_ms": _stats(frame_ms),
		"collision_build_ms": _stats(collision_ms),
		"max_new_chunks_in_one_frame": _max_int(loaded_per_frame),
		"diagnostics": diagnostics,
	}


func _measure_stale_rejection(manager) -> Dictionary:
	if not manager.reset_remesh_diagnostics():
		_fail("Could not reset diagnostics before stale-result gate")
		return {}
	var runtime = manager.get_playable_world_runtime()
	var original_center: Vector2i = runtime.center
	runtime.set_center(STALE_TEST_CENTER)
	runtime._pump_builds()
	var started_tasks := int(manager.get_remesh_diagnostics().get("active_tasks", 0))
	if started_tasks <= 0:
		_fail("Stale-result gate did not start any background tasks")
		return {}
	runtime.set_center(original_center)
	var start_usec := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start_usec < WAIT_TIMEOUT_MSEC * 1000:
		await process_frame
		var diagnostics: Dictionary = manager.get_remesh_diagnostics()
		if (
			int(diagnostics.get("stale_results_discarded", 0)) > 0
			and _render_window_ready(manager, original_center)
			and manager.is_remesh_idle()
		):
			return {
				"jump_center": [STALE_TEST_CENTER.x, STALE_TEST_CENTER.y],
				"return_center": [original_center.x, original_center.y],
				"active_tasks_started": started_tasks,
				"stale_results_discarded": int(diagnostics.get("stale_results_discarded", 0)),
				"results_applied": int(diagnostics.get("results_applied", 0)),
				"final_window_ready": true,
			}
	_fail("Stale worker results were not rejected and recovered within %d ms" % WAIT_TIMEOUT_MSEC)
	return {}


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