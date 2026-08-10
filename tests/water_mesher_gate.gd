extends SceneTree

const BUILDER := preload("res://scripts/world/localized_water_mesh_builder.gd")
const WATER_MANAGER := preload("res://scripts/world/localized_water_bodies.gd")

class FakeWaterData extends RefCounted:
	var heights: Dictionary = {}
	var waters: Dictionary = {}

	func terrain_height(x: int, z: int) -> int:
		return int(heights.get(Vector2i(x, z), 0))

	func water_info_at(x: int, z: int) -> Vector2i:
		return waters.get(Vector2i(x, z), Vector2i(0, -1))


func _initialize() -> void:
	var failures: Array[String] = []
	_run_mesh_cases(failures)
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
	var empty := FakeWaterData.new()
	var empty_result := BUILDER.build(empty, Vector2i.ZERO, 4)
	_expect(failures, empty_result.get("vertices", PackedVector3Array()).is_empty(), "empty water region must emit no geometry")

	var single := FakeWaterData.new()
	single.waters[Vector2i(1, 1)] = Vector2i(1, 7)
	var single_result := BUILDER.build(single, Vector2i.ZERO, 4)
	_expect(failures, int(single_result.get("quad_count", 0)) == 5, "single water cell should emit one top plus four exposed sides")

	var lake := FakeWaterData.new()
	for z in range(2):
		for x in range(2):
			lake.waters[Vector2i(x, z)] = Vector2i(1, 7)
	var lake_result := BUILDER.build(lake, Vector2i.ZERO, 4)
	_expect(failures, int(lake_result.get("quad_count", 0)) == 9, "2x2 lake should greedy-merge its top and omit four internal sides")
	_expect(failures, lake_result.get("vertices", PackedVector3Array()).size() == 36, "2x2 lake should emit 36 vertices after greedy top merging")

	var shore := FakeWaterData.new()
	shore.waters[Vector2i(1, 1)] = Vector2i(1, 7)
	shore.heights[Vector2i(2, 1)] = 7
	var shore_result := BUILDER.build(shore, Vector2i.ZERO, 4)
	_expect(failures, int(shore_result.get("quad_count", 0)) == 4, "terrain-filled shoreline neighbor must suppress that water side")

	var boundary_left := FakeWaterData.new()
	boundary_left.waters[Vector2i(3, 1)] = Vector2i(1, 7)
	boundary_left.waters[Vector2i(4, 1)] = Vector2i(1, 7)
	var left_result := BUILDER.build(boundary_left, Vector2i.ZERO, 4)
	var right_result := BUILDER.build(boundary_left, Vector2i(1, 0), 4)
	_expect(failures, int(left_result.get("quad_count", 0)) == 4, "chunk-edge water must not create a duplicate shared side when neighbor chunk contains water")
	_expect(failures, int(right_result.get("quad_count", 0)) == 4, "neighbor chunk water must suppress its shared boundary side")

	var filled := FakeWaterData.new()
	for z in range(4):
		for x in range(4):
			filled.waters[Vector2i(x, z)] = Vector2i(1, 7)
	var filled_result := BUILDER.build(filled, Vector2i.ZERO, 4)
	_expect(failures, int(filled_result.get("quad_count", 0)) == 17, "4x4 filled water region should emit one top plus 16 perimeter side quads")


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


func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
