extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-placement-step3.png"
const BLOCK_AIR := 0
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const FIRST_BASE := Vector3i(0, 20, 0)
const SECOND_BASE := Vector3i(4, 20, 0)
const EMPTY_BASE := Vector3i(8, 20, 0)

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
	_validate_input_replacement()

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
	if not player.has_method("get_inventory") or not player.has_method("select_inventory_slot"):
		_fail("Player does not expose inventory placement selection")
		_finish()
		return
	if main.get_node_or_null("PaletteUI") != null:
		_fail("Legacy hardcoded palette UI still exists in the runtime scene")

	var inventory = player.get_inventory()
	if inventory == null:
		_fail("Player inventory is null")
		_finish()
		return
	if inventory.get_slot_count() != 24 or inventory.get_max_stack_size() != 64:
		_fail("Player inventory does not use the accepted 24-slot/64-stack contract")

	player.set_physics_process(false)
	player.set_process(true)
	player.global_position = Vector3(12.5, 20.0, 8.5)
	manager.refresh_streaming(Vector3(4.5, 20.5, 0.5))
	manager.set_process(false)
	await _wait_frames(12)

	for base_coord in [FIRST_BASE, SECOND_BASE, EMPTY_BASE]:
		_prepare_base(manager, base_coord)
	await _wait_frames(8)
	if not failures.is_empty():
		_finish()
		return

	if not inventory.add_item(BLOCK_STONE, 2):
		_fail("Failed to seed two stone items in slot 0")
	if not inventory.add_item(BLOCK_DIRT, 1):
		_fail("Failed to seed one dirt item in slot 1")
	if not player.select_inventory_slot(0):
		_fail("Failed to select inventory slot 0")
	if player.get_selected_inventory_slot() != 0:
		_fail("Selected inventory slot was not 0")
	if player.select_inventory_slot(-1) or player.select_inventory_slot(24):
		_fail("Out-of-range inventory slot selection was accepted")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 2, "seeded stone slot")
	_assert_slot(inventory.get_slot(1), BLOCK_DIRT, 1, "seeded dirt slot")

	var first_coord := FIRST_BASE + Vector3i.UP
	await _aim_at_block(player, camera, FIRST_BASE)
	await _press_place_action()
	if manager.get_block_world(first_coord) != BLOCK_STONE:
		_fail("First inventory placement did not write stone at %s" % first_coord)
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 1, "stone slot after first placement")
	_assert_slot(inventory.get_slot(1), BLOCK_DIRT, 1, "dirt slot after first placement")
	await _assert_collision_ray(player, first_coord, "first inventory placement")

	var second_coord := SECOND_BASE + Vector3i.UP
	await _aim_at_block(player, camera, SECOND_BASE)
	await _press_place_action()
	if manager.get_block_world(second_coord) != BLOCK_STONE:
		_fail("Second inventory placement did not write stone at %s" % second_coord)
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "stone slot cleared at zero")
	_assert_slot(inventory.get_slot(1), BLOCK_DIRT, 1, "dirt slot after stone depletion")
	await _assert_collision_ray(player, second_coord, "second inventory placement")

	var empty_coord := EMPTY_BASE + Vector3i.UP
	var empty_chunk_coord = manager.world_to_chunk_coord(Vector3(empty_coord) + Vector3.ONE * 0.5)
	var empty_chunk = manager.get_chunk(empty_chunk_coord)
	if empty_chunk == null:
		_fail("Empty-slot placement chunk is not loaded")
		_finish()
		return
	var world_before_empty_attempt: int = manager.get_block_world(empty_coord)
	var inventory_before_empty_attempt: Array[Dictionary] = inventory.get_slots()
	var mesh_before_empty_attempt = empty_chunk.mesh_instance.mesh
	var collision_before_empty_attempt = empty_chunk.collision_shape.shape

	await _aim_at_block(player, camera, EMPTY_BASE)
	await _press_place_action()

	if world_before_empty_attempt != BLOCK_AIR or manager.get_block_world(empty_coord) != BLOCK_AIR:
		_fail("Selected-empty-slot placement changed the world at %s" % empty_coord)
	if inventory.get_slots() != inventory_before_empty_attempt:
		_fail("Selected-empty-slot placement mutated inventory")
	if empty_chunk.mesh_instance.mesh != mesh_before_empty_attempt:
		_fail("Selected-empty-slot placement rebuilt the chunk mesh")
	if empty_chunk.collision_shape.shape != collision_before_empty_attempt:
		_fail("Selected-empty-slot placement rebuilt chunk collision")
	var target_after_empty_attempt: Dictionary = player.get_block_target()
	if target_after_empty_attempt.is_empty() or target_after_empty_attempt.get("block_coord", Vector3i.ZERO) != EMPTY_BASE:
		_fail("Selected-empty-slot placement did not preserve the current target")
	if player.place_block_at(empty_coord):
		_fail("Direct selected-empty-slot placement returned true")
	if manager.get_block_world(empty_coord) != BLOCK_AIR:
		_fail("Direct selected-empty-slot placement changed the world")

	if not player.select_inventory_slot(1):
		_fail("Failed to select inventory slot 1 for retry")
	if player.get_selected_inventory_slot() != 1:
		_fail("Selected inventory slot was not 1 for retry")
	await _aim_at_block(player, camera, EMPTY_BASE)
	await _press_place_action()
	if manager.get_block_world(empty_coord) != BLOCK_DIRT:
		_fail("Retry from selected dirt slot did not place dirt")
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "stone slot after dirt retry")
	_assert_slot(inventory.get_slot(1), BLOCK_AIR, 0, "dirt slot cleared at zero")
	await _assert_collision_ray(player, empty_coord, "dirt retry placement")

	camera.global_position = Vector3(12.0, 25.0, 12.0)
	camera.look_at(Vector3(4.5, 20.5, 0.5), Vector3.UP)
	await _wait_frames(12)
	await _capture_screenshot()

	if failures.is_empty():
		print("INVENTORY_PLACEMENT_STEP_3_GATE_PASS")
		print("PLACEMENT_CONSUMPTION=slot 0 stone 2->1->air/0")
		print("PLACEMENT_EMPTY_SLOT=BLOCKED; world, inventory, mesh, collision, and target unchanged")
		print("PLACEMENT_SELECTED_RETRY=slot 1 dirt 1->air/0")
		print("LEGACY_PALETTE=retired; no actions and no PaletteUI")
	_finish()


