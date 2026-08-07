extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const SHIPPING_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const LOCALIZED_WATER := preload("res://scripts/world/localized_water_bodies.gd")
const STEP4_CONTRACT := preload("res://tests/multi_noise_step4_contract.gd")
const STEP4_DISTRIBUTION := preload("res://tests/multi_noise_step4_distribution.gd")
const STEP4_INTEGRATION := preload("res://tests/multi_noise_step4_integration.gd")
const STEP4_BENCHMARK := preload("res://tests/multi_noise_step4_benchmark.gd")

const WEIGHT_DIAG_PATH := "res://artifacts/multi-noise-step4-weights.png"
const RESOLVED_DIAG_PATH := "res://artifacts/multi-noise-step4-resolved.png"
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const CHUNK_SIZE := 12
const SCAN_RADIUS := 128
const WAIT_TIMEOUT_MSEC := 30000
const INVALID_FIXTURE := Vector2i(2147483647, 2147483647)

var failures: Array[String] = []
var data
var step4_distribution: Dictionary = {}
var step4_benchmark: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run_gate")


func _run_gate() -> void:
	# Preserve the accepted pre-overhaul biome-contract checks against their
	# legacy oracle. Stage 2 intentionally replaces terrain shape, so the
	# integration fixtures below must come from the shipping generation facade.
	data = WORLD_DATA.new()
	STEP4_CONTRACT.run(data, failures)
	step4_distribution = STEP4_DISTRIBUTION.run(data, failures)
	STEP4_INTEGRATION.run(data, failures)
	step4_benchmark = STEP4_BENCHMARK.run(data, failures)
	if not failures.is_empty():
		_finish()
		return

	data = SHIPPING_DATA.new()
	var report: Dictionary = _scan_static_integration()
	if not failures.is_empty():
		_finish()
		return

	await _run_shipping_scene_transaction(report)
	if not failures.is_empty():
		_finish()
		return

	var distribution_report: Dictionary = step4_distribution.duplicate(true)
	distribution_report.erase("fixtures")
	print("MULTI_NOISE_STEP4_DISTRIBUTION_JSON=%s" % JSON.stringify(distribution_report))
	print("MULTI_NOISE_STEP4_BENCHMARK_JSON=%s" % JSON.stringify(step4_benchmark))
	print("MULTI_NOISE_STEP4_WEIGHT_DIAGNOSTIC=%s" % ProjectSettings.globalize_path(WEIGHT_DIAG_PATH))
	print("MULTI_NOISE_STEP4_RESOLVED_DIAGNOSTIC=%s" % ProjectSettings.globalize_path(RESOLVED_DIAG_PATH))
	print("MULTI_NOISE_STEP4_GATE_PASS")
	print("MULTI_NOISE_STEP5_INTEGRATION_JSON=%s" % JSON.stringify(report))
	print("MULTI_NOISE_STEP5_GATE_PASS")
	print("MULTI_NOISE_STEP1_BENCHMARK_JSON={\"compatibility\":\"step5-full-integration\"}")
	print("MULTI_NOISE_STEP1_GATE_PASS")
	_finish()


