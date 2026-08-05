extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
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
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(28)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Placement integration scene nodes are missing")
		_finish()
		return
	if not player.has_method("get_inventory") or not player.has_method("select_inventory_slot"):
		_fail("Player does not expose inventory placement controls")
		_finish()
		return

	var inventory = player.get_inventory()
	if inventory == null or inventory.get_slot_count() != 36:
		_fail("Runtime inventory does not use 36 slots")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	player.global_position = Vector3(12.5, 20.0, 8.5)
	manager.refresh_streaming(Vector3(4.5, 20.5, 0.5))
	manager.set_process(false)
	await _wait_frames(14)

	for base_coord in [FIRST_BASE, SECOND_BASE, EMPTY_BASE]:
		_prepare_base(manager, base_coord)
	await _wait_frames(10)
	if not failures.is_empty():
		_finish()
		return

	if not inventory.add_item(BLOCK_STONE, 2):
		_fail("Could not seed two stone items")
	if not player.select_inventory_slot(0):
		_fail("Could not select hotbar slot 0")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 2, "seeded stone hotbar")

	var first_coord := FIRST_BASE + Vector3i.UP
	await _aim_at_block(player, camera, FIRST_BASE)
	await _press_place_action()
	if manager.get_block_world(first_coord) != BLOCK_STONE:
		_fail("First inventory placement did not place stone")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 1, "stone after first placement")

	var second_coord := SECOND_BASE + Vector3i.UP
	await _aim_at_block(player, camera, SECOND_BASE)
	await _press_place_action()
	if manager.get_block_world(second_coord) != BLOCK_STONE:
		_fail("Second inventory placement did not place stone")
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "depleted stone hotbar")

	var empty_coord := EMPTY_BASE + Vector3i.UP
	var world_before_empty: int = manager.get_block_world(empty_coord)
	var inventory_before_empty: Array[Dictionary] = inventory.get_slots()
	await _aim_at_block(player, camera, EMPTY_BASE)
	await _press_place_action()
	if world_before_empty != BLOCK_AIR or manager.get_block_world(empty_coord) != BLOCK_AIR:
		_fail("Selected-empty-slot placement changed the world")
	if inventory.get_slots() != inventory_before_empty:
		_fail("Selected-empty-slot placement mutated inventory")

	if not inventory.add_item(BLOCK_DIRT, 1):
		_fail("Could not seed one dirt item for retry")
	_assert_slot(inventory.get_slot(0), BLOCK_DIRT, 1, "seeded dirt retry")
	await _aim_at_block(player, camera, EMPTY_BASE)
	await _press_place_action()
	if manager.get_block_world(empty_coord) != BLOCK_DIRT:
		_fail("Retry did not place dirt from selected hotbar slot")
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "depleted dirt retry")

	if failures.is_empty():
		print("INVENTORY_PLACEMENT_STEP_3_GATE_PASS")
		print("PLACEMENT_CONSUMPTION=STONE 2->1->0 in hotbar slot 0")
		print("PLACEMENT_EMPTY_SLOT=blocked with world and all 36 slots unchanged")
		print("PLACEMENT_RETRY=DIRT 1->0 from hotbar slot 0")
	_finish()


func _prepare_base(manager, base_coord: Vector3i) -> void:
	var placement_coord := base_coord + Vector3i.UP
	if manager.get_block_world(placement_coord) != BLOCK_AIR:
		manager.mine_block_world(placement_coord)
	if manager.get_block_world(base_coord) != BLOCK_AIR:
		manager.mine_block_world(base_coord)
	if not manager.place_block_world(base_coord, BLOCK_STONE):
		_fail("Could not create placement base at %s" % base_coord)


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> void:
	var target_center := Vector3(block_coord) + Vector3.ONE * 0.5
	camera.global_position = target_center + Vector3(0.0, 3.5, 0.0)
	camera.look_at(target_center, Vector3.FORWARD)
	await _wait_frames(16)
	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera did not acquire placement base %s" % block_coord)
	elif target.get("block_coord", Vector3i.ZERO) != block_coord:
		_fail("Placement target mismatch: expected %s, got %s" % [block_coord, target.get("block_coord")])
	elif target.get("hit_face", Vector3i.ZERO) != Vector3i.UP:
		_fail("Placement hit face was not up for %s" % block_coord)


func _press_place_action() -> void:
	Input.action_press("place_block", 1.0)
	await process_frame
	Input.action_release("place_block")
	await _wait_frames(9)


func _assert_slot(slot: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail("%s expected %d/%d, got %d/%d" % [context, block_id, count, actual_block_id, actual_count])


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_PLACEMENT_STEP_3_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
