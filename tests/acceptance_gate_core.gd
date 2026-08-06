extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/acceptance-gate.png"
const WORLD_READY_FRAME_LIMIT := 900
const MAX_RETAINED_CHUNK_COUNT := 81
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_SAND := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6

var failures: Array[String] = []
var headless_only := false


func _initialize() -> void:
	headless_only = OS.get_cmdline_user_args().has("--headless-only")
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _wait_for_world_ready(manager, context: String) -> bool:
	for _frame in range(WORLD_READY_FRAME_LIMIT):
		await process_frame
		if (
			manager.chunk_count() >= manager.expected_chunk_count()
			and manager.chunk_count() <= MAX_RETAINED_CHUNK_COUNT
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
	_fail(
		"Playable world did not become ready during %s: chunks=%d expected=%d collision=%s idle=%s"
		% [
			context,
			manager.chunk_count(),
			manager.expected_chunk_count(),
			manager.is_playable_world_collision_ring_ready(),
			manager.is_remesh_idle(),
		]
	)
	return false


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager = main.get_node_or_null("ChunkManager")
	var player := main.get_node_or_null("Player") as CharacterBody3D
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	var environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if manager == null:
		_fail("ChunkManager node is missing")
	if player == null:
		_fail("Player node is missing")
	if camera == null:
		_fail("Player camera is missing")
	if environment == null or environment.environment == null:
		_fail("WorldEnvironment is missing or unconfigured")
	if sun == null:
		_fail("DirectionalLight3D sun is missing")
	if not failures.is_empty():
		_finish()
		return

	if not manager.is_playable_world_port_active():
		_fail("Desktop/headless main scene did not activate the playable-world system")
	if player.get("_chunk_manager") != manager:
		_fail("Player did not bind to the single ChunkManager world contract")
	if not failures.is_empty():
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(false)
	print("HEADLESS_SCENE_LAUNCH_PASS")
	print("SINGLE_WORLD_BINDING=playable_world_port.gd")

	await _test_streaming(manager, player)
	_test_terrain_and_features(manager)

	if headless_only:
		_finish()
		return

	await _test_render_and_collision(manager, player)
	await _test_player_controller(manager, player, camera)
	_test_atmosphere(environment, sun)
	await _capture_screenshot(manager, player, camera)
	_finish()


func _test_streaming(manager, player: CharacterBody3D) -> void:
	var expected_count: int = manager.expected_chunk_count()
	if expected_count != 49:
		_fail("Playable-world expected chunk count changed from 49 to %d" % expected_count)
		return

	var traversal_positions := [
		Vector3(0.5, 20.0, 0.5),
		Vector3(72.5, 20.0, 0.5),
		Vector3(-72.5, 20.0, 0.5),
		Vector3(0.5, 20.0, 72.5),
		Vector3(0.5, 20.0, -72.5),
		Vector3(0.5, 20.0, 0.5),
	]
	var previous_center := Vector3i(2147483647, 0, 2147483647)
	var max_loaded_count := 0

	for traversal_position in traversal_positions:
		player.global_position = traversal_position
		manager.refresh_streaming(traversal_position)
		if not await _wait_for_world_ready(manager, "streaming traversal at %s" % traversal_position):
			return
		var center: Vector3i = manager.world_to_chunk_coord(traversal_position)
		var loaded_count: int = manager.chunk_count()
		max_loaded_count = maxi(max_loaded_count, loaded_count)
		if loaded_count < expected_count or loaded_count > MAX_RETAINED_CHUNK_COUNT:
			_fail(
				"Traversal at %s retained %d chunks; expected %d active and at most %d buffered"
				% [center, loaded_count, expected_count, MAX_RETAINED_CHUNK_COUNT]
			)
			return
		if not manager.has_chunk(center):
			_fail("Playable-world center chunk was not loaded at %s" % center)
			return
		var entry: Dictionary = manager.get_playable_world_chunk_entry(Vector2i(center.x, center.z))
		if not _entry_has_mesh(entry):
			_fail("Center chunk render entry was invalid at %s" % center)
			return
		if not is_instance_valid(entry.get("collision")):
			_fail("Center chunk collision was unavailable at %s" % center)
			return
		if previous_center.x != 2147483647 and previous_center.distance_squared_to(center) > 25:
			if manager.has_chunk(previous_center):
				_fail("Far previous center %s remained loaded after traversal to %s" % [previous_center, center])
				return
		previous_center = center

	print("PLAYABLE_STREAMING_GATE_PASS")
	print("TRAVERSAL_POSITIONS_TESTED=%d" % traversal_positions.size())
	print("ACTIVE_CHUNK_TARGET=%d" % expected_count)
	print("MAX_RETAINED_CHUNKS=%d" % max_loaded_count)


func _test_terrain_and_features(manager) -> void:
	var heights: Dictionary = {}
	for sample in [Vector2i(0, 0), Vector2i(28, 7), Vector2i(-19, 31), Vector2i(47, -23), Vector2i(-64, -64)]:
		var height: int = manager.get_playable_world_height(sample.x, sample.y)
		heights[height] = true
		if height < 3 or height > 27:
			_fail("Terrain height %d was outside playable-world bounds at %s" % [height, sample])
		var surface_block: int = manager.get_block_world(Vector3i(sample.x, height, sample.y))
		if surface_block != BLOCK_GRASS and surface_block != BLOCK_SAND:
			_fail("Terrain surface at %s used unexpected block ID %d" % [sample, surface_block])

	if heights.size() < 2:
		_fail("Playable-world terrain samples did not vary in height")

	var tree_origin := Vector2i(2147483647, 2147483647)
	for z in range(-32, 33):
		for x in range(-32, 33):
			var surface: int = manager.get_playable_world_height(x, z)
			if manager.get_block_world(Vector3i(x, surface + 1, z)) == BLOCK_LOG:
				tree_origin = Vector2i(x, z)
				break
		if tree_origin.x != 2147483647:
			break

	if tree_origin.x == 2147483647:
		_fail("No deterministic playable-world tree was found in the validation area")
	else:
		var tree_surface: int = manager.get_playable_world_height(tree_origin.x, tree_origin.y)
		var leaves_found := false
		for y in range(tree_surface + 3, tree_surface + 6):
			for z_offset in range(-1, 2):
				for x_offset in range(-1, 2):
					if manager.get_block_world(Vector3i(tree_origin.x + x_offset, y, tree_origin.y + z_offset)) == BLOCK_LEAVES:
						leaves_found = true
		if not leaves_found:
			_fail("Playable-world tree at %s had no leaf canopy" % tree_origin)

	if failures.is_empty():
		print("PLAYABLE_TERRAIN_FEATURE_GATE_PASS")
		print("HEIGHT_VARIANTS=%d" % heights.size())
		print("TREE_ORIGIN=%s" % tree_origin)


func _test_render_and_collision(manager, player: CharacterBody3D) -> void:
	var origin_position := Vector3(0.5, 20.0, 0.5)
	player.global_position = origin_position
	manager.refresh_streaming(origin_position)
	if not await _wait_for_world_ready(manager, "render and collision validation"):
		return
	var entry: Dictionary = manager.get_playable_world_chunk_entry(Vector2i.ZERO)
	if not _entry_has_mesh(entry):
		_fail("Origin playable-world chunk render mesh is missing")
	if not is_instance_valid(entry.get("collision")):
		_fail("Origin playable-world collision is missing")
	if failures.is_empty():
		print("PLAYABLE_RENDER_COLLISION_GATE_PASS")


func _entry_has_mesh(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	var root_node := entry.get("root") as Node3D
	var mesh := entry.get("mesh") as ArrayMesh
	return is_instance_valid(root_node) and mesh != null and mesh.get_surface_count() > 0


func _test_player_controller(manager, player: CharacterBody3D, camera: Camera3D) -> void:
	var spawn_y: float = float(manager.get_playable_world_height(0, 0)) + 2.2
	player.global_position = Vector3(0.5, spawn_y, 0.5)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	manager.refresh_streaming(player.global_position)
	if not await _wait_for_world_ready(manager, "player controller collision readiness"):
		return
	player.set_physics_process(true)
	player.set_process(true)

	if not await _wait_until_stably_grounded(player, 3, 240):
		_fail("Player did not remain grounded for three consecutive physics frames")
		return

	Input.action_release("jump")
	await physics_frame
	var jump_start_y := player.global_position.y
	player.set_physics_process(false)
	Input.action_press("jump", 1.0)
	player.call("_physics_process", 1.0 / float(Engine.physics_ticks_per_second))
	Input.action_release("jump")
	player.set_physics_process(true)
	if player.velocity.y <= 0.0:
		_fail("Jump InputMap action did not produce upward controller velocity")
		return
	if not await _wait_until_above_y(player, jump_start_y + 0.05, 12):
		_fail("Jump action did not raise the player")
		return
	if not await _wait_until_grounded(player, 240):
		_fail("Player did not return to ground after jumping")
		return

	var movement_start := player.global_position
	Input.action_press("move_forward", 1.0)
	await _wait_physics_frames(15)
	Input.action_release("move_forward")
	var horizontal_distance := Vector2(
		player.global_position.x - movement_start.x,
		player.global_position.z - movement_start.z
	).length()
	if horizontal_distance < 0.25:
		_fail("Player movement produced only %.3f units of travel" % horizontal_distance)
		return

	var yaw_before := player.rotation.y
	var pitch_before := camera.rotation.x
	player.apply_look_delta(Vector2(0.2, -0.1))
	if is_equal_approx(player.rotation.y, yaw_before):
		_fail("Look input did not change player yaw")
	if is_equal_approx(camera.rotation.x, pitch_before):
		_fail("Look input did not change camera pitch")

	if failures.is_empty():
		print("PLAYER_CONTROLLER_GATE_PASS")


func _wait_until_grounded(player: CharacterBody3D, frame_limit: int) -> bool:
	for _frame in range(frame_limit):
		await physics_frame
		if player.is_on_floor():
			return true
	return false


func _wait_until_stably_grounded(player: CharacterBody3D, required_frames: int, frame_limit: int) -> bool:
	var consecutive := 0
	for _frame in range(frame_limit):
		await physics_frame
		if player.is_on_floor():
			consecutive += 1
			if consecutive >= required_frames:
				return true
		else:
			consecutive = 0
	return false


func _wait_until_above_y(player: CharacterBody3D, minimum_y: float, frame_limit: int) -> bool:
	for _frame in range(frame_limit):
		await physics_frame
		if player.global_position.y > minimum_y:
			return true
	return false


func _test_atmosphere(environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if environment.environment.background_mode != Environment.BG_SKY:
		_fail("World environment is not using the configured sky")
	if environment.environment.sky == null:
		_fail("World environment sky resource is missing")
	if sun.shadow_enabled:
		_fail("Vanilla lighting must keep directional shadow maps disabled")
	if failures.is_empty():
		print("ATMOSPHERE_GATE_PASS")


func _capture_screenshot(manager, player: CharacterBody3D, camera: Camera3D) -> void:
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(0.5, manager.get_playable_world_height(0, 24) + 6.0, 24.0)
	player.rotation = Vector3.ZERO
	camera.rotation_degrees.x = -22.0
	manager.refresh_streaming(player.global_position)
	if not await _wait_for_world_ready(manager, "screenshot terrain readiness"):
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Viewport screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Screenshot dimensions were %dx%d instead of 1280x720" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Screenshot save failed with error %d" % save_error)
		return
	print("SCREENSHOT_PASS=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	for action in ["jump", "move_forward"]:
		Input.action_release(action)
	if failures.is_empty():
		print("TEKNIK_ACCEPTANCE_GATE_PASS")
		quit(0)
	else:
		print("TEKNIK_ACCEPTANCE_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
