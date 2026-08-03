extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/acceptance-gate.png"

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


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(20)

	var manager := main.get_node_or_null("ChunkManager")
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

	player.set_physics_process(false)
	player.set_process(false)
	print("HEADLESS_SCENE_LAUNCH_PASS")

	await _test_chunk_streaming(manager, player)
	await _test_terrain_and_biomes(manager, player)

	if headless_only:
		_finish()
		return

	await _test_mesh_and_collision(manager, player)
	await _test_player_controller(manager, player, camera)
	_test_atmosphere(environment, sun)
	await _capture_screenshot(manager, player, camera)
	_finish()


func _test_chunk_streaming(manager, player: CharacterBody3D) -> void:
	var expected_count: int = manager.expected_chunk_count()
	if manager.chunk_count() != expected_count:
		_fail("Initial chunk count mismatch: expected %d, got %d" % [expected_count, manager.chunk_count()])

	var traversal_positions := [
		Vector3(0.5, 20.0, 0.5),
		Vector3(48.5, 20.0, 0.5),
		Vector3(-48.5, 20.0, 0.5),
		Vector3(0.5, 20.0, 48.5),
		Vector3(0.5, 20.0, -48.5),
		Vector3(0.5, 20.0, 0.5),
	]
	var previous_center := Vector3i(2147483647, 2147483647, 2147483647)

	for traversal_position in traversal_positions:
		player.global_position = traversal_position
		manager.refresh_streaming(traversal_position)
		await _wait_frames(5)
		var center = manager.world_to_chunk_coord(traversal_position)
		if manager.chunk_count() != expected_count:
			_fail(
				"Traversal chunk count mismatch at %s: expected %d, got %d"
				% [center, expected_count, manager.chunk_count()]
			)
			return
		if not manager.has_chunk(center):
			_fail("Center chunk %s was not loaded" % center)
			return
		if previous_center.x != 2147483647:
			if previous_center.distance_squared_to(center) > manager.render_radius * manager.render_radius:
				if manager.has_chunk(previous_center):
					_fail("Previous center %s remained loaded after traversal to %s" % [previous_center, center])
					return
		previous_center = center

	if failures.is_empty():
		print("STEP_1_GATE_PASS")
		print("TRAVERSAL_POSITIONS_TESTED=%d" % traversal_positions.size())
		print("EXPECTED_CHUNK_COUNT=%d" % expected_count)


func _test_terrain_and_biomes(manager, player: CharacterBody3D) -> void:
	var biome_samples: Dictionary = {}
	for sample_x in range(-4096, 4097, 128):
		for sample_z in range(-4096, 4097, 128):
			var noise_value: float = manager._biome_noise.get_noise_2d(sample_x, sample_z)
			var biome_id := 0
			if noise_value < -0.25:
				biome_id = 2
			elif noise_value > 0.25:
				biome_id = 1
			if not biome_samples.has(biome_id):
				biome_samples[biome_id] = Vector2i(sample_x, sample_z)
			if biome_samples.size() == 3:
				break
		if biome_samples.size() == 3:
			break

	if biome_samples.size() != 3:
		_fail("Biome noise scan found %d of 3 configured biomes" % biome_samples.size())
		return

	for expected_biome in biome_samples.keys():
		var sample_position: Vector2i = biome_samples[expected_biome]
		var world_position := Vector3(sample_position.x + 0.5, 8.0, sample_position.y + 0.5)
		player.global_position = world_position
		manager.refresh_streaming(world_position)
		await _wait_frames(3)

		var center_coord = manager.world_to_chunk_coord(world_position)
		var sample_chunk = manager.get_chunk(center_coord)
		if sample_chunk == null:
			_fail("Biome sample chunk failed to load at %s" % center_coord)
			continue

		var local_column := Vector2i(posmod(sample_position.x, 16), posmod(sample_position.y, 16))
		var actual_biome: int = sample_chunk.get_biome(local_column)
		if actual_biome != int(expected_biome):
			_fail("Biome mismatch at %s: expected %d, got %d" % [sample_position, expected_biome, actual_biome])
			continue

		var expected_density := 20
		if int(expected_biome) == 1:
			expected_density = 75
		elif int(expected_biome) == 2:
			expected_density = 0
		var actual_density: int = sample_chunk.get_vegetation_density(local_column)
		if actual_density != expected_density:
			_fail("Vegetation density mismatch for biome %d: expected %d, got %d" % [expected_biome, expected_density, actual_density])

		var surface_block := 0
		for local_y in range(15, -1, -1):
			var block_id: int = sample_chunk.get_block(Vector3i(local_column.x, local_y, local_column.y))
			if block_id != 0:
				surface_block = block_id
				break
		var expected_surface := 4 if int(expected_biome) == 2 else 1
		if surface_block != expected_surface:
			_fail("Surface block mismatch for biome %d: expected %d, got %d" % [expected_biome, expected_surface, surface_block])

	if failures.is_empty():
		print("STEP_2_GATE_PASS")
		print("BIOMES_VALIDATED=3")


