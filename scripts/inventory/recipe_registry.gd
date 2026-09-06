extends RefCounted
class_name RecipeRegistry

# Static crafting recipe list. Each recipe is single-input/single-output,
# matching BlockInventory.craft_item()'s existing signature exactly --
# deliberately not extending craft_item() to accept multiple inputs yet,
# since nothing needs it today and it's a small, safe extension to make
# later once a recipe actually requires it.
#
# Recipe shape:
# {
#   "id": String,             # stable identifier, not shown to the player
#   "name": String,           # display name
#   "input_block_id": int,
#   "input_count": int,
#   "output_block_id": int,
#   "output_count": int,
# }

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const MECHANICAL_DATA := preload("res://scripts/world/mechanical_block_data.gd")
const BLOCK_INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")

const RECIPES: Array[Dictionary] = [
	{
		"id": "shaft",
		"name": "Shaft",
		"input_block_id": WORLD_DATA.BLOCK_STONE,
		"input_count": 4,
		"output_block_id": MECHANICAL_DATA.MECH_SHAFT,
		"output_count": 1,
	},
]


static func get_recipes() -> Array[Dictionary]:
	return RECIPES


static func can_craft(inventory, recipe: Dictionary) -> bool:
	if inventory == null:
		return false
	return inventory.get_item_count(int(recipe["input_block_id"])) >= int(recipe["input_count"])


static func craft(inventory, recipe: Dictionary) -> bool:
	if not can_craft(inventory, recipe):
		return false
	return inventory.craft_item(
		int(recipe["input_block_id"]),
		int(recipe["input_count"]),
		int(recipe["output_block_id"]),
		int(recipe["output_count"])
	)
