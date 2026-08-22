extends SceneTree

## Inventory & crafting redo gate.
## Covers the rewritten data layer (explicit craft grid, quick move,
## compact, grid return), recipe matching, and a headless UI smoke pass
## of the tabbed screen: auto-fill, output take, close-with-carry.

const INVENTORY := preload("res://scripts/inventory/block_inventory.gd")
const RECIPES := preload("res://scripts/crafting/crafting_recipes.gd")
const SCREEN := preload("res://scripts/ui/minecraft_inventory_screen.gd")
const ITEM_REGISTRY := preload("res://scripts/items/item_registry.gd")
const FURNACE_RECIPES := preload("res://scripts/smelting/furnace_recipes.gd")

const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_LOG := 5
const BLOCK_FURNACE := 13
const BLOCK_IRON_INGOT := 14
const BLOCK_IRON_ORE := 11
const BLOCK_COAL := 16

var failures: Array[String] = []
var checks := 0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 10:
		if not failures.has(message):
			failures.append(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_basic_ops()
	_test_quick_move()
	_test_compact()
	_test_craft_grid_state()
	_test_grid_return()
	_test_grid_return_full_inventory()
	_test_recipe_matching()
	await _test_screen_flow()

	if failures.is_empty():
		print("INVENTORY_REDO_GATE_PASS checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: %s" % failure)
		print("INVENTORY_REDO_GATE_FAIL checks=%d" % checks)
		quit(1)


# ---------------------------------------------------------------- data layer

func _test_basic_ops() -> void:
	var inv = INVENTORY.new()
	_expect(inv.add_item(BLOCK_DIRT, 40), "add 40 dirt")
	_expect(inv.get_item_count(BLOCK_DIRT) == 40, "count 40 dirt")
	_expect(inv.remove_item(BLOCK_DIRT, 15), "remove 15 dirt")
	_expect(inv.get_item_count(BLOCK_DIRT) == 25, "count 25 dirt")
	var taken: Dictionary = inv.take_from_slot(0)
	_expect(int(taken.get("block_id", 0)) == BLOCK_DIRT and int(taken.get("count", 0)) > 0,
		"take_from_slot returns dirt stack")
	var put_back: Dictionary = inv.put_stack_into_slot(0, taken)
	_expect(int(put_back.get("block_id", -1)) == 0, "put_stack_into_slot fully places stack")


func _test_quick_move() -> void:
	var inv = INVENTORY.new()
	inv.add_item(BLOCK_DIRT, 30) # hotbar slot 0
	inv.quick_move_slot(0)
	_expect(int(inv.get_slot(0).get("count", 0)) == 0, "quick move empties hotbar slot 0")
	_expect(int(inv.get_slot(INVENTORY.HOTBAR_SLOT_COUNT).get("block_id", 0)) == BLOCK_DIRT
		and int(inv.get_slot(INVENTORY.HOTBAR_SLOT_COUNT).get("count", 0)) == 30,
		"quick move lands dirt in first storage slot")
	inv.quick_move_slot(INVENTORY.HOTBAR_SLOT_COUNT)
	_expect(int(inv.get_slot(0).get("count", 0)) == 30, "quick move returns dirt to hotbar")
	inv.quick_move_slot(3) # empty slot: no-op
	_expect(inv.get_item_count(BLOCK_DIRT) == 30, "quick move on empty slot is a no-op")


func _test_compact() -> void:
	var inv = INVENTORY.new()
	inv.add_item(BLOCK_DIRT, 64)
	inv.add_item(BLOCK_DIRT, 64)
	inv.add_item(BLOCK_DIRT, 64)
	inv.add_item(BLOCK_DIRT, 10)
	# punch holes
	inv.remove_from_slot(1, 64)
	inv.remove_from_slot(3, 10)
	inv.compact()
	var total := 0
	var first_empty := -1
	for slot_index in range(inv.get_slot_count()):
		var stack := inv.get_slot(slot_index)
		var count := int(stack.get("count", 0))
		total += count
		if count == 0 and first_empty < 0:
			first_empty = slot_index
		elif count > 0 and first_empty >= 0:
			_expect(false, "compact left item after an empty slot (slot %d)" % slot_index)
			break
	_expect(total == 64 * 3 + 10 - 74, "compact preserves totals (got %d)" % total)


func _test_craft_grid_state() -> void:
	var inv = INVENTORY.new()
	inv.add_item(BLOCK_STONE, 8)
	var remainder: Dictionary = inv.set_craft_slot(0, {"block_id": BLOCK_STONE, "count": 8})
	_expect(int(remainder.get("block_id", -1)) == 0, "set_craft_slot places whole stack")
	_expect(int(inv.get_craft_slot(0).get("count", 0)) == 8, "grid slot holds 8")
	# set_craft_slot is a raw region write: bag is only debited by explicit
	# callers (UI cursor moves, auto-fill). Conservation is enforced there.
	_expect(inv.get_item_count(BLOCK_STONE) == 8, "raw grid write leaves bag untouched")
	var half: Dictionary = inv.split_craft_slot(0)
	_expect(int(half.get("count", 0)) == 4, "split_craft_slot takes half")
	_expect(int(inv.get_craft_slot(0).get("count", 0)) == 4, "grid slot holds 4 after split")
	var back: Dictionary = inv.take_craft_slot(0)
	_expect(int(back.get("count", 0)) == 4, "take_craft_slot empties grid slot")
	_expect(inv.get_item_count(BLOCK_STONE) == 8, "take_craft_slot hands to caller, bag unchanged")


func _test_grid_return() -> void:
	var inv = INVENTORY.new()
	inv.set_craft_slot(0, {"block_id": BLOCK_STONE, "count": 5})
	inv.set_craft_slot(2, {"block_id": BLOCK_DIRT, "count": 2})
	var returned: int = inv.return_craft_grid_to_inventory()
	_expect(returned == 0, "grid return strands nothing when inventory has room")
	_expect(inv.get_item_count(BLOCK_STONE) == 5 and inv.get_item_count(BLOCK_DIRT) == 2,
		"grid return restores items")
	for craft_index in range(INVENTORY.CRAFT_GRID_SIZE):
		_expect(int(inv.get_craft_slot(craft_index).get("block_id", 0)) == 0,
			"grid slot %d empty after return" % craft_index)


func _test_grid_return_full_inventory() -> void:
	var inv = INVENTORY.new()
	for slot_index in range(inv.get_slot_count()):
		inv.set_slot_stack(slot_index, {"block_id": BLOCK_STONE, "count": 64})
	inv.set_craft_slot(0, {"block_id": BLOCK_DIRT, "count": 3})
	var stranded: int = inv.return_craft_grid_to_inventory()
	_expect(stranded == 3, "full inventory strands the grid stack (got %d)" % stranded)
	_expect(int(inv.get_craft_slot(0).get("count", 0)) == 3, "stranded stack stays in grid")


func _test_recipe_matching() -> void:
	var furnace: Dictionary = RECIPES.find_recipe_for_output(BLOCK_FURNACE)
	_expect(not furnace.is_empty(), "furnace recipe exists")
	var full_stacks: Array[Dictionary] = [{"block_id": BLOCK_STONE, "count": 8}]
	var short_stacks: Array[Dictionary] = [{"block_id": BLOCK_STONE, "count": 7}]
	_expect(RECIPES.max_craftable(furnace, full_stacks) == 1, "8 stone crafts 1 furnace")
	_expect(RECIPES.max_craftable(furnace, short_stacks) == 0, "7 stone crafts nothing")

	var drill: Dictionary = RECIPES.find_recipe_for_output(BLOCK_IRON_INGOT)
	_expect(drill.is_empty(), "iron ingot is not a craft output")

	var grid: Array[Dictionary] = RECIPES.empty_grid(INVENTORY.CRAFT_GRID_SIZE)
	grid[0] = {"block_id": BLOCK_STONE, "count": 8}
	var matched: Dictionary = RECIPES.find_recipe(grid)
	_expect(not matched.is_empty() and int(matched.get("output", {}).get("block_id", 0)) == BLOCK_FURNACE,
		"stone grid matches furnace recipe")
	grid[0] = {"block_id": BLOCK_STONE, "count": 7}
	_expect(RECIPES.find_recipe(grid).is_empty(), "7 stone grid matches nothing")


# ---------------------------------------------------------------- screen flow

func _test_screen_flow() -> void:
	var inv = INVENTORY.new()
	inv.add_item(BLOCK_STONE, 64)
	var screen = SCREEN.new()
	root.add_child(screen)
	await process_frame
	screen.setup(inv, Node.new())
	await process_frame

	_expect(not screen.is_inventory_open(), "screen starts closed")
	screen.open_crafting()
	await process_frame
	_expect(screen.is_inventory_open(), "crafting tab opens the screen")
	_expect(screen.get_active_tab() == screen.Tab.CRAFTING, "crafting tab is active")
	_expect(screen.get_crafting_panel() != null and screen.get_crafting_panel().visible,
		"crafting panel visible")
	_expect(screen.get_inventory_panel() != null and not screen.get_inventory_panel().visible,
		"inventory panel hidden while crafting")

	var furnace_recipe: Dictionary = RECIPES.find_recipe_for_output(BLOCK_FURNACE)
	_expect(screen.auto_fill_grid(furnace_recipe), "auto fill pulls 8 stone into the grid")
	var grid_total := 0
	for craft_index in range(INVENTORY.CRAFT_GRID_SIZE):
		grid_total += int(inv.get_craft_slot(craft_index).get("count", 0))
	_expect(grid_total == 8, "grid holds 8 stone after auto fill (got %d)" % grid_total)
	_expect(inv.get_item_count(BLOCK_STONE) == 56, "auto fill removed 8 stone from inventory")

	var output: Dictionary = screen.interact_craft_output()
	_expect(int(output.get("block_id", 0)) == BLOCK_FURNACE and int(output.get("count", 0)) == 1,
		"craft output goes to cursor")
	_expect(int(inv.get_item_count(BLOCK_STONE)) == 56, "output take consumed exactly the grid")

	# close: cursor stack must return to the inventory (the orphan fix)
	var closed: bool = screen.close_inventory()
	_expect(closed, "close_inventory succeeds with a carried stack")
	_expect(inv.get_item_count(BLOCK_FURNACE) == 1, "carried furnace returned on close")
	_expect(screen.get_cursor_stack().is_empty() or int(screen.get_cursor_stack().get("block_id", 0)) == 0,
		"cursor empty after close")

	# grid leftovers must also survive close
	inv.set_craft_slot(1, {"block_id": BLOCK_LOG, "count": 2})
	screen.open_inventory()
	await process_frame
	screen.close_inventory()
	_expect(inv.get_item_count(BLOCK_LOG) == 2, "grid contents returned on close")

	# craft all path: 16 stone -> 2 furnaces straight to the bag
	var inv2 = INVENTORY.new()
	inv2.add_item(BLOCK_STONE, 16)
	var screen2 = SCREEN.new()
	root.add_child(screen2)
	await process_frame
	screen2.setup(inv2, Node.new())
	await process_frame
	screen2.open_crafting()
	await process_frame
	_expect(screen2.auto_fill_grid(furnace_recipe), "second auto fill")
	_expect(screen2.craft_all_to_inventory() == 2, "craft all produces 2 furnaces")
	_expect(inv2.get_item_count(BLOCK_FURNACE) == 2, "furnaces landed in the bag")
	_expect(inv2.get_item_count(BLOCK_STONE) == 0, "craft all consumed all stone")

	# furnace tab smoke
	inv2.add_item(BLOCK_IRON_ORE, 4)
	inv2.add_item(BLOCK_COAL, 4)
	screen2.open_furnace()
	await process_frame
	_expect(screen2.get_furnace_panel() != null and screen2.get_furnace_panel().visible,
		"furnace panel visible")
	_expect(screen2.get_furnace_status_label() != null, "furnace status label exists")
	_expect(String(screen2.get_furnace_status_label().text).contains("IRON ORE"),
		"status lists ore counts")
	# REGRESSION: E / ESC / X must close from ANY tab (was: toggled tabs)
	screen2.open_crafting()
	await process_frame
	_expect(screen2.is_inventory_open() and screen2.get_active_tab() == screen2.Tab.CRAFTING,
		"crafting tab open before toggle regression check")
	screen2.toggle_inventory()
	await process_frame
	_expect(not screen2.is_inventory_open(), "toggle_inventory closes from the crafting tab")
	screen2.toggle_crafting()
	await process_frame
	_expect(screen2.is_inventory_open(), "toggle_crafting opens from closed")
	screen2.toggle_crafting()
	await process_frame
	_expect(not screen2.is_inventory_open(), "toggle_crafting closes an open screen")

	screen2.close_inventory()
	await process_frame

	screen.queue_free()
	screen2.queue_free()
	await process_frame