func _validate_input_replacement() -> void:
	if not InputMap.has_action("place_block"):
		_fail("place_block InputMap action is missing")
	elif InputMap.action_get_events("place_block").is_empty():
		_fail("place_block InputMap action has no desktop test binding")
	for legacy_action in ["select_block_1", "select_block_2", "select_block_3", "select_block_4"]:
		if InputMap.has_action(legacy_action):
			_fail("Legacy hardcoded palette action still exists: %s" % legacy_action)


func _prepare_base(manager, base_coord: Vector3i) -> void:
	var placement_coord := base_coord + Vector3i.UP
	if manager.get_block_world(placement_coord) != BLOCK_AIR:
		manager.mine_block_world(placement_coord)
	if manager.get_block_world(base_coord) != BLOCK_AIR:
		manager.mine_block_world(base_coord)
	if not manager.place_block_world(base_coord, BLOCK_STONE):
		_fail("Failed to create controlled placement base at %s" % base_coord)


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> void:
	var target_center := Vector3(block_coord) + Vector3.ONE * 0.5
	camera.global_position = target_center + Vector3(0.0, 3.5, 0.0)
	camera.look_at(target_center, Vector3.FORWARD)
	await _wait_frames(16)
	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera did not acquire controlled placement base %s" % block_coord)
	elif target.get("block_coord", Vector3i.ZERO) != block_coord:
		_fail("Placement target mismatch: expected %s, got %s" % [block_coord, target.get("block_coord")])
	elif target.get("hit_face", Vector3i.ZERO) != Vector3i.UP:
		_fail("Placement hit face was not up for %s" % block_coord)


func _press_place_action() -> void:
	Input.action_press("place_block", 1.0)
	await process_frame
	Input.action_release("place_block")
	await _wait_frames(8)


func _assert_slot(slot: Dictionary, expected_block_id: int, expected_count: int, context: String) -> void:
	if slot.is_empty():
		_fail("%s returned an empty slot dictionary" % context)
		return
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != expected_block_id or actual_count != expected_count:
		_fail(
			"%s expected block/count %d/%d, got %d/%d"
			% [context, expected_block_id, expected_count, actual_block_id, actual_count]
		)


func _assert_collision_ray(player, coord: Vector3i, context: String) -> void:
	await _wait_frames(4)
	var world_3d: World3D = player.get_world_3d()
	if world_3d == null:
		_fail("World3D unavailable for %s" % context)
		return
	var center := Vector3(coord) + Vector3.ONE * 0.5
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3(0.0, 2.0, 0.0),
		center - Vector3(0.0, 2.0, 0.0)
	)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_fail("Placed block had no collision ray hit for %s" % context)
		return
	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var inside_sample := hit_position - hit_normal * 0.001
	var hit_coord := Vector3i(
		floori(inside_sample.x),
		floori(inside_sample.y),
		floori(inside_sample.z)
	)
	if hit_coord != coord:
		_fail("Collision ray for %s hit %s instead of %s" % [context, hit_coord, coord])


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Inventory placement screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Inventory placement screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Inventory placement screenshot save failed with error %d" % save_error)
		return
	print("INVENTORY_PLACEMENT_STEP_3_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_PLACEMENT_STEP_3_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