func _test_mesh_and_collision(manager, player: CharacterBody3D) -> void:
	var origin_position := Vector3(0.5, 20.0, 0.5)
	player.global_position = origin_position
	manager.refresh_streaming(origin_position)
	await _wait_frames(8)
	var terrain_chunk = manager.get_chunk(Vector3i(0, 0, 0))
	if terrain_chunk == null:
		_fail("Terrain chunk (0, 0, 0) was unavailable for mesh validation")
		return
	if terrain_chunk.mesh_instance == null or terrain_chunk.mesh_instance.mesh == null:
		_fail("Terrain chunk render mesh is missing")
	elif terrain_chunk.mesh_instance.mesh.get_surface_count() == 0:
		_fail("Terrain chunk render mesh has no surfaces")
	if terrain_chunk.collision_shape == null or terrain_chunk.collision_shape.shape == null:
		_fail("Terrain chunk collision shape is missing")
	if failures.is_empty():
		print("STEP_3_GATE_PASS")


func _test_player_controller(manager, player: CharacterBody3D, camera: Camera3D) -> void:
	player.global_position = Vector3(0.5, 18.0, 0.5)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	manager.refresh_streaming(player.global_position)
	player.set_physics_process(true)
	player.set_process(true)

	var grounded := await _wait_until_grounded(player, 240)
	if not grounded:
		_fail("Player did not reach a grounded state within 240 physics frames")
		return

	Input.action_release("jump")
	await physics_frame
	var jump_start_y := player.global_position.y
	Input.action_press("jump", 1.0)
	await physics_frame
	Input.action_release("jump")
	await _wait_physics_frames(3)
	if player.global_position.y <= jump_start_y + 0.05:
		_fail("Jump action did not raise the player above the grounded position")
		return

	grounded = await _wait_until_grounded(player, 240)
	if not grounded:
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
		_fail("Player movement action produced only %.3f units of horizontal travel" % horizontal_distance)
		return

	var yaw_before := player.rotation.y
	var pitch_before := camera.rotation.x
	player.apply_look_delta(Vector2(0.2, -0.1))
	if is_equal_approx(player.rotation.y, yaw_before):
		_fail("Abstract look input did not change player yaw")
	if is_equal_approx(camera.rotation.x, pitch_before):
		_fail("Abstract look input did not change camera pitch")

	if failures.is_empty():
		print("STEP_4_GATE_PASS")


func _wait_until_grounded(player: CharacterBody3D, frame_limit: int) -> bool:
	for _frame in range(frame_limit):
		await physics_frame
		if player.is_on_floor():
			return true
	return false


func _test_atmosphere(environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if environment.environment.background_mode != Environment.BG_SKY:
		_fail("World environment is not using the configured sky background")
	if environment.environment.sky == null:
		_fail("World environment sky resource is missing")
	if not sun.shadow_enabled:
		_fail("Directional light shadows are disabled")
	if failures.is_empty():
		print("STEP_5_GATE_PASS")


func _capture_screenshot(manager, player: CharacterBody3D, camera: Camera3D) -> void:
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(0.5, 18.0, 24.0)
	player.rotation = Vector3.ZERO
	camera.rotation_degrees.x = -22.0
	manager.refresh_streaming(player.global_position)
	await _wait_frames(20)
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
	if failures.is_empty():
		print("TEKNIK_ACCEPTANCE_GATE_PASS")
		quit(0)
	else:
		print("TEKNIK_ACCEPTANCE_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
