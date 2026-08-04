extends SceneTree

const WORLD_PORT_SCRIPT := preload("res://scripts/world/playable_world_port.gd")
const FRAME_LIMIT := 1200

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_for_idle(manager, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if (
			manager.chunk_count() == manager.expected_chunk_count()
			and manager.is_remesh_idle()
		):
			return true
	_fail("Playable-world port did not become idle during %s" % context)
	return false


func _run_gate() -> void:
	var test_root := Node3D.new()
	test_root.name = "PlayableWorldMiningPortGate"
	root.add_child(test_root)

	var target := Node3D.new()
	target.name = "Target"
	target.position = Vector3(0.5, 20.0, 0.5)
	test_root.add_child(target)

	var manager = WORLD_PORT_SCRIPT.new()
	manager.name = "ChunkManager"
	manager.force_playable_world_port = true
	manager.streaming_target_path = NodePath("../Target")
	test_root.add_child(manager)

	await process_frame
	if not manager.is_playable_world_port_active():
		_fail("Forced playable-world port did not activate")
		_finish()
		return

	if not await _wait_for_idle(manager, "initial world generation"):
		_finish()
		return

	if manager.chunk_count() != 49:
		_fail("Imported world must load 49 visual chunks, got %d" % manager.chunk_count())

	var height_samples: Dictionary = {}
	for sample in [Vector2i(2, 2), Vector2i(28, 7), Vector2i(-19, 31), Vector2i(47, -23)]:
		height_samples[manager._legacy_terrain_height(sample.x, sample.y)] = true
	if height_samples.size() < 2:
		_fail("Imported deterministic terrain did not produce varied heights")

	var surface_y: int = manager._legacy_terrain_height(2, 2)
	var mine_coord := Vector3i(2, surface_y, 2)
	var original_block: int = manager.get_block_world(mine_coord)
	if original_block == 0:
		_fail("Imported terrain surface was unexpectedly air at %s" % mine_coord)
		_finish()
		return

	var legacy_coord := Vector2i(0, 0)
	var old_entry: Dictionary = manager._legacy_loaded_chunks.get(legacy_coord, {})
	var old_root := old_entry.get("root") as Node3D
	if not is_instance_valid(old_root):
		_fail("Imported origin chunk root was missing before mining")
		_finish()
		return
	if not is_instance_valid(old_entry.get("collision")):
		_fail("Imported origin collision was not ready before mining")
		_finish()
		return

	if not manager.mine_block_world(mine_coord):
		_fail("Imported mining system rejected a valid surface block")
		_finish()
		return
	if manager.get_block_world(mine_coord) != 0:
		_fail("Mined block data did not become air immediately")

	if not await _wait_for_idle(manager, "atomic mining rebuild"):
		_finish()
		return

	var new_entry: Dictionary = manager._legacy_loaded_chunks.get(legacy_coord, {})
	var new_root := new_entry.get("root") as Node3D
	if not is_instance_valid(new_root):
		_fail("Imported origin chunk root was missing after mining")
	elif new_root == old_root:
		_fail("Mining did not atomically replace the affected chunk")
	if not is_instance_valid(new_entry.get("collision")):
		_fail("Mining replacement did not preserve nearby collision")

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	if int(diagnostics.get("atomic_swaps", 0)) < 1:
		_fail("Mining diagnostics did not record an atomic chunk swap")
	if int(diagnostics.get("atomic_swap_failures", 0)) != 0:
		_fail("Mining atomic replacement reported a failure")

	if failures.is_empty():
		print("PLAYABLE_WORLD_MINING_PORT_GATE_PASS")
		print("PLAYABLE_WORLD_CHUNKS=%d" % manager.chunk_count())
		print("PLAYABLE_WORLD_MINED_BLOCK=%d" % original_block)
		print("PLAYABLE_WORLD_ATOMIC_SWAPS=%d" % int(diagnostics.get("atomic_swaps", 0)))

	_finish()


func _finish() -> void:
	quit(1 if not failures.is_empty() else 0)
