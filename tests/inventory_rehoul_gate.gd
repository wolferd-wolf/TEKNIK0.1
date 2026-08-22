extends SceneTree

## Inventory/UI/crafting rehoul gate.
## Sections map to GATES.md:
##   G4_LAYOUT   - CRAFT button entirely LEFT, CLOSE button entirely RIGHT
##                 of the player-inventory panel, vertically aligned.
##   G5_STATIONS - chest per-position storage, break-return, crafting-table
##                 grid + table-only recipes, furnace smelt loop intact.
##   G6_REGISTRY - block ids 13/19/20 known, recipes expose table + chest,
##                 presentation data complete.

const INVENTORY := preload("res://scripts/inventory/block_inventory.gd")
const STATIONS := preload("res://scripts/inventory/block_stations.gd")
const SCREEN := preload("res://scripts/ui/station_screen.gd")
const RECIPES := preload("res://scripts/crafting/crafting_recipes.gd")
const FURNACE := preload("res://scripts/smelting/furnace_recipes.gd")
const REGISTRY := preload("res://scripts/items/item_registry.gd")

const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_LOG := 5
const BLOCK_FURNACE := 13
const BLOCK_IRON_ORE := 11
const BLOCK_COAL := 16
const BLOCK_IRON_INGOT := 14
const BLOCK_TABLE := 19
const BLOCK_CHEST := 20

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _mark(section: String, before: int) -> void:
	if failures.size() == before:
		print("%s PASS" % section)
	else:
		print("%s FAIL (%d problems)" % [section, failures.size()])


func _run() -> void:
	var before := failures.size()
	await _test_layout()
	_mark("G4_LAYOUT", before)

	before = failures.size()
	_test_stations()
	_mark("G5_STATIONS", before)

	before = failures.size()
	_test_registry()
	_mark("G6_REGISTRY", before)

	print("LEDGER %d/%d" % [checks - failures.size(), checks])
	if failures.is_empty():
		print("REHOUL_GATE_PASS")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: %s" % failure)
		quit(1)


# ---------------------------------------------------------------- G4 layout

func _test_layout() -> void:
	var inv = INVENTORY.new()
	var stations = STATIONS.new()
	root.add_child(stations)
	var screen = SCREEN.new()
	root.add_child(screen)
	await _wait_frames(2)
	screen.setup(inv, stations)
	screen.open_inventory()
	await _wait_frames(3)

	var craft_button := screen.get_craft_button()
	var close_button := screen.get_close_button()
	var panel := screen.get_inventory_panel()
	_expect(craft_button != null, "CRAFT button exists")
	_expect(close_button != null, "CLOSE button exists")
	_expect(panel != null, "inventory panel exists")
	if craft_button == null or close_button == null or panel == null:
		return

	_expect(screen.visible and screen.is_inventory_open(), "screen opens into inventory mode")

	var panel_rect := panel.get_global_rect()
	var craft_rect := craft_button.get_global_rect()
	var close_rect := close_button.get_global_rect()

	# The core rehoul contract: CRAFT left of the inventory, CLOSE right of it.
	_expect(craft_rect.position.x + craft_rect.size.x <= panel_rect.position.x + 0.5,
		"CRAFT button sits entirely left of the inventory panel")
	_expect(close_rect.position.x >= panel_rect.position.x + panel_rect.size.x - 0.5,
		"CLOSE button sits entirely right of the inventory panel")
	var craft_vertical: float = (
		minf(craft_rect.position.y + craft_rect.size.y, panel_rect.position.y + panel_rect.size.y)
		- maxf(craft_rect.position.y, panel_rect.position.y)
	)
	_expect(craft_vertical > 0.0, "CRAFT button is vertically aligned with the inventory panel")
	var close_vertical: float = (
		minf(close_rect.position.y + close_rect.size.y, panel_rect.position.y + panel_rect.size.y)
		- maxf(close_rect.position.y, panel_rect.position.y)
	)
	_expect(close_vertical > 0.0, "CLOSE button is vertically aligned with the inventory panel")
	_expect(panel_rect.size.x > 300.0, "inventory panel renders at full width (got %s)" % panel_rect.size)

	# Same geometry must hold while a station menu is open above the panel.
	screen.open_crafting()
	await _wait_frames(2)
	panel_rect = panel.get_global_rect()
	craft_rect = craft_button.get_global_rect()
	close_rect = close_button.get_global_rect()
	_expect(craft_rect.position.x + craft_rect.size.x <= panel_rect.position.x + 0.5,
		"CRAFT stays left of the inventory panel in crafting mode")
	_expect(close_rect.position.x >= panel_rect.position.x + panel_rect.size.x - 0.5,
		"CLOSE stays right of the inventory panel in crafting mode")

	screen.queue_free()


# ---------------------------------------------------------------- G5 stations

