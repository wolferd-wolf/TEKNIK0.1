extends SceneTree

# Phase 2 gate: kinetic network core.
#
# Verifies:
# - a hand crank + a chain of same-axis shafts resolve into one network
#   with the crank's speed/capacity
# - a shaft on a different axis (not touching the chain) forms its own,
#   powerless network
# - removing the crank re-resolves the remaining shafts down to speed 0
# - a mesh instance exists per placed block and gets freed on removal
# - a running network's mesh instance actually rotates over simulated
#   ticks; a powerless one does not

const AIR_ORIGIN := Vector3i(5, 50, 5)  # WORLD_HEIGHT=60, air well above terrain

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
	var mechanical_data_script = load("res://scripts/world/mechanical_block_data.gd")
	var runtime = runtime_script.new()

	var crank_cell := AIR_ORIGIN
	var shaft1_cell := AIR_ORIGIN + Vector3i(0, 1, 0)
	var shaft2_cell := AIR_ORIGIN + Vector3i(0, 2, 0)
	var isolated_cell := AIR_ORIGIN + Vector3i(5, 0, 0)  # far away, own axis

	runtime.place_mechanical_block(crank_cell, mechanical_data_script.MECH_HAND_CRANK, Vector3i.AXIS_Y)
	runtime.place_mechanical_block(shaft1_cell, mechanical_data_script.MECH_SHAFT, Vector3i.AXIS_Y)
	runtime.place_mechanical_block(shaft2_cell, mechanical_data_script.MECH_SHAFT, Vector3i.AXIS_Y)
	runtime.place_mechanical_block(isolated_cell, mechanical_data_script.MECH_SHAFT, Vector3i.AXIS_X)

	var crank_state: Dictionary = runtime.get_mechanical_block(crank_cell).get("state", {})
	var shaft1_state: Dictionary = runtime.get_mechanical_block(shaft1_cell).get("state", {})
	var shaft2_state: Dictionary = runtime.get_mechanical_block(shaft2_cell).get("state", {})
	var isolated_state: Dictionary = runtime.get_mechanical_block(isolated_cell).get("state", {})

	if float(shaft1_state.get("rotation_speed", -1.0)) != 1.0:
		_fail("shaft1 rotation_speed expected 1.0, got %s" % shaft1_state.get("rotation_speed"))
	if float(shaft2_state.get("rotation_speed", -1.0)) != 1.0:
		_fail("shaft2 rotation_speed expected 1.0, got %s" % shaft2_state.get("rotation_speed"))
	if crank_state.get("network_id") != shaft1_state.get("network_id") or shaft1_state.get("network_id") != shaft2_state.get("network_id"):
		_fail("crank/shaft1/shaft2 should share one network_id")
	if float(crank_state.get("capacity", -1.0)) != 10.0:
		_fail("network capacity expected 10.0 (one crank), got %s" % crank_state.get("capacity"))
	if float(isolated_state.get("rotation_speed", -1.0)) != 0.0:
		_fail("isolated same-network-less shaft should have rotation_speed 0.0, got %s" % isolated_state.get("rotation_speed"))
	if isolated_state.get("network_id") == crank_state.get("network_id"):
		_fail("isolated shaft (different axis, far away) should NOT share the crank's network")

	# Visual lifecycle: one MeshInstance3D per placed block.
	if runtime.mechanical_visuals.size() != 4:
		_fail("expected 4 mechanical visuals, got %d" % runtime.mechanical_visuals.size())

	# Rotation over time: a powered shaft's mesh should actually spin.
	var shaft1_visual: MeshInstance3D = runtime.mechanical_visuals.get(mechanical_data_script.cell_key(shaft1_cell))
	var isolated_visual: MeshInstance3D = runtime.mechanical_visuals.get(mechanical_data_script.cell_key(isolated_cell))
	if shaft1_visual == null or isolated_visual == null:
		_fail("expected visuals missing from mechanical_visuals dict")
	else:
		var shaft1_rotation_before := shaft1_visual.rotation.y
		var isolated_rotation_before := isolated_visual.rotation.x
		for _tick in range(5):
			runtime._tick_mechanical_visuals(0.1)
		if is_equal_approx(shaft1_visual.rotation.y, shaft1_rotation_before):
			_fail("powered shaft1's mesh did not rotate after ticking")
		if not is_equal_approx(isolated_visual.rotation.x, isolated_rotation_before):
			_fail("unpowered isolated shaft's mesh rotated even though it has no source")

	# Removing the crank should re-resolve the chain down to speed 0.
	runtime.remove_mechanical_block(crank_cell)
	var shaft1_after_removal: Dictionary = runtime.get_mechanical_block(shaft1_cell).get("state", {})
	if float(shaft1_after_removal.get("rotation_speed", -1.0)) != 0.0:
		_fail("shaft1 rotation_speed should drop to 0.0 after removing the crank, got %s" % shaft1_after_removal.get("rotation_speed"))
	if runtime.mechanical_visuals.has(mechanical_data_script.cell_key(crank_cell)):
		_fail("crank's mesh instance should be removed from mechanical_visuals after removal")

	runtime.save_mechanical_blocks()
	save_manager.clear_save()
	runtime.free()

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("KINETIC_NETWORK_CORE_GATE_PASS")
		quit(0)
	else:
		print("KINETIC_NETWORK_CORE_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
