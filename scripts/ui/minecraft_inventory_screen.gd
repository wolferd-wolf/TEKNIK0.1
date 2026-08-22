extends CanvasLayer
class_name MinecraftInventoryScreen

## Inventory / crafting / furnace UI (rewritten).
## Tabs replace floating panels. Slots are visual swatches driven by
## ItemRegistry. The craft grid lives in BlockInventory (no meta hacks),
## and closing the screen always returns carried + grid items.

signal inventory_visibility_changed(is_open: bool)

const TOGGLE_ACTION := StringName("toggle_inventory")
const CRAFT_ACTION := StringName("toggle_crafting")

const ITEM_REGISTRY := preload("res://scripts/items/item_registry.gd")
const CRAFTING_RECIPES := preload("res://scripts/crafting/crafting_recipes.gd")
const FURNACE_RECIPES := preload("res://scripts/smelting/furnace_recipes.gd")

## Kept for backward-compatible gate access; canonical list lives in
## CraftingRecipes.RECIPES.
const RECIPES: Array[Dictionary] = CraftingRecipes.RECIPES

const HOTBAR_SLOT_COUNT := 9
const STORAGE_SLOT_COUNT := 27
const STORAGE_START_INDEX := HOTBAR_SLOT_COUNT
const LONG_PRESS_SECONDS := 0.45
const DOUBLE_TAP_SECONDS := 0.35
const CRAFT_GRID_SIZE := BlockInventory.CRAFT_GRID_SIZE

enum Tab { INVENTORY, CRAFTING, FURNACE }

const SLOT_SIZE := Vector2(64.0, 64.0)
const SWATCH_SIZE := Vector2(42.0, 42.0)
const PANEL_PADDING := 20.0
const TITLE_SIZE := 20
const SUBTITLE_SIZE := 13

const UI_PANEL_TEX := "res://assets/textures/icons/default_stone.png"
const UI_BUTTON_TEX := "res://assets/textures/icons/default_junglewood.png"
const UI_SLOT_TEX := "res://assets/textures/icons/default_obsidian.png"

const COLOR_ACCENT := Color(0.98, 0.80, 0.20)
const COLOR_OK := Color(0.40, 0.90, 0.45)
const COLOR_DIM := Color(1, 1, 1, 0.45)

var _inventory: BlockInventory
var _player: Node

var _root: Control
var _dim: ColorRect
var _tab_buttons := {}
var _panels := {}
var _close_button: Button

# slot visuals: key = slot index (0..35)
var _slot_buttons := {}
var _slot_swatch_styles := {}
var _slot_swatch_panels := {}
var _slot_count_labels := {}

# craft grid visuals: key = craft index (0..3), plus output
var _craft_slot_buttons := {}
var _craft_output_button: Button
var _craft_output_style: StyleBoxFlat
var _craft_result_label: Label

# furnace
var _furnace_status_label: Label
var _furnace_buttons: Array[Button] = []
var _smelt_running := false
const SMELT_SECONDS_PER_OPERATION := 1.2

# cursor stack
var _cursor_stack := {"block_id": 0, "count": 0}
var _cursor_visual: PanelContainer
var _cursor_style: StyleBoxFlat
var _cursor_count_label: Label

# touch state
var _active_touch_index := -1
var _active_touch_slot := -1
var _long_press_consumed := false
var _long_press_timer: Timer
var _last_tap_slot := -1
var _last_tap_msec := -1

var _is_open := false
var _active_tab: int = Tab.INVENTORY


func _ready() -> void:
	layer = 60
	_build_screen()
	_apply_tab(Tab.INVENTORY, false)
	set_process(true)
	set_process_input(true)


func setup(inventory: BlockInventory, player: Node) -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_inventory = inventory
	_player = player
	if _inventory != null and not _inventory.changed.is_connected(_refresh):
		_inventory.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(TOGGLE_ACTION):
		toggle_inventory()
	elif Input.is_action_just_pressed(CRAFT_ACTION):
		toggle_crafting()
	if _is_open and Input.is_key_pressed(KEY_SHIFT):
		pass # shift is read at click time
	_update_cursor_visual_position()


# ================================================================ public API

func is_inventory_open() -> bool:
	return _is_open


func toggle_inventory() -> void:
	if _is_open:
		close_inventory() # closes from ANY tab (E / ESC always dismiss)
	else:
		open_inventory()


func open_inventory() -> void:
	_apply_tab(Tab.INVENTORY, true)


func close_inventory() -> bool:
	_cancel_active_touch()
	if not return_cursor_stack():
		return false
	_return_grid_on_close()
	_apply_tab(Tab.INVENTORY, false)
	return true


func toggle_crafting() -> void:
	if _is_open:
		close_inventory()
	else:
		open_crafting()


func open_crafting() -> void:
	_apply_tab(Tab.CRAFTING, true)


func close_crafting() -> void:
	close_inventory()


func open_furnace() -> void:
	_apply_tab(Tab.FURNACE, true)


func close_furnace() -> void:
	close_inventory()


## Returns carried stack to the inventory (best effort). True when nothing
## is left stranded.
func return_cursor_stack() -> bool:
	if _is_stack_empty(_cursor_stack):
		return true
	if _inventory == null:
		return false
	var block_id := int(_cursor_stack.get("block_id", 0))
	var count := int(_cursor_stack.get("count", 0))
	if not _inventory.can_add_item(block_id, count):
		# carry as much back as fits
		var max_stack := _inventory.get_max_stack_size()
		var capacity := 0
		for slot_index in range(_inventory.get_slot_count()):
			var slot := _inventory.get_slot(slot_index)
			var slot_id := int(slot["block_id"])
			var slot_count := int(slot["count"])
			if slot_id == block_id:
				capacity += max_stack - slot_count
			elif slot_id == 0:
				capacity += max_stack
		count = mini(count, maxi(capacity, 0))
		if count <= 0:
			return false
	if not _inventory.add_item(block_id, count):
		return false
	_cursor_stack = {"block_id": 0, "count": 0}
	_refresh()
	return true


