extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT := "res://artifacts/threaded-remesh-step5-final.png"
const CSV_PATH := "res://artifacts/threaded-remesh-step5-frames.csv"
const JSON_PATH := "res://artifacts/threaded-remesh-step5-summary.json"
const AIR := 0
const DIRT := 2
const STONE := 3
const IDLE_LIMIT := 720
const GROUND_LIMIT := 240

var failures: Array[String] = []
var frame_rows: Array[String] = ["sample,time_ms,delta_ms,phase,player_x,player_y,player_z,remesh_idle"]
var all_deltas: Array[float] = []
var phase_deltas: Dictionary = {}
var phase_order: Array[String] = []
var previous_usec := 0
var elapsed_ms := 0.0
var sample_index := 0
var max_jump_y := -INF
var action_results: Dictionary = {}
var manager
var player
var camera: Camera3D
var overlay: Label


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("Main scene failed to load")
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	for _frame in range(24):
		await process_frame
	manager = main.get_node_or_null("ChunkManager")
	player = main.get_node_or_null("Player")
	camera = main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Main scene is missing manager, player, or camera")
		_finish()
		return
	if not await _wait_idle_unmeasured("initial world load"):
		_finish()
		return

	_add_overlay(main)
	var inventory = player.get_inventory()
	if inventory == null or not inventory.add_item(DIRT, 7):
		_fail("Could not seed seven dirt blocks")
		_finish()
		return
	await _tap_unmeasured("select_hotbar_1")

	var surface_y := _find_surface_y(0, 0)
	if surface_y == -2147483648:
		_fail("No origin surface found")
		_finish()
		return
	var target_coord := Vector3i(0, surface_y, 0)
	var target_center := Vector3(0.5, surface_y + 0.5, 0.5)
	player.set_physics_process(false)
	player.set_process(true)
	player.global_position = Vector3(0.5, surface_y + 3.0, 0.5)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(target_center, Vector3.FORWARD)
	for _frame in range(20):
		await process_frame

	if not manager.reset_remesh_diagnostics():
		_fail("Could not reset remesh diagnostics")
	previous_usec = Time.get_ticks_usec()

	await _record_process_frames(20, "aim_before_first_mine")
	var initial_target: Dictionary = player.get_block_target()
	if initial_target.get("block_coord", Vector3i(9999, 9999, 9999)) != target_coord:
		_fail("Initial target mismatch: expected %s got %s" % [target_coord, initial_target.get("block_coord")])
	var original_block := int(manager.get_block_world(target_coord))

	await _pulse("mine_block", "first_mine_input")
	await _wait_idle_recorded("first_mine_remesh")
	var first_mine_ok: bool = manager.get_block_world(target_coord) == AIR
	if not first_mine_ok:
		_fail("First mine did not remove target")

	camera.look_at(target_center, Vector3.FORWARD)
	await _record_process_frames(16, "aim_before_place")
	await _pulse("select_hotbar_1", "select_dirt_slot")
	await _pulse("place_block", "place_input")
	await _wait_idle_recorded("place_remesh")
	var place_ok: bool = manager.get_block_world(target_coord) == DIRT
	if not place_ok:
		_fail("Placement did not restore target as dirt")

	camera.look_at(target_center, Vector3.FORWARD)
	await _record_process_frames(16, "aim_before_second_mine")
	await _pulse("mine_block", "second_mine_input")
	await _wait_idle_recorded("second_mine_remesh")
	var second_mine_ok: bool = manager.get_block_world(target_coord) == AIR
	if not second_mine_ok:
		_fail("Second mine did not remove placed dirt")

	var dirt_before_craft := int(inventory.get_item_count(DIRT))
	var stone_before_craft := int(inventory.get_item_count(STONE))
	var craft_snapshots: Array[Dictionary] = []
	for attempt in range(3):
		await _pulse("craft_test_recipe", "craft_attempt_%d" % (attempt + 1))
		await _record_process_frames(12, "craft_result_%d" % (attempt + 1))
		craft_snapshots.append({
			"dirt": int(inventory.get_item_count(DIRT)),
			"stone": int(inventory.get_item_count(STONE)),
		})
	if dirt_before_craft != 7:
		_fail("Expected seven dirt before crafting, got %d" % dirt_before_craft)
	if craft_snapshots.size() == 3:
		if int(craft_snapshots[0].dirt) != 3 or int(craft_snapshots[0].stone) != stone_before_craft + 1:
			_fail("First craft did not consume four dirt and add one stone")
		if craft_snapshots[1] != craft_snapshots[0] or craft_snapshots[2] != craft_snapshots[0]:
			_fail("Insufficient-resource craft attempts changed inventory")

	var movement_y := _find_surface_y(8, 8)
	if movement_y == -2147483648:
		_fail("No movement surface found")
		movement_y = surface_y
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(8.5, movement_y + 2.1, 8.5)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	player.set_process(true)
	player.set_physics_process(true)
	if not await _wait_stably_grounded("movement_settle", 3, GROUND_LIMIT):
		_fail("Player did not become stably grounded before movement")

	var movement_start: Vector3 = player.global_position
	Input.action_press("move_backward")
	await _record_physics_frames(20, "movement_before_jump")
	Input.action_release("move_backward")
	if not await _wait_stably_grounded("movement_ground_recovery", 3, GROUND_LIMIT):
		_fail("Player did not recover a stable grounded state before jump")
	var jump_start_y: float = player.global_position.y
	max_jump_y = jump_start_y
	Input.action_press("jump")
	await _record_physics_frames(2, "jump_input")
	Input.action_release("jump")
	Input.action_press("move_backward")
	await _record_physics_frames(90, "movement_and_jump")
	Input.action_release("move_backward")
	await _record_physics_frames(45, "movement_after_jump")

	var movement_end: Vector3 = player.global_position
	var movement_distance := Vector2(
		movement_end.x - movement_start.x,
		movement_end.z - movement_start.z
	).length()
	var jump_height := max_jump_y - jump_start_y
	action_results = {
		"first_mine": first_mine_ok,
		"place": place_ok,
		"second_mine": second_mine_ok,
		"craft_snapshots": craft_snapshots,
		"movement_distance": movement_distance,
		"jump_height": jump_height,
		"original_mined_block": original_block,
	}
	if movement_distance < 1.0:
		_fail("Movement distance was only %.3f" % movement_distance)
	if jump_height < 0.3:
		_fail("Jump height was only %.3f" % jump_height)

	await _record_process_frames(30, "final_settle")
	await _capture_screenshot()
	_write_outputs()
	_print_summary(first_mine_ok, place_ok, second_mine_ok, movement_distance, jump_height)
	_finish()


