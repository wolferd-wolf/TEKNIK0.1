extends "res://tests/multi_noise_step1_gate.gd"

# The consolidated threaded streamer can temporarily retain completed chunks
# from the previous center while a distant fixture becomes ready. The modern
# acceptance contract therefore requires at least the expected active set,
# collision-ring readiness, and an idle remesh queue instead of exact equality.
func _wait_for_world(manager: Variant, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		if (
			manager.chunk_count() >= manager.expected_chunk_count()
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
		await process_frame
	_fail("Timed out waiting for %s" % label)
	return false


# Chunk roots can be swapped during a process frame while PhysicsServer3D only
# exposes the new collision state after the next physics synchronization. Slow
# hosted runners make that ordering visible. Keep polling the real shipping
# player's raycast instead of replacing the assertion with a direct world-data
# lookup: the gate still proves that a generated tree can actually be targeted
# through gameplay collision.
func _wait_for_block_target(player: Variant, expected: Vector3i, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await physics_frame
		await process_frame
		var hit: Dictionary = player.get_block_target()
		if not hit.is_empty() and hit.get("block_coord", Vector3i.ZERO) == expected:
			return true
	_fail("Timed out waiting for %s target at %s" % [label, expected])
	return false


# The historical parent integration predates the consolidated public player
# API and still calls removed private helpers (`_get_block_hit`,
# `_try_mine_targeted_block`) plus an obsolete inventory crafting interface.
# Keep its terrain/tree/water fixture discovery, but run the shipping-scene
# transaction through the public APIs that the game actually exposes today.
func _run_shipping_scene_transaction(report: Dictionary) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("The shipping main scene failed to load")
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _wait_frames(6)

	var manager: Variant = main.get_node_or_null("ChunkManager")
	var player: Variant = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	var localized_water: Variant = main.get_node_or_null("ChunkManager/LocalizedWaterBodies")
	var runtime: Variant = main.get_node_or_null("ChunkManager/PlayableWorldRuntime")
	if manager == null or player == null or camera == null or localized_water == null or runtime == null:
		_fail("The shipping scene is missing a Step 5 integration node")
		return
	if not bool(manager.is_playable_world_port_active()):
		_fail("Step 5 did not run on the consolidated playable world")
		return
	if (
		not player.has_method("get_block_target")
		or not player.has_method("mine_targeted_block")
		or not player.has_method("get_inventory")
	):
		_fail("The shipping player is missing its public targeting/inventory API")
		return

	player.set_physics_process(false)
	player.set_process(true)
	if not await _wait_for_world(manager, "shipping startup spawn"):
		return
	await _wait_frames(2)
	if not bool(localized_water.get("_active")):
		_fail("Localized water did not activate in the shipping scene")
	if is_instance_valid(runtime.get_node_or_null("Water")):
		_fail("The retired global water plane remained active")

	var water_values: Array = report.get("water_fixture", [])
	var dry_values: Array = report.get("dry_fixture", [])
	var tree_values: Array = report.get("tree_fixture", [])
	var access_values: Array = report.get("tree_access", [])
	var placement_values: Array = report.get("placement_fixture", [])
	if water_values.size() != 2 or dry_values.size() != 2 or tree_values.size() != 2 or access_values.size() != 2 or placement_values.size() != 2:
		_fail("The static Step 5 fixtures were incomplete")
		return

	var water_point := Vector2i(int(water_values[0]), int(water_values[1]))
	player.global_position = Vector3(
		water_point.x + 0.5,
		data.terrain_height(water_point.x, water_point.y) + 3.0,
		water_point.y + 0.5
	)
	manager.refresh_streaming(player.global_position)
	if not await _wait_for_world(manager, "localized water"):
		return
	await _wait_frames(12)
	var water_coord := Vector2i(
		floori(float(water_point.x) / float(CHUNK_SIZE)),
		floori(float(water_point.y) / float(CHUNK_SIZE))
	)
	var water_chunks: Dictionary = localized_water.get("_chunks")
	var water_instance := water_chunks.get(water_coord) as MeshInstance3D
	if not is_instance_valid(water_instance) or water_instance.mesh == null:
		_fail("The shipping water system did not render the real water-body fixture")

	var tree_origin := Vector2i(int(tree_values[0]), int(tree_values[1]))
	var access := Vector2i(int(access_values[0]), int(access_values[1]))
	var tree_surface: int = manager.get_playable_world_height(tree_origin.x, tree_origin.y)
	var base_log := Vector3i(tree_origin.x, tree_surface + 1, tree_origin.y)
	var eye := Vector3(
		tree_origin.x + 0.5 + float(access.x) * 3.0,
		float(tree_surface) + 1.6,
		tree_origin.y + 0.5 + float(access.y) * 3.0
	)
	player.global_position = eye - camera.position
	manager.refresh_streaming(player.global_position)
	if not await _wait_for_world(manager, "generated tree"):
		return
	if manager.get_block_world(base_log) != BLOCK_LOG:
		_fail("Generated tree fixture no longer contains its base log")
		return
	camera.look_at(
		Vector3(tree_origin.x + 0.5, tree_surface + 1.5, tree_origin.y + 0.5),
		Vector3.UP
	)
	if not await _wait_for_block_target(player, base_log, "generated tree base log"):
		return
	var inventory: Variant = player.get_inventory()
	if inventory == null:
		_fail("Player inventory is missing from the shipping transaction")
		return
	var logs_before: int = inventory.get_item_count(BLOCK_LOG)
	if not bool(player.mine_targeted_block()):
		_fail("Generated tree base log was not mineable")
		return
	if inventory.get_item_count(BLOCK_LOG) != logs_before + 1:
		_fail("Mining the generated tree did not add exactly one log")
	if not await _wait_for_remesh(manager):
		return
	if manager.get_block_world(base_log) != BLOCK_AIR:
		_fail("Mined generated tree base log remained solid")

	var placement_point := Vector2i(int(placement_values[0]), int(placement_values[1]))
	var placement_surface: int = manager.get_playable_world_height(placement_point.x, placement_point.y)
	var place_cell := Vector3i(placement_point.x, placement_surface + 1, placement_point.y)
	if manager.get_block_world(place_cell) != BLOCK_AIR:
		_fail("Placement fixture is not empty in the shipping runtime")
		return
	if not bool(manager.place_block_world(place_cell, BLOCK_DIRT)):
		_fail("Placement failed on the generated-world fixture")
		return
	if not await _wait_for_remesh(manager):
		return
	if manager.get_block_world(place_cell) != BLOCK_DIRT:
		_fail("Placed dirt did not persist through the world runtime")

	var dry_point := Vector2i(int(dry_values[0]), int(dry_values[1]))
	if not LOCALIZED_WATER.is_water_column(runtime.data, water_point.x, water_point.y):
		_fail("Runtime data lost the real water-body classification")
	if LOCALIZED_WATER.is_water_column(runtime.data, dry_point.x, dry_point.y):
		_fail("Runtime data classified dry terrain as water")

	report["runtime_water_chunk"] = [water_coord.x, water_coord.y]
	report["global_water_plane_removed"] = not is_instance_valid(runtime.get_node_or_null("Water"))
	report["mined_tree_log"] = [base_log.x, base_log.y, base_log.z]
	report["placed_dirt"] = [place_cell.x, place_cell.y, place_cell.z]
	report["inventory_logs_after_mine"] = inventory.get_item_count(BLOCK_LOG)

	main.queue_free()
	await _wait_frames(2)