func interact_slot_primary(slot_index: int) -> void:
	if not _can_interact():
		return
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = _inventory.take_from_slot(slot_index)
	else:
		_cursor_stack = _inventory.put_stack_into_slot(slot_index, _cursor_stack)
	_track_double_tap(slot_index)
	_refresh()


func interact_slot_secondary(slot_index: int) -> void:
	if not _can_interact():
		return
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = _inventory.split_from_slot(slot_index)
	else:
		_cursor_stack = _inventory.put_stack_into_slot(slot_index, _cursor_stack, true)
	_refresh()


## Shift+click / double-tap: move whole stack between hotbar and storage.
func quick_move_slot(slot_index: int) -> void:
	if not _can_interact():
		return
	# carrying something? drop the carried stack into this region instead
	if not _is_stack_empty(_cursor_stack):
		interact_slot_primary(slot_index)
		return
	_inventory.quick_move_slot(slot_index)
	_refresh()


func interact_craft_input(craft_index: int, single_item: bool = false) -> void:
	if not _can_interact():
		return
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = _inventory.take_craft_slot(craft_index)
	else:
		_cursor_stack = _inventory.set_craft_slot(craft_index, _cursor_stack, single_item)
	_refresh()


func split_craft_input(craft_index: int) -> void:
	if not _can_interact():
		return
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = _inventory.split_craft_slot(craft_index)
	_refresh()


## Take the crafted result to the cursor (or merge into carried same-id stack).
func interact_craft_output() -> Dictionary:
	if not _can_interact():
		return {}
	var grid := _inventory.get_craft_grid()
	var recipe: Dictionary = CraftingRecipes.find_recipe(grid)
	if recipe.is_empty():
		return {}
	var output: Dictionary = recipe.get("output", {})
	var out_id := int(output.get("block_id", 0))
	var out_count := int(output.get("count", 0))
	if out_id <= 0 or out_count <= 0:
		return {}
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = {"block_id": out_id, "count": out_count}
	elif int(_cursor_stack.get("block_id", 0)) == out_id 			and int(_cursor_stack.get("count", 0)) + out_count <= 64:
		_cursor_stack["count"] = int(_cursor_stack.get("count", 0)) + out_count
	else:
		return {} # cursor busy with something else
	_inventory.consume_grid_inputs(recipe)
	_refresh()
	return _cursor_stack.duplicate(true)


## Craft as many times as possible straight into the inventory.
func craft_all_to_inventory() -> int:
	## Craft repeatedly into the inventory, refilling the grid from the bag
	## while ingredients last. Stops on full inventory or missing inputs.
	if not _can_interact():
		return 0
	var crafted := 0
	for _attempt in range(64):
		var grid := _inventory.get_craft_grid()
		var recipe: Dictionary = CraftingRecipes.find_recipe(grid)
		if recipe.is_empty():
			if grid_has_any_item(grid):
				break # unrelated leftovers: do not wipe them
			recipe = CraftingRecipes.first_craftable_from_inventory(_inventory)
			if recipe.is_empty() or not auto_fill_grid(recipe):
				break
			grid = _inventory.get_craft_grid()
			recipe = CraftingRecipes.find_recipe(grid)
			if recipe.is_empty():
				break
		var output: Dictionary = recipe.get("output", {})
		var out_id := int(output.get("block_id", 0))
		var out_count := int(output.get("count", 0))
		if not _inventory.can_add_item(out_id, out_count):
			break
		_inventory.consume_grid_inputs(recipe)
		if not _inventory.add_item(out_id, out_count):
			break # should not happen after can_add_item
		crafted += 1
	if crafted > 0:
		_refresh()
	return crafted


## Recipe book: pull the required items out of the inventory into the grid,
## keeping anything already in the grid that matches. Rollback-safe.
func auto_fill_grid(recipe: Dictionary) -> bool:
	if not _can_interact() or recipe.is_empty():
		return false
	# how much of each requirement is still needed given current grid contents
	var needed := {}
	for req in recipe.get("inputs", []):
		needed[int(req.get("block_id", 0))] = int(req.get("count", 0))
	for grid_slot in _inventory.get_craft_grid():
		var gid := int(grid_slot.get("block_id", 0))
		if needed.has(gid):
			needed[gid] = maxi(0, int(needed[gid]) - int(grid_slot.get("count", 0)))
	# verify the inventory can cover the remainder BEFORE touching anything
	for req_id in needed.keys():
		if int(needed[req_id]) > 0 and not _inventory.has_item(int(req_id), int(needed[req_id])):
			return false
	# execute
	var pulled: Array[Dictionary] = [] # [{block_id, count}] for rollback
	var ok := true
	for req_id in needed.keys():
		var amount := int(needed[req_id])
		if amount <= 0:
			continue
		if not _inventory.remove_item(int(req_id), amount):
			ok = false
			break
		pulled.append({"block_id": int(req_id), "count": amount})
		# place: prefer merging into matching grid slots, then empty slots
		var remaining := amount
		for craft_index in range(CRAFT_GRID_SIZE):
			if remaining <= 0:
				break
			var grid_slot := _inventory.get_craft_slot(craft_index)
			if int(grid_slot.get("block_id", 0)) != int(req_id):
				continue
			var space := 64 - int(grid_slot.get("count", 0))
			if space <= 0:
				continue
			var moved := mini(space, remaining)
			var remainder := _inventory.set_craft_slot(
				craft_index, {"block_id": int(req_id), "count": int(grid_slot.get("count", 0)) + moved}
			)
			remaining -= moved
		for craft_index in range(CRAFT_GRID_SIZE):
			if remaining <= 0:
				break
			var grid_slot := _inventory.get_craft_slot(craft_index)
			if int(grid_slot.get("block_id", 0)) != 0:
				continue
			var placed_amount := remaining
			_inventory.set_craft_slot(craft_index, {"block_id": int(req_id), "count": placed_amount})
			remaining = 0
		if remaining > 0:
			ok = false
			break
	if not ok:
		# rollback: put pulled items back, leave grid untouched going forward
		for entry in pulled:
			_inventory.add_item(int(entry["block_id"]), int(entry["count"]))
		_refresh()
		return false
	_refresh()
	return true


