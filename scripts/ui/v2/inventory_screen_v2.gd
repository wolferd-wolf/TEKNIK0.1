extends CanvasLayer
class_name InventoryScreenV2

## v2 inventory screen — WRITER TIER. This is the only UI node allowed to
## call mutating backend methods (BlockInventory mutators,
## CraftingRecipes.*, FurnaceRecipes.*). Slots and panels are dumb
## widgets fed view payloads; backend state is the single source of truth.

signal inventory_visibility_changed(is_open: bool)

const TOGGLE_ACTION := StringName("toggle_inventory")
const CRAFT_ACTION := StringName("toggle_crafting")

const ITEM_REGISTRY := preload("res://scripts/items/item_registry.gd")
const CRAFTING_RECIPES := preload("res://scripts/crafting/crafting_recipes.gd")
const FURNACE_RECIPES := preload("res://scripts/smelting/furnace_recipes.gd")
const SLOT_VIEW := preload("res://scripts/ui/v2/slot_view_builder.gd")

const HOTBAR_SLOT_COUNT := 9
const STORAGE_SLOT_COUNT := 27
const STORAGE_START_INDEX := HOTBAR_SLOT_COUNT
const DOUBLE_TAP_SECONDS := 0.35
const SMELT_SECONDS_PER_OPERATION := 1.2

enum Tab { INVENTORY, CRAFTING, FURNACE }

var _inventory: BlockInventory
var _player: Node

@onready var _root: Control = %Root
@onready var _dim: ColorRect = %Dim
@onready var _tab_bar: HBoxContainer = %TabBar
@onready var _inventory_panel: PanelContainer = %InventoryPanel
@onready var _storage_grid: GridContainer = %StorageGrid
@onready var _hotbar_grid: GridContainer = %HotbarGrid
@onready var _crafting_panel: PanelContainer = %CraftingPanel
@onready var _furnace_panel: PanelContainer = %FurnacePanel
@onready var _cursor_visual: PanelContainer = %CursorStack

var _slot_widgets := {} # slot index -> ItemSlotV2
var _tab_buttons := {}
var _close_button: Button

var _cursor_stack := {"block_id": 0, "count": 0}
var _is_open := false
var _active_tab: int = Tab.INVENTORY

var _last_tap_slot := -1
var _last_tap_msec := -1


func _ready() -> void:
	_build_tab_buttons()
	_populate_grids()
	var tidy := Button.new()
	tidy.text = "TIDY"
	tidy.pressed.connect(func() -> void:
		if _can_interact():
			_inventory.compact()
			_refresh()
	)
	(%Footer as HBoxContainer).add_child(tidy)
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			close_inventory()
	)
	_apply_tab(Tab.INVENTORY, false)


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
	_update_cursor_position()


# ---------------------------------------------------------------- public API

func is_inventory_open() -> bool:
	return _is_open


func get_active_tab() -> int:
	return _active_tab


func toggle_inventory() -> void:
	if _is_open:
		close_inventory() # closes from ANY tab
	else:
		open_inventory()


func open_inventory() -> void:
	_apply_tab(Tab.INVENTORY, true)


func close_inventory() -> bool:
	if not _return_cursor_to_inventory():
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


func get_cursor_stack() -> Dictionary:
	return _cursor_stack.duplicate(true)


func get_slot_widget(slot_index: int) -> ItemSlotV2:
	return _slot_widgets.get(slot_index)


func get_panel_for(tab: int) -> PanelContainer:
	match tab:
		Tab.INVENTORY: return _inventory_panel
		Tab.CRAFTING: return _crafting_panel
		Tab.FURNACE: return _furnace_panel
	return null


# ---------------------------------------------------------------- writer tier

func _can_interact() -> bool:
	return _is_open and _inventory != null


func _carry_empty() -> bool:
	return int(_cursor_stack.get("block_id", 0)) <= 0 or int(_cursor_stack.get("count", 0)) <= 0


## Tap-to-move: pick up / place / swap. Shift+tap quick-moves.
func _on_slot_tapped(slot_index: int) -> void:
	if not _can_interact():
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_on_quick_move(slot_index)
		return
	if _carry_empty():
		_cursor_stack = _inventory.take_from_slot(slot_index)
	else:
		_cursor_stack = _inventory.put_stack_into_slot(slot_index, _cursor_stack)
	_track_double_tap(slot_index)
	_refresh()


## Long-press or right-click: split half into the carry stack.
func _on_slot_split(slot_index: int) -> void:
	if not _can_interact():
		return
	if _carry_empty():
		_cursor_stack = _inventory.split_from_slot(slot_index)
	else:
		_cursor_stack = _inventory.put_stack_into_slot(slot_index, _cursor_stack, true)
	_refresh()


## Double-tap or Shift+click: quick move between hotbar and storage.
func _on_quick_move(slot_index: int) -> void:
	if not _can_interact():
		return
	if not _carry_empty():
		_on_slot_tapped(slot_index) # carrying: drop carried stack here instead
		return
	_inventory.quick_move_slot(slot_index)
	_refresh()


