extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const REMESH_IDLE_FRAME_LIMIT := 360
const PLAYER_GROUND_FRAME_LIMIT := 240

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return

	var main := packed_scene.instantiate()
	var manager = main.get_node_or_null("ChunkManager")
	if manager == null:
		_fail("ChunkManager is missing before scene startup")
		_finish()
		return
	manager.force_mobile_profile = true
	root.add_child(main)
	await process_frame
	await process_frame

	var player := main.get_node_or_null("Player") as CharacterBody3D
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if not manager.is_mobile_profile_active():
		_fail("Forced mobile profile did not activate")
	if manager.render_radius != 1:
		_fail("Mobile render radius was %d instead of 1" % manager.render_radius)
	if manager.expected_chunk_count() != 7:
		_fail("Mobile profile expected %d startup chunks instead of 7" % manager.expected_chunk_count())
	if manager.chunk_count() != manager.expected_chunk_count():
		_fail(
			"Mobile startup loaded %d chunks instead of %d"
			% [manager.chunk_count(), manager.expected_chunk_count()]
		)
	if sun == null:
		_fail("Directional light is missing")
	elif sun.directional_shadow_max_distance > 48.0:
		_fail(
			"Mobile shadow distance remained %.1f instead of being capped at 48"
			% sun.directional_shadow_max_distance
		)
	if player == null:
		_fail("Player is missing")

	if not await _wait_for_remesh_idle(manager):
		_finish()
		return

	var terrain_chunk = manager.get_chunk(Vector3i(0, 0, 0))
	if terrain_chunk == null:
		_fail("Ground chunk (0, 0, 0) was not loaded by the mobile profile")
	elif (
		terrain_chunk.collision_shape == null
		or terrain_chunk.collision_shape.shape == null
	):
		_fail("Ground collision was not ready after mobile startup remeshing")

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	var tasks_started := int(diagnostics.get("tasks_started", 0))
	if tasks_started <= 0 or tasks_started > manager.expected_chunk_count():
		_fail(
			"Mobile startup submitted %d remesh tasks for %d chunks"
			% [tasks_started, manager.expected_chunk_count()]
		)

	if player != null:
		var grounded := await _wait_for_player_ground(player)
		if not grounded:
			_fail(
				"Player did not reach stable ground during the mobile startup window; y=%.3f"
				% player.global_position.y
			)

	if failures.is_empty():
		print("MOBILE_STARTUP_PROFILE=%s" % manager.get_mobile_profile_diagnostics())
		print("MOBILE_STARTUP_REMESH=%s" % diagnostics)
		print("MOBILE_STARTUP_GATE_PASS")
	_finish()


func _wait_for_remesh_idle(manager) -> bool:
	for _frame in range(REMESH_IDLE_FRAME_LIMIT):
		await process_frame
		if manager.is_remesh_idle():
			return true
	_fail("Mobile remesh queue did not become idle")
	return false


func _wait_for_player_ground(player: CharacterBody3D) -> bool:
	var stable_frames := 0
	for _frame in range(PLAYER_GROUND_FRAME_LIMIT):
		await physics_frame
		if player.is_on_floor():
			stable_frames += 1
			if stable_frames >= 3:
				return true
		else:
			stable_frames = 0
		if player.global_position.y < -16.0:
			return false
	return false


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MOBILE_STARTUP_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