func get_inventory_panel() -> PanelContainer:
	return _panels.get(Tab.INVENTORY)


func get_crafting_panel() -> PanelContainer:
	return _panels.get(Tab.CRAFTING)


func get_furnace_panel() -> PanelContainer:
	return _panels.get(Tab.FURNACE)


func get_furnace_status_label() -> Label:
	return _furnace_status_label


func get_toggle_button() -> Button:
	return _tab_buttons.get(Tab.INVENTORY)


func get_close_button() -> Button:
	return _close_button


func get_cursor_stack() -> Dictionary:
	return _cursor_stack.duplicate(true)


func get_cursor_label() -> Label:
	return _cursor_count_label


func get_slot_button(slot_index: int) -> Button:
	return _slot_buttons.get(slot_index)


func get_slot_count_label(slot_index: int) -> Label:
	return _slot_count_labels.get(slot_index)


func get_craft_slot_button(craft_index: int) -> Button:
	return _craft_slot_buttons.get(craft_index)


func get_craft_output_button() -> Button:
	return _craft_output_button


func get_result_label() -> Label:
	return _craft_result_label


func get_active_tab() -> int:
	return _active_tab


# ================================================================ interaction internals

func _can_interact() -> bool:
	return _is_open and _inventory != null


func _is_stack_empty(stack: Dictionary) -> bool:
	return int(stack.get("block_id", 0)) <= 0 or int(stack.get("count", 0)) <= 0


func _track_double_tap(slot_index: int) -> void:
	var now := Time.get_ticks_msec()
	if _last_tap_slot == slot_index and now - _last_tap_msec <= int(DOUBLE_TAP_SECONDS * 1000.0):
		_last_tap_slot = -1
		_last_tap_msec = -1
		# second tap of a double-tap: quick move whatever this slot holds
		_inventory.quick_move_slot(slot_index)
	else:
		_last_tap_slot = slot_index
		_last_tap_msec = now


func _update_cursor_visual_position() -> void:
	if not is_instance_valid(_cursor_visual):
		return
	var show := _is_open and not _is_stack_empty(_cursor_stack)
	if show:
		var carried_id := int(_cursor_stack.get("block_id", 0))
		var inner := _cursor_visual.get_node("CursorSwatch") as PanelContainer
		var style := inner.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = ITEM_REGISTRY.swatch_color(carried_id)
		var icon_rect := inner.get_node_or_null("CursorIcon") as TextureRect
		if icon_rect != null:
			icon_rect.texture = ITEM_REGISTRY.icon(carried_id)
			icon_rect.modulate = ITEM_REGISTRY.icon_tint(carried_id)
		_cursor_count_label.text = "x%d" % int(_cursor_stack.get("count", 0))
	_cursor_visual.visible = show
	if not show:
		return
	var mouse := _root.get_local_mouse_position()
	var viewport_size := _root.size
	var pos := Vector2(
		clampf(mouse.x + 12.0, 0.0, maxf(viewport_size.x - 80.0, 0.0)),
		clampf(mouse.y + 12.0, 0.0, maxf(viewport_size.y - 80.0, 0.0))
	)
	_cursor_visual.position = pos


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not _is_open:
				return
			var slot_index := _slot_at_position(touch.position)
			if slot_index >= 0:
				_begin_touch_slot(touch.index, slot_index)
				get_viewport().set_input_as_handled()
		else:
			if touch.index == _active_touch_index:
				_finish_touch_slot()
				get_viewport().set_input_as_handled()


func _slot_at_position(position: Vector2) -> int:
	for key in _slot_buttons.keys():
		var button := _slot_buttons[key] as Button
		if is_instance_valid(button) and button.visible and button.get_global_rect().has_point(position):
			return int(key)
	return -1


func _begin_touch_slot(touch_index: int, slot_index: int) -> void:
	_cancel_active_touch()
	_active_touch_index = touch_index
	_active_touch_slot = slot_index
	_long_press_consumed = false
	if is_instance_valid(_long_press_timer):
		_long_press_timer.start(LONG_PRESS_SECONDS)


func _finish_touch_slot() -> void:
	if is_instance_valid(_long_press_timer):
		_long_press_timer.stop()
	if not _long_press_consumed and _active_touch_slot >= 0:
		interact_slot_primary(_active_touch_slot)
	_active_touch_index = -1
	_active_touch_slot = -1
	_long_press_consumed = false


func _on_long_press_timeout() -> void:
	if _active_touch_index < 0 or _active_touch_slot < 0 or not _is_open:
		return
	_long_press_consumed = true
	interact_slot_secondary(_active_touch_slot)


