extends Node
class_name BlockStations

## Session-side registry for placed station blocks (backend for the
## crafting table / chest / furnace rehoul).
## The furnace stays stateless: smelting still runs through the player's
## BlockInventory via FurnaceRecipes, exactly as before. The crafting table
## is stateless too: it only opens a larger craft grid in the UI. The chest
## is the one block with real per-position state, owned here.

const STATION_FURNACE := 13
const STATION_CRAFTING_TABLE := 19
const STATION_CHEST := 20
const CHEST_SLOT_COUNT := 27

signal chest_changed(coord: Vector3i)

const BLOCK_INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")

var _chests: Dictionary = {}


static func is_station_block(block_id: int) -> bool:
	return [
		STATION_FURNACE,
		STATION_CRAFTING_TABLE,
		STATION_CHEST,
	].has(block_id)


## True when placing this stack would create station state.
static func is_placeable_station(block_id: int) -> bool:
	return block_id == STATION_CHEST


func register_chest(coord: Vector3i) -> BlockInventory:
	if _chests.has(coord):
		return _chests[coord]
	var chest := BLOCK_INVENTORY_SCRIPT.new(CHEST_SLOT_COUNT)
	chest.changed.connect(func() -> void: chest_changed.emit(coord))
	_chests[coord] = chest
	return chest


func has_chest(coord: Vector3i) -> bool:
	return _chests.has(coord)


func get_chest_inventory(coord: Vector3i) -> BlockInventory:
	return register_chest(coord)


func clear_chest(coord: Vector3i) -> Array[Dictionary]:
	## Called when a chest is mined: hands back its contents snapshot and
	## forgets the position. Empty slots are filtered out by the caller.
	var chest: BlockInventory = _chests.get(coord)
	_chests.erase(coord)
	if chest == null:
		return []
	return chest.get_slots()


func chest_count() -> int:
	return _chests.size()
