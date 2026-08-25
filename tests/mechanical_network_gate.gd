extends SceneTree

## Headless unit test for MechanicalNetwork (no scene tree required).
## Run with: godot --path /home/ubuntu/TEKNIK0.1 --headless -s res://tests/mechanical_network_gate.gd

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
	# Test 1: single source -> shaft chain -> consumer
	print("Test 1: source -> shaft chain -> consumer")
	var net: MechanicalNetwork = MechanicalNetwork.new()
	var water_wheel := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0,   # RPM
		64.0,   # stress capacity
		0.0
	)
	water_wheel.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(water_wheel)

	var shaft1 := MechanicalNode.new(
		MechanicalNode.NodeKind.SHAFT,
		Vector3i(1, 0, 0),
		0.0, 256.0, 0.0
	)
	shaft1.connect_face(MechanicalNode.Face.NEG_X)
	shaft1.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(shaft1)

	var shaft2 := MechanicalNode.new(
		MechanicalNode.NodeKind.SHAFT,
		Vector3i(2, 0, 0),
		0.0, 256.0, 0.0
	)
	shaft2.connect_face(MechanicalNode.Face.NEG_X)
	shaft2.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(shaft2)

	var drill := MechanicalNode.new(
		MechanicalNode.NodeKind.CONSUMER,
		Vector3i(3, 0, 0),
		0.0, 64.0, 32.0
	)
	drill.connect_face(MechanicalNode.Face.NEG_X)
	net.add_node(drill)

	net.solve()

	_assert_float(water_wheel.network_rpm, 32.0, "water wheel RPM")
	_assert_true(water_wheel.network_su > 0.0, "water wheel SU")
	_assert_false(water_wheel.overstressed, "water wheel not overstressed")

	_assert_float(shaft1.network_rpm, 32.0, "shaft1 RPM")
	_assert_false(shaft1.overstressed, "shaft1 not overstressed")

	_assert_float(shaft2.network_rpm, 32.0, "shaft2 RPM")
	_assert_false(shaft2.overstressed, "shaft2 not overstressed")

	_assert_float(drill.network_rpm, 32.0, "drill RPM")
	_assert_float(drill.network_su, 32.0, "drill SU = 32")
	_assert_false(drill.overstressed, "drill powered")
	print("  PASS")

	# Test 2: two sources at SAME RPM merge correctly
	print("Test 2: two sources same RPM")
	net = MechanicalNetwork.new()
	var source1 := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0, 64.0, 0.0
	)
	source1.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(source1)

	var source2 := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(2, 0, 0),
		32.0, 64.0, 0.0
	)
	source2.connect_face(MechanicalNode.Face.NEG_X)
	net.add_node(source2)

	var shaft := MechanicalNode.new(
		MechanicalNode.NodeKind.SHAFT,
		Vector3i(1, 0, 0),
		0.0, 256.0, 0.0
	)
	shaft.connect_face(MechanicalNode.Face.NEG_X)
	shaft.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(shaft)

	net.solve()

	_assert_float(source1.network_rpm, 32.0, "source1 RPM")
	_assert_float(source2.network_rpm, 32.0, "source2 RPM")
	_assert_float(shaft.network_rpm, 32.0, "shaft RPM")
	_assert_false(source1.overstressed, "source1 not overstressed")
	_assert_false(source2.overstressed, "source2 not overstressed")
	print("  PASS")

	# Test 3: two sources at DIFFERENT RPM -> overstress
	print("Test 3: conflicting RPM sources")
	net = MechanicalNetwork.new()
	var source_a := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0, 64.0, 0.0
	)
	source_a.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(source_a)

	var source_b := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(2, 0, 0),
		64.0, 64.0, 0.0  # different RPM!
	)
	source_b.connect_face(MechanicalNode.Face.NEG_X)
	net.add_node(source_b)

	var shaft_mid := MechanicalNode.new(
		MechanicalNode.NodeKind.SHAFT,
		Vector3i(1, 0, 0),
		0.0, 256.0, 0.0
	)
	shaft_mid.connect_face(MechanicalNode.Face.NEG_X)
	shaft_mid.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(shaft_mid)

	net.solve()

	_assert_true(source_a.overstressed, "source_a overstressed")
	_assert_true(source_b.overstressed, "source_b overstressed")
	_assert_true(shaft_mid.overstressed, "shaft_mid overstressed")
	print("  PASS")

	# Test 4: bottleneck shaft capacity < consumer demand
	print("Test 4: bottleneck capacity")
	net = MechanicalNetwork.new()
	var big_source := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0, 512.0, 0.0
	)
	big_source.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(big_source)

	var weak_shaft := MechanicalNode.new(
		MechanicalNode.NodeKind.SHAFT,
		Vector3i(1, 0, 0),
		0.0, 16.0, 0.0  # low capacity!
	)
	weak_shaft.connect_face(MechanicalNode.Face.NEG_X)
	weak_shaft.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(weak_shaft)

	var big_drill := MechanicalNode.new(
		MechanicalNode.NodeKind.CONSUMER,
		Vector3i(2, 0, 0),
		0.0, 512.0, 64.0  # needs 64 SU
	)
	big_drill.connect_face(MechanicalNode.Face.NEG_X)
	net.add_node(big_drill)

	net.solve()

	_assert_true(big_drill.overstressed, "drill overstressed (bottleneck 16 < 64)")
	_assert_float(big_drill.network_su, 0.0, "drill SU = 0")
	print("  PASS")

	# Test 5: disconnected consumer gets no power
	print("Test 5: disconnected consumer")
	net = MechanicalNetwork.new()
	var source_c := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0, 64.0, 0.0
	)
	source_c.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(source_c)

	var orphan := MechanicalNode.new(
		MechanicalNode.NodeKind.CONSUMER,
		Vector3i(10, 0, 0),
		0.0, 64.0, 32.0
	)
	# no face connections
	net.add_node(orphan)

	net.solve()

	_assert_true(orphan.overstressed, "orphan overstressed")
	_assert_float(orphan.network_su, 0.0, "orphan SU = 0")
	print("  PASS")

	# Test 6: consumer with cost 0 (idle) should not overstress
	print("Test 6: zero-cost consumer")
	net = MechanicalNetwork.new()
	var source_d := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0, 64.0, 0.0
	)
	source_d.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(source_d)

	var idle := MechanicalNode.new(
		MechanicalNode.NodeKind.CONSUMER,
		Vector3i(1, 0, 0),
		0.0, 64.0, 0.0  # cost = 0
	)
	idle.connect_face(MechanicalNode.Face.NEG_X)
	net.add_node(idle)

	net.solve()

	_assert_false(idle.overstressed, "idle not overstressed")
	print("  PASS")

	# Test 7: three consumers, supply < total demand
	print("Test 7: supply < demand")
	net = MechanicalNetwork.new()
	var source_e := MechanicalNode.new(
		MechanicalNode.NodeKind.SOURCE,
		Vector3i(0, 0, 0),
		32.0, 64.0, 0.0
	)
	source_e.connect_face(MechanicalNode.Face.POS_X)
	net.add_node(source_e)

	for i in range(3):
		var consumer := MechanicalNode.new(
			MechanicalNode.NodeKind.CONSUMER,
			Vector3i(i + 1, 0, 0),
			0.0, 64.0, 32.0
		)
		consumer.connect_face(MechanicalNode.Face.NEG_X)
		consumer.connect_face(MechanicalNode.Face.POS_X)
		net.add_node(consumer)

	net.solve()

	# All three overstressed because 64 supply < 96 demand
	for i in range(3):
		var c := net.get_node_at(Vector3i(i + 1, 0, 0)) as MechanicalNode
		_assert_true(c.overstressed, "consumer %d overstressed (supply 64 < demand 96)" % i)
		_assert_float(c.network_su, 0.0, "consumer %d SU = 0" % i)
	print("  PASS")

	# Test 8: refresh_connectivity rebuilds faces from neighbors
	print("Test 8: refresh_connectivity")
	net = MechanicalNetwork.new()
	var n1 := MechanicalNode.new(MechanicalNode.NodeKind.SHAFT, Vector3i(0, 0, 0))
	var n2 := MechanicalNode.new(MechanicalNode.NodeKind.SHAFT, Vector3i(1, 0, 0))
	n1.connect_face(MechanicalNode.Face.POS_X)
	# n2 intentionally does NOT connect NEG_X yet
	net.add_node(n1)
	net.add_node(n2)
	net.refresh_connectivity()
	_assert_false(n1.is_face_connected(MechanicalNode.Face.POS_X), "n1 disconnected before refresh")
	n2.connect_face(MechanicalNode.Face.NEG_X)
	net.refresh_connectivity()
	_assert_true(n1.is_face_connected(MechanicalNode.Face.POS_X), "n1 connected after refresh")
	_assert_true(n2.is_face_connected(MechanicalNode.Face.NEG_X), "n2 connected after refresh")
	print("  PASS")

	# Test 9: remove_node_at removes and breaks connections
	print("Test 9: remove_node_at")
	net = MechanicalNetwork.new()
	var na := MechanicalNode.new(MechanicalNode.NodeKind.SHAFT, Vector3i(0, 0, 0))
	var nb := MechanicalNode.new(MechanicalNode.NodeKind.SHAFT, Vector3i(1, 0, 0))
	na.connect_face(MechanicalNode.Face.POS_X)
	nb.connect_face(MechanicalNode.Face.NEG_X)
	net.add_node(na)
	net.add_node(nb)
	net.refresh_connectivity()
	_assert_true(na.is_face_connected(MechanicalNode.Face.POS_X), "na connected after refresh")
	_assert_true(nb.is_face_connected(MechanicalNode.Face.NEG_X), "nb connected after refresh")
	net.remove_node_at(Vector3i(0, 0, 0))
	net.refresh_connectivity()
	_assert_false(nb.is_face_connected(MechanicalNode.Face.NEG_X), "nb disconnected after removal")
	print("  PASS")

	# Test 10: stress capacity sum from multiple sources
	print("Test 10: multi-source supply sum")
	net = MechanicalNetwork.new()
	var s1 := MechanicalNode.new(MechanicalNode.NodeKind.SOURCE, Vector3i(0, 0, 0), 32.0, 64.0, 0.0)
	var s2 := MechanicalNode.new(MechanicalNode.NodeKind.SOURCE, Vector3i(0, 1, 0), 32.0, 64.0, 0.0)
	var shaft_v := MechanicalNode.new(MechanicalNode.NodeKind.SHAFT, Vector3i(0, 2, 0), 0.0, 256.0, 0.0)
	s1.connect_face(MechanicalNode.Face.POS_Y)
	s2.connect_face(MechanicalNode.Face.NEG_Y)
	s2.connect_face(MechanicalNode.Face.POS_Y)
	shaft_v.connect_face(MechanicalNode.Face.NEG_Y)
	shaft_v.connect_face(MechanicalNode.Face.POS_Y)
	net.add_node(s1)
	net.add_node(s2)
	net.add_node(shaft_v)

	var drill2 := MechanicalNode.new(MechanicalNode.NodeKind.CONSUMER, Vector3i(0, 3, 0), 0.0, 256.0, 100.0)
	drill2.connect_face(MechanicalNode.Face.NEG_Y)
	net.add_node(drill2)

	net.refresh_connectivity()
	net.solve()

	# supply = 128, demand = 100, bottleneck = 256 -> powered
	_assert_false(drill2.overstressed, "drill powered by two sources")
	_assert_float(drill2.network_su, 100.0, "drill SU = 100")
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