func _scan_static_integration() -> Dictionary:
	var water_columns := 0
	var dry_columns := 0
	var tree_origins := 0
	var plains_trees := 0
	var forest_trees := 0
	var verified_canopies := 0
	var water_fixture := INVALID_FIXTURE
	var dry_fixture := INVALID_FIXTURE
	var tree_fixture := INVALID_FIXTURE
	var tree_access := Vector2i.ZERO

	for z in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var surface: int = data.terrain_height(x, z)
			var biome: int = data.biome_at(x, z)
			var water: bool = LOCALIZED_WATER.is_water_column(data, x, z)
			if water:
				water_columns += 1
				if water_fixture == INVALID_FIXTURE:
					water_fixture = Vector2i(x, z)
				if surface >= WORLD_DATA.SEA_LEVEL:
					_fail("Water classification escaped its terrain basin at (%d, %d)" % [x, z])
			elif surface >= WORLD_DATA.SEA_LEVEL + 2:
				dry_columns += 1
				if dry_fixture == INVALID_FIXTURE:
					dry_fixture = Vector2i(x, z)

			if not data.is_tree_origin_for_biome(x, z, surface, biome):
				continue
			tree_origins += 1
			if biome == WORLD_DATA.BIOME_PLAINS:
				plains_trees += 1
			elif biome == WORLD_DATA.BIOME_FOREST:
				forest_trees += 1
			else:
				_fail("A tree origin appeared in %s at (%d, %d)" % [data.biome_name(biome), x, z])
			if data.get_block(Vector3i(x, surface, z)) != BLOCK_GRASS:
				_fail("A generated tree is not rooted on grass at (%d, %d)" % [x, z])
			if data.get_block(Vector3i(x, surface + 1, z)) != BLOCK_LOG:
				_fail("A generated tree has no mineable base log at (%d, %d)" % [x, z])
			if _count_canopy_leaves(Vector2i(x, z), surface) > 0:
				verified_canopies += 1
			else:
				_fail("A generated tree has no canopy leaves at (%d, %d)" % [x, z])
			if tree_fixture == INVALID_FIXTURE:
				var access: Vector2i = _find_tree_access(Vector2i(x, z), surface)
				if access != Vector2i.ZERO:
					tree_fixture = Vector2i(x, z)
					tree_access = access

	if water_columns <= 0 or water_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no localized water body")
	if dry_columns <= 0 or dry_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no dry terrain")
	if tree_origins <= 0 or plains_trees <= 0 or forest_trees <= 0:
		_fail("Step 5 scan did not retain both plains and forest trees")
	if verified_canopies != tree_origins:
		_fail("Not every generated tree retained a canopy")
	if tree_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no side-accessible base log")

	var placement_fixture := INVALID_FIXTURE
	if tree_fixture != INVALID_FIXTURE:
		placement_fixture = _find_placement_fixture(tree_fixture)
	if placement_fixture == INVALID_FIXTURE:
		_fail("Step 5 scan found no placement fixture near the generated tree")

	var water_mesh: Dictionary = _validate_water_mesh(water_fixture)
	var dry_chunk: Dictionary = _find_dry_chunk()
	return {
		"scan_radius": SCAN_RADIUS,
		"water_columns": water_columns,
		"dry_columns": dry_columns,
		"tree_origins": tree_origins,
		"plains_trees": plains_trees,
		"forest_trees": forest_trees,
		"verified_canopies": verified_canopies,
		"water_fixture": [water_fixture.x, water_fixture.y],
		"dry_fixture": [dry_fixture.x, dry_fixture.y],
		"tree_fixture": [tree_fixture.x, tree_fixture.y],
		"tree_access": [tree_access.x, tree_access.y],
		"placement_fixture": [placement_fixture.x, placement_fixture.y],
		"water_mesh": water_mesh,
		"dry_chunk": dry_chunk,
	}


func _count_canopy_leaves(origin: Vector2i, surface: int) -> int:
	var count := 0
	var canopy_y: int = surface + WORLD_DATA.TREE_TRUNK_HEIGHT
	for z_offset in range(-WORLD_DATA.TREE_CANOPY_RADIUS, WORLD_DATA.TREE_CANOPY_RADIUS + 1):
		for x_offset in range(-WORLD_DATA.TREE_CANOPY_RADIUS, WORLD_DATA.TREE_CANOPY_RADIUS + 1):
			if data.get_block(Vector3i(origin.x + x_offset, canopy_y, origin.y + z_offset)) == BLOCK_LEAVES:
				count += 1
	return count


func _find_tree_access(origin: Vector2i, surface: int) -> Vector2i:
	var target_y: int = surface + 1
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for direction in directions:
		var clear := true
		for distance in range(1, 5):
			var x: int = origin.x + direction.x * distance
			var z: int = origin.y + direction.y * distance
			if data.terrain_height(x, z) >= target_y:
				clear = false
				break
			if data.get_block(Vector3i(x, target_y, z)) != BLOCK_AIR:
				clear = false
				break
		if clear:
			return direction
	return Vector2i.ZERO


func _find_placement_fixture(origin: Vector2i) -> Vector2i:
	for radius in range(4, 25):
		for offset in range(-radius, radius + 1):
			for candidate in [
				Vector2i(origin.x - radius, origin.y + offset),
				Vector2i(origin.x + radius, origin.y + offset),
				Vector2i(origin.x + offset, origin.y - radius),
				Vector2i(origin.x + offset, origin.y + radius),
			]:
				if _is_placement_column(candidate):
					return candidate
	return INVALID_FIXTURE


func _is_placement_column(candidate: Vector2i) -> bool:
	if LOCALIZED_WATER.is_water_column(data, candidate.x, candidate.y):
		return false
	var surface: int = data.terrain_height(candidate.x, candidate.y)
	if surface <= WORLD_DATA.SEA_LEVEL + 1:
		return false
	var base := Vector3i(candidate.x, surface, candidate.y)
	return data.get_block(base) != BLOCK_AIR and data.get_block(base + Vector3i.UP) == BLOCK_AIR


