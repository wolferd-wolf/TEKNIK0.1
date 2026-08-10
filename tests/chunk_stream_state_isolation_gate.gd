extends SceneTree

const SHIPPING_DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const WORKER_DATA := preload("res://scripts/world/playable_world_worker_carpathian_data.gd")
const OVERRIDE_INDEX := preload("res://scripts/world/playable_world_override_spatial_index.gd")

const CHUNK_SIZE := 12
const PADDING := 2

var failures: Array[String] = []


func _cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


func _parse_cell_key(key_value: Variant) -> Variant:
	var parts := String(key_value).split(",")
	if parts.size() != 3:
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func _expected_snapshot(source: Dictionary, coord: Vector2i) -> Dictionary:
	var min_x := coord.x * CHUNK_SIZE - PADDING
	var min_z := coord.y * CHUNK_SIZE - PADDING
	var max_x := coord.x * CHUNK_SIZE + CHUNK_SIZE + PADDING - 1
	var max_z := coord.y * CHUNK_SIZE + CHUNK_SIZE + PADDING - 1
	var expected: Dictionary = {}
	for key_value: Variant in source.keys():
		var parsed: Variant = _parse_cell_key(key_value)
		if parsed == null:
			continue
		var cell: Vector3i = parsed
		if cell.x < min_x or cell.x > max_x or cell.z < min_z or cell.z > max_z:
			continue
		expected[String(key_value)] = int(source[key_value])
	return expected


func _compare_snapshot(source: Dictionary, coord: Vector2i, index) -> void:
	var expected := _expected_snapshot(source, coord)
	var actual: Dictionary = index.snapshot_for_chunk(coord, CHUNK_SIZE, PADDING)
	if actual.size() != expected.size():
		failures.append(
			"Snapshot size mismatch coord=%s actual=%d expected=%d"
			% [coord, actual.size(), expected.size()]
		)
		return
	for key_value: Variant in expected.keys():
		if not actual.has(key_value) or int(actual[key_value]) != int(expected[key_value]):
			failures.append("Snapshot value mismatch coord=%s key=%s" % [coord, key_value])


func _gate_spatial_index() -> void:
	var source: Dictionary = {}
	# Dense distant edit history: none of this should be copied into a near chunk.
	for index_value in range(1200):
		var cell := Vector3i(10000 + index_value, posmod(index_value, 50), -9000 - index_value)
		source[_cell_key(cell)] = 1 + posmod(index_value, 6)
	# Boundary and negative-coordinate cases that must be preserved exactly.
	var targeted: Array[Vector3i] = [
		Vector3i(-14, 11, -13),
		Vector3i(-13, 12, -12),
		Vector3i(-2, 13, -1),
		Vector3i(-1, 14, 0),
		Vector3i(0, 15, 0),
		Vector3i(11, 16, 11),
		Vector3i(12, 17, 12),
		Vector3i(13, 18, 13),
		Vector3i(24, 19, -36),
	]
	for targeted_index in range(targeted.size()):
		source[_cell_key(targeted[targeted_index])] = 1 + posmod(targeted_index, 6)

	var index = OVERRIDE_INDEX.new()
	index.rebuild(source, CHUNK_SIZE)
	for coord in [Vector2i.ZERO, Vector2i(-1, -1), Vector2i(1, 1), Vector2i(2, -3)]:
		_compare_snapshot(source, coord, index)

	var new_cell := Vector3i(12, 22, -1)
	source[_cell_key(new_cell)] = 3
	index.set_override(new_cell, 3)
	_compare_snapshot(source, Vector2i(1, 0), index)

	var near_snapshot: Dictionary = index.snapshot_for_chunk(Vector2i.ZERO, CHUNK_SIZE, PADDING)
	if near_snapshot.size() >= 100:
		failures.append(
			"Chunk-local snapshot unexpectedly retained distant history size=%d" % near_snapshot.size()
		)


func _gate_worker_save_isolation() -> void:
	var save_path: String = SHIPPING_DATA.SAVE_PATH
	var had_previous := FileAccess.file_exists(save_path)
	var previous_contents := FileAccess.get_file_as_string(save_path) if had_previous else ""
	var sentinel_key := "123,4,567"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		failures.append("Unable to create sentinel world save")
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"seed": SHIPPING_DATA.WORLD_SEED,
		"overrides": {sentinel_key: SHIPPING_DATA.BLOCK_GRASS},
	}))
	file.close()

	var worker = WORKER_DATA.new()
	if worker.overrides.has(sentinel_key):
		failures.append("Generation-only worker loaded persistent save overrides")
	var authoritative = SHIPPING_DATA.new()
	if not authoritative.overrides.has(sentinel_key):
		failures.append("Sentinel setup invalid: authoritative data did not load save")

	if had_previous:
		var restore := FileAccess.open(save_path, FileAccess.WRITE)
		if restore != null:
			restore.store_string(previous_contents)
			restore.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _init() -> void:
	_gate_spatial_index()
	_gate_worker_save_isolation()
	if failures.is_empty():
		print("CHUNK_STREAM_STATE_ISOLATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
