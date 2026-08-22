extends RefCounted
class_name CraftingRecipes

## Shapeless recipe book + pure matching helpers (moved out of the UI layer).
## A recipe matches a grid when every required (block_id, count) is covered by
## the grid contents; extra unrelated items in the grid do not block a match,
## but they are left untouched after crafting.

const RECIPES: Array[Dictionary] = [
	# 4 DIRT -> 1 STONE (test recipe)
	{
		"inputs": [{"block_id": 2, "count": 4}],
		"output": {"block_id": 3, "count": 1}
	},
	# 3 STONE + 1 DIRT -> 1 WATER_WHEEL (block 7)
	{
		"inputs": [{"block_id": 3, "count": 3}, {"block_id": 2, "count": 1}],
		"output": {"block_id": 7, "count": 1}
	},
	# 2 STONE + 2 DIRT -> 1 SHAFT (block 8)
	{
		"inputs": [{"block_id": 3, "count": 2}, {"block_id": 2, "count": 2}],
		"output": {"block_id": 8, "count": 1}
	},
	# 2 WATER_WHEEL + 1 STONE + 1 DIRT -> 1 MECHANICAL_DRILL (block 9)
	{
		"inputs": [{"block_id": 7, "count": 2}, {"block_id": 3, "count": 1}, {"block_id": 2, "count": 1}],
		"output": {"block_id": 9, "count": 1}
	},
	# 8 STONE -> 1 FURNACE (block 13)
	{
		"inputs": [{"block_id": 3, "count": 8}],
		"output": {"block_id": 13, "count": 1}
	},
	# Metal machine path: 2 IRON_INGOT + 1 COPPER_INGOT -> 1 MECHANICAL_DRILL
	{
		"inputs": [{"block_id": 14, "count": 2}, {"block_id": 15, "count": 1}],
		"output": {"block_id": 9, "count": 1}
	},
	# 1 IRON_INGOT + 2 STONE -> 2 SHAFT
	{
		"inputs": [{"block_id": 14, "count": 1}, {"block_id": 3, "count": 2}],
		"output": {"block_id": 8, "count": 2}
	},
]


static func _tally(stacks: Array) -> Dictionary:
	var available := {}
	for stack in stacks:
		var block_id := int(stack.get("block_id", 0))
		var count := int(stack.get("count", 0))
		if block_id > 0 and count > 0:
			available[block_id] = int(available.get(block_id, 0)) + count
	return available


static func empty_grid(size: int) -> Array[Dictionary]:
	var grid: Array[Dictionary] = []
	for _slot_index in range(size):
		grid.append({"block_id": 0, "count": 0})
	return grid


## First recipe whose output block id matches, or {} when none.
static func find_recipe_for_output(output_block_id: int, recipes: Array = RECIPES) -> Dictionary:
	for recipe in recipes:
		if int(recipe.get("output", {}).get("block_id", 0)) == output_block_id:
			return recipe
	return {}


static func match_recipe(grid: Array, recipe: Dictionary) -> bool:
	var available := _tally(grid)
	for req in recipe.get("inputs", []):
		var req_id := int(req.get("block_id", 0))
		var req_count := int(req.get("count", 0))
		if int(available.get(req_id, 0)) < req_count:
			return false
	return true


static func find_recipe(grid: Array, recipes: Array = RECIPES) -> Dictionary:
	for recipe in recipes:
		if match_recipe(grid, recipe):
			return recipe
	return {}


## First recipe the raw inventory can cover (ignores grid contents).
static func first_craftable_from_inventory(inventory, recipes: Array = RECIPES) -> Dictionary:
	for recipe in recipes:
		if can_craft_from_inventory(recipe, inventory):
			return recipe
	return {}


static func can_craft_from_inventory(recipe: Dictionary, inventory) -> bool:
	if inventory == null:
		return false
	var available := _tally(inventory.get_slots())
	for req in recipe.get("inputs", []):
		if int(available.get(int(req.get("block_id", 0)), 0)) < int(req.get("count", 0)):
			return false
	return true


## How many times a recipe could run with the given stacks.
static func max_craftable(recipe: Dictionary, stacks: Array) -> int:
	if recipe.is_empty():
		return 0
	var available := _tally(stacks)
	var best := -1
	for req in recipe.get("inputs", []):
		var have := int(available.get(int(req.get("block_id", 0)), 0))
		var need := int(req.get("count", 0))
		if need <= 0:
			continue
		best = (have / need) if best < 0 else mini(best, have / need)
	return maxi(best, 0)
