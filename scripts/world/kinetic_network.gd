extends RefCounted
class_name KineticNetwork

# Phase 2 core: propagates rotation through connected mechanical blocks as a
# pure graph simulation -- no Jolt joints, no physics engine involved at
# all. Matches Create mod's actual approach (confirmed via source reading
# during planning): RotationPropagator assigns a signed speed ratio per
# connection, KineticNetwork aggregates connected blocks and tracks
# capacity (supply) vs stress (demand).
#
# Honest scope note for this increment: only MECH_SHAFT and MECH_HAND_CRANK
# exist. A shaft only connects to a same-axis neighbor directly ahead of or
# behind it (a straight chain) -- there's no gearbox yet to change axis or
# ratio, so every connection ratio in this version is 1.0. The ratio field
# exists now specifically so adding gears later is a new connection rule,
# not a data model change. Similarly, "stress" is always 0.0 right now --
# there's no consumer/machine block yet to demand power. The ledger exists
# so Phase 3's processing machines slot into it without redesigning this.

const MECHANICAL_DATA := preload("res://scripts/world/mechanical_block_data.gd")

const AXIS_VECTORS := {
	Vector3i.AXIS_X: Vector3i(1, 0, 0),
	Vector3i.AXIS_Y: Vector3i(0, 1, 0),
	Vector3i.AXIS_Z: Vector3i(0, 0, 1),
}

const SOURCE_TYPES := {
	MECHANICAL_DATA.MECH_HAND_CRANK: {"speed": 1.0, "capacity": 10.0},
}


# Rebuilds every network from scratch given the full set of placed
# mechanical blocks. Called on any placement/removal -- deliberately not
# incremental yet. Fine at today's scale (a handful of blocks); revisit
# with dirty-region propagation if/when block counts make a full rebuild
# show up in profiling, not before.
#
# Returns: Dictionary of cell_key (String) -> {
#   "network_id": int,
#   "rotation_speed": float,
#   "capacity": float,
#   "stress": float,
# }
static func resolve(mechanical_data) -> Dictionary:
	var cells: Array[String] = mechanical_data.get_all_cells()
	var visited := {}
	var result := {}
	var next_network_id := 0

	for cell_key in cells:
		if visited.has(cell_key):
			continue
		var component := _flood_fill(mechanical_data, cell_key, visited)
		var network_result := _resolve_component(mechanical_data, component, next_network_id)
		for member_key in network_result.keys():
			result[member_key] = network_result[member_key]
		next_network_id += 1

	return result


static func _flood_fill(mechanical_data, start_key: String, visited: Dictionary) -> Array[String]:
	var component: Array[String] = []
	var queue: Array[String] = [start_key]
	visited[start_key] = true

	while not queue.is_empty():
		var current_key: String = queue.pop_back()
		component.append(current_key)
		var current_cell := _key_to_cell(current_key)
		var entry: Dictionary = mechanical_data.get_block(current_cell)
		if entry.is_empty():
			continue
		var axis := int(entry.get("axis", Vector3i.AXIS_Y))
		var direction: Vector3i = AXIS_VECTORS.get(axis, Vector3i(0, 1, 0))

		for neighbor_cell in [current_cell + direction, current_cell - direction]:
			var neighbor_key := MECHANICAL_DATA.cell_key(neighbor_cell)
			if visited.has(neighbor_key):
				continue
			if not mechanical_data.has_block(neighbor_cell):
				continue
			var neighbor_entry: Dictionary = mechanical_data.get_block(neighbor_cell)
			# Same-axis only -- this is the whole connection rule until a
			# gearbox-equivalent block exists to bridge different axes.
			if int(neighbor_entry.get("axis", -1)) != axis:
				continue
			visited[neighbor_key] = true
			queue.append(neighbor_key)

	return component


static func _resolve_component(mechanical_data, component: Array[String], network_id: int) -> Dictionary:
	var capacity := 0.0
	var stress := 0.0
	var driven_speed := 0.0

	for member_key in component:
		var entry: Dictionary = mechanical_data.get_block(_key_to_cell(member_key))
		var type_id := int(entry.get("type_id", -1))
		if SOURCE_TYPES.has(type_id):
			var source: Dictionary = SOURCE_TYPES[type_id]
			capacity += float(source["capacity"])
			driven_speed = maxf(driven_speed, float(source["speed"]))

	# No consumer block type exists yet (Phase 3), so nothing ever demands
	# power -- a network with a crank always has capacity to spare and
	# every member just runs at the source's speed. This intentionally
	# does nothing interesting with stress yet; the field is here so
	# Phase 3 machines have somewhere to register demand without another
	# data-model change.
	var rotation_speed := driven_speed if capacity > stress else 0.0

	var result := {}
	for member_key in component:
		result[member_key] = {
			"network_id": network_id,
			"rotation_speed": rotation_speed,
			"capacity": capacity,
			"stress": stress,
		}
	return result


static func _key_to_cell(key: String) -> Vector3i:
	var parts := key.split(",")
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
