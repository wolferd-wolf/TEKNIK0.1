extends SceneTree

const BUILDER := preload("res://scripts/world/localized_water_mesh_builder.gd")
const WATER_MANAGER := preload("res://scripts/world/localized_water_bodies.gd")
const WORKER_DATA := preload("res://scripts/world/playable_world_worker_carpathian_data.gd")

class FakeVoxelData extends RefCounted:
	const WORLD_HEIGHT := 60
	const BLOCK_AIR := 0
	const BLOCK_STONE := 3
	const BLOCK_WATER := 7
	var blocks: Dictionary = {}
	var overrides: Dictionary = {}
	var reported_water: Dictionary = {}

	func terrain_height(x: int, z: int) -> int:
		var highest := -1
		for cell in blocks.keys():
			var c: Vector3i = cell
			if c.x == x and c.z == z and int(blocks[cell]) != BLOCK_AIR and int(blocks[cell]) != BLOCK_WATER:
				highest = maxi(highest, c.y)
		return highest

	func get_block(cell: Vector3i) -> int:
		if overrides.has("%d,%d,%d" % [cell.x, cell.y, cell.z]):
			return int(overrides["%d,%d,%d" % [cell.x, cell.y, cell.z]])
		return int(blocks.get(cell, BLOCK_AIR))

	func water_info_at(x: int, z: int) -> Vector2i:
		return reported_water.get(Vector2i(x, z), Vector2i(0, -1))

	func set_block(cell: Vector3i, block_id: int) -> void:
		blocks[cell] = block_id


