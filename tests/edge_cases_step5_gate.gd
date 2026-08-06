extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/edge-cases-step5.png"
const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const EDGE_STRESS_CYCLES := 16
const FRAME_LIMIT := 900

var failures: Array[String] = []
var boundary_summary := ""
var overlap_summary := ""
var edge_summary := ""


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_for_world_ready(manager, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if (
			manager.chunk_count() == manager.expected_chunk_count()
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
	_fail("Playable world did not become ready during %s" % context)
	return false


func _wait_for_atomic_swaps(manager, previous_count: int, expected_delta: int, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		var current := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
		if current >= previous_count + expected_delta and manager.is_remesh_idle():
			return true
	_fail("Atomic playable-world rebuild did not complete during %s" % context)
	return false


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Edge-case gate scene nodes are missing")
		_finish()
		return
	if not manager.is_playable_world_port_active():
		_fail("Edge-case gate did not receive the single playable-world implementation")
		_finish()
		return
	if not player.has_method("get_inventory") or not player.has_method("select_inventory_slot"):
		_fail("Inventory placement API is missing from edge-case player")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	manager.refresh_streaming(Vector3(0.5, 20.0, 0.5))
	if not await _wait_for_world_ready(manager, "initial edge-case fixture"):
		_finish()
		return

	await _validate_boundary_mining_and_placement(manager, player)
	_validate_player_overlap_rejection(manager, player)
	await _validate_loaded_world_edge(manager, player, camera)
	await _capture_screenshot()

	if failures.is_empty():
		print("EDGE_CASES_STEP_5_GATE_PASS")
		print("BOUNDARY_PLAYABLE_WORLD=%s" % boundary_summary)
		print("PLAYER_OVERLAP=%s" % overlap_summary)
		print("LOADED_EDGE_MUTATION=%s" % edge_summary)
	_finish()


func _validate_boundary_mining_and_placement(manager, player) -> void:
	var target := Vector3i(CHUNK_SIZE - 1, 20, 0)
	var neighbor := Vector3i(CHUNK_SIZE, 20, 0)
	await _clear_cell(manager, target)
	await _clear_cell(manager, neighbor)

	var setup_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.place_block_world(neighbor, BLOCK_STONE):
		_fail("Failed to create playable-world boundary neighbor")
		return
	if not manager.place_block_world(target, BLOCK_STONE):
		_fail("Failed to create playable-world boundary target")
		return
	if not await _wait_for_atomic_swaps(manager, setup_swaps, 2, "boundary setup"):
		return

	var left_before := manager.get_playable_world_chunk_entry(Vector2i(0, 0)).get("root") as Node3D
	var right_before := manager.get_playable_world_chunk_entry(Vector2i(1, 0)).get("root") as Node3D
	var mine_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.mine_block_world(target):
		_fail("Boundary target mining returned false")
		return
	if not await _wait_for_atomic_swaps(manager, mine_swaps, 2, "boundary mining"):
		return
	var left_after_mine := manager.get_playable_world_chunk_entry(Vector2i(0, 0)).get("root") as Node3D
	var right_after_mine := manager.get_playable_world_chunk_entry(Vector2i(1, 0)).get("root") as Node3D
	if left_after_mine == left_before or right_after_mine == right_before:
		_fail("Boundary mining did not rebuild both playable-world chunks")
	if manager.get_block_world(target) != BLOCK_AIR:
		_fail("Boundary target did not become air")
	if manager.get_block_world(neighbor) != BLOCK_STONE:
		_fail("Boundary neighbor changed unexpectedly")
	_assert_collision_ray(player, target, false, "mined boundary target")
	_assert_collision_ray(player, neighbor, true, "boundary neighbor after mining")

	var inventory = player.get_inventory()
	if not inventory.add_item(BLOCK_SAND, 1):
		_fail("Failed to seed sand for boundary inventory placement")
		return
	var sand_slot: int = inventory.find_first_slot(BLOCK_SAND)
	if sand_slot < 0 or not player.select_inventory_slot(sand_slot):
		_fail("Failed to select sand for boundary inventory placement")
		return
	player.global_position = Vector3(6.5, 20.0, 5.5)
	var place_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not player.place_block_at(target):
		_fail("Boundary inventory placement returned false")
		return
	if not await _wait_for_atomic_swaps(manager, place_swaps, 2, "boundary inventory placement"):
		return
	if manager.get_block_world(target) != BLOCK_SAND:
		_fail("Boundary inventory placement wrote the wrong block")
	_assert_slot(inventory.get_slot(sand_slot), BLOCK_AIR, 0, "boundary sand slot")
	_assert_collision_ray(player, target, true, "placed boundary target")
	_assert_collision_ray(player, neighbor, true, "boundary neighbor after placement")
	boundary_summary = "%s<->%s mined and inventory-restored across 12-block boundary" % [target, neighbor]


func _validate_player_overlap_rejection(manager, player) -> void:
	var overlap_coord := Vector3i(6, 20, 5)
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		manager.set_block_world(overlap_coord, BLOCK_AIR)
	player.global_position = Vector3(6.5, 20.0, 5.5)
	var inventory = player.get_inventory()
	if not inventory.add_item(BLOCK_SAND, 1):
		_fail("Failed to seed sand for overlap rejection")
		return
	var sand_slot: int = inventory.find_first_slot(BLOCK_SAND)
	if sand_slot < 0 or not player.select_inventory_slot(sand_slot):
		_fail("Failed to select sand for overlap rejection")
		return
	var before: Array[Dictionary] = inventory.get_slots()
	if player.can_place_block_at(overlap_coord):
		_fail("Capsule-overlapping coordinate was reported placeable")
	if player.place_block_at(overlap_coord):
		_fail("Capsule-overlapping placement returned true")
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		_fail("Capsule-overlap rejection modified the world")
	if inventory.get_slots() != before:
		_fail("Capsule-overlap rejection consumed inventory")
	overlap_summary = "%s rejected with inventory unchanged" % overlap_coord


func _validate_loaded_world_edge(manager, player, camera: Camera3D) -> void:
	var edge_chunk := Vector2i(RENDER_RADIUS, 0)
	var outside_chunk := Vector2i(RENDER_RADIUS + 1, 0)
	var edge_coord3 := Vector3i(edge_chunk.x, 0, edge_chunk.y)
	var outside_coord3 := Vector3i(outside_chunk.x, 0, outside_chunk.y)
	if not manager.has_chunk(edge_coord3):
		_fail("Playable-world visual edge chunk was not loaded: %s" % edge_chunk)
		return
	if manager.has_chunk(outside_coord3):
		_fail("Chunk outside the playable render radius was unexpectedly loaded")
		return
	var target := Vector3i(edge_chunk.x * CHUNK_SIZE + CHUNK_SIZE - 1, 20, 0)
	await _clear_cell(manager, target)
	var entry_before: Dictionary = manager.get_playable_world_chunk_entry(edge_chunk)
	var root_before := entry_before.get("root") as Node3D
	var place_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.place_block_world(target, BLOCK_STONE):
		_fail("Could not place a block at the loaded playable-world edge")
		return
	if not await _wait_for_atomic_swaps(manager, place_swaps, 1, "loaded-edge placement"):
		return
	var root_after_place := manager.get_playable_world_chunk_entry(edge_chunk).get("root") as Node3D
	if root_after_place == root_before:
		_fail("Loaded-edge placement did not replace the edge chunk root")
	var mine_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.mine_block_world(target):
		_fail("Could not mine the loaded playable-world edge")
		return
	if not await _wait_for_atomic_swaps(manager, mine_swaps, 1, "loaded-edge mining"):
		return
	if manager.get_block_world(target) != BLOCK_AIR:
		_fail("Loaded-edge mining did not clear the target")
	if manager.has_chunk(outside_coord3):
		_fail("Loaded-edge mutation loaded the outside chunk")

	for cycle in range(EDGE_STRESS_CYCLES):
		if not manager.place_block_world(target, BLOCK_STONE):
			_fail("Loaded-edge stress cycle %d failed to place" % cycle)
			break
		if not manager.mine_block_world(target):
			_fail("Loaded-edge stress cycle %d failed to mine" % cycle)
			break
		if manager.has_chunk(outside_coord3):
			_fail("Loaded-edge stress cycle %d loaded the outside chunk" % cycle)
			break
		if manager.chunk_count() != manager.expected_chunk_count():
			_fail("Loaded-edge stress cycle %d changed the chunk count" % cycle)
			break
	var stress_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not await _wait_for_atomic_swaps(manager, stress_swaps, 1, "coalesced edge stress rebuild"):
		return
	var restore_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.place_block_world(target, BLOCK_STONE):
		_fail("Could not restore loaded-edge screenshot target")
	elif await _wait_for_atomic_swaps(manager, restore_swaps, 1, "loaded-edge screenshot restore"):
		player.global_position = Vector3(target) + Vector3(-5.0, 4.0, 5.0)
		camera.look_at(Vector3(target) + Vector3.ONE * 0.5, Vector3.UP)
		await _wait_frames(8)
	edge_summary = "%s survived %d place/mine cycles while outside %s stayed unloaded" % [target, EDGE_STRESS_CYCLES, outside_chunk]


func _clear_cell(manager, coord: Vector3i) -> void:
	if manager.get_block_world(coord) == BLOCK_AIR:
		return
	var swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if manager.mine_block_world(coord):
		await _wait_for_atomic_swaps(manager, swaps, 1, "fixture clear at %s" % coord)


func _assert_slot(slot: Dictionary, expected_block_id: int, expected_count: int, context: String) -> void:
	if int(slot.get("block_id", -1)) != expected_block_id or int(slot.get("count", -1)) != expected_count:
		_fail("%s expected %d/%d, got %s" % [context, expected_block_id, expected_count, slot])


func _assert_collision_ray(player, coord: Vector3i, expected_hit: bool, context: String) -> void:
	var world_3d: World3D = player.get_world_3d()
	if world_3d == null:
		_fail("World3D unavailable for %s" % context)
		return
	var center := Vector3(coord) + Vector3.ONE * 0.5
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 2.0, center - Vector3.UP * 2.0)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if expected_hit and hit.is_empty():
		_fail("Expected collision ray missed for %s" % context)
		return
	if not expected_hit and not hit.is_empty():
		var inside := Vector3(hit["position"]) - Vector3(hit["normal"]) * 0.001
		var hit_coord := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
		if hit_coord == coord:
			_fail("Unexpected collision remained for %s" % context)
		return
	if hit.is_empty():
		return
	var inside := Vector3(hit["position"]) - Vector3(hit["normal"]) * 0.001
	var hit_coord := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
	if hit_coord != coord:
		_fail("Collision ray for %s hit %s instead of %s" % [context, hit_coord, coord])


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Edge-case screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Edge-case screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if error != OK:
		_fail("Edge-case screenshot save failed with error %d" % error)
	else:
		print("EDGE_CASES_STEP_5_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("EDGE_CASES_STEP_5_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