func _cancel_active_touch() -> void:
	if is_instance_valid(_long_press_timer):
		_long_press_timer.stop()
	_active_touch_index = -1
	_active_touch_slot = -1
	_long_press_consumed = false


func _on_slot_pressed(slot_index: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		quick_move_slot(slot_index)
	else:
		interact_slot_primary(slot_index)


func _on_slot_right_clicked(slot_index: int) -> void:
	interact_slot_secondary(slot_index)


# ================================================================ tabs & refresh

func _apply_tab(tab: int, open: bool) -> void:
	var was_open := _is_open
	_is_open = open
	_active_tab = tab if open else _active_tab
	if is_instance_valid(_root):
		_root.visible = _is_open
		_root.mouse_filter = Control.MOUSE_FILTER_STOP if _is_open else Control.MOUSE_FILTER_IGNORE
		for key in _panels.keys():
			var panel := _panels[key] as Control
			panel.visible = _is_open and int(key) == _active_tab
		for key in _tab_buttons.keys():
			var button := _tab_buttons[key] as Button
			button.modulate = Color.WHITE if int(key) == _active_tab and _is_open else Color(1, 1, 1, 0.55)
	if _is_open and not was_open:
		_refresh()
	inventory_visibility_changed.emit(_is_open)


func _refresh() -> void:
	if _inventory == null or not is_instance_valid(_root):
		return
	for slot_index in range(_inventory.get_slot_count()):
		_paint_slot(slot_index, _inventory.get_slot(slot_index))
	for craft_index in range(CRAFT_GRID_SIZE):
		_paint_craft_slot(craft_index, _inventory.get_craft_slot(craft_index))
	_update_output_preview()
	_refresh_recipe_book()
	_refresh_furnace()
	_update_cursor_visual_position()


func _paint_slot(slot_index: int, stack: Dictionary) -> void:
	var style: StyleBoxFlat = _slot_swatch_styles.get(slot_index)
	var swatch: PanelContainer = _slot_swatch_panels.get(slot_index)
	var count_label: Label = _slot_count_labels.get(slot_index)
	if style == null or swatch == null or count_label == null:
		return
	var block_id := int(stack.get("block_id", 0))
	var count := int(stack.get("count", 0))
	var has_item := block_id > 0 and count > 0
	swatch.visible = has_item
	if has_item:
		style.bg_color = ITEM_REGISTRY.swatch_color(block_id)
		swatch.tooltip_text = ITEM_REGISTRY.display_name(block_id)
		var icon_rect := swatch.get_node("Icon") as TextureRect
		icon_rect.texture = ITEM_REGISTRY.icon(block_id)
		icon_rect.modulate = ITEM_REGISTRY.icon_tint(block_id)
	count_label.text = "x%d" % count if has_item else ""


func _paint_craft_slot(craft_index: int, stack: Dictionary) -> void:
	var button := _craft_slot_buttons.get(craft_index) as Button
	if button == null:
		return
	var block_id := int(stack.get("block_id", 0))
	var count := int(stack.get("count", 0))
	var has_item := block_id > 0 and count > 0
	var swatch := button.get_meta("swatch_panel") as PanelContainer
	var style := button.get_meta("swatch_style") as StyleBoxFlat
	var label := button.get_meta("count_label") as Label
	swatch.visible = has_item
	if has_item:
		style.bg_color = ITEM_REGISTRY.swatch_color(block_id)
		swatch.tooltip_text = ITEM_REGISTRY.display_name(block_id)
		var icon_rect := swatch.get_node("Icon") as TextureRect
		icon_rect.texture = ITEM_REGISTRY.icon(block_id)
		icon_rect.modulate = ITEM_REGISTRY.icon_tint(block_id)
	label.text = "x%d" % count if has_item else ""


func _update_output_preview() -> void:
	if _craft_output_button == null:
		return
	var grid := _inventory.get_craft_grid() if _inventory != null else []
	var recipe: Dictionary = CraftingRecipes.find_recipe(grid)
	var output: Dictionary = recipe.get("output", {})
	var out_id := int(output.get("block_id", 0))
	var out_count := int(output.get("count", 0))
	var has_result := out_id > 0 and out_count > 0
	var swatch := _craft_output_button.get_meta("swatch_panel") as PanelContainer
	var style := _craft_output_button.get_meta("swatch_style") as StyleBoxFlat
	var label := _craft_output_button.get_meta("count_label") as Label
	swatch.visible = has_result
	if has_result:
		style.bg_color = ITEM_REGISTRY.swatch_color(out_id)
		var icon_rect := swatch.get_node("Icon") as TextureRect
		icon_rect.texture = ITEM_REGISTRY.icon(out_id)
		icon_rect.modulate = ITEM_REGISTRY.icon_tint(out_id)
		label.text = "x%d" % out_count
	if _craft_result_label != null:
		if has_result:
			_craft_result_label.text = "%s x%d" % [ITEM_REGISTRY.display_name(out_id), out_count]
			_craft_result_label.add_theme_color_override("font_color", COLOR_OK)
		elif grid_has_any_item(grid):
			_craft_result_label.text = "No matching recipe"
			_craft_result_label.add_theme_color_override("font_color", COLOR_DIM)
		else:
			_craft_result_label.text = "Place items in the grid"
			_craft_result_label.add_theme_color_override("font_color", COLOR_DIM)


func grid_has_any_item(grid: Array) -> bool:
	for stack in grid:
		if int(stack.get("block_id", 0)) > 0 and int(stack.get("count", 0)) > 0:
			return true
	return false


func _refresh_recipe_book() -> void:
	if not _root.has_meta("recipe_rows"):
		return
	var rows: Array = _root.get_meta("recipe_rows")
	for i in range(rows.size()):
		var row := rows[i] as Button
		if not is_instance_valid(row):
			continue
		var recipe: Dictionary = CraftingRecipes.RECIPES[i]
		var craftable := CraftingRecipes.can_craft_from_inventory(recipe, _inventory)
		row.modulate = Color(1, 1, 1, 1.0) if craftable else Color(1, 1, 1, 0.45)


# ================================================================ furnace tab

func _ore_label(ore_id: int) -> String:
	return ITEM_REGISTRY.display_name(ore_id)


func _smelt_from_inventory(input_ore_id: int, max_operations: int) -> void:
	if _inventory == null or _smelt_running:
		return
	if not _inventory.has_item(input_ore_id, 1):
		if _furnace_status_label != null:
			_furnace_status_label.text = "No %s to smelt." % _ore_label(input_ore_id)
		return
	_smelt_running = true
	_set_furnace_buttons_enabled(false)
	var planned := mini(maxi(1, max_operations), _inventory.get_item_count(input_ore_id))
	var completed := 0
	for _op in range(planned):
		if not _inventory.has_item(input_ore_id, 1):
			break
		var report: Dictionary = FURNACE_RECIPES.smelt_once(_inventory)
		if not bool(report.get("ok", false)):
			break
		completed += 1
		if _furnace_status_label != null:
			_furnace_status_label.text = "SMELTING %s ... %d/%d" % [
				_ore_label(input_ore_id), completed, planned,
			]
		_refresh()
		var tree := get_tree()
		if tree == null:
			break
		await tree.create_timer(SMELT_SECONDS_PER_OPERATION).timeout
	_smelt_running = false
	_set_furnace_buttons_enabled(true)
	if _furnace_status_label != null:
		_furnace_status_label.text = (
			"SMELTED %d x %s" % [completed, _ore_label(input_ore_id)]
			if completed > 0
			else "Need %s and fuel (coal or charcoal or log)." % _ore_label(input_ore_id)
		)
	_refresh()


func _set_furnace_buttons_enabled(enabled: bool) -> void:
	for button in _furnace_buttons:
		if is_instance_valid(button):
			button.disabled = not enabled


func _refresh_furnace() -> void:
	if _furnace_status_label == null or _inventory == null:
		return
	var parts: Array[String] = []
	for input_id in FURNACE_RECIPES.SMELT_MAP.keys():
		parts.append("%s x%d" % [_ore_label(int(input_id)), _inventory.get_item_count(int(input_id))])
	parts.append("COAL x%d" % _inventory.get_item_count(FURNACE_RECIPES.FUEL_COAL))
	parts.append("LOG x%d" % _inventory.get_item_count(FURNACE_RECIPES.FUEL_LOG))
	_furnace_status_label.text = " | ".join(parts)


func _return_grid_on_close() -> void:
	if _inventory == null:
		return
	var stranded := _inventory.return_craft_grid_to_inventory()
	if stranded > 0:
		push_warning("Inventory full: %d crafted-grid items stayed in the grid" % stranded)


# ================================================================ construction

func _build_screen() -> void:
	_root = Control.new()
	_root.name = "InventoryRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.02, 0.04, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			close_inventory()
	)
	_root.add_child(_dim)

	_long_press_timer = Timer.new()
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)

	_build_tab_bar()
	_build_inventory_panel()
	_build_crafting_panel()
	_build_furnace_panel()
	_build_cursor_visual()


