extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/placement-step3.png"
const BLOCK_AIR := 0

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _run_gate() -> void:
	if not InputMap.has_action("place_block"):
		_fail("place_block InputMap action is missing")
	elif InputMap.action_get_events("place_block").is_empty():
		_fail("place_block InputMap action has no desktop test binding")

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(24)

	var manager := main.get_node_or_null("ChunkManager")
	var player := main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null:
		_fail("ChunkManager node is missing")
	if player == null:
		_fail("Player node is missing")
	if camera == null:
		_fail("Player camera is missing")
	if not failures.is_empty():
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	var inspection_position := Vector3(0.5, 20.0, 0.5)
	manager.refresh_streaming(inspection_position)
	await _wait_frames(12)

	var surface_y := _find_surface_y(manager, 0, 0)
	if surface_y == -2147483648:
		_fail("No solid surface block was found for placement")
		_finish()
		return

	var target_coord := Vector3i(0, surface_y, 0)
	var target_center := Vector3(0.5, surface_y + 0.5, 0.5)
	player.global_position = Vector3(4.5, surface_y + 3.0, 0.5)
	player.rotation = Vector3.ZERO
	camera.global_position = target_center + Vector3(0.0, 3.5, 0.0)
	camera.look_at(target_center, Vector3.FORWARD)
	await _wait_frames(20)

	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera did not acquire a block before placement")
		_finish()
		return

	var acquired_coord: Vector3i = target.get("block_coord", Vector3i.ZERO)
	var hit_face: Vector3i = target.get("hit_face", Vector3i.ZERO)
	if acquired_coord != target_coord:
		_fail("Placement target mismatch: expected %s, got %s" % [target_coord, acquired_coord])
	var placement_coord := acquired_coord + hit_face
	if manager.get_block_world(placement_coord) != BLOCK_AIR:
		_fail("Placement candidate was not air: %s" % placement_coord)
	if not player.can_place_block_at(placement_coord):
		_fail("Valid placement candidate was rejected before input: %s" % placement_coord)

	var placement_chunk_coord = manager.world_to_chunk_coord(Vector3(placement_coord) + Vector3(0.5, 0.5, 0.5))
	var placement_chunk = manager.get_chunk(placement_chunk_coord)
	if placement_chunk == null:
		_fail("Placement chunk was not loaded")
		_finish()
		return
	var mesh_before = placement_chunk.mesh_instance.mesh
	var collision_before = placement_chunk.collision_shape.shape

	Input.action_press("place_block", 1.0)
	await process_frame
	Input.action_release("place_block")
	await _wait_frames(12)

	var placed_block_id: int = manager.get_block_world(placement_coord)
	if placed_block_id != player.active_placement_block_id:
		_fail(
			"place_block action wrote block id %d instead of active id %d"
			% [placed_block_id, player.active_placement_block_id]
		)
	if placement_chunk.mesh_instance.mesh == null:
		_fail("Affected chunk mesh became null after placement")
	elif placement_chunk.mesh_instance.mesh == mesh_before:
		_fail("Affected chunk mesh resource was not rebuilt after placement")
	if placement_chunk.collision_shape.shape == null:
		_fail("Affected chunk collision became null after placement")
	elif placement_chunk.collision_shape.shape == collision_before:
		_fail("Affected chunk collision resource was not rebuilt after placement")

	await _validate_placed_collision(player, placement_coord)

	if player.place_block_at(placement_coord):
		_fail("Occupied placement coordinate accepted a second block")
	if manager.get_block_world(placement_coord) != placed_block_id:
		_fail("Occupied-placement rejection changed the existing block")

	var overlap_coord := Vector3i(
		floori(player.global_position.x),
		floori(player.global_position.y + 0.5),
		floori(player.global_position.z)
	)
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		_fail("Player-overlap probe coordinate was unexpectedly solid: %s" % overlap_coord)
	elif player.can_place_block_at(overlap_coord):
		_fail("Capsule-overlapping block was reported as placeable: %s" % overlap_coord)
	elif player.place_block_at(overlap_coord):
		_fail("Capsule-overlapping block placement returned true: %s" % overlap_coord)
	elif manager.get_block_world(overlap_coord) != BLOCK_AIR:
		_fail("Capsule-overlap rejection still modified the world")

	var unloaded_coord := Vector3i(2048, 2048, 2048)
	if manager.place_block_world(unloaded_coord, player.active_placement_block_id):
		_fail("Placement into an unloaded chunk returned true")

	camera.global_position = Vector3(
		placement_coord.x + 4.0,
		placement_coord.y + 3.0,
		placement_coord.z + 4.0
	)
	camera.look_at(
		Vector3(placement_coord) + Vector3(0.5, 0.5, 0.5),
		Vector3.UP
	)
	await _wait_frames(12)
	await _capture_screenshot()

	if failures.is_empty():
		print("PLACEMENT_STEP_3_GATE_PASS")
		print("PLACED_BLOCK_COORD=%s" % placement_coord)
		print("PLACED_BLOCK_ID=%d" % placed_block_id)
		print("PLAYER_OVERLAP_REJECTED=%s" % overlap_coord)
	_finish()


func _validate_placed_collision(player, placement_coord: Vector3i) -> void:
	var world_3d: World3D = player.get_world_3d()
	if world_3d == null:
		_fail("World3D was unavailable for placement collision ray")
		return

	var center := Vector3(placement_coord) + Vector3(0.5, 0.5, 0.5)
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3(0.0, 2.0, 0.0),
		center - Vector3(0.0, 2.0, 0.0)
	)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_fail("Placed block had no collision ray hit")
		return

	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var inside_sample := hit_position - hit_normal * 0.001
	var hit_coord := Vector3i(
		floori(inside_sample.x),
		floori(inside_sample.y),
		floori(inside_sample.z)
	)
	if hit_coord != placement_coord:
		_fail("Placed collision ray hit %s instead of %s" % [hit_coord, placement_coord])


func _find_surface_y(manager, world_x: int, world_z: int) -> int:
	for world_y in range(31, -17, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != BLOCK_AIR:
			return world_y
	return -2147483648


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Placement screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Placement screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Placement screenshot save failed with error %d" % save_error)
		return
	print("PLACEMENT_STEP_3_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("PLACEMENT_STEP_3_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
