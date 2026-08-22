extends SceneTree

## Furnace smelting gate (build plan steps 15-16).
## Verifies the whole smelting loop over a real BlockInventory:
##  - ore -> ingot mapping and fuel acceptance
##  - coal ore mining drop becomes coal fuel
##  - smelt consumes exactly 1 input + 1 fuel per ingot
##  - failure modes: no input, no fuel, full inventory (rollback intact)
##  - crafting screen exposes furnace block recipe + metal machine recipes
##  - block names cover every new id

const INVENTORY := preload("res://scripts/inventory/block_inventory.gd")
const FURNACE := preload("res://scripts/smelting/furnace_recipes.gd")
const SCREEN := preload("res://scripts/ui/minecraft_inventory_screen.gd")

var failures: Array[String] = []
var checks := 0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 10:
		if not failures.has(message):
			failures.append(message)


func _init() -> void:
	# --- mapping contract
	_expect(FURNACE.smelt_output_for(11) == 14, "iron ore must smelt to iron ingot")
	_expect(FURNACE.smelt_output_for(12) == 15, "copper ore must smelt to copper ingot")
	_expect(FURNACE.smelt_output_for(3) == 0, "stone must not smelt")
	_expect(FURNACE.smelt_output_for(0) == 0, "air must not smelt")
	_expect(FURNACE.smelt_output_for(4) == 17, "sand must smelt to glass")
	_expect(FURNACE.smelt_output_for(5) == 18, "log must smelt to charcoal")
	_expect(FURNACE.is_fuel(16), "coal must be fuel")
	_expect(FURNACE.is_fuel(18), "charcoal must be fuel")
	_expect(FURNACE.is_fuel(5), "log must be fuel")
	_expect(not FURNACE.is_fuel(3), "stone must not be fuel")

	# --- mining drops
	_expect(FURNACE.mining_drop_for(10) == 16, "coal ore drops coal")
	_expect(FURNACE.mining_drop_for(11) == 11, "iron ore drops itself")
	_expect(FURNACE.mining_drop_for(2) == 2, "dirt drops itself")

	# --- happy path: 2 iron + 1 copper with coal fuel
	var inv = INVENTORY.new()
	inv.add_item(11, 2)
	inv.add_item(12, 1)
	inv.add_item(16, 3)

	var r1: Dictionary = FURNACE.smelt_once(inv)
	_expect(bool(r1.get("ok", false)), "smelt iron #1 should succeed")
	_expect(int(r1.get("output", -1)) == 14, "smelt iron output id")
	_expect(inv.get_item_count(11) == 1, "one iron consumed")
	_expect(inv.get_item_count(14) == 1, "one ingot produced")
	_expect(inv.get_item_count(16) == 2, "one coal consumed")

	FURNACE.smelt_once(inv)
	var r3: Dictionary = FURNACE.smelt_once(inv)
	_expect(bool(r3.get("ok", false)) and int(r3.get("input", -1)) == 12, "third smelt should hit copper")
	_expect(inv.get_item_count(15) == 1, "copper ingot produced")
	_expect(inv.get_item_count(11) == 0 and inv.get_item_count(12) == 0, "ores exhausted after three smelts")

	# --- no fuel left -> fail without side effects
	var before := inv.get_slot_count()
	var r4: Dictionary = FURNACE.smelt_once(inv)
	_expect(not bool(r4.get("ok", false)) and r4.get("reason", "") == "no_input", "exhausted ores report no_input")
	# add ore but no fuel
	inv.add_item(11, 1)
	var r5: Dictionary = FURNACE.smelt_once(inv)
	_expect(not bool(r5.get("ok", false)) and r5.get("reason", "") == "no_fuel", "missing fuel reports no_fuel")
	_expect(inv.get_item_count(11) == 1, "ore not consumed when fuel missing")
	_expect(inv.get_slot_count() == before, "inventory shape unchanged on failed smelts")

	# --- log as alternative fuel
	inv.add_item(5, 1)
	var r6: Dictionary = FURNACE.smelt_once(inv)
	_expect(bool(r6.get("ok", false)) and int(r6.get("fuel", -1)) == 5, "log fuels a smelt when no coal remains")
	_expect(inv.get_item_count(14) == 3, "iron ingots total 3 after log-fueled smelt")

	# --- full inventory rollback (two slots, stack cap 1: ore + fuel occupy all)
	var tiny = INVENTORY.new(2, 1)
	_expect(tiny.add_item(11, 1), "tiny: iron fits slot 0")
	_expect(tiny.add_item(16, 1), "tiny: coal fits slot 1")
	var r7: Dictionary = FURNACE.smelt_once(tiny)
	_expect(not bool(r7.get("ok", false)) and r7.get("reason", "") == "output_full",
		"full inventory reports output_full")
	_expect(tiny.get_item_count(11) == 1 and tiny.get_item_count(16) == 1,
		"input+fuel preserved when output cannot fit")

	# --- sand -> glass and log -> charcoal (charcoal then fuels itself)
	var campfire = INVENTORY.new()
	campfire.add_item(4, 1)
	campfire.add_item(5, 3)
	var g1: Dictionary = FURNACE.smelt_once(campfire)
	_expect(bool(g1.get("ok", false)) and int(g1.get("output", -1)) == 17,
		"sand + log fuel should yield glass")
	var g2: Dictionary = FURNACE.smelt_once(campfire)
	_expect(bool(g2.get("ok", false)) and int(g2.get("input", -1)) == 5
		and int(g2.get("output", -1)) == 18, "second smelt turns a log into charcoal")
	# charcoal produced by g2 is itself fuel: one more sand smelts off it
	campfire.add_item(4, 1)
	var g_char: Dictionary = FURNACE.smelt_once(campfire)
	_expect(bool(g_char.get("ok", false)) and int(g_char.get("fuel", -1)) == 18,
		"produced charcoal fuels the next smelt")

	# a single log alone can't be both burned and converted
	var solo = INVENTORY.new()
	solo.add_item(5, 1)
	var g_lone: Dictionary = FURNACE.smelt_once(solo)
	_expect(not bool(g_lone.get("ok", false)) and g_lone.get("reason", "") == "no_fuel",
		"single log can't be fuel and input at once")
	_expect(solo.get_item_count(5) == 1, "lone log preserved on failed self-smelt")

	# --- crafting screen contract
	var recipes: Array = SCREEN.RECIPES
	var found_furnace := false
	var found_metal_drill := false
	for recipe in recipes:
		var inputs: Array = recipe.get("inputs", [])
		var output_id := int(recipe.get("output", {}).get("block_id", -1))
		if inputs.size() == 1 and int(inputs[0].get("block_id", -1)) == 3 				and int(inputs[0].get("count", 0)) >= 8 and output_id == 13:
			found_furnace = true
		if output_id == 9:
			for entry in inputs:
				if int(entry.get("block_id", -1)) == 14:
					found_metal_drill = true
	_expect(found_furnace, "crafting must expose 8 stone -> furnace")
	_expect(found_metal_drill, "crafting must expose iron-ingot mechanical drill recipe")
	for new_name_id in [10, 11, 12, 13, 14, 15, 16, 17, 18]:
		_expect(SCREEN.BLOCK_NAMES.has(new_name_id), "BLOCK_NAMES missing id %d" % new_name_id)

	print("SMELTING_GATE_JSON=", JSON.stringify({
		"gate": "smelting",
		"checks": checks,
		"failures": failures,
	}))
	if failures.is_empty():
		print("SMELTING_GATE_PASS")
	else:
		print("SMELTING_GATE_FAIL")
	quit(0 if failures.is_empty() else 1)