func _build_tab_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TabBar"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.0
	bar.offset_left = -300.0
	bar.offset_right = 300.0
	bar.offset_top = 18.0
	bar.offset_bottom = 58.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	_root.add_child(bar)

	var tabs := {
		Tab.INVENTORY: "INVENTORY",
		Tab.CRAFTING: "CRAFTING",
		Tab.FURNACE: "FURNACE",
	}
	for tab in tabs.keys():
		var button := Button.new()
		button.text = tabs[tab]
		button.custom_minimum_size = Vector2(150, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_hover_color", COLOR_ACCENT)
		button.add_theme_stylebox_override(
			"normal", _texture_style(UI_BUTTON_TEX, Color(0.60, 0.60, 0.60), 3))
		button.add_theme_stylebox_override(
			"hover", _texture_style(UI_BUTTON_TEX, Color(0.95, 0.95, 0.95), 3))
		button.add_theme_stylebox_override(
			"pressed", _texture_style(UI_BUTTON_TEX, Color(0.42, 0.42, 0.42), 3))
		button.pressed.connect(_on_tab_pressed.bind(tab))
		bar.add_child(button)
		_tab_buttons[tab] = button

	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close (E / ESC)"
	close_button.custom_minimum_size = Vector2(52, 44)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.75, 0.70))
	close_button.add_theme_stylebox_override(
		"normal", _texture_style(UI_SLOT_TEX, Color(0.55, 0.30, 0.28), 3))
	close_button.add_theme_stylebox_override(
		"hover", _texture_style(UI_SLOT_TEX, Color(0.85, 0.40, 0.36), 3))
	close_button.add_theme_stylebox_override(
		"pressed", _texture_style(UI_SLOT_TEX, Color(0.40, 0.22, 0.20), 3))
	close_button.pressed.connect(close_inventory)
	bar.add_child(close_button)
	_close_button = close_button


