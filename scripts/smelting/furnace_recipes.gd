class_name FurnaceRecipes
extends RefCounted

## Furnace smelting contract (build plan step 15).
## Pure static policy over block ids so gates can verify the whole loop
## without booting the scene tree. The placed furnace block (id 13) is the
## in-world station; the UI panel drives these functions through the
## player's BlockInventory only, so there is no extra persistent state.

const INPUT_ORE_IRON := 11
const INPUT_ORE_COPPER := 12
const OUTPUT_INGOT_IRON := 14
const OUTPUT_INGOT_COPPER := 15
const FUEL_COAL := 16
const FUEL_LOG := 5

## Ore -> ingot. Unknown inputs return 0 (no-op).
const SMELT_MAP := {
	INPUT_ORE_IRON: OUTPUT_INGOT_IRON,
	INPUT_ORE_COPPER: OUTPUT_INGOT_COPPER,
}

## Items accepted as fuel. One fuel item powers one smelt operation.
const FUEL_SET := [FUEL_COAL, FUEL_LOG]


static func smelt_output_for(input_block_id: int) -> int:
	return int(SMELT_MAP.get(input_block_id, 0))


static func is_fuel(block_id: int) -> bool:
	return FUEL_SET.has(block_id)


## What a mined block adds to the inventory. Coal ore breaks into coal fuel;
## everything else drops itself.
static func mining_drop_for(block_id: int) -> int:
	if block_id == 10: # BLOCK_COAL_ORE
		return FUEL_COAL
	return block_id


## Consume one smelt operation from the inventory:
## 1 smeltable input + 1 fuel item -> 1 ingot.
## Returns a report dict; "ok" false carries the reason.
static func smelt_once(inventory) -> Dictionary:
	if inventory == null:
		return {"ok": false, "reason": "no_inventory"}
	var input_id := 0
	for candidate in SMELT_MAP.keys():
		if inventory.has_item(int(candidate), 1):
			input_id = int(candidate)
			break
	if input_id == 0:
		return {"ok": false, "reason": "no_input"}
	var fuel_id := 0
	for candidate in FUEL_SET:
		if inventory.has_item(int(candidate), 1):
			fuel_id = int(candidate)
			break
	if fuel_id == 0:
		return {"ok": false, "reason": "no_fuel"}
	var output_id := smelt_output_for(input_id)
	if not inventory.can_add_item(output_id, 1):
		return {"ok": false, "reason": "output_full"}
	if not inventory.remove_item(input_id, 1):
		return {"ok": false, "reason": "input_remove_failed"}
	if not inventory.remove_item(fuel_id, 1):
		inventory.add_item(input_id, 1) # rollback input
		return {"ok": false, "reason": "fuel_remove_failed"}
	if not inventory.add_item(output_id, 1):
		inventory.add_item(input_id, 1)
		inventory.add_item(fuel_id, 1)
		return {"ok": false, "reason": "output_add_failed"}
	return {
		"ok": true,
		"input": input_id,
		"fuel": fuel_id,
		"output": output_id,
	}
