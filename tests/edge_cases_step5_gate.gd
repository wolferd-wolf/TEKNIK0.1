extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/edge-cases-step5.png"
const CHUNK_SIZE := 16
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const EDGE_STRESS_CYCLES := 16
const REMESH_IDLE_FRAME_LIMIT := 720

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


func _wait_for_remesh_idle(manager, context: String) -> bool:
	if not manager.has_method("is_remesh_idle"):
		return true
	for _frame in range(REMESH_IDLE_FRAME_LIMIT):
		await physics_frame
		if manager.is_remesh_idle():
			await physics_frame
			return true
	_fail("Remesh queue did not become idle during %s" % context)
	return false


func _run_gate() -> void:
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
		_fail("Inventory placement API is missing from edge-case player")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	manager.refresh_streaming(Vector3(0.5, 20.5, 0.5))
	manager.set_process(false)
	if not await _wait_for_remesh_idle(manager, "initial edge-case streaming"):
		_finish()
		return

	await _validate_boundary_mining_and_placement(manager, player)
	_validate_player_overlap_rejection(manager, player)
	await _validate_render_radius_edge_mining(manager, player, camera)
	await _capture_screenshot()

	if failures.is_empty():
		print("EDGE_CASES_STEP_5_GATE_PASS")
		print("BOUNDARY_MESH_COLLISION=%s" % boundary_summary)
		print("PLAYER_OVERLAP=%s" % overlap_summary)
		print("RENDER_EDGE_MINING=%s" % edge_summary)
	_finish()


func _validate_boundary_mining_and_placement(manager, player) -> void:
	var target := Vector3i(15, 20, 0)
	var neighbor := Vector3i(16, 20, 0)
	var target_chunk_coord: Vector3i = manager.world_to_chunk_coord(Vector3(target) + Vector3.ONE * 0.5)
	var neighbor_chunk_coord: Vector3i = manager.world_to_chunk_coord(Vector3(neighbor) + Vector3.ONE * 0.5)
	var target_chunk = manager.get_chunk(target_chunk_coord)
	var neighbor_chunk = manager.get_chunk(neighbor_chunk_coord)
	if target_chunk == null or neighbor_chunk == null:
		_fail("Boundary test chunks were not loaded: %s / %s" % [target_chunk_coord, neighbor_chunk_coord])
		return

	_clear_if_solid(manager, target)
	_clear_if_solid(manager, neighbor)
	if not manager.place_block_world(neighbor, BLOCK_STONE):
		_fail("Failed to create boundary neighbor block at %s" % neighbor)
		return
	if not manager.place_block_world(target, BLOCK_STONE):
		_fail("Failed to create boundary target block at %s" % target)
		return
	if not await _wait_for_remesh_idle(manager, "boundary setup"):
		return

	if not _chunk_has_render_and_collision(target_chunk, "Boundary target before mine"):
		return
	if not _chunk_has_render_and_collision(neighbor_chunk, "Boundary neighbor before mine"):
		return

	var target_mesh_before: ArrayMesh = target_chunk.mesh_instance.mesh as ArrayMesh
	var neighbor_mesh_before: ArrayMesh = neighbor_chunk.mesh_instance.mesh as ArrayMesh
	var target_collision_before: Shape3D = target_chunk.collision_shape.shape
	var neighbor_collision_before: Shape3D = neighbor_chunk.collision_shape.shape
	if _vertex_count(target_mesh_before) != 30:
		_fail("Boundary target expected 30 vertices before mine, got %d" % _vertex_count(target_mesh_before))
	if _vertex_count(neighbor_mesh_before) != 30:
		_fail("Boundary neighbor expected 30 vertices before mine, got %d" % _vertex_count(neighbor_mesh_before))

	if not manager.mine_block_world(target):
		_fail("Boundary target mining returned false")
		return
	if not await _wait_for_remesh_idle(manager, "boundary mine"):
		return

	if manager.get_block_world(target) != BLOCK_AIR:
		_fail("Boundary target did not become air")
	if target_chunk.mesh_instance.visible:
		_fail("Emptied boundary target chunk remained visible")
	if target_chunk.collision_shape.shape != null:
		_fail("Emptied boundary target chunk retained collision")

	var neighbor_mesh_after_mine: ArrayMesh = neighbor_chunk.mesh_instance.mesh as ArrayMesh
	var neighbor_collision_after_mine: Shape3D = neighbor_chunk.collision_shape.shape
	if neighbor_mesh_after_mine == neighbor_mesh_before:
		_fail("Boundary neighbor mesh resource was not replaced after mine")
	if _vertex_count(neighbor_mesh_after_mine) != 36:
		_fail("Boundary neighbor expected 36 vertices after mine, got %d" % _vertex_count(neighbor_mesh_after_mine))
	if neighbor_collision_after_mine == null:
		_fail("Boundary neighbor lost collision after mine")
	elif neighbor_collision_after_mine == neighbor_collision_before:
		_fail("Boundary neighbor collision resource was not replaced after mine")

	_assert_collision_ray(player, target, false, "mined boundary target")
	_assert_collision_ray(player, neighbor, true, "boundary neighbor after mine")

	player.global_position = Vector3(8.5, 20.0, 4.5)
	var inventory = player.get_inventory()
	if not inventory.add_item(BLOCK_SAND, 1):
		_fail("Failed to seed sand for boundary inventory placement")
		return
	var sand_slot: int = inventory.find_first_slot(BLOCK_SAND)
	if sand_slot < 0 or not player.select_inventory_slot(sand_slot):
		_fail("Failed to select seeded sand inventory slot")
		return
	if not player.place_block_at(target):
		_fail("Boundary inventory placement returned false at %s" % target)
		return
	if not await _wait_for_remesh_idle(manager, "boundary inventory placement"):
		return

	if manager.get_block_world(target) != BLOCK_SAND:
		_fail("Boundary placement wrote ID %d instead of sand ID 4" % manager.get_block_world(target))
	_assert_slot(inventory.get_slot(sand_slot), BLOCK_AIR, 0, "boundary sand slot after placement")
	if not target_chunk.mesh_instance.visible:
		_fail("Boundary target chunk remained hidden after placement")
	var target_mesh_after_place: ArrayMesh = target_chunk.mesh_instance.mesh as ArrayMesh
	var target_collision_after_place: Shape3D = target_chunk.collision_shape.shape
	if target_mesh_after_place == target_mesh_before:
		_fail("Boundary target mesh resource was not replaced after placement")
	if _vertex_count(target_mesh_after_place) != 30:
		_fail("Boundary target expected 30 vertices after placement, got %d" % _vertex_count(target_mesh_after_place))
	if target_collision_after_place == null:
		_fail("Boundary target lacked collision after placement")
	elif target_collision_after_place == target_collision_before:
		_fail("Boundary target collision resource was not replaced after placement")

	var neighbor_mesh_after_place: ArrayMesh = neighbor_chunk.mesh_instance.mesh as ArrayMesh
	var neighbor_collision_after_place: Shape3D = neighbor_chunk.collision_shape.shape
	if neighbor_mesh_after_place == neighbor_mesh_after_mine:
		_fail("Boundary neighbor mesh resource was not replaced after placement")
	if _vertex_count(neighbor_mesh_after_place) != 30:
		_fail("Boundary neighbor expected 30 vertices after placement, got %d" % _vertex_count(neighbor_mesh_after_place))
	if neighbor_collision_after_place == null:
		_fail("Boundary neighbor lacked collision after placement")
	elif neighbor_collision_after_place == neighbor_collision_after_mine:
		_fail("Boundary neighbor collision resource was not replaced after placement")

	_assert_collision_ray(player, target, true, "placed boundary target")
	_assert_collision_ray(player, neighbor, true, "boundary neighbor after placement")
	boundary_summary = "%s<->%s mine 30->air/36, inventory-place sand 30/30" % [target, neighbor]