func _on_tab_pressed(tab: int) -> void:
	if not _is_open:
		_apply_tab(tab, true)
	elif _active_tab == tab:
		close_inventory()
	else:
		_apply_tab(tab, true)


func _panel_shell(panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -430.0
	panel.offset_top = -270.0
	panel.offset_right = 430.0
	panel.offset_bottom = 270.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	panel.add_theme_stylebox_override(
		"panel", _texture_style(UI_PANEL_TEX, Color(0.30, 0.30, 0.34))
	)
	_root.add_child(panel)
	return panel


func _make_column(parent: Control, separation := 10) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column


func _title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TITLE_SIZE)
	return label


## Nine-patch style from a downloaded 16x16 texture.
func _texture_style(tex_path: String, tint: Color, margin := 3) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(tex_path)
	style.modulate_color = tint
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.set_content_margin_all(PANEL_PADDING)
	return style


func _slot_box(bg: Color, border: Color, width: int, radius := 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _build_slot_button(interact_primary: Callable, interact_secondary: Callable,
		key_number := "") -> Dictionary:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(
		"normal", _texture_style(UI_SLOT_TEX, Color(0.55, 0.55, 0.62), 2)
	)
	button.add_theme_stylebox_override(
		"hover", _texture_style(UI_SLOT_TEX, Color(0.85, 0.85, 0.92), 2)
	)
	button.add_theme_stylebox_override(
		"pressed", _texture_style(UI_SLOT_TEX, Color(0.40, 0.40, 0.46), 2)
	)

	var swatch := PanelContainer.new()
	swatch.name = "Swatch"
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.visible = false
	var swatch_style := _slot_box(Color(0.13, 0.13, 0.16), Color(0, 0, 0, 0.45), 2, 4)
	swatch.add_theme_stylebox_override("panel", swatch_style)

	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.offset_left = 4
	icon_rect.offset_top = 4
	icon_rect.offset_right = -4
	icon_rect.offset_bottom = -4
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_child(icon_rect)

	button.add_child(swatch)

	var count_label := Label.new()
	count_label.name = "Count"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.anchor_left = 0.0
	count_label.anchor_right = 1.0
	count_label.anchor_top = 1.0
	count_label.anchor_bottom = 1.0
	count_label.offset_left = -SLOT_SIZE.x + 5.0
	count_label.offset_top = -18.0
	count_label.offset_right = -4.0
	count_label.offset_bottom = -3.0
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	count_label.add_theme_constant_override("shadow_offset_x", 1)
	count_label.add_theme_constant_override("shadow_offset_y", 1)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(count_label)

	if key_number != "":
		var key_label := Label.new()
		key_label.text = key_number
		key_label.position = Vector2(4, 2)
		key_label.add_theme_font_size_override("font_size", 11)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(key_label)

	button.pressed.connect(interact_primary)
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			interact_secondary.call()
			get_viewport().set_input_as_handled()
	)
	button.set_meta("swatch_panel", swatch)
	button.set_meta("swatch_style", swatch_style)
	button.set_meta("count_label", count_label)
	return {"button": button, "swatch": swatch, "style": swatch_style, "count": count_label}


func _build_inventory_panel() -> void:
	var panel := _panel_shell("InventoryPanel")
	_panels[Tab.INVENTORY] = panel

	var column := _make_column(panel)
	column.add_child(_title_label("Inventory"))

	var storage_title := Label.new()
	storage_title.text = "Storage"
	storage_title.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	storage_title.modulate = COLOR_DIM
	column.add_child(storage_title)

	var storage_grid := GridContainer.new()
	storage_grid.columns = 9
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(storage_grid)

	for storage_index in range(STORAGE_SLOT_COUNT):
		var slot_index := STORAGE_START_INDEX + storage_index
		var nodes := _build_slot_button(
			_on_slot_pressed.bind(slot_index),
			_on_slot_right_clicked.bind(slot_index)
		)
		storage_grid.add_child(nodes["button"])
		_register_slot(slot_index, nodes)

	var hotbar_spacer := Control.new()
	hotbar_spacer.custom_minimum_size = Vector2(0, 8)
	column.add_child(hotbar_spacer)

	var hotbar_title := Label.new()
	hotbar_title.text = "Hotbar (1-9)"
	hotbar_title.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	hotbar_title.modulate = COLOR_DIM
	column.add_child(hotbar_title)

	var hotbar_grid := GridContainer.new()
	hotbar_grid.columns = 9
	hotbar_grid.add_theme_constant_override("h_separation", 6)
	hotbar_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(hotbar_grid)

	for hotbar_index in range(HOTBAR_SLOT_COUNT):
		var nodes := _build_slot_button(
			_on_slot_pressed.bind(hotbar_index),
			_on_slot_right_clicked.bind(hotbar_index),
			str(hotbar_index + 1)
		)
		hotbar_grid.add_child(nodes["button"])
		_register_slot(hotbar_index, nodes)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)

	var hint := Label.new()
	hint.text = "Tap/click: pick & place   |   Hold / right-click: half stack   |   Double-tap / Shift+click: quick move"
	hint.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	hint.modulate = COLOR_DIM
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)

	var sort_button := Button.new()
	sort_button.text = "TIDY"
	sort_button.focus_mode = Control.FOCUS_NONE
	sort_button.pressed.connect(func() -> void:
		_inventory.compact()
		_refresh()
	)
	footer.add_child(sort_button)


func _register_slot(slot_index: int, nodes: Dictionary) -> void:
	_slot_buttons[slot_index] = nodes["button"]
	_slot_swatch_styles[slot_index] = nodes["style"]
	_slot_swatch_panels[slot_index] = nodes["swatch"]
	_slot_count_labels[slot_index] = nodes["count"]


