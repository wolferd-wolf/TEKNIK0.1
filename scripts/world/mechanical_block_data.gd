extends RefCounted

# Storage for non-voxel mechanical blocks (shafts, gears, machines, etc.).
#
# Kept separate from playable_world_data.gd's `overrides` dictionary because
# mechanical blocks carry more than a single block_id: they need an axis/
# orientation and a per-block state dict (network id, recipe progress, ...)
# that plain voxel overrides have no room for.
#
# Follows the same "x,y,z" string-keyed Dictionary convention as
# playable_world_data.gd's overrides so it serializes to JSON the same way
# and stays consistent with the rest of the save format.
#
# Entry shape stored per cell:
# {
#   "type_id": int,
#   "axis": int,      # Vector3i.AXIS_X / AXIS_Y / AXIS_Z
#   "state": Dictionary,
# }

var _blocks: Dictionary = {}


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


func has_block(cell: Vector3i) -> bool:
	return _blocks.has(cell_key(cell))


func place_block(cell: Vector3i, type_id: int, axis: int) -> bool:
	if has_block(cell):
		return false
	_blocks[cell_key(cell)] = {
		"type_id": type_id,
		"axis": axis,
		"state": {},
	}
	return true


func remove_block(cell: Vector3i) -> bool:
	return _blocks.erase(cell_key(cell))


func get_block(cell: Vector3i) -> Dictionary:
	var entry: Variant = _blocks.get(cell_key(cell), {})
	return entry if entry is Dictionary else {}


func get_block_state(cell: Vector3i) -> Dictionary:
	var entry := get_block(cell)
	var state: Variant = entry.get("state", {})
	return state if state is Dictionary else {}


func set_block_state(cell: Vector3i, state: Dictionary) -> bool:
	var key := cell_key(cell)
	if not _blocks.has(key):
		return false
	_blocks[key]["state"] = state
	return true


func get_all_cells() -> Array[String]:
	var keys: Array[String] = []
	keys.assign(_blocks.keys())
	return keys


func count() -> int:
	return _blocks.size()


# Returns a plain Dictionary suitable for JSON.stringify via SaveManager.
func to_save_dict() -> Dictionary:
	return _blocks.duplicate(true)


# Replaces all current blocks with the contents of a previously-saved dict.
# Tolerant of malformed/missing entries so an old or hand-edited save file
# degrades to "no mechanical blocks" instead of crashing.
func load_from_save_dict(saved: Dictionary) -> void:
	_blocks = {}
	for key in saved.keys():
		var entry: Variant = saved[key]
		if not (entry is Dictionary):
			continue
		if not entry.has("type_id"):
			continue
		_blocks[key] = {
			"type_id": int(entry.get("type_id", 0)),
			"axis": int(entry.get("axis", Vector3i.AXIS_X)),
			"state": entry.get("state", {}) if entry.get("state", {}) is Dictionary else {},
		}