func _validate_player_overlap_rejection(manager, player) -> void:
	player.global_position = Vector3(8.5, 20.0, 4.5)
	var overlap_coord := Vector3i(8, 20, 4)
	_clear_if_solid(manager, overlap_coord)
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		_fail("Player-overlap coordinate could not be cleared: %s" % overlap_coord)
		return
	var inventory = player.get_inventory()
	if not inventory.add_item(BLOCK_SAND, 1):
		_fail("Failed to seed sand for overlap rejection")
		return
	var sand_slot: int = inventory.find_first_slot(BLOCK_SAND)
	if sand_slot < 0 or not player.select_inventory_slot(sand_slot):
		_fail("Failed to select sand for overlap rejection")
		return
	var inventory_before: Array[Dictionary] = inventory.get_slots()
	if player.can_place_block_at(overlap_coord):
		_fail("Capsule-overlapping coordinate was reported placeable: %s" % overlap_coord)
	if player.place_block_at(overlap_coord):
		_fail("Capsule-overlapping placement returned true: %s" % overlap_coord)
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		_fail("Capsule-overlap rejection still modified the world")
	if inventory.get_slots() != inventory_before:
		_fail("Capsule-overlap rejection consumed inventory")
	overlap_summary = "%s rejected, remained air, and retained sand" % overlap_coord