func _build_crafting_panel() -> void:
	var panel := _panel_shell("CraftingPanel")
	_panels[Tab.CRAFTING] = panel

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	# left: grid + output
	var left := _make_column(columns, 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_title_label("Crafting"))

	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 14)
	craft_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(craft_row)

	var grid_box := GridContainer.new()
	grid_box.columns = 2
	grid_box.add_theme_constant_override("h_separation", 6)
	grid_box.add_theme_constant_override("v_separation", 6)
	craft_row.add_child(grid_box)

	for craft_index in range(CRAFT_GRID_SIZE):
		var idx := craft_index # capture
		var nodes := _build_slot_button(
			func() -> void: interact_craft_input(idx, Input.is_key_pressed(KEY_SHIFT)),
			func() -> void: split_craft_input(idx)
		)
		grid_box.add_child(nodes["button"])
		_craft_slot_buttons[craft_index] = nodes["button"]

	var arrow := Label.new()
	arrow.text = "->"
	arrow.add_theme_font_size_override("font_size", 26)
	arrow.modulate = COLOR_DIM
	craft_row.add_child(arrow)

	var output_wrapper := CenterContainer.new()
	output_wrapper.custom_minimum_size = Vector2(SLOT_SIZE.x + 8, SLOT_SIZE.y + 8)
	craft_row.add_child(output_wrapper)
	var out_nodes := _build_slot_button(
		func() -> void: interact_craft_output(),
		func() -> void: pass
	)
	_craft_output_button = out_nodes["button"]
	_craft_output_style = out_nodes["style"]
	_craft_output_button.custom_minimum_size = Vector2(72, 72)
	output_wrapper.add_child(_craft_output_button)

	left.add_child(_craft_result_label_placeholder())

	var craft_row2 := HBoxContainer.new()
	craft_row2.add_theme_constant_override("separation", 10)
	left.add_child(craft_row2)

	var take_button := Button.new()
	take_button.text = "TAKE RESULT"
	take_button.focus_mode = Control.FOCUS_NONE
	take_button.pressed.connect(func() -> void:
		interact_craft_output()
		_refresh()
	)
	craft_row2.add_child(take_button)

	var craft_all := Button.new()
	craft_all.text = "CRAFT ALL -> BAG"
	craft_all.focus_mode = Control.FOCUS_NONE
	craft_all.pressed.connect(func() -> void:
		craft_all_to_inventory()
	)
	craft_row2.add_child(craft_all)

	var clear_grid := Button.new()
	clear_grid.text = "RETURN GRID"
	clear_grid.focus_mode = Control.FOCUS_NONE
	clear_grid.pressed.connect(func() -> void:
		_inventory.return_craft_grid_to_inventory()
		_refresh()
	)
	craft_row2.add_child(clear_grid)

	# right: recipe book
	var right := _make_column(columns, 8)
	right.custom_minimum_size = Vector2(360, 0)
	var book_title := Label.new()
	book_title.text = "Recipe Book  (click to fill the grid)"
	book_title.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	book_title.modulate = COLOR_DIM
	right.add_child(book_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)

	var recipe_list := VBoxContainer.new()
	recipe_list.add_theme_constant_override("separation", 6)
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(recipe_list)

	var rows: Array = []
	for recipe in CraftingRecipes.RECIPES:
		var row := _build_recipe_row(recipe)
		recipe_list.add_child(row)
		rows.append(row)
	_root.set_meta("recipe_rows", rows)


func _craft_result_label_placeholder() -> Label:
	_craft_result_label = Label.new()
	_craft_result_label.text = "Place items in the grid"
	_craft_result_label.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	_craft_result_label.modulate = COLOR_DIM
	return _craft_result_label


func _build_recipe_row(recipe: Dictionary) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(340, 52)
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = false
	var normal := _texture_style(UI_BUTTON_TEX, Color(0.62, 0.62, 0.62), 2)
	var hover := _texture_style(UI_BUTTON_TEX, Color(0.90, 0.90, 0.90), 2)
	normal.set_content_margin_all(8.0)
	hover.set_content_margin_all(8.0)
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", hover)

	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var out_icon_id := int(recipe.get("output", {}).get("block_id", 0))
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(30, 30)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _slot_box(Color(0.13, 0.13, 0.16), Color(0, 0, 0, 0.45), 2, 4)
	style.bg_color = ITEM_REGISTRY.swatch_color(out_icon_id)
	swatch.add_theme_stylebox_override("panel", style)
	if ITEM_REGISTRY.icon(out_icon_id) != null:
		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 3
		icon_rect.offset_top = 3
		icon_rect.offset_right = -3
		icon_rect.offset_bottom = -3
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.texture = ITEM_REGISTRY.icon(out_icon_id)
		icon_rect.modulate = ITEM_REGISTRY.icon_tint(out_icon_id)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.add_child(icon_rect)
	box.add_child(swatch)

	var text := Label.new()
	var out_id := int(recipe.get("output", {}).get("block_id", 0))
	var out_count := int(recipe.get("output", {}).get("count", 1))
	var parts: Array[String] = []
	for req in recipe.get("inputs", []):
		parts.append("%dx %s" % [int(req.get("count", 0)), ITEM_REGISTRY.display_name(int(req.get("block_id", 0)))])
	text.text = "%s x%d\n%s" % [ITEM_REGISTRY.display_name(out_id), out_count, " + ".join(parts)]
	text.add_theme_font_size_override("font_size", 12)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)

	row.pressed.connect(func() -> void:
		auto_fill_grid(recipe)
	)
	return row