func _test_stations() -> void:
	var stations = STATIONS.new()
	root.add_child(stations)

	_expect(stations.is_station_block(BLOCK_FURNACE), "furnace counts as station")
	_expect(stations.is_station_block(BLOCK_TABLE), "crafting table counts as station")
	_expect(stations.is_station_block(BLOCK_CHEST), "chest counts as station")
	_expect(not stations.is_station_block(BLOCK_STONE), "stone is not a station")

	# chest: per-position storage round trip
	var coord := Vector3i(7, -2, 11)
	_expect(not stations.has_chest(coord), "no chest registered before placement")
	var chest: BlockInventory = stations.register_chest(coord)
	_expect(chest.get_slot_count() == stations.CHEST_SLOT_COUNT,
		"chest inventory exposes 27 slots")
	_expect(chest.add_item(BLOCK_DIRT, 40), "chest accepts 40 dirt")
	_expect(stations.get_chest_inventory(coord).get_item_count(BLOCK_DIRT) == 40,
		"per-position lookup returns the same storage")
	_expect(stations.chest_count() == 1, "one chest registered")

	var contents: Array[Dictionary] = stations.clear_chest(coord)
	_expect(not stations.has_chest(coord), "clear_chest forgets the position")
	var total_returned := 0
	for stack in contents:
		total_returned += int(stack.get("count", 0))
	_expect(total_returned == 40, "cleared chest hands back all 40 dirt (got %d)" % total_returned)
	var fresh: BlockInventory = stations.register_chest(coord)
	_expect(fresh.is_empty(), "re-registered chest starts empty")

	# crafting table: larger grid state through BlockInventory
	var table_grid = INVENTORY.new(1, 64, 9)
	_expect(table_grid.get_craft_grid_size() == 9, "table grid holds 9 slots")
	_expect(int(table_grid.set_craft_slot(8, {"block_id": BLOCK_LOG, "count": 3})
		.get("count", 0)) == 0,
		"table grid slot 8 accepts stacks")
	_expect(int(table_grid.take_craft_slot(8).get("count", 0)) == 3, "table grid slot 8 returns stacks")

	# table-only recipes: match at a table, never in the 2x2 player grid
	var stone_stack: Array[Dictionary] = [{"block_id": BLOCK_STONE, "count": 8}]
	_expect(RECIPES.find_recipe(stone_stack).is_empty(),
		"furnace recipe does not match outside a table")
	_expect(int(RECIPES.find_recipe(stone_stack, RECIPES.RECIPES, true)
		.get("output", {}).get("block_id", 0)) == BLOCK_FURNACE,
		"furnace recipe matches in table mode")

	# furnace loop unchanged: ore + fuel -> ingot
	var smelter = INVENTORY.new()
	smelter.add_item(BLOCK_IRON_ORE, 1)
	smelter.add_item(BLOCK_COAL, 1)
	var report: Dictionary = FURNACE.smelt_once(smelter)
	_expect(bool(report.get("ok", false)), "furnace smelt succeeds")
	_expect(smelter.get_item_count(BLOCK_IRON_INGOT) == 1, "smelt produced an iron ingot")


# ---------------------------------------------------------------- G6 registry

func _test_registry() -> void:
	_expect(REGISTRY.display_name(BLOCK_FURNACE) == "FURNACE", "id 13 named FURNACE")
	_expect(REGISTRY.display_name(BLOCK_TABLE) == "CRAFTING TABLE", "id 19 named CRAFTING TABLE")
	_expect(REGISTRY.display_name(BLOCK_CHEST) == "CHEST", "id 20 named CHEST")
	_expect(REGISTRY.swatch_color(BLOCK_TABLE) != Color.MAGENTA,
		"crafting table has a swatch color")
	_expect(REGISTRY.swatch_color(BLOCK_CHEST) != Color.MAGENTA, "chest has a swatch color")
	_expect(REGISTRY.glyph(BLOCK_TABLE) == "T", "crafting table glyph")
	_expect(REGISTRY.glyph(BLOCK_CHEST) == "C", "chest glyph")
	_expect(REGISTRY.STATION_IDS.has(BLOCK_FURNACE) and REGISTRY.STATION_IDS.has(BLOCK_TABLE)
		and REGISTRY.STATION_IDS.has(BLOCK_CHEST), "station id list covers 13/19/20")

	var table_recipe: Dictionary = RECIPES.find_recipe_for_output(BLOCK_TABLE)
	_expect(not table_recipe.is_empty(), "recipe book exposes crafting table")
	var chest_recipe: Dictionary = RECIPES.find_recipe_for_output(BLOCK_CHEST)
	_expect(not chest_recipe.is_empty(), "recipe book exposes chest")
	var logs: Array[Dictionary] = [{"block_id": BLOCK_LOG, "count": 2}]
	_expect(RECIPES.match_recipe(logs, table_recipe), "2 logs craft a crafting table")

	_expect(FURNACE.mining_drop_for(BLOCK_CHEST) == BLOCK_CHEST, "mined chest drops itself")
	_expect(FURNACE.mining_drop_for(BLOCK_TABLE) == BLOCK_TABLE, "mined table drops itself")
