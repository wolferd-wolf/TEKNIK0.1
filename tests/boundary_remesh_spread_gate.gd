extends SceneTree

const CHUNK_MANAGER_SCRIPT := preload("res://scripts/world/chunk_manager.gd")
const CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const CHUNK_SIZE := 16
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const REMESH_IDLE_FRAME_LIMIT := 240

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run_gate() -> void:
	var manager := CHUNK_MANAGER_SCRIPT.new()
	root.add_child(manager)
	await process_frame

	var positions := _boundary_positions()
	var neighbor_remesh_transitions := 0
	var negative_base_cases := 0

	for case_index in range(positions.size()):
		var local_coord: Vector3i = positions[case_index]
		var base_coord := _base_chunk_coord(case_index)
		if base_coord.x < 0 or base_coord.y < 0 or base_coord.z < 0:
			negative_base_cases += 1

		var base_chunk = _create_registered_chunk(manager, base_coord)
		var target_world := base_coord * CHUNK_SIZE + local_coord
		var directions := _outward_directions(local_coord)
		var neighbor_records: Array[Dictionary] = []

		base_chunk.set_block(local_coord, BLOCK_STONE)
		for direction in directions:
			var neighbor_coord: Vector3i = base_coord + direction
			var neighbor_chunk = _create_registered_chunk(manager, neighbor_coord)
			var neighbor_world: Vector3i = target_world + direction
			var neighbor_local: Vector3i = manager.world_to_local_coord(neighbor_world)
			neighbor_chunk.set_block(neighbor_local, BLOCK_STONE)
			neighbor_records.append({
				"direction": direction,
				"chunk": neighbor_chunk,
				"local": neighbor_local,
			})

		_rebuild_chunk(base_chunk, manager)
		for record in neighbor_records:
			_rebuild_chunk(record["chunk"], manager)
			var before_mesh: ArrayMesh = record["chunk"].mesh_instance.mesh
			record["before_mesh_id"] = before_mesh.get_instance_id()
			if _vertex_count(before_mesh) != 30:
				_fail(
					"Case %d neighbor %s expected 30 pre-mine vertices, got %d"
					% [case_index, record["direction"], _vertex_count(before_mesh)]
				)

		if not manager.mine_block_world(target_world):
			_fail("Case %d failed to mine boundary target %s" % [case_index, target_world])
			continue
		if not await _wait_for_remesh_idle(manager, case_index, "mine"):
			continue
		if manager.get_block_world(target_world) != BLOCK_AIR:
			_fail("Case %d target did not become air" % case_index)
		if base_chunk.mesh_instance.visible:
			_fail("Case %d emptied base chunk remained visible" % case_index)
		if base_chunk.collision_shape.shape != null:
			_fail("Case %d emptied base chunk retained collision" % case_index)

		for record in neighbor_records:
			var mined_mesh: ArrayMesh = record["chunk"].mesh_instance.mesh
			if mined_mesh.get_instance_id() == record["before_mesh_id"]:
				_fail("Case %d neighbor %s mesh was not replaced after mine" % [case_index, record["direction"]])
			if _vertex_count(mined_mesh) != 36:
				_fail(
					"Case %d neighbor %s expected 36 post-mine vertices, got %d"
					% [case_index, record["direction"], _vertex_count(mined_mesh)]
				)
			if record["chunk"].collision_shape.shape == null:
				_fail("Case %d neighbor %s lost collision after mine" % [case_index, record["direction"]])
			record["mined_mesh_id"] = mined_mesh.get_instance_id()
			neighbor_remesh_transitions += 1

		if not manager.set_block_world(target_world, BLOCK_STONE):
			_fail("Case %d failed to restore boundary target %s" % [case_index, target_world])
			continue
		if not await _wait_for_remesh_idle(manager, case_index, "restore"):
			continue
		if manager.get_block_world(target_world) != BLOCK_STONE:
			_fail("Case %d target did not restore to stone" % case_index)
		if not base_chunk.mesh_instance.visible:
			_fail("Case %d restored base chunk remained hidden" % case_index)
		if base_chunk.collision_shape.shape == null:
			_fail("Case %d restored base chunk lacked collision" % case_index)

		for record in neighbor_records:
			var restored_mesh: ArrayMesh = record["chunk"].mesh_instance.mesh
			if restored_mesh.get_instance_id() == record["mined_mesh_id"]:
				_fail("Case %d neighbor %s mesh was not replaced after restore" % [case_index, record["direction"]])
			if _vertex_count(restored_mesh) != 30:
				_fail(
					"Case %d neighbor %s expected 30 restored vertices, got %d"
					% [case_index, record["direction"], _vertex_count(restored_mesh)]
				)
			neighbor_remesh_transitions += 1

	if failures.is_empty():
		print("BOUNDARY_REMESH_SPREAD_GATE_PASS")
		print("BOUNDARY_POSITIONS_TESTED=%d" % positions.size())
		print("NEIGHBOR_REMESH_TRANSITIONS=%d" % neighbor_remesh_transitions)
		print("NEGATIVE_BASE_CASES=%d" % negative_base_cases)
		quit(0)
	else:
		print("BOUNDARY_REMESH_SPREAD_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)


func _wait_for_remesh_idle(manager, case_index: int, phase: String) -> bool:
	for _frame in range(REMESH_IDLE_FRAME_LIMIT):
		await process_frame
		if manager.is_remesh_idle():
			return true
	_fail("Case %d %s remesh did not become idle" % [case_index, phase])
	return false


func _create_registered_chunk(manager, chunk_coord: Vector3i):
	var existing = manager.get_chunk(chunk_coord)
	if is_instance_valid(existing):
		return existing

	var chunk := CHUNK_SCRIPT.new()
	chunk.configure(chunk_coord)
	if not manager.register_chunk(chunk_coord, chunk):
		_fail("Failed to register chunk %s" % chunk_coord)
	return chunk


func _rebuild_chunk(chunk, manager) -> void:
	chunk.rebuild_mesh(Callable(manager, "get_block_world"))


func _vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _outward_directions(local_coord: Vector3i) -> Array[Vector3i]:
	var directions: Array[Vector3i] = []
	if local_coord.x == 0:
		directions.append(Vector3i.LEFT)
	elif local_coord.x == CHUNK_SIZE - 1:
		directions.append(Vector3i.RIGHT)
	if local_coord.y == 0:
		directions.append(Vector3i.DOWN)
	elif local_coord.y == CHUNK_SIZE - 1:
		directions.append(Vector3i.UP)
	if local_coord.z == 0:
		directions.append(Vector3i.FORWARD)
	elif local_coord.z == CHUNK_SIZE - 1:
		directions.append(Vector3i.BACK)
	return directions


func _base_chunk_coord(case_index: int) -> Vector3i:
	if case_index % 2 == 0:
		return Vector3i(case_index * 4 + 2, case_index % 5, case_index % 7)
	return Vector3i(-case_index * 4 - 3, -(case_index % 5) - 1, -(case_index % 7) - 1)


func _boundary_positions() -> Array[Vector3i]:
	return [
		Vector3i(0, 5, 9),
		Vector3i(15, 6, 10),
		Vector3i(4, 0, 11),
		Vector3i(5, 15, 12),
		Vector3i(6, 7, 0),
		Vector3i(8, 9, 15),
		Vector3i(0, 0, 7),
		Vector3i(0, 15, 8),
		Vector3i(15, 0, 9),
		Vector3i(15, 15, 10),
		Vector3i(0, 6, 0),
		Vector3i(0, 7, 15),
		Vector3i(15, 8, 0),
		Vector3i(15, 9, 15),
		Vector3i(5, 0, 0),
		Vector3i(6, 0, 15),
		Vector3i(7, 15, 0),
		Vector3i(8, 15, 15),
		Vector3i(0, 0, 0),
		Vector3i(0, 0, 15),
		Vector3i(0, 15, 0),
		Vector3i(0, 15, 15),
		Vector3i(15, 0, 0),
		Vector3i(15, 0, 15),
		Vector3i(15, 15, 0),
		Vector3i(15, 15, 15),
	]
