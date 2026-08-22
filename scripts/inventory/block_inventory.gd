extends RefCounted
class_name BlockInventory

## Player inventory data layer (rewritten).
## Owns: 9 hotbar + 27 storage slots, plus the 2x2 craft grid as real state.
## The UI is dumb: it only calls transfer operations here. No meta hacks.
## Stack shape: {"block_id": int, "count": int}; empty slot = {"block_id": 0, "count": 0}.

signal changed

const EMPTY_BLOCK_ID := 0
const HOTBAR_SLOT_COUNT := 9
const STORAGE_SLOT_COUNT := 27
const DEFAULT_SLOT_COUNT := HOTBAR_SLOT_COUNT + STORAGE_SLOT_COUNT
const DEFAULT_MAX_STACK_SIZE := 64
const CRAFT_GRID_SIZE := 4

var _slot_count: int
var _max_stack_size: int
var _slots: Array[Dictionary] = []
var _craft_grid: Array[Dictionary] = []


func _init(
	slot_count: int = DEFAULT_SLOT_COUNT,
	max_stack_size: int = DEFAULT_MAX_STACK_SIZE
) -> void:
	_slot_count = maxi(slot_count, 1)
	_max_stack_size = maxi(max_stack_size, 1)
	for _slot_index in range(_slot_count):
		_slots.append(_empty_slot())
	for _grid_index in range(CRAFT_GRID_SIZE):
		_craft_grid.append(_empty_slot())


# ---------------------------------------------------------------- read access

func get_slot_count() -> int:
	return _slot_count


func get_hotbar_slot_count() -> int:
	return mini(HOTBAR_SLOT_COUNT, _slot_count)


func get_storage_slot_count() -> int:
	return maxi(_slot_count - get_hotbar_slot_count(), 0)


func get_max_stack_size() -> int:
	return _max_stack_size


func get_slot(slot_index: int) -> Dictionary:
	if not _is_valid_slot(slot_index):
		return _empty_slot()
	return _slots[slot_index].duplicate(true)


func get_slots() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for slot in _slots:
		snapshot.append(slot.duplicate(true))
	return snapshot


func get_item_count(block_id: int) -> int:
	if block_id <= EMPTY_BLOCK_ID:
		return 0
	var total := 0
	for slot in _slots:
		if int(slot["block_id"]) == block_id:
			total += int(slot["count"])
	return total


func find_first_slot(block_id: int) -> int:
	if block_id <= EMPTY_BLOCK_ID:
		return -1
	for slot_index in range(_slots.size()):
		if int(_slots[slot_index]["block_id"]) == block_id:
			return slot_index
	return -1


func has_item(block_id: int, count: int = 1) -> bool:
	return count > 0 and get_item_count(block_id) >= count


func is_empty() -> bool:
	for slot in _slots:
		if int(slot["count"]) > 0:
			return false
	return true


func is_full() -> bool:
	for slot in _slots:
		if int(slot["count"]) < _max_stack_size:
			return false
	return true


# ---------------------------------------------------------------- mutations

func can_add_item(block_id: int, count: int = 1) -> bool:
	if block_id <= EMPTY_BLOCK_ID or count <= 0:
		return false
	return _available_capacity(block_id) >= count


func add_item(block_id: int, count: int = 1) -> bool:
	if not can_add_item(block_id, count):
		return false
	var staged := _snapshot_slots()
	if not _add_item_to_slots(staged, block_id, count):
		return false
	_slots = staged
	changed.emit()
	return true


func remove_item(block_id: int, count: int = 1) -> bool:
	if block_id <= EMPTY_BLOCK_ID or count <= 0:
		return false
	if get_item_count(block_id) < count:
		return false
	var staged := _snapshot_slots()
	if not _remove_item_from_slots(staged, block_id, count):
		return false
	_slots = staged
	changed.emit()
	return true


func remove_from_slot(slot_index: int, count: int = 1) -> bool:
	if not _is_valid_slot(slot_index) or count <= 0:
		return false
	var slot: Dictionary = _slots[slot_index]
	var current_count := int(slot["count"])
	if current_count < count:
		return false
	var new_count := current_count - count
	_slots[slot_index] = (
		_empty_slot()
		if new_count == 0
		else {"block_id": int(slot["block_id"]), "count": new_count}
	)
	changed.emit()
	return true


