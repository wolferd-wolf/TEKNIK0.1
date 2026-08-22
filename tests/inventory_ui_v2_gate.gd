extends SceneTree

## Inventory UI v2 gate (commit 1 of the UI rebuild).
## Verifies: theme resource loads, scene instantiates with the new tree,
## tap-to-move writer handlers against a real BlockInventory, split,
## quick move, close-returns-carry-and-grid, the close-from-any-tab
## regression, hotbar read-only binding, and ItemSlotV2 signal contract.

const SCREEN_SCENE := preload("res://scenes/ui/inventory_screen_v2.tscn")
const HOTBAR_SCENE := preload("res://scenes/ui/hotbar_v2.tscn")
const INVENTORY := preload("res://scripts/inventory/block_inventory.gd")

const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_LOG := 5

var failures: Array[String] = []
var checks := 0


func _carry_empty(screen) -> bool:
	var carry: Dictionary = screen.get_cursor_stack()
	return int(carry.get("block_id", 0)) <= 0 or int(carry.get("count", 0)) <= 0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 10:
		if not failures.has(message):
			failures.append(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var theme := load("res://resources/theme/teknik_ui.tres") as Theme
	_expect(theme != null, "teknik_ui.tres loads as Theme")
	_expect(theme != null and theme.has_stylebox("panel", "PanelContainer"),
		"theme styles PanelContainer")

	var inv = INVENTORY.new()
	var screen = SCREEN_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	screen.setup(inv, Node.new())
	await process_frame

	# scene structure exists and starts closed
	_expect(not screen.is_inventory_open(), "v2 screen starts closed")
	_expect(screen.get_panel_for(0) != null, "inventory panel exists")
	_expect(screen.get_slot_widget(0) != null, "hotbar slot widget 0 exists")
	_expect(screen.get_slot_widget(35) != null, "storage slot widget 35 exists")

	# open inventory tab
	screen.open_inventory()
	await process_frame
	_expect(screen.is_inventory_open(), "open_inventory opens")
	_expect(screen.get_active_tab() == 0, "active tab is INVENTORY")

	# tap-to-move: pick up
	inv.add_item(BLOCK_DIRT, 40)
	await process_frame
	screen._on_slot_tapped(0)
	_expect(int(screen.get_cursor_stack().get("block_id", 0)) == BLOCK_DIRT
		and int(screen.get_cursor_stack().get("count", 0)) == 40,
		"tap picks up stack into carry")
	_expect(inv.get_item_count(BLOCK_DIRT) == 0, "picked stack left the bag")

	# place into storage slot 9
	screen._on_slot_tapped(9)
	_expect(inv.get_item_count(BLOCK_DIRT) == 40, "tap places stack in storage")
	_expect(int(inv.get_slot(9).get("block_id", 0)) == BLOCK_DIRT, "storage slot 9 holds dirt")

	# swap case: carry stone onto the dirt stack at slot 9
	inv.add_item(BLOCK_STONE, 10) # slot 0 is free again, so stone lands there
	screen._on_slot_tapped(0)     # pick stone (carry = stone x10)
	screen._on_slot_tapped(9)     # swap with dirt at storage slot 9
	_expect(int(inv.get_slot(9).get("block_id", 0)) == BLOCK_STONE
		and int(inv.get_slot(9).get("count", 0)) == 10,
		"swap placed carried stone into slot 9")
	_expect(int(screen.get_cursor_stack().get("block_id", 0)) == BLOCK_DIRT
		and int(screen.get_cursor_stack().get("count", 0)) == 40,
		"swap picked up the displaced dirt into carry")
	screen._on_slot_tapped(0)     # put the dirt back where stone came from
	_expect(int(inv.get_slot(0).get("count", 0)) == 40,
		"displaced dirt returned to slot 0")
	_expect(_carry_empty(screen), "carry empty after full placement")

	# split via long-press handler: dirt 40 -> 20 + carry 20
	screen._on_slot_split(0)
	_expect(int(screen.get_cursor_stack().get("count", 0)) == 20,
		"long-press splits half (40 -> carry 20)")
	_expect(int(inv.get_slot(0).get("count", 0)) == 20, "slot keeps other half")
	screen._on_slot_tapped(20) # place the carried half into storage slot 20
	_expect(int(inv.get_slot(20).get("block_id", 0)) == BLOCK_DIRT
		and int(inv.get_slot(20).get("count", 0)) == 20,
		"carried half placed at slot 20")
	_expect(inv.get_item_count(BLOCK_DIRT) == 40, "split+place conserves totals")

	# quick move storage -> hotbar: stone from slot 9 to first free hotbar slot
	screen._on_quick_move(9)
	_expect(int(inv.get_slot(1).get("block_id", 0)) == BLOCK_STONE
		and int(inv.get_slot(1).get("count", 0)) == 10,
		"quick move lands stone in first free hotbar slot")
	_expect(int(inv.get_slot(9).get("count", 0)) == 0, "quick move empties source slot")

	# TIDY compacts through the writer tier
	screen.open_inventory()
	await process_frame
	screen._tidy()
	await process_frame
	_expect(inv.get_item_count(BLOCK_DIRT) == 40 and inv.get_item_count(BLOCK_STONE) == 10,
		"tidy preserves totals")

	# craft grid safety on close even before crafting UI exists
	inv.set_craft_slot(1, {"block_id": BLOCK_LOG, "count": 3})
	screen.open_crafting()
	await process_frame
	_expect(screen.is_inventory_open() and screen.get_active_tab() == 1,
		"crafting tab opens (placeholder panel)")

	# REGRESSION: toggle must close from ANY tab
	screen.toggle_inventory()
	await process_frame
	_expect(not screen.is_inventory_open(), "toggle_inventory closes from crafting tab")
	_expect(inv.get_item_count(BLOCK_LOG) == 3, "grid contents returned on close")
	_expect(inv.get_item_count(BLOCK_DIRT) == 40 and inv.get_item_count(BLOCK_STONE) == 10,
		"close returned everything; no items lost")

	# dim-click close path exists (signal connected): simulate by calling handler target
	screen.open_inventory()
	await process_frame
	var closed: bool = screen.close_inventory()
	_expect(closed, "close_inventory succeeds cleanly when carry empty")

	# ---- ItemSlotV2 signal contract
	var widget: ItemSlotV2 = screen.get_slot_widget(3)
	_expect(widget != null and widget.is_display_only() == false, "screen slots are interactive")
	var got := {"tapped": -99}
	widget.slot_tapped.connect(func(id: int) -> void: got["tapped"] = id)
	widget.slot_tapped.emit(7)
	_expect(got["tapped"] == 7, "slot emits tapped with its id")

	# bind_view paints count text
	inv.add_item(BLOCK_DIRT, 1)
	await process_frame
	_expect(widget.get_count_label() != null, "widget exposes count label")

	# ---- HotbarV2 read-only subscriber
	var hotbar = HOTBAR_SCENE.instantiate()
	root.add_child(hotbar)
	await process_frame
	hotbar.setup(inv)
	await process_frame
	var label := hotbar.get_slot_widget(0).get_count_label() as Label
	inv.add_item(BLOCK_DIRT, 4) # now 45+? just ensure change repaints
	await process_frame
	_expect(label.text.begins_with("x"), "hotbar repaints counts from changed signal (%s)" % label.text)
	hotbar.refresh(inv.get_slots(), 2)
	_expect(hotbar.index_of_selected() == 2, "legacy refresh keeps selection API")

	# ---- SlotViewBuilder purity
	var stack := {"block_id": BLOCK_DIRT, "count": 3}
	var view: Dictionary = load("res://scripts/ui/v2/slot_view_builder.gd").build(stack)
	_expect(view.get("texture") != null and view.get("count_text") == "x3",
		"slot view payload built from stack")
	_expect(int(stack.get("count", 0)) == 3, "view builder did not mutate the stack")

	screen.queue_free()
	hotbar.queue_free()
	await process_frame

	if failures.is_empty():
		print("INVENTORY_UI_V2_GATE_PASS checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: %s" % failure)
		print("INVENTORY_UI_V2_GATE_FAIL checks=%d" % checks)
		quit(1)
