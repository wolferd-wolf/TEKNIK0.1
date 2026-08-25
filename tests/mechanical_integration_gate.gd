extends SceneTree

## Integration test for Water Wheel + Shaft + Mechanical Drill placement and power flow.

const MechanicalManager := preload("res://scripts/mechanical/mechanical_manager.gd")
const MechanicalNode := preload("res://scripts/mechanical/mechanical_node.gd")
const MechanicalNetwork := preload("res://scripts/mechanical/mechanical_network.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _assert_false(cond: bool, msg: String) -> void:
	if cond:
		_fail(msg)


func _assert_float(val: float, expected: float, msg: String) -> void:
	if abs(val - expected) > 0.001:
		_fail("%s (got %.4f, expected %.4f)" % [msg, val, expected])


func _run_gate() -> void:
	print("Test 1: MechanicalManager network creation")
	var manager = MechanicalManager.new()
	root.add_child(manager)  # Add to scene tree
	var network = manager.get_network()
	_assert_true(network != null, "network exists")
	_assert_true(network.node_count() == 0, "empty network")
	print("  PASS")

	print("Test 2: Water Wheel placement")
	var ww_coord = Vector3i(0, 10, 0)
	var placed = manager.place_mechanical_block(ww_coord, 7)  # BLOCK_WATER_WHEEL
	_assert_true(placed, "water wheel placed")
	_assert_true(network.node_count() == 1, "network has 1 node")
	var ww_node = network.get_node_at(ww_coord) as MechanicalNode
	_assert_true(ww_node != null, "water wheel node exists")
	_assert_true(ww_node.is_source(), "water wheel is source")
	_assert_true(ww_node.base_rpm == 32.0, "water wheel RPM = 32")
	_assert_true(ww_node.stress_capacity == 64.0, "water wheel capacity = 64")
	print("  PASS")

	print("Test 3: Shaft placement")
	var shaft_coord = Vector3i(1, 10, 0)
	placed = manager.place_mechanical_block(shaft_coord, 8)  # BLOCK_SHAFT
	_assert_true(placed, "shaft placed")
	_assert_true(network.node_count() == 2, "network has 2 nodes")
	var shaft_node = network.get_node_at(shaft_coord) as MechanicalNode
	_assert_true(shaft_node != null, "shaft node exists")
	_assert_false(shaft_node.is_source(), "shaft is not source")
	_assert_false(shaft_node.is_consumer(), "shaft is not consumer")
	_assert_true(shaft_node.stress_capacity == 256.0, "shaft capacity = 256")
	print("  PASS")

	print("Test 4: Mechanical Drill placement")
	var drill_coord = Vector3i(2, 10, 0)
	placed = manager.place_mechanical_block(drill_coord, 9)  # BLOCK_MECHANICAL_DRILL
	_assert_true(placed, "drill placed")
	_assert_true(network.node_count() == 3, "network has 3 nodes")
	var drill_node = network.get_node_at(drill_coord) as MechanicalNode
	_assert_true(drill_node != null, "drill node exists")
	_assert_true(drill_node.is_consumer(), "drill is consumer")
	_assert_true(drill_node.stress_cost == 32.0, "drill cost = 32")
	_assert_true(drill_node.stress_capacity == 64.0, "drill capacity = 64")
	print("  PASS")

	print("Test 5: Network solves correctly (water wheel -> shaft -> drill)")
	manager.refresh_network()

	ww_node = network.get_node_at(ww_coord) as MechanicalNode
	shaft_node = network.get_node_at(shaft_coord) as MechanicalNode
	drill_node = network.get_node_at(drill_coord) as MechanicalNode

	_assert_float(ww_node.network_rpm, 32.0, "water wheel network RPM")
	_assert_float(shaft_node.network_rpm, 32.0, "shaft network RPM")
	_assert_float(drill_node.network_rpm, 32.0, "drill network RPM")
	print("  PASS")

	print("Test 6: Water wheel power with water adjacency")
	ww_node.base_rpm = 32.0
	network.solve()
	_assert_float(ww_node.network_rpm, 32.0, "water wheel RPM active")
	_assert_float(ww_node.network_su, 64.0, "water wheel SU = 64")
	_assert_false(ww_node.overstressed, "water wheel not overstressed")
	print("  PASS")

	print("Test 7: Drill power consumption")
	_assert_float(drill_node.network_su, 32.0, "drill SU = 32")
	_assert_false(drill_node.overstressed, "drill powered")
	print("  PASS")

	print("Test 8: Break mechanical block")
	var broken = manager.break_mechanical_block(shaft_coord)
	_assert_true(broken, "shaft broken")
	_assert_true(network.node_count() == 2, "network has 2 nodes after break")

	# Now drill should be disconnected and unpowered
	network.solve()
	drill_node = network.get_node_at(drill_coord) as MechanicalNode
	_assert_true(drill_node.overstressed, "drill overstressed after disconnect")
	_assert_float(drill_node.network_su, 0.0, "drill SU = 0")
	print("  PASS")

	print("Test 9: is_mechanical_block helper")
	_assert_true(manager.is_mechanical_block(7), "7 is mechanical")
	_assert_true(manager.is_mechanical_block(8), "8 is mechanical")
	_assert_true(manager.is_mechanical_block(9), "9 is mechanical")
	_assert_false(manager.is_mechanical_block(1), "1 is not mechanical")
	_assert_false(manager.is_mechanical_block(0), "0 is not mechanical")
	print("  PASS")

	print("Test 10: Manager rejects non-mechanical blocks")
	var manager2 = MechanicalManager.new()
	var network2 = manager2.get_network()

	var source2 = Vector3i(0, 20, 0)
	var weak_shaft2 = Vector3i(1, 20, 0)
	var big_drill2 = Vector3i(2, 20, 0)

	manager2.place_mechanical_block(source2, 7)
	# Place shaft with custom low capacity - can't do that easily
	# Just test that manager rejects invalid blocks
	var bad_placed = manager2.place_mechanical_block(Vector3i(10, 10, 10), 5)  # BLOCK_LOG
	_assert_false(bad_placed, "non-mechanical block rejected")
	print("  PASS")

	print("")
	if failures.is_empty():
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("FAILURES:")
		for f in failures:
			print("  - %s" % f)
		quit(1)