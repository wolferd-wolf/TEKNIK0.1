class_name MechanicalNetwork
extends RefCounted

## Rotational power network solver (Create-style SU model).
## A network is an undirected graph of MechanicalNode components connected
## face-to-face. Each connected component is solved independently:
##   - RPM is the stress-capacity-weighted average of all SOURCE nodes.
##   - Supply SU is the sum of source stress capacities.
##   - Demand SU is the sum of consumer stress costs.
##   - A consumer is powered only if supply >= demand AND the bottleneck
##     stress capacity along its path from a source >= its stress cost.
##   - A component with sources at conflicting RPM is blocked (overstressed).

const RPM_EPSILON := 0.001

var nodes: Dictionary = {}  # Vector3i -> MechanicalNode


func add_node(node: MechanicalNode) -> void:
	nodes[node.world_coord] = node


func remove_node_at(coord: Vector3i) -> bool:
	return nodes.erase(coord)


func get_node_at(coord: Vector3i) -> MechanicalNode:
	return nodes.get(coord, null)


func has_node_at(coord: Vector3i) -> bool:
	return nodes.has(coord)


func clear() -> void:
	nodes.clear()


func node_count() -> int:
	return nodes.size()


## Rebuild each node's connection set from its current face flags plus the
## matching opposite face on its neighbor. Call this after placement/break.
func refresh_connectivity() -> void:
	for coord in nodes.keys():
		var node := nodes[coord] as MechanicalNode
		for face_index in range(MechanicalNode.FACE_DIRECTIONS.size()):
			var neighbor_coord := node.neighbor_coord(face_index)
			if nodes.has(neighbor_coord):
				var neighbor := nodes[neighbor_coord] as MechanicalNode
				var opposite := face_index ^ 1
				if neighbor.is_face_connected(opposite):
					node.connect_face(face_index)
				else:
					node.disconnect_face(face_index)
			else:
				node.disconnect_face(face_index)


## Solve the whole network, filling each node's network_rpm / network_su /
## overstressed fields.
func solve() -> void:
	for node in nodes.values():
		node.network_rpm = 0.0
		node.network_su = 0.0
		node.overstressed = false

	var adjacency := _build_adjacency()
	var visited: Dictionary = {}
	for coord in nodes.keys():
		if visited.has(coord):
			continue
		var component: Array[Vector3i] = []
		var queue: Array[Vector3i] = [coord]
		visited[coord] = true
		while queue.size() > 0:
			var current := queue.pop_front() as Vector3i
			component.append(current)
			for neighbor in adjacency[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		_solve_component(component, adjacency)


func _build_adjacency() -> Dictionary:
	var adjacency: Dictionary = {}
	for coord in nodes.keys():
		adjacency[coord] = []
	for coord in nodes.keys():
		var node := nodes[coord] as MechanicalNode
		for face_index in range(MechanicalNode.FACE_DIRECTIONS.size()):
			if not node.is_face_connected(face_index):
				continue
			var neighbor_coord := node.neighbor_coord(face_index)
			if not nodes.has(neighbor_coord):
				continue
			var neighbor := nodes[neighbor_coord] as MechanicalNode
			var opposite := face_index ^ 1
			if neighbor.is_face_connected(opposite):
				adjacency[coord].append(neighbor_coord)
	return adjacency


func _solve_component(component: Array[Vector3i], adjacency: Dictionary) -> void:
	var sources: Array[MechanicalNode] = []
	var consumers: Array[MechanicalNode] = []
	var shafts: Array[MechanicalNode] = []
	for coord in component:
		var node := nodes[coord] as MechanicalNode
		if node.is_source():
			sources.append(node)
		elif node.is_consumer():
			consumers.append(node)
		else:
			shafts.append(node)

	if sources.is_empty():
		# No sources in this component -> all consumers are unpowered (overstressed)
		for consumer in consumers:
			consumer.network_rpm = 0.0
			consumer.network_su = 0.0
			consumer.overstressed = true
		return

	# Conflicting-speed detection: two sources at materially different RPM
	# cannot share one rigid component (Create blocks it).
	var base_rpm := sources[0].base_rpm
	for source in sources:
		if abs(source.base_rpm - base_rpm) > RPM_EPSILON:
			for coord in component:
				(nodes[coord] as MechanicalNode).overstressed = true
			return

	# Network stress = sum of all source stress capacities (Create SU model).
	var rpm_weight := 0.0
	var rpm_denom := 0.0
	var supply := 0.0
	for source in sources:
		rpm_weight += source.base_rpm * source.stress_capacity
		rpm_denom += source.stress_capacity
		supply += source.stress_capacity
	var rpm := rpm_weight / rpm_denom if rpm_denom > 0.0 else 0.0

	var demand := 0.0
	for consumer in consumers:
		demand += consumer.stress_cost

	# A component is overstressed if network stress exceeds any transmission
	# node's capacity, OR total demand exceeds total supply.
	var transmission_overstressed := false
	for shaft in shafts:
		if supply > shaft.stress_capacity:
			transmission_overstressed = true
			break

	for coord in component:
		var node := nodes[coord] as MechanicalNode
		node.network_rpm = rpm
		node.overstressed = false
		node.network_su = 0.0

	# Sources are never overstressed: they generate stress, they do not
	# transmit it beyond their own generation.
	for source in sources:
		source.network_su = source.stress_capacity

	for shaft in shafts:
		shaft.overstressed = transmission_overstressed

	for consumer in consumers:
		var powered := (not transmission_overstressed) and supply >= demand and supply >= consumer.stress_cost
		consumer.network_su = consumer.stress_cost if powered else 0.0
		consumer.overstressed = not powered


## Debug representation for the overlay (added in a later step).
func debug_lines() -> Array[String]:
	var lines: Array[String] = []
	for coord in nodes.keys():
		var node := nodes[coord] as MechanicalNode
		var kind := "shaft"
		if node.is_source():
			kind = "source"
		elif node.is_consumer():
			kind = "consumer"
		lines.append(
			"%s @ %s rpm=%.2f su=%.1f%s" % [
				kind, coord, node.network_rpm, node.network_su,
				" OVERSTRESSED" if node.overstressed else ""
			]
		)
	return lines
