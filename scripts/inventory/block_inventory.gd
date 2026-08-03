extends RefCounted
class_name BlockInventory

signal changed

const EMPTY_BLOCK_ID := 0
const DEFAULT_SLOT_COUNT := 24
const DEFAULT_MAX_STACK_SIZE := 64

var _slot_count: int
var _max_stack_size: int
var _slots: Array[Dictionary] = []


func _init(
	slot_count: int = DEFAULT_SLOT_COUNT,
	max_stack_size: int = DEFAULT_MAX_STACK_SIZE
) -> void:
	_slot_count = maxi(slot_count, 1)
	_max_stack_size = maxi(max_stack_size, 1)
	for _slot_index in range(_slot_count):
		_slots.append(_empty_slot())


func get_slot_count() -> int:
	return _slot_count


func get_max_stack_size() -> int:
	return _max_stack_size


func get_slot(slot_index: int) -> Dictionary:
	if not _is_valid_slot(slot_index):
		return {}
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


func can_add_item(block_id: int, count: int = 1) -> bool:
	if block_id <= EMPTY_BLOCK_ID or count <= 0:
		return false
	return _available_capacity(block_id) >= count


func add_item(block_id: int, count: int = 1) -> bool:
	if not can_add_item(block_id, count):
		return false

	var remaining := count
	for slot_index in range(_slots.size()):
		var slot: Dictionary = _slots[slot_index]
		if int(slot["block_id"]) != block_id:
			continue
		var available := _max_stack_size - int(slot["count"])
		if available <= 0:
			continue
		var added := mini(available, remaining)
		slot["count"] = int(slot["count"]) + added
		_slots[slot_index] = slot
		remaining -= added
		if remaining == 0:
			changed.emit()
			return true

	for slot_index in range(_slots.size()):
		var slot: Dictionary = _slots[slot_index]
		if int(slot["block_id"]) != EMPTY_BLOCK_ID:
			continue
		var added := mini(_max_stack_size, remaining)
		_slots[slot_index] = {
			"block_id": block_id,
			"count": added,
		}
		remaining -= added
		if remaining == 0:
			changed.emit()
			return true

	if remaining == 0:
		changed.emit()
		return true
	return false


func remove_item(block_id: int, count: int = 1) -> bool:
	if block_id <= EMPTY_BLOCK_ID or count <= 0:
		return false
	if get_item_count(block_id) < count:
		return false

	var remaining := count
	for slot_index in range(_slots.size() - 1, -1, -1):
		var slot: Dictionary = _slots[slot_index]
		if int(slot["block_id"]) != block_id:
			continue
		var removed := mini(int(slot["count"]), remaining)
		var new_count := int(slot["count"]) - removed
		_slots[slot_index] = (
			_empty_slot()
			if new_count == 0
			else {"block_id": block_id, "count": new_count}
		)
		remaining -= removed
		if remaining == 0:
			changed.emit()
			return true

	if remaining == 0:
		changed.emit()
		return true
	return false


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


func _available_capacity(block_id: int) -> int:
	var capacity := 0
	for slot in _slots:
		var slot_block_id := int(slot["block_id"])
		if slot_block_id == block_id:
			capacity += _max_stack_size - int(slot["count"])
		elif slot_block_id == EMPTY_BLOCK_ID:
			capacity += _max_stack_size
	return capacity


func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _slots.size()


func _empty_slot() -> Dictionary:
	return {
		"block_id": EMPTY_BLOCK_ID,
		"count": 0,
	}