func _build_furnace_panel() -> void:
	var panel := _panel_shell("FurnacePanel")
	_panels[Tab.FURNACE] = panel

	var column := _make_column(panel, 12)
	column.add_child(_title_label("Furnace"))

	_furnace_status_label = Label.new()
	_furnace_status_label.name = "FurnaceStatus"
	_furnace_status_label.text = "No smeltable ores."
	_furnace_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_furnace_status_label.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	column.add_child(_furnace_status_label)

	var hint := Label.new()
	hint.text = "1 ore + 1 fuel (coal, charcoal or log) -> 1 item, one op at a time."
	hint.add_theme_font_size_override("font_size", SUBTITLE_SIZE)
	hint.modulate = COLOR_DIM
	column.add_child(hint)

	_furnace_buttons.clear()
	for input_id in FURNACE_RECIPES.SMELT_MAP.keys():
		var ore_id := int(input_id)
		var out_id := FURNACE_RECIPES.smelt_output_for(ore_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		column.add_child(row)

		var swatch := PanelContainer.new()
		swatch.custom_minimum_size = Vector2(30, 30)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := _slot_box(Color.WHITE, Color(0, 0, 0, 0.45), 2, 4)
		style.bg_color = ITEM_REGISTRY.swatch_color(out_id)
		swatch.add_theme_stylebox_override("panel", style)
		row.add_child(swatch)

		var ore_swatch := PanelContainer.new()
		ore_swatch.name = "OreSwatch"
		ore_swatch.custom_minimum_size = Vector2(30, 30)
		ore_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ore_style := _slot_box(Color(0.13, 0.13, 0.16), Color(0, 0, 0, 0.45), 2, 4)
		ore_style.bg_color = ITEM_REGISTRY.swatch_color(out_id)
		ore_swatch.add_theme_stylebox_override("panel", ore_style)
		if ITEM_REGISTRY.icon(ore_id) != null:
			var ore_icon := TextureRect.new()
			ore_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			ore_icon.offset_left = 3
			ore_icon.offset_top = 3
			ore_icon.offset_right = -3
			ore_icon.offset_bottom = -3
			ore_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ore_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ore_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ore_icon.texture = ITEM_REGISTRY.icon(ore_id)
			ore_icon.modulate = ITEM_REGISTRY.icon_tint(ore_id)
			ore_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ore_swatch.add_child(ore_icon)
		row.add_child(ore_swatch)

		var smelt_one := Button.new()
		smelt_one.text = "SMELT 1 %s" % _ore_label(ore_id)
		smelt_one.custom_minimum_size = Vector2(230, 40)
		smelt_one.focus_mode = Control.FOCUS_NONE
		smelt_one.add_theme_stylebox_override(
			"normal", _texture_style(UI_BUTTON_TEX, Color(0.62, 0.62, 0.62), 2))
		smelt_one.add_theme_stylebox_override(
			"hover", _texture_style(UI_BUTTON_TEX, Color(0.95, 0.95, 0.95), 2))
		smelt_one.add_theme_stylebox_override(
			"pressed", _texture_style(UI_BUTTON_TEX, Color(0.45, 0.45, 0.45), 2))
		smelt_one.pressed.connect(func() -> void: _smelt_from_inventory(ore_id, 1))
		row.add_child(smelt_one)

		var smelt_all := Button.new()
		smelt_all.text = "SMELT ALL"
		smelt_all.custom_minimum_size = Vector2(130, 40)
		smelt_all.focus_mode = Control.FOCUS_NONE
		smelt_all.add_theme_stylebox_override(
			"normal", _texture_style(UI_BUTTON_TEX, Color(0.62, 0.62, 0.62), 2))
		smelt_all.add_theme_stylebox_override(
			"hover", _texture_style(UI_BUTTON_TEX, Color(0.95, 0.95, 0.95), 2))
		smelt_all.add_theme_stylebox_override(
			"pressed", _texture_style(UI_BUTTON_TEX, Color(0.45, 0.45, 0.45), 2))
		smelt_all.pressed.connect(func() -> void: _smelt_from_inventory(ore_id, 64))
		row.add_child(smelt_all)

		_furnace_buttons.append(smelt_one)
		_furnace_buttons.append(smelt_all)


func _build_cursor_visual() -> void:
	_cursor_visual = PanelContainer.new()
	_cursor_visual.name = "CursorStack"
	_cursor_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_visual.z_index = 100
	_cursor_visual.visible = false
	_cursor_style = _slot_box(Color(0.95, 0.85, 0.30), Color(0, 0, 0, 0.6), 2, 6)
	_cursor_style.bg_color = Color(0.12, 0.12, 0.14)
	_cursor_visual.add_theme_stylebox_override("panel", _cursor_style)
	var inner := PanelContainer.new()
	inner.name = "CursorSwatch"
	inner.custom_minimum_size = Vector2(36, 36)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _slot_box(Color(0.13, 0.13, 0.16), Color(0, 0, 0, 0.45), 2, 4))
	var cursor_icon := TextureRect.new()
	cursor_icon.name = "CursorIcon"
	cursor_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	cursor_icon.offset_left = 3
	cursor_icon.offset_top = 3
	cursor_icon.offset_right = -3
	cursor_icon.offset_bottom = -3
	cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cursor_icon)
	_cursor_visual.add_child(inner)
	_cursor_count_label = Label.new()
	_cursor_count_label.name = "CursorCount"
	_cursor_count_label.add_theme_font_size_override("font_size", 13)
	_cursor_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_cursor_count_label)
	_root.add_child(_cursor_visual)