## Direct overwrite used by tests and save/restore paths.
func set_slot_stack(slot_index: int, stack: Dictionary) -> void:
	if not _is_valid_slot(slot_index):
		return
	_slots[slot_index] = _normalize_stack(stack)
	changed.emit()


func take_from_slot(slot_index: int, count: int = -1) -> Dictionary:
	if not _is_valid_slot(slot_index) or count == 0:
		return _empty_slot()
	var slot: Dictionary = _slots[slot_index]
	var current_count := int(slot["count"])
	if current_count <= 0:
		return _empty_slot()
	var take_count := current_count if count < 0 else mini(count, current_count)
	var remainder := current_count - take_count
	_slots[slot_index] = (
		_empty_slot()
		if remainder == 0
		else {"block_id": int(slot["block_id"]), "count": remainder}
	)
	changed.emit()
	return {"block_id": int(slot["block_id"]), "count": take_count}


func split_from_slot(slot_index: int) -> Dictionary:
	if not _is_valid_slot(slot_index):
		return _empty_slot()
	var current_count := int(_slots[slot_index]["count"])
	if current_count <= 0:
		return _empty_slot()
	return take_from_slot(slot_index, ceili(float(current_count) * 0.5))


func put_stack_into_slot(
	slot_index: int,
	incoming_stack: Dictionary,
	single_item: bool = false
) -> Dictionary:
	var incoming := _normalize_stack(incoming_stack)
	if int(incoming["count"]) <= 0:
		return _empty_slot()
	if not _is_valid_slot(slot_index):
		return incoming

	var incoming_block_id := int(incoming["block_id"])
	var incoming_count := int(incoming["count"])
	var target: Dictionary = _slots[slot_index]
	var target_block_id := int(target["block_id"])
	var target_count := int(target["count"])

	if target_count == 0:
		var placed := 1 if single_item else mini(incoming_count, _max_stack_size)
		_slots[slot_index] = {"block_id": incoming_block_id, "count": placed}
		changed.emit()
		return _stack_or_empty(incoming_block_id, incoming_count - placed)

	if target_block_id == incoming_block_id:
		var capacity := _max_stack_size - target_count
		if capacity <= 0:
			return incoming
		var requested := 1 if single_item else incoming_count
		var merged := mini(capacity, requested)
		target["count"] = target_count + merged
		_slots[slot_index] = target
		changed.emit()
		return _stack_or_empty(incoming_block_id, incoming_count - merged)

	if single_item or incoming_count > _max_stack_size:
		return incoming

	_slots[slot_index] = incoming
	changed.emit()
	return target.duplicate(true)


## Shift-click: move a whole stack between the hotbar and storage halves.
## Returns true when the stack fully left its region.
func quick_move_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false
	var source: Dictionary = _slots[slot_index]
	if int(source["count"]) <= 0:
		return false
	var hotbar_count := get_hotbar_slot_count()
	var in_hotbar := slot_index < hotbar_count
	var search_from := hotbar_count if in_hotbar else 0
	var search_to := _slot_count if in_hotbar else hotbar_count

	var staged := _snapshot_slots()
	var moving_block_id := int(staged[slot_index]["block_id"])
	var moving_count := int(staged[slot_index]["count"])

	# merge into existing stacks in the destination region
	for target_index in range(search_from, search_to):
		if moving_count == 0:
			break
		var target: Dictionary = staged[target_index]
		if int(target["block_id"]) != moving_block_id:
			continue
		var capacity := _max_stack_size - int(target["count"])
		if capacity <= 0:
			continue
		var merged := mini(capacity, moving_count)
		target["count"] = int(target["count"]) + merged
		staged[target_index] = target
		moving_count -= merged

	# then into empty destination slots
	for target_index in range(search_from, search_to):
		if moving_count == 0:
			break
		if int(staged[target_index]["block_id"]) != EMPTY_BLOCK_ID:
			continue
		var placed := mini(_max_stack_size, moving_count)
		staged[target_index] = {"block_id": moving_block_id, "count": placed}
		moving_count -= placed

	if moving_count == int(staged[slot_index]["count"]):
		return false # nothing fit
	staged[slot_index] = _stack_or_empty(moving_block_id, moving_count)
	_slots = staged
	changed.emit()
	return true


## Merge every stack pair and defrag toward the hotbar. Frees scattered slots.
func compact() -> int:
	## Tidy within regions: hotbar slots compact among themselves, storage
	## among themselves, so muscle memory positions survive a TIDY press.
	var freed := 0
	var hotbar_count := get_hotbar_slot_count()
	_compact_region(_slots, 0, hotbar_count)
	_compact_region(_slots, hotbar_count, _slots.size())
	for slot in _slots:
		if int(slot["count"]) <= 0:
			freed += 1
	changed.emit()
	return freed


