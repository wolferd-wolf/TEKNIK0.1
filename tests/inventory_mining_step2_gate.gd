extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_SAND := 4
const DIRT_TARGET := Vector3i(0, 20, 0)
const FULL_TARGET := Vector3i(4, 20, 0)
const WAIT_TIMEOUT_MSEC := 30000
const AIM_TIMEOUT_MSEC := 3000

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_for_world_ready(manager, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await process_frame
		if (
			manager.chunk_count() >= manager.expected_chunk_count()
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
	_fail("Playable world did not become ready during %s" % context)
	return false


func _wait_for_remesh_idle(manager, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await process_frame
		if manager.is_remesh_idle():
			return true
	_fail("Playable-world remesh did not become idle during %s" % context)
	return false


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Mining integration scene nodes are missing")
		_finish()
		return
	var inventory = player.get_inventory()
	if inventory == null or inventory.get_slot_count() != 36:
		_fail("Runtime inventory does not use 36 slots")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	manager.refresh_streaming(Vector3(2.5, 20.5, 0.5))
	if not await _wait_for_world_ready(manager, "inventory mining startup"):
		_finish()
		return
	if not manager.set_block_world(DIRT_TARGET, BLOCK_DIRT):
		_fail("Could not create dirt mining target")
	if not manager.set_block_world(FULL_TARGET, BLOCK_GRASS):
		_fail("Could not create full-inventory mining target")
	if not await _wait_for_remesh_idle(manager, "inventory mining fixture rebuild"):
		_finish()
		return

	if not inventory.add_item(BLOCK_DIRT, 63):
		_fail("Could not seed 63 dirt")
	if not await _aim_at_block(player, camera, DIRT_TARGET):
		_finish()
		return
	await _press_mine_action(manager, "dirt mining")
	if manager.get_block_world(DIRT_TARGET) != BLOCK_AIR:
		_fail("Mining did not remove dirt target")
	_assert_slot(inventory.get_slot(0), BLOCK_DIRT, 64, "mined dirt stack")

	if not inventory.add_item(BLOCK_SAND, 35 * 64):
		_fail("Could not fill remaining 35 inventory slots")
	if not inventory.is_full():
		_fail("36-slot runtime inventory did not report full")
	var full_snapshot: Array[Dictionary] = inventory.get_slots()
	if not await _aim_at_block(player, camera, FULL_TARGET):
		_finish()
		return
	await _press_mine_action(manager, "full-inventory blocked mining")
	if manager.get_block_world(FULL_TARGET) != BLOCK_GRASS:
		_fail("Full inventory did not block mining")
	if inventory.get_slots() != full_snapshot:
		_fail("Blocked full-inventory mining mutated inventory")

	if not inventory.remove_from_slot(35, 64):
		_fail("Could not free final storage slot")
	if not await _aim_at_block(player, camera, FULL_TARGET):
		_finish()
		return
	await _press_mine_action(manager, "grass mining retry")
	if manager.get_block_world(FULL_TARGET) != BLOCK_AIR:
		_fail("Mining did not resume after freeing storage")
	_assert_slot(inventory.get_slot(35), BLOCK_GRASS, 1, "retried grass pickup")

	if failures.is_empty():
		print("INVENTORY_MINING_STEP_2_GATE_PASS")
		print("MINING_PICKUP=DIRT 63+1 -> 64")
		print("MINING_FULL_FALLBACK=blocked across all 36 slots")
		print("MINING_RETRY=freed slot 35 -> GRASS x1")
	_finish()


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> bool:
	player.global_position = Vector3(block_coord.x + 0.5, block_coord.y + 3.0, block_coord.z + 0.5)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(Vector3(block_coord) + Vector3.ONE * 0.5, Vector3.FORWARD)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < AIM_TIMEOUT_MSEC:
		await process_frame
		var target: Dictionary = player.get_block_target()
		if target.is_empty():
			continue
		if target.get("block_coord", Vector3i.ZERO) == block_coord:
			return true
	_fail("Camera did not acquire target %s" % block_coord)
	return false


func _press_mine_action(manager, context: String) -> void:
	Input.action_press("mine_block", 1.0)
	await process_frame
	Input.action_release("mine_block")
	await _wait_for_remesh_idle(manager, context)


func _assert_slot(slot: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail("%s expected %d/%d, got %d/%d" % [context, block_id, count, actual_block_id, actual_count])


func _finish() -> void:
	Input.action_release("mine_block")
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_MINING_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)