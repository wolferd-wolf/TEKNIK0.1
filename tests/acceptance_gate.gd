extends "res://tests/acceptance_gate_core.gd"

const BLOCK_STONE := 3
const ASYNC_WORLD_WAIT_TIMEOUT_MSEC := 30000


func _wait_for_world_ready(manager, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < ASYNC_WORLD_WAIT_TIMEOUT_MSEC:
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


func _test_terrain_and_features(manager) -> void:
	var heights: Dictionary = {}
	for sample in [Vector2i(0, 0), Vector2i(28, 7), Vector2i(-19, 31), Vector2i(47, -23), Vector2i(-64, -64)]:
		var height: int = manager.get_playable_world_height(sample.x, sample.y)
		heights[height] = true
		if height < 3 or height > 27:
			_fail("Terrain height %d was outside playable-world bounds at %s" % [height, sample])
		var surface_block: int = manager.get_block_world(Vector3i(sample.x, height, sample.y))
		if surface_block != BLOCK_GRASS and surface_block != BLOCK_SAND and surface_block != BLOCK_STONE:
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