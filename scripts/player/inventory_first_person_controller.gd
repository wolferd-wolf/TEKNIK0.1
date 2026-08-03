extends "res://scripts/player/first_person_controller.gd"
class_name InventoryFirstPersonController

const BLOCK_INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")

var _inventory: BlockInventory = BLOCK_INVENTORY_SCRIPT.new()
var _selected_inventory_slot: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch_radians = camera.rotation.x
	_configure_target_highlight()


func _process(delta: float) -> void:
	var action_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	if not action_look.is_zero_approx():
		apply_look_delta(action_look * action_look_speed * delta)
	_update_block_target()
	if Input.is_action_just_pressed("mine_block"):
		mine_targeted_block()
	if Input.is_action_just_pressed("place_block"):
		place_targeted_block()


func get_inventory() -> BlockInventory:
	return _inventory


func get_selected_inventory_slot() -> int:
	return _selected_inventory_slot


func get_selected_inventory_item() -> Dictionary:
	return _inventory.get_slot(_selected_inventory_slot)


func select_inventory_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _inventory.get_slot_count():
		return false
	_selected_inventory_slot = slot_index
	return true


func mine_targeted_block() -> bool:
	var target := get_block_target()
	if target.is_empty() or _chunk_manager == null:
		return false

	var mined_coord: Vector3i = target["block_coord"]
	var mined_block_id: int = _chunk_manager.get_block_world(mined_coord)
	if mined_block_id == BLOCK_AIR:
		return false
	if not _inventory.can_add_item(mined_block_id, 1):
		return false
	if not _chunk_manager.mine_block_world(mined_coord):
		return false

	if not _inventory.add_item(mined_block_id, 1):
		var restored := _chunk_manager.set_block_world(mined_coord, mined_block_id)
		if not restored:
			push_error("Inventory mining rollback failed at %s" % mined_coord)
		return false

	_clear_block_target()
	return true


func place_block_at(world_block_coord: Vector3i) -> bool:
	if not can_place_block_at(world_block_coord):
		return false

	var selected_item := get_selected_inventory_item()
	if selected_item.is_empty():
		return false
	var block_id := int(selected_item.get("block_id", BLOCK_AIR))
	var count := int(selected_item.get("count", 0))
	if block_id == BLOCK_AIR or count <= 0:
		return false
	if not _chunk_manager.place_block_world(world_block_coord, block_id):
		return false

	if not _inventory.remove_from_slot(_selected_inventory_slot, 1):
		var rolled_back := _chunk_manager.set_block_world(world_block_coord, BLOCK_AIR)
		if not rolled_back:
			push_error("Inventory placement rollback failed at %s" % world_block_coord)
		return false
	return true