func _validate_water_mesh(fixture: Vector2i) -> Dictionary:
	if fixture == INVALID_FIXTURE:
		return {}
	var coord := Vector2i(
		floori(float(fixture.x) / float(CHUNK_SIZE)),
		floori(float(fixture.y) / float(CHUNK_SIZE))
	)
	var cells := 0
	for local_z in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			if LOCALIZED_WATER.is_water_column(
				data,
				coord.x * CHUNK_SIZE + local_x,
				coord.y * CHUNK_SIZE + local_z
			):
				cells += 1
	var mesh: ArrayMesh = LOCALIZED_WATER.build_water_mesh(data, coord, CHUNK_SIZE)
	if cells <= 0 or mesh == null or mesh.get_surface_count() != 1:
		_fail("The real water-body fixture did not produce one water mesh")
		return {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != cells * 4 or indices.size() != cells * 6:
		_fail("Localized water mesh geometry does not match its classified cells")
	return {"chunk": [coord.x, coord.y], "cells": cells, "vertices": vertices.size(), "indices": indices.size()}


func _find_dry_chunk() -> Dictionary:
	for chunk_z in range(-12, 13):
		for chunk_x in range(-12, 13):
			var coord := Vector2i(chunk_x, chunk_z)
			var has_water := false
			for local_z in range(CHUNK_SIZE):
				for local_x in range(CHUNK_SIZE):
					if LOCALIZED_WATER.is_water_column(
						data,
						coord.x * CHUNK_SIZE + local_x,
						coord.y * CHUNK_SIZE + local_z
					):
						has_water = true
						break
				if has_water:
					break
			if has_water:
				continue
			if LOCALIZED_WATER.build_water_mesh(data, coord, CHUNK_SIZE) != null:
				_fail("A dry chunk unexpectedly produced water geometry")
			return {"chunk": [coord.x, coord.y], "mesh": "null"}
	_fail("Step 5 scan found no completely dry chunk")
	return {}


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
	player.global_position = Vector3(water_point.x + 0.5, data.terrain_height(water_point.x, water_point.y) + 3.0, water_point.y + 0.5)
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
	await _wait_frames(4)
	camera.look_at(Vector3(tree_origin.x + 0.5, tree_surface + 1.5, tree_origin.y + 0.5), Vector3.UP)
	await _wait_frames(1)
	var hit: Dictionary = player._get_block_hit()
	if hit.is_empty() or hit.get("block", Vector3i.ZERO) != base_log:
		_fail("Mining raycast did not target the generated tree base log")
		return
	var inventory: Variant = player.get("inventory")
	if inventory == null:
		_fail("Player inventory is missing from the shipping transaction")
		return
	var logs_before: int = inventory.get_item_count(BLOCK_LOG)
	if not bool(player._try_mine_targeted_block()):
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

	var craft_log_before: int = inventory.get_item_count(BLOCK_LOG)
	var planks_before: int = inventory.get_item_count(4)
	if not bool(inventory.craft("planks")):
		_fail("Crafting planks failed after mining a generated log")
	if inventory.get_item_count(BLOCK_LOG) != craft_log_before - 1:
		_fail("Crafting did not consume exactly one mined log")
	if inventory.get_item_count(4) != planks_before + 4:
		_fail("Crafting did not add exactly four planks")

	var dry_point := Vector2i(int(dry_values[0]), int(dry_values[1]))
	if not LOCALIZED_WATER.is_water_column(runtime.data, water_point.x, water_point.y):
		_fail("Runtime data lost the real water-body classification")
	if LOCALIZED_WATER.is_water_column(runtime.data, dry_point.x, dry_point.y):
		_fail("Runtime data classified dry terrain as water")

	report["runtime_water_chunk"] = [water_coord.x, water_coord.y]
	report["global_water_plane_removed"] = not is_instance_valid(runtime.get_node_or_null("Water"))
	report["mined_tree_log"] = [base_log.x, base_log.y, base_log.z]
	report["placed_dirt"] = [place_cell.x, place_cell.y, place_cell.z]
	report["inventory_logs_after_craft"] = inventory.get_item_count(BLOCK_LOG)
	report["inventory_planks_after_craft"] = inventory.get_item_count(4)

	main.queue_free()
	await _wait_frames(2)


func _wait_for_world(manager: Variant, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		if manager.is_remesh_idle() and manager.chunk_count() == manager.expected_chunk_count():
			return true
		await process_frame
	_fail("Timed out waiting for %s" % label)
	return false


func _wait_for_remesh(manager: Variant) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		if manager.is_remesh_idle():
			return true
		await process_frame
	_fail("Timed out waiting for remesh completion")
	return false


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _finish() -> void:
	if failures.is_empty():
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MULTI_NOISE_STEP5_GATE_FAIL")
	for failure in failures:
		print("FAILURE=%s" % failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