func _compact_region(slots: Array[Dictionary], begin_index: int, end_index: int) -> void:
	var totals := {}
	var order: Array[int] = []
	for index in range(begin_index, end_index):
		var slot: Dictionary = slots[index]
		if int(slot["count"]) <= 0:
			continue
		var id := int(slot["block_id"])
		if not totals.has(id):
			totals[id] = 0
			order.append(id)
		totals[id] = int(totals[id]) + int(slot["count"])
	var write := begin_index
	for id in order:
		var left := int(totals[id])
		while left > 0 and write < end_index:
			var put := mini(left, _max_stack_size)
			slots[write] = {"block_id": id, "count": put}
			left -= put
			write += 1
	for index in range(write, end_index):
		slots[index] = _empty_slot()


# ---------------------------------------------------------------- craft grid

func get_craft_grid() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for slot in _craft_grid:
		snapshot.append(slot.duplicate(true))
	return snapshot


func get_craft_slot(craft_index: int) -> Dictionary:
	if not _is_valid_craft_index(craft_index):
		return _empty_slot()
	return _craft_grid[craft_index].duplicate(true)


## Place a stack (or one item of it) into a grid slot; returns the remainder.
func set_craft_slot(craft_index: int, stack: Dictionary, single_item: bool = false) -> Dictionary:
	if not _is_valid_craft_index(craft_index):
		return _normalize_stack(stack)
	var incoming := _normalize_stack(stack)
	if int(incoming["count"]) <= 0:
		return _empty_slot()
	var target: Dictionary = _craft_grid[craft_index]
	var target_id := int(target["block_id"])
	var target_count := int(target["count"])
	var incoming_id := int(incoming["block_id"])
	var incoming_count := int(incoming["count"])

	if target_count == 0:
		var placed := 1 if single_item else mini(incoming_count, _max_stack_size)
		_craft_grid[craft_index] = {"block_id": incoming_id, "count": placed}
		changed.emit()
		return _stack_or_empty(incoming_id, incoming_count - placed)
	if target_id == incoming_id:
		var capacity := _max_stack_size - target_count
		var requested := 1 if single_item else incoming_count
		var merged := mini(maxi(capacity, 0), requested)
		_craft_grid[craft_index] = {"block_id": target_id, "count": target_count + merged}
		changed.emit()
		return _stack_or_empty(incoming_id, incoming_count - merged)
	if single_item:
		return incoming
	# swap
	_craft_grid[craft_index] = {"block_id": incoming_id, "count": incoming_count}
	changed.emit()
	return {"block_id": target_id, "count": target_count}


func take_craft_slot(craft_index: int) -> Dictionary:
	if not _is_valid_craft_index(craft_index):
		return _empty_slot()
	var taken: Dictionary = _craft_grid[craft_index].duplicate(true)
	_craft_grid[craft_index] = _empty_slot()
	if int(taken["count"]) > 0:
		changed.emit()
	return taken


func split_craft_slot(craft_index: int) -> Dictionary:
	if not _is_valid_craft_index(craft_index):
		return _empty_slot()
	var current_count := int(_craft_grid[craft_index]["count"])
	if current_count <= 1:
		return _empty_slot()
	var take := current_count / 2
	var block_id := int(_craft_grid[craft_index]["block_id"])
	_craft_grid[craft_index] = {"block_id": block_id, "count": current_count - take}
	changed.emit()
	return {"block_id": block_id, "count": take}


## Consume one craft: removes the recipe inputs from the grid (exact counts,
## spread across grid slots), leaving other grid contents untouched.
## Returns the leftover grid snapshot.
func consume_grid_inputs(recipe: Dictionary) -> Array[Dictionary]:
	var staged: Array[Dictionary] = []
	for slot in _craft_grid:
		staged.append(slot.duplicate(true))
	for req in recipe.get("inputs", []):
		var need := int(req.get("count", 0))
		var want_id := int(req.get("block_id", 0))
		for grid_index in range(staged.size()):
			if need <= 0:
				break
			var slot: Dictionary = staged[grid_index]
			if int(slot["block_id"]) != want_id:
				continue
			var take := mini(int(slot["count"]), need)
			var left := int(slot["count"]) - take
			staged[grid_index] = _stack_or_empty(want_id, left)
			need -= take
	_craft_grid = staged
	changed.emit()
	return get_craft_grid()