func _validate_render_radius_edge_mining(manager, player, camera: Camera3D) -> void:
	var center_chunk: Vector3i = manager.last_center_chunk
	var edge_chunk_coord: Vector3i = center_chunk + Vector3i(int(manager.render_radius), 0, 0)
	var outside_chunk_coord: Vector3i = edge_chunk_coord + Vector3i.RIGHT
	if not manager.has_chunk(edge_chunk_coord):
		_fail("Render-radius edge chunk was not loaded: %s" % edge_chunk_coord)
		return
	if manager.has_chunk(outside_chunk_coord):
		_fail("Outward chunk was unexpectedly loaded: %s" % outside_chunk_coord)
		return

	var target: Vector3i = edge_chunk_coord * CHUNK_SIZE + Vector3i(CHUNK_SIZE - 1, 4, 0)
	var edge_chunk = manager.get_chunk(edge_chunk_coord)
	_clear_if_solid(manager, target)
	if not manager.place_block_world(target, BLOCK_STONE):
		_fail("Failed to create render-edge mining target: %s" % target)
		return
	if not await _wait_for_remesh_idle(manager, "render-edge setup"):
		return
	if not _chunk_has_render_and_collision(edge_chunk, "Render-edge chunk before mine"):
		return

	var expected_chunk_count: int = manager.expected_chunk_count()
	if manager.chunks.size() != expected_chunk_count:
		_fail("Render-edge setup loaded %d chunks instead of %d" % [manager.chunks.size(), expected_chunk_count])

	var target_center := Vector3(target) + Vector3.ONE * 0.5
	player.global_position = target_center + Vector3(-3.0, -1.55, 0.0)
	camera.global_position = target_center + Vector3(-3.0, 0.0, 0.0)
	camera.look_at(target_center, Vector3.UP)
	await _wait_frames(16)

	var acquired: Dictionary = player.get_block_target()
	if acquired.is_empty():
		_fail("Player did not acquire render-edge mining target")
		return
	if acquired.get("block_coord", Vector3i.ZERO) != target:
		_fail("Render-edge target mismatch: expected %s, got %s" % [target, acquired.get("block_coord")])
		return

	Input.action_press("mine_block", 1.0)
	await process_frame
	Input.action_release("mine_block")
	if not await _wait_for_remesh_idle(manager, "render-edge input mining"):
		return
	if manager.get_block_world(target) != BLOCK_AIR:
		_fail("InputMap mining did not clear render-edge target")
	if edge_chunk.mesh_instance.visible:
		_fail("Emptied render-edge chunk remained visible")
	if edge_chunk.collision_shape.shape != null:
		_fail("Emptied render-edge chunk retained collision")
	if manager.has_chunk(outside_chunk_coord):
		_fail("Render-edge mining unexpectedly loaded outward chunk")

	for cycle in range(EDGE_STRESS_CYCLES):
		if not manager.place_block_world(target, BLOCK_STONE):
			_fail("Render-edge stress cycle %d failed to place target" % cycle)
			break
		if not manager.mine_block_world(target):
			_fail("Render-edge stress cycle %d failed to mine target" % cycle)
			break
		if manager.has_chunk(outside_chunk_coord):
			_fail("Render-edge stress cycle %d loaded outward chunk" % cycle)
			break
		if manager.chunks.size() != expected_chunk_count:
			_fail(
				"Render-edge stress cycle %d changed chunk count to %d"
				% [cycle, manager.chunks.size()]
			)
			break

	if not manager.place_block_world(target, BLOCK_STONE):
		_fail("Failed to restore render-edge target for screenshot")
	elif await _wait_for_remesh_idle(manager, "render-edge screenshot restore"):
		camera.look_at(target_center, Vector3.UP)
		await _wait_frames(8)
	edge_summary = "%s mined by InputMap plus %d unloaded-neighbor cycles; outside %s stayed unloaded" % [
		target,
		EDGE_STRESS_CYCLES,
		outside_chunk_coord,
	]


func _assert_slot(slot: Dictionary, expected_block_id: int, expected_count: int, context: String) -> void:
	if slot.is_empty():
		_fail("%s returned an empty slot dictionary" % context)
		return
	if int(slot.get("block_id", -1)) != expected_block_id or int(slot.get("count", -1)) != expected_count:
		_fail("%s expected %d/%d, got %s" % [context, expected_block_id, expected_count, slot])


func _chunk_has_render_and_collision(chunk, context: String) -> bool:
	if chunk == null:
		_fail("%s chunk is null" % context)
		return false
	if not is_instance_valid(chunk.mesh_instance):
		_fail("%s mesh instance is missing" % context)
		return false
	if chunk.mesh_instance.mesh == null:
		_fail("%s mesh is null" % context)
		return false
	if not chunk.mesh_instance.visible:
		_fail("%s mesh is hidden" % context)
		return false
	if not is_instance_valid(chunk.collision_shape):
		_fail("%s collision shape node is missing" % context)
		return false
	if chunk.collision_shape.shape == null:
		_fail("%s collision shape resource is null" % context)
		return false
	return true


func _clear_if_solid(manager, coord: Vector3i) -> void:
	if manager.get_block_world(coord) != BLOCK_AIR:
		manager.mine_block_world(coord)


func _vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _assert_collision_ray(player, coord: Vector3i, expected_hit: bool, context: String) -> void:
	var world_3d: World3D = player.get_world_3d()
	if world_3d == null:
		_fail("World3D unavailable for %s collision ray" % context)
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
	if not expected_hit:
		if not hit.is_empty():
			_fail("Unexpected collision ray hit for %s" % context)
		return
	if hit.is_empty():
		_fail("Expected collision ray missed for %s" % context)
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
		_fail("Step 5 screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Step 5 screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Step 5 screenshot save failed with error %d" % save_error)
		return
	print("EDGE_CASES_STEP_5_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("EDGE_CASES_STEP_5_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