func _add_overlay(main: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	main.add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(620, 116)
	panel.color = Color(0.0, 0.0, 0.0, 0.72)
	layer.add_child(panel)
	overlay = Label.new()
	overlay.position = Vector2(28, 25)
	overlay.add_theme_font_size_override("font_size", 20)
	layer.add_child(overlay)


func _tap_unmeasured(action: String) -> void:
	Input.action_press(action)
	await process_frame
	Input.action_release(action)


func _pulse(action: String, phase: String) -> void:
	Input.action_press(action)
	await _record_process_frames(2, phase)
	Input.action_release(action)
	await _record_process_frames(2, phase + "_release")


func _record_process_frames(count: int, phase: String) -> void:
	for _frame in range(count):
		await process_frame
		_record_sample(phase)


func _record_physics_frames(count: int, phase: String) -> void:
	for _frame in range(count):
		await physics_frame
		_record_sample(phase)


func _record_sample(phase: String) -> void:
	var now_usec := Time.get_ticks_usec()
	var delta_ms := (now_usec - previous_usec) / 1000.0
	previous_usec = now_usec
	elapsed_ms += delta_ms
	sample_index += 1
	all_deltas.append(delta_ms)
	if not phase_deltas.has(phase):
		phase_deltas[phase] = []
		phase_order.append(phase)
	phase_deltas[phase].append(delta_ms)
	max_jump_y = maxf(max_jump_y, player.global_position.y)
	frame_rows.append("%d,%.3f,%.3f,%s,%.4f,%.4f,%.4f,%s" % [
		sample_index,
		elapsed_ms,
		delta_ms,
		phase,
		player.global_position.x,
		player.global_position.y,
		player.global_position.z,
		manager.is_remesh_idle(),
	])
	overlay.text = "THREADED REMESH PLAYTHROUGH\nPhase: %s\nSample: %d   delta: %.2f ms\nRemesh queue: %s" % [
		phase,
		sample_index,
		delta_ms,
		"IDLE" if manager.is_remesh_idle() else "BUSY",
	]


func _wait_stably_grounded(phase: String, required_frames: int, frame_limit: int) -> bool:
	var consecutive := 0
	for _frame in range(frame_limit):
		await physics_frame
		_record_sample(phase)
		if player.is_on_floor():
			consecutive += 1
			if consecutive >= required_frames:
				return true
		else:
			consecutive = 0
	return false


func _wait_idle_recorded(phase: String) -> void:
	for sampled in range(IDLE_LIMIT):
		await _record_process_frames(1, phase)
		if manager.is_remesh_idle() and sampled >= 3:
			return
	_fail("Remesh queue did not become idle during %s" % phase)


func _wait_idle_unmeasured(context: String) -> bool:
	for _frame in range(IDLE_LIMIT):
		await process_frame
		if manager.is_remesh_idle():
			return true
	_fail("Remesh queue did not become idle during %s" % context)
	return false


func _find_surface_y(world_x: int, world_z: int) -> int:
	for world_y in range(47, -33, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != AIR:
			return world_y
	return -2147483648


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"median": 0.0, "p95": 0.0, "max": 0.0, "over_16_67": 0, "over_33_33": 0, "over_50": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var over_16 := 0
	var over_33 := 0
	var over_50 := 0
	for value in values:
		if float(value) > 16.67:
			over_16 += 1
		if float(value) > 33.33:
			over_33 += 1
		if float(value) > 50.0:
			over_50 += 1
	return {
		"median": float(sorted[floori((sorted.size() - 1) * 0.5)]),
		"p95": float(sorted[ceili((sorted.size() - 1) * 0.95)]),
		"max": float(sorted.back()),
		"over_16_67": over_16,
		"over_33_33": over_33,
		"over_50": over_50,
	}


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Final screenshot is empty")
		return
	var error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT))
	if error != OK:
		_fail("Final screenshot save failed: %d" % error)
	else:
		print("THREADED_REMESH_STEP_5_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT))


func _write_outputs() -> void:
	var csv := FileAccess.open(ProjectSettings.globalize_path(CSV_PATH), FileAccess.WRITE)
	if csv == null:
		_fail("Could not write frame CSV")
	else:
		for row in frame_rows:
			csv.store_line(row)
	var phase_summary := {}
	for phase in phase_order:
		phase_summary[phase] = _stats(phase_deltas[phase])
	var summary := {
		"pass": failures.is_empty(),
		"limitations": "Graphical GitHub runner under Xvfb/llvmpipe; not a physical Android-device recording.",
		"frames": _stats(all_deltas),
		"phase_frames": phase_summary,
		"actions": action_results,
		"remesh": manager.get_remesh_diagnostics(),
		"failures": failures,
	}
	var json := FileAccess.open(ProjectSettings.globalize_path(JSON_PATH), FileAccess.WRITE)
	if json == null:
		_fail("Could not write JSON summary")
	else:
		json.store_string(JSON.stringify(summary, "  "))


func _print_summary(
	first_mine_ok: bool,
	place_ok: bool,
	second_mine_ok: bool,
	movement_distance: float,
	jump_height: float
) -> void:
	var stats := _stats(all_deltas)
	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	print("FRAME_SUMMARY samples=%d median_ms=%.3f p95_ms=%.3f max_ms=%.3f over_16_67=%d over_33_33=%d over_50=%d" % [
		all_deltas.size(),
		stats.median,
		stats.p95,
		stats.max,
		stats.over_16_67,
		stats.over_33_33,
		stats.over_50,
	])
	print("PLAYTHROUGH_ACTIONS first_mine=%s place=%s second_mine=%s craft_successes=1 craft_failures=2 movement_distance=%.3f jump_height=%.3f" % [
		first_mine_ok,
		place_ok,
		second_mine_ok,
		movement_distance,
		jump_height,
	])
	print("REMESH_DIAGNOSTICS tasks_started=%d results_applied=%d stale_discarded=%d coalesced=%d max_queue_ms=%.3f max_background_ms=%.3f max_apply_ms=%.3f max_pump_ms=%.3f" % [
		int(diagnostics.get("tasks_started", 0)),
		int(diagnostics.get("results_applied", 0)),
		int(diagnostics.get("stale_results_discarded", 0)),
		int(diagnostics.get("coalesced_requests", 0)),
		float(diagnostics.get("max_queue_ms", 0.0)),
		float(diagnostics.get("max_background_compute_ms", 0.0)),
		float(diagnostics.get("max_apply_ms", 0.0)),
		float(diagnostics.get("max_pump_ms", 0.0)),
	])


func _finish() -> void:
	for action in ["mine_block", "place_block", "craft_test_recipe", "select_hotbar_1", "move_backward", "jump"]:
		Input.action_release(action)
	if failures.is_empty():
		print("THREADED_REMESH_STEP_5_PLAYTHROUGH_PASS")
		quit(0)
	else:
		print("THREADED_REMESH_STEP_5_PLAYTHROUGH_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
