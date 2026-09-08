extends SceneTree

# Verifies Phase 1's actual in-game wiring in playable_world_runtime.gd:
# place_mechanical_block / remove_mechanical_block / get_mechanical_block /
# load_mechanical_blocks / save_mechanical_blocks, and that they persist
# through a real SaveManager round trip -- as opposed to
# mechanical_block_placement_gate.gd, which only proves the standalone
# MechanicalBlockData class in isolation.
#
# Also doubles as proof that a script referencing a bare `SaveManager`
# identifier resolves correctly when *lazily loaded at runtime* (`load()`
# inside a deferred call) from within a --script entry file -- as opposed
# to being a compile-time `preload()` dependency of the entry script, which
# fails (see CLAUDE.md's autoload gotcha section for why).

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")

const AIR_CELL := Vector3i(5, 50, 5)      # WORLD_HEIGHT=60, well above any terrain height
const SOLID_CELL := Vector3i(5, 0, 5)     # below sea level / terrain, expected non-air by default
const TEST_TYPE_ID := 42
const TEST_AXIS := Vector3i.AXIS_Y

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run_gate() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager == null:
		_fail("SaveManager singleton not available")
		_finish()
		return
	save_manager.clear_save()

	var runtime_script = load("res://scripts/world/playable_world_runtime.gd")
	var runtime = runtime_script.new()
	runtime.load_mechanical_blocks()  # should tolerate an empty save cleanly

	if runtime.data.get_block(SOLID_CELL) == WORLD_DATA.BLOCK_AIR:
		_fail("Test setup invalid: SOLID_CELL is air by default, pick a different cell")
	elif runtime.place_mechanical_block(SOLID_CELL, TEST_TYPE_ID, TEST_AXIS):
		_fail("place_mechanical_block succeeded on a non-air voxel cell")

	if not runtime.place_mechanical_block(AIR_CELL, TEST_TYPE_ID, TEST_AXIS):
		_fail("place_mechanical_block failed on an air cell")
		runtime.free()
		_finish()
		return
	if runtime.place_mechanical_block(AIR_CELL, TEST_TYPE_ID, TEST_AXIS):
		_fail("place_mechanical_block succeeded twice on the same cell")
	if not runtime.has_mechanical_block(AIR_CELL):
		_fail("has_mechanical_block false immediately after placement")

	var entry: Dictionary = runtime.get_mechanical_block(AIR_CELL)
	if int(entry.get("type_id", -1)) != TEST_TYPE_ID:
		_fail("get_mechanical_block type_id mismatch")
	if int(entry.get("axis", -1)) != TEST_AXIS:
		_fail("get_mechanical_block axis mismatch")

	# Bypass the debounce timer and save immediately -- proves the bare
	# SaveManager identifier resolves inside this non-entry script.
	runtime.save_mechanical_blocks()
	if runtime.mechanical_dirty:
		_fail("mechanical_dirty still true after save_mechanical_blocks()")

	# Fresh runtime instance, load from the save that was just written.
	var reloaded_runtime = runtime_script.new()
	reloaded_runtime.load_mechanical_blocks()
	if not reloaded_runtime.has_mechanical_block(AIR_CELL):
		_fail("Reloaded runtime is missing the block after save/reload")
	else:
		var reloaded_entry: Dictionary = reloaded_runtime.get_mechanical_block(AIR_CELL)
		if int(reloaded_entry.get("type_id", -1)) != TEST_TYPE_ID:
			_fail("Reloaded type_id mismatch")
		if int(reloaded_entry.get("axis", -1)) != TEST_AXIS:
			_fail("Reloaded axis mismatch")

	if not runtime.remove_mechanical_block(AIR_CELL):
		_fail("remove_mechanical_block failed on a placed cell")
	if runtime.has_mechanical_block(AIR_CELL):
		_fail("has_mechanical_block still true after removal")

	save_manager.clear_save()
	runtime.free()
	reloaded_runtime.free()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("MECHANICAL_RUNTIME_WIRING_GATE_PASS")
		quit(0)
	else:
		print("MECHANICAL_RUNTIME_WIRING_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
