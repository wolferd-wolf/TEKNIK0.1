extends SceneTree

# Phase 1 gate: MechanicalBlockData placement + persistence.
#
# "Done when" from TEKNIK_PHASE3_PLAN.md Phase 1 step 5:
# place one shaft block, save, reload, assert same block + orientation
# present. This gate proves the on-disk JSON round-trip specifically,
# since a true process-restart isn't possible within one script run --
# reading the written file back with a fresh FileAccess + JSON.parse_string
# and a brand new MechanicalBlockData instance is the strongest persistence
# proof achievable in a single process.

const MechanicalBlockData := preload("res://scripts/world/mechanical_block_data.gd")

const TEST_CELL := Vector3i(1, 2, 3)
const TEST_TYPE_ID := 42
const TEST_AXIS := Vector3i.AXIS_Y

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run_gate() -> void:
	_validate_placement_api()
	_validate_save_reload_round_trip()
	_finish()


func _validate_placement_api() -> void:
	var data := MechanicalBlockData.new()

	if data.has_block(TEST_CELL):
		_fail("Fresh MechanicalBlockData reported a block before any placement")
		return
	if not data.place_block(TEST_CELL, TEST_TYPE_ID, TEST_AXIS):
		_fail("place_block failed on an empty cell")
		return
	if not data.has_block(TEST_CELL):
		_fail("has_block false immediately after place_block")
		return
	if data.place_block(TEST_CELL, TEST_TYPE_ID, TEST_AXIS):
		_fail("place_block succeeded twice on the same cell (duplicate placement)")

	var entry := data.get_block(TEST_CELL)
	if int(entry.get("type_id", -1)) != TEST_TYPE_ID:
		_fail("get_block type_id mismatch: expected %d, got %s" % [TEST_TYPE_ID, entry.get("type_id")])
	if int(entry.get("axis", -1)) != TEST_AXIS:
		_fail("get_block axis mismatch: expected %d, got %s" % [TEST_AXIS, entry.get("axis")])

	if not data.set_block_state(TEST_CELL, {"network_id": 7}):
		_fail("set_block_state failed on a placed cell")
	if int(data.get_block_state(TEST_CELL).get("network_id", -1)) != 7:
		_fail("get_block_state did not return the state that was just set")

	if data.count() != 1:
		_fail("count() expected 1, got %d" % data.count())

	if not data.remove_block(TEST_CELL):
		_fail("remove_block failed on a placed cell")
	if data.has_block(TEST_CELL):
		_fail("has_block still true after remove_block")
	if data.count() != 0:
		_fail("count() expected 0 after removal, got %d" % data.count())


func _validate_save_reload_round_trip() -> void:
	# Engine.get_singleton() only sees native/GDExtension singletons in this
	# headless --script main-loop-override mode; plain GDScript autoloads
	# still exist as nodes under root, so fetch it that way instead.
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager == null:
		_fail("SaveManager singleton not available")
		return

	save_manager.clear_save()

	var data := MechanicalBlockData.new()
	data.place_block(TEST_CELL, TEST_TYPE_ID, TEST_AXIS)
	data.set_block_state(TEST_CELL, {"network_id": 7})
	save_manager.write_mechanical_blocks_state(data.to_save_dict())

	# In-memory read-back through the live SaveManager cache.
	var cached: Dictionary = save_manager.get_saved_mechanical_blocks()
	if cached.is_empty():
		_fail("get_saved_mechanical_blocks returned empty right after writing")
		return

	# Disk round-trip: read the actual save file back with a fresh
	# FileAccess + JSON parse, independent of SaveManager's in-memory cache,
	# and load it into a brand new MechanicalBlockData instance.
	const SAVE_PATH := "user://teknik_save.json"
	if not FileAccess.file_exists(SAVE_PATH):
		_fail("Save file does not exist at %s after write_mechanical_blocks_state" % SAVE_PATH)
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open save file for disk round-trip read")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not parsed.has("mechanical_blocks"):
		_fail("Parsed save file missing mechanical_blocks key")
		return

	var reloaded := MechanicalBlockData.new()
	reloaded.load_from_save_dict(parsed["mechanical_blocks"])

	if not reloaded.has_block(TEST_CELL):
		_fail("Reloaded MechanicalBlockData is missing the test block after disk round-trip")
		return
	var reloaded_entry := reloaded.get_block(TEST_CELL)
	if int(reloaded_entry.get("type_id", -1)) != TEST_TYPE_ID:
		_fail("Reloaded type_id mismatch: expected %d, got %s" % [TEST_TYPE_ID, reloaded_entry.get("type_id")])
	if int(reloaded_entry.get("axis", -1)) != TEST_AXIS:
		_fail("Reloaded axis mismatch: expected %d, got %s" % [TEST_AXIS, reloaded_entry.get("axis")])
	if int(reloaded.get_block_state(TEST_CELL).get("network_id", -1)) != 7:
		_fail("Reloaded state.network_id mismatch")

	save_manager.clear_save()


func _finish() -> void:
	if failures.is_empty():
		print("MECHANICAL_BLOCK_PLACEMENT_GATE_PASS")
		quit(0)
	else:
		print("MECHANICAL_BLOCK_PLACEMENT_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
