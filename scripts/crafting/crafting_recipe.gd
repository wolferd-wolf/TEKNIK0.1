extends Resource
class_name CraftingRecipe

@export var recipe_id: String = ""
@export var required_items: Array[Dictionary] = []
@export var output_item: int = 0
@export var output_quantity: int = 1


func _init(
	id: String = "",
	inputs: Array[Dictionary] = [],
	out_item: int = 0,
	out_qty: int = 1
) -> void:
	recipe_id = id
	required_items = inputs
	output_item = out_item
	output_quantity = out_qty


func get_required_count(item_id: int) -> int:
	var total := 0
	for req in required_items:
		if int(req.get("item_id", -1)) == item_id:
			total += int(req.get("quantity", 0))
	return total