func _on_secondary(slot_index: int) -> void:
	_on_slot_split(slot_index)


## Commit-2 note: crafting grid + recipe book + furnace handlers land with
## those tabs. Close-time safety below already covers the craft grid so a
## half-built grid can never strand items even in this commit.


func _track_double_tap(slot_index: int) -> void:
	var now := Time.get_ticks_msec()
	if _last_tap_slot == slot_index and now - _last_tap_msec <= int(DOUBLE_TAP_SECONDS * 1000.0):
		_last_tap_slot = -1
		_last_tap_msec = -1
		_inventory.quick_move_slot(slot_index)
	else:
		_last_tap_slot = slot_index
		_last_tap_msec = now


## TIDY button entry point.
func _tidy() -> void:
	if _can_interact():
		_inventory.compact()
		_refresh()


func _return_cursor_to_inventory() -> bool:
	if _carry_empty():
		return true
	var block_id := int(_cursor_stack.get("block_id", 0))
	var count := int(_cursor_stack.get("count", 0))
	if not _inventory.can_add_item(block_id, count):
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


func _return_grid_on_close() -> void:
	if _inventory == null:
		return
	var stranded := _inventory.return_craft_grid_to_inventory()
	if stranded > 0:
		push_warning("Inventory full: %d crafted-grid items stayed in the grid" % stranded)


# ---------------------------------------------------------------- tabs & paint

func _apply_tab(tab: int, open_state: bool) -> void:
	var was_open := _is_open
	_is_open = open_state
	_active_tab = tab if open_state else _active_tab
	_root.visible = _is_open
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if _is_open else Control.MOUSE_FILTER_IGNORE
	for key in [Tab.INVENTORY, Tab.CRAFTING, Tab.FURNACE]:
		var panel := get_panel_for(key)
		panel.visible = _is_open and key == _active_tab
		var button := _tab_buttons[key] as Button
		button.modulate = Color.WHITE if (key == _active_tab and _is_open) else Color(1, 1, 1, 0.55)
	if _is_open and not was_open:
		_refresh()
	inventory_visibility_changed.emit(_is_open)


func _refresh() -> void:
	if _inventory == null or _root == null:
		return
	for slot_index in range(_inventory.get_slot_count()):
		var widget := _slot_widgets.get(slot_index) as ItemSlotV2
		if widget != null:
			widget.bind_view(SLOT_VIEW.build(_inventory.get_slot(slot_index)))
	_update_cursor_position()


func _update_cursor_position() -> void:
	if _cursor_visual == null:
		return
	var show := _is_open and not _carry_empty()
	_cursor_visual.visible = show
	if not show:
		return
	var carried_id := int(_cursor_stack.get("block_id", 0))
	var icon_rect := _cursor_visual.get_node("%CursorIcon") as TextureRect
	icon_rect.texture = ITEM_REGISTRY.icon(carried_id)
	icon_rect.modulate = ITEM_REGISTRY.icon_tint(carried_id)
	var count_label := _cursor_visual.get_node("%CursorCount") as Label
	count_label.text = "x%d" % int(_cursor_stack.get("count", 0))
	var mouse := _root.get_local_mouse_position()
	var viewport_size := _root.size
	_cursor_visual.position = Vector2(
		clampf(mouse.x + 12.0, 0.0, maxf(viewport_size.x - 90.0, 0.0)),
		clampf(mouse.y + 12.0, 0.0, maxf(viewport_size.y - 90.0, 0.0))
	)


# ---------------------------------------------------------------- construction

func _build_tab_buttons() -> void:
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
		button.pressed.connect(_on_tab_pressed.bind(tab))
		_tab_bar.add_child(button)
		_tab_buttons[tab] = button

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.tooltip_text = "Close (E / ESC)"
	_close_button.custom_minimum_size = Vector2(52, 44)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	_close_button.pressed.connect(close_inventory)
	_tab_bar.add_child(_close_button)


func _on_tab_pressed(tab: int) -> void:
	if not _is_open:
		_apply_tab(tab, true)
	elif _active_tab == tab:
		close_inventory()
	else:
		_apply_tab(tab, true)


func _populate_grids() -> void:
	for hotbar_index in range(HOTBAR_SLOT_COUNT):
		_hotbar_grid.add_child(_make_slot(hotbar_index, str(hotbar_index + 1)))
	for storage_index in range(STORAGE_SLOT_COUNT):
		var slot_index := STORAGE_START_INDEX + storage_index
		_storage_grid.add_child(_make_slot(slot_index))


func _make_slot(slot_index: int, key_number := "") -> ItemSlotV2:
	var widget := ItemSlotV2.new()
	widget.configure(slot_index, key_number)
	widget.slot_tapped.connect(_on_slot_tapped)
	widget.slot_long_pressed.connect(_on_slot_split)
	widget.slot_secondary.connect(_on_secondary)
	_slot_widgets[slot_index] = widget
	return widget
