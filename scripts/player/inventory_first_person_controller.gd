extends "res://scripts/player/first_person_controller.gd"
class_name InventoryFirstPersonController

const BLOCK_INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")

var _inventory: BlockInventory = BLOCK_INVENTORY_SCRIPT.new()


func get_inventory() -> BlockInventory:
	return _inventory


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