func _initialize() -> void:
	var failures: Array[String] = []
	_run_mesh_cases(failures)
	_run_real_world_voxel_cases(failures)
	_run_invalidation_cases(failures)
	if failures.is_empty():
		print("WATER_MESHER_GATE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("WATER_MESHER_GATE_FAIL count=%d" % failures.size())
		quit(1)


func _run_mesh_cases(failures: Array[String]) -> void:
	var empty := FakeVoxelData.new()
	var empty_result := BUILDER.build(empty, Vector2i.ZERO, 4)
	_expect(failures, empty_result.get("vertices", PackedVector3Array()).is_empty(), "empty voxel water region must emit no geometry")

	var fake_ocean := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			fake_ocean.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
			fake_ocean.reported_water[Vector2i(x, z)] = Vector2i(1, 7)
	var fake_ocean_result := BUILDER.build(fake_ocean, Vector2i.ZERO, 4)
	# surface_y is the highest water voxel coordinate, so floor=0/surface=7
	# represents seven full water voxels in every one of the 16 columns.
	_expect(failures, int(fake_ocean_result.get("water_voxel_count", 0)) == 112, "fluid source must materialize the complete water voxel stack per column")
	_expect(failures, int(fake_ocean_result.get("top_quad_count", 0)) == 1, "flat fluid source must merge its complete top into one quad")
	_expect(failures, int(fake_ocean_result.get("quad_count", 0)) == 17, "flat fluid source should emit one top plus perimeter sides")

	var single := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			single.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
	single.set_block(Vector3i(1, 1, 1), FakeVoxelData.BLOCK_WATER)
	var single_result := BUILDER.build(single, Vector2i.ZERO, 4)
	_expect(failures, int(single_result.get("water_voxel_count", 0)) == 0, "explicit voxel without a fluid column must not create procedural water")
	# A real fluid column is represented by water_info_at; this test verifies the
	# dedicated mesher uses that source while still honoring explicit overrides.
	single.reported_water[Vector2i(1, 1)] = Vector2i(1, 1)
	var single_fluid_result := BUILDER.build(single, Vector2i.ZERO, 4)
	_expect(failures, int(single_fluid_result.get("water_voxel_count", 0)) == 1, "single generated fluid cell must be meshed")
	_expect(failures, int(single_fluid_result.get("top_quad_count", 0)) == 1, "single water cell should emit one top quad")
	_expect(failures, int(single_fluid_result.get("quad_count", 0)) == 5, "single water cell should emit one top plus four exposed sides")

	var lake := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			lake.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
			if x < 2 and z < 2:
				lake.reported_water[Vector2i(x, z)] = Vector2i(1, 1)
	var lake_result := BUILDER.build(lake, Vector2i.ZERO, 4)
	_expect(failures, int(lake_result.get("water_voxel_count", 0)) == 4, "2x2 lake must contain four water voxels")
	_expect(failures, int(lake_result.get("top_quad_count", 0)) == 1, "2x2 lake top must greedily merge to one quad")
	_expect(failures, int(lake_result.get("quad_count", 0)) == 9, "2x2 lake should emit one top plus eight exposed sides")
	_expect(failures, lake_result.get("vertices", PackedVector3Array()).size() == 36, "2x2 lake should emit 36 vertices")

	var stacked := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			stacked.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
	stacked.reported_water[Vector2i(1, 1)] = Vector2i(1, 2)
	var stacked_result := BUILDER.build(stacked, Vector2i.ZERO, 4)
	_expect(failures, int(stacked_result.get("water_voxel_count", 0)) == 2, "stacked water must contain both fluid voxels")
	_expect(failures, int(stacked_result.get("top_quad_count", 0)) == 1, "stacked water must have one exposed top, not an internal top")
	# The two water cells form one continuous vertical side stack. Internal
	# water/water faces are suppressed, so this remains one top + four sides.
	_expect(failures, int(stacked_result.get("quad_count", 0)) == 5, "stacked water must suppress the internal horizontal face")

	var shore := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			shore.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
	shore.reported_water[Vector2i(1, 1)] = Vector2i(1, 1)
	shore.blocks[Vector3i(2, 1, 1)] = FakeVoxelData.BLOCK_STONE
	var shore_result := BUILDER.build(shore, Vector2i.ZERO, 4)
	_expect(failures, int(shore_result.get("quad_count", 0)) == 4, "terrain-filled shoreline neighbor must suppress that water side")

	var boundary := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			boundary.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
	boundary.reported_water[Vector2i(3, 1)] = Vector2i(1, 1)
	boundary.reported_water[Vector2i(4, 1)] = Vector2i(1, 1)
	var left_result := BUILDER.build(boundary, Vector2i.ZERO, 4)
	var right_result := BUILDER.build(boundary, Vector2i(1, 0), 4)
	_expect(failures, int(left_result.get("quad_count", 0)) == 4, "chunk-edge water must suppress the shared internal side")
	_expect(failures, int(right_result.get("quad_count", 0)) == 4, "neighbor chunk water must suppress the shared internal side")

	var filled := FakeVoxelData.new()
	for z in range(4):
		for x in range(4):
			filled.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
			filled.reported_water[Vector2i(x, z)] = Vector2i(1, 1)
	var filled_result := BUILDER.build(filled, Vector2i.ZERO, 4)
	_expect(failures, int(filled_result.get("top_quad_count", 0)) == 1, "4x4 filled water must merge its complete top into one quad")
	_expect(failures, int(filled_result.get("quad_count", 0)) == 17, "4x4 filled water should emit one top plus 16 perimeter sides")

	var removed := FakeVoxelData.new()
	for z in range(2):
		for x in range(2):
			removed.blocks[Vector3i(x, 0, z)] = FakeVoxelData.BLOCK_STONE
			removed.reported_water[Vector2i(x, z)] = Vector2i(1, 1)
	removed.overrides["0,1,0"] = FakeVoxelData.BLOCK_AIR
	var removed_result := BUILDER.build(removed, Vector2i.ZERO, 2)
	_expect(failures, int(removed_result.get("water_voxel_count", 0)) == 3, "explicit AIR override must remove a generated water voxel")


func _run_real_world_voxel_cases(failures: Array[String]) -> void:
	var data = WORKER_DATA.new()
	var water_cell: Variant = null
	var dry_column: Variant = null
	for z in range(-64, 65):
		for x in range(-64, 65):
			var info: Vector2i = data.water_info_at(x, z)
			if info.x != 0 and info.y > data.terrain_height(x, z):
				water_cell = Vector3i(x, data.terrain_height(x, z) + 1, z)
				break
		if water_cell != null:
			break
	for z in range(-64, 65):
		for x in range(-64, 65):
			var info: Vector2i = data.water_info_at(x, z)
			if info.x == 0:
				dry_column = Vector3i(x, data.terrain_height(x, z) + 1, z)
				break
		if dry_column != null:
			break
	_expect(failures, water_cell != null, "shipping sampler must expose at least one generated water column")
	_expect(failures, dry_column != null, "shipping sampler must expose dry columns")
	if water_cell != null:
		_expect(failures, int(data.get_block(water_cell)) == 7, "generated water must be an explicit BLOCK_WATER voxel")
		var edited := data.get_block(water_cell)
		_expect(failures, edited == 7, "water voxel must be mineable/editable as a block")
		data.set_block(water_cell, 0)
		_expect(failures, int(data.get_block(water_cell)) == 0, "removing a water voxel must override the generated fluid cell")
	if dry_column != null:
		_expect(failures, int(data.get_block(dry_column)) != 7, "dry terrain excavation must not expose synthetic water")


func _run_invalidation_cases(failures: Array[String]) -> void:
	var center := Vector3i(11, 4, 11)
	var affected := WATER_MANAGER.affected_chunks_for_world_cell(center, 12)
	_expect(failures, affected.has(Vector2i(0, 0)), "terrain edit must invalidate its own chunk")
	_expect(failures, affected.has(Vector2i(1, 0)), "x-boundary terrain edit must invalidate neighboring chunk")
	_expect(failures, affected.has(Vector2i(0, 1)), "z-boundary terrain edit must invalidate neighboring chunk")
	_expect(failures, not affected.has(Vector2i(1, 1)), "single-cell edit must not invalidate diagonal chunk without an affected column")
	_expect(failures, not WATER_MANAGER.water_result_is_stale(2, 2, 4, 4, true), "matching generation/revision result must be accepted")
	_expect(failures, WATER_MANAGER.water_result_is_stale(1, 2, 4, 4, true), "old generation result must be rejected")
	_expect(failures, WATER_MANAGER.water_result_is_stale(2, 2, 3, 4, true), "old revision result must be rejected")
	_expect(failures, WATER_MANAGER.water_result_is_stale(2, 2, 4, 4, false), "out-of-radius result must be rejected")

	var manager = WATER_MANAGER.new()
	manager.notify_world_change(Vector3i(11, 4, 11))
	var diagnostics: Dictionary = manager.diagnostics()
	_expect(failures, int(diagnostics.get("water_dirty_chunks", 0)) == 3, "terrain edit at chunk corner must dirty exactly the affected three chunks")
	manager.mark_water_chunk_dirty(Vector2i(5, 5))
	diagnostics = manager.diagnostics()
	_expect(failures, int(diagnostics.get("water_dirty_chunks", 0)) == 4, "water edit must dirty its affected chunk without rebuilding unrelated chunks")
	manager.free()


func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