## Return every grid item to the inventory. Returns the number of items
## that could NOT be returned (inventory full); those stay in the grid.
func return_craft_grid_to_inventory() -> int:
	var stranded := 0
	for craft_index in range(CRAFT_GRID_SIZE):
		var stack: Dictionary = _craft_grid[craft_index]
		if int(stack["count"]) <= 0:
			continue
		var block_id := int(stack["block_id"])
		var count := int(stack["count"])
		if add_item(block_id, count):
			_craft_grid[craft_index] = _empty_slot()
		else:
			# return as much as fits
			var space := _available_capacity(block_id)
			var moved := maxi(space, 0)
			if moved > 0 and add_item(block_id, moved):
				var left := count - moved
				_craft_grid[craft_index] = _stack_or_empty(block_id, left)
				stranded += left
			else:
				stranded += count
	if stranded == 0:
		changed.emit()
	return stranded


# ---------------------------------------------------------------- legacy craft

func craft_item(
	input_block_id: int,
	input_count: int,
	output_block_id: int,
	output_count: int
) -> bool:
	if (
		input_block_id <= EMPTY_BLOCK_ID
		or output_block_id <= EMPTY_BLOCK_ID
		or input_count <= 0
		or output_count <= 0
	):
		return false
	if get_item_count(input_block_id) < input_count:
		return false

	var staged_slots := _snapshot_slots()
	if not _remove_item_from_slots(staged_slots, input_block_id, input_count):
		return false
	if not _add_item_to_slots(staged_slots, output_block_id, output_count):
		return false

	_slots = staged_slots
	changed.emit()
	return true


# ---------------------------------------------------------------- internals

func _snapshot_slots() -> Array[Dictionary]:
	var staged: Array[Dictionary] = []
	for slot in _slots:
		staged.append(slot.duplicate(true))
	return staged


func _add_item_to_slots(slots: Array[Dictionary], block_id: int, count: int) -> bool:
	var remaining := count
	for slot_index in range(slots.size()):
		var slot: Dictionary = slots[slot_index]
		if int(slot["block_id"]) != block_id:
			continue
		var available := _max_stack_size - int(slot["count"])
		if available <= 0:
			continue
		var added := mini(available, remaining)
		slot["count"] = int(slot["count"]) + added
		slots[slot_index] = slot
		remaining -= added
		if remaining == 0:
			return true
	for slot_index in range(slots.size()):
		if int(slots[slot_index]["block_id"]) != EMPTY_BLOCK_ID:
			continue
		var added := mini(_max_stack_size, remaining)
		slots[slot_index] = {"block_id": block_id, "count": added}
		remaining -= added
		if remaining == 0:
			return true
	return remaining == 0


func _remove_item_from_slots(slots: Array[Dictionary], block_id: int, count: int) -> bool:
	var remaining := count
	for slot_index in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[slot_index]
		if int(slot["block_id"]) != block_id:
			continue
		var removed := mini(int(slot["count"]), remaining)
		var new_count := int(slot["count"]) - removed
		slots[slot_index] = (
			_empty_slot()
			if new_count == 0
			else {"block_id": block_id, "count": new_count}
		)
		remaining -= removed
		if remaining == 0:
			return true
	return remaining == 0


func _available_capacity(block_id: int) -> int:
	var capacity := 0
	for slot in _slots:
		var slot_block_id := int(slot["block_id"])
		if slot_block_id == block_id:
			capacity += _max_stack_size - int(slot["count"])
		elif slot_block_id == EMPTY_BLOCK_ID:
			capacity += _max_stack_size
	return capacity


func _normalize_stack(stack: Dictionary) -> Dictionary:
	var block_id := int(stack.get("block_id", EMPTY_BLOCK_ID))
	var count := int(stack.get("count", 0))
	return _stack_or_empty(block_id, count)


func _stack_or_empty(block_id: int, count: int) -> Dictionary:
	if block_id <= EMPTY_BLOCK_ID or count <= 0:
		return _empty_slot()
	return {"block_id": block_id, "count": count}


func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _slots.size()


func _is_valid_craft_index(craft_index: int) -> bool:
	return craft_index >= 0 and craft_index < CRAFT_GRID_SIZE


func _empty_slot() -> Dictionary:
	return {"block_id": EMPTY_BLOCK_ID, "count": 0}
