extends SceneTree

const WORLD_PORT_SCRIPT := preload("res://scripts/world/playable_world_port.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SOURCE_PATH := "res://scripts/world/playable_world_port.gd"
const FRAME_LIMIT := 600
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

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	if int(diagnostics.get("atomic_swap_failures", 0)) != 0:
		_fail("Standalone adapter reported an atomic swap failure")

	if failures.is_empty():
		print("PLAYABLE_WORLD_STANDALONE_GATE_PASS")
		print("STANDALONE_INHERITANCE=Node3D only; no legacy fallback")
		print("STANDALONE_STARTUP_CHUNKS=%d" % manager.chunk_count())
		print("STANDALONE_PLACE_MINE=%s -> stone -> air" % edit_coord)
		print("STANDALONE_MAIN_SCENE_BINDING=player uses ChunkManager node contract")

	_finish()


func _finish() -> void:
	quit(1 if not failures.is_empty() else 0)
