extends Node
class_name CraftingSystem

const CraftingRecipe = preload("res://scripts/crafting/crafting_recipe.gd")


static func can_craft(recipe: CraftingRecipe, inventory: BlockInventory) -> bool:
	if recipe == null or inventory == null:
		return false
	
	for req in recipe.required_items:
		var item_id: int = int(req.get("item_id", -1))
		var quantity: int = int(req.get("quantity", 0))
		
		if item_id <= 0 or quantity <= 0:
			return false
		
		if not inventory.has_item(item_id, quantity):
			return false
	
	return true


static func get_test_recipe() -> CraftingRecipe:
	var log_block_id := 5
	var planks_block_id := 4
	
	var recipe := CraftingRecipe.new(
		"log_to_planks",
		[{"item_id": log_block_id, "quantity": 4}],
		planks_block_id,
		1
	)
	return recipe
