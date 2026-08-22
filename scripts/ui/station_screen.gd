extends CanvasLayer
class_name StationScreen

## Rehauled fullscreen menu: player inventory panel flanked by a CRAFT
## button on its left edge and a CLOSE button on its right edge. The upper
## area swaps between crafting (2x2), a placed crafting table (3x3), a
## furnace panel and a placed chest. All item state lives in BlockInventory
## / BlockStations; this screen only moves stacks between them.

signal inventory_visibility_changed(is_open: bool)

const SLOT_SIZE := 46
const MAX_STACK := 64

enum Mode { INVENTORY, CRAFT, TABLE, FURNACE, CHEST, BOOK }

var player_inventory: BlockInventory
var stations: BlockStations

var _mode: int = Mode.INVENTORY
var _is_open := false
var _station_coord := Vector3i.ZERO
var _held: Dictionary = {}
var _last_smelt_output := {}
var _table_grid: Array[Dictionary] = []

var _root: Control
var _title: Label
var _station_area: VBoxContainer
var _inv_panel: PanelContainer
var _craft_button: Button
var _close_button: Button
var _storage_views: Array[ItemSlotView] = []
var _hotbar_views: Array[ItemSlotView] = []
var _craft_views: Array[ItemSlotView] = []
var _result_view: ItemSlotView
var _craft_area: HBoxContainer
var _craft_grid_container: GridContainer
var _table_grid_container: GridContainer
var _table_views: Array[ItemSlotView] = []
var _chest_box: VBoxContainer
var _chest_views: Array[ItemSlotView] = []
var _furnace_box: HBoxContainer
var _furnace_input_view: ItemSlotView
var _furnace_fuel_view: ItemSlotView
var _furnace_output_view: ItemSlotView
var _held_view: ItemSlotView
var _active_touch_index := -1
var _extra_buttons: Array[Button] = []
var _book_button: Button
var _book_pan_active := false
var _book_pan_last_y := 0.0
var _pending_press := {}
const LONG_PRESS_MSEC := 450
const TAP_MOVE_CANCEL_PX := 24.0
var _book_box: VBoxContainer
var _book_rows: Array[Dictionary] = []
var _book_table_mode := false


func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()
	set_process(true)


func setup(p_inventory: BlockInventory, p_stations: BlockStations) -> void:
	player_inventory = p_inventory
	stations = p_stations
	if player_inventory != null and not player_inventory.changed.is_connected(_refresh):
		player_inventory.changed.connect(_refresh)


# ---------------------------------------------------------------- public API

func is_inventory_open() -> bool:
	return _is_open


func get_craft_button() -> Button:
	return _craft_button


func get_close_button() -> Button:
	return _close_button


func get_inventory_panel() -> Control:
	return _inv_panel


func open_inventory() -> void:
	_set_mode(Mode.INVENTORY)
	_set_open(true)


func open_crafting() -> void:
	_set_mode(Mode.CRAFT)
	_set_open(true)


## Compat contract used by TouchActionControls (and the old screen's API).
func toggle_inventory() -> void:
	if _is_open:
		close_screen()
	else:
		open_inventory()


## Compat contract: opens crafting from closed, closes an open screen.
func toggle_crafting() -> void:
	if _is_open:
		close_screen()
	else:
		open_crafting()


func open_station(block_id: int, coord: Vector3i) -> void:
	_station_coord = coord
	match block_id:
		BlockStations.STATION_CRAFTING_TABLE:
			_reset_table_grid()
			_set_mode(Mode.TABLE)
		BlockStations.STATION_CHEST:
			if stations != null:
				stations.register_chest(coord)
			_set_mode(Mode.CHEST)
		BlockStations.STATION_FURNACE:
			_set_mode(Mode.FURNACE)
		_:
			_set_mode(Mode.INVENTORY)
	_set_open(true)


func close_screen() -> void:
	_return_transient_items()
	_held = {}
	_set_open(false)


# ---------------------------------------------------------------- construction

static func _panel_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.08, 0.08, 0.10)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 12.0
	return style


static func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.05, 0.05, 0.06)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _make_button(text_value: String, min_width: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(min_width, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.22, 0.24, 0.28)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.30, 0.33, 0.38)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.17, 0.20)))
	return button


func _make_grid(columns: int, rows: int, kind: String, target: Array[ItemSlotView]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for index in range(columns * rows):
		var view := ItemSlotView.new({"kind": kind, "index": index})
		view.slot_clicked.connect(_on_slot_clicked)
		grid.add_child(view)
		target.append(view)
	return grid


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.13, 0.15, 0.98)))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title = Label.new()
	_title.text = "INVENTORY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 5)
	vbox.add_child(_title)

	_station_area = VBoxContainer.new()
	_station_area.add_theme_constant_override("separation", 6)
	_station_area.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_station_area)
	_build_station_areas()

	# The row required by the rehoul: CRAFT | inventory panel | CLOSE.
	var main_row := HBoxContainer.new()
	main_row.name = "MainRow"
	main_row.add_theme_constant_override("separation", 8)
	vbox.add_child(main_row)

	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 4)
	main_row.add_child(left_column)

	_craft_button = _make_button("CRAFT", 92)
	_craft_button.name = "CraftButton"
	_craft_button.pressed.connect(_on_craft_pressed)
	left_column.add_child(_craft_button)
	_extra_buttons.append(_craft_button)

	_book_button = _make_button("RECIPES", 92)
	_book_button.name = "BookButton"
	_book_button.pressed.connect(_on_book_pressed)
	left_column.add_child(_book_button)
	_extra_buttons.append(_book_button)

	_inv_panel = PanelContainer.new()
	_inv_panel.name = "InvPanel"
	_inv_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.16, 0.16, 0.19))
	)
	main_row.add_child(_inv_panel)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 5)
	_inv_panel.add_child(inv_vbox)
	var storage_grid := _make_grid(9, 3, "storage", _storage_views)
	inv_vbox.add_child(storage_grid)
	var hotbar_grid := _make_grid(9, 1, "hotbar", _hotbar_views)
	inv_vbox.add_child(hotbar_grid)

	_close_button = _make_button("CLOSE", 92)
	_close_button.name = "CloseButton"
	_close_button.pressed.connect(close_screen)
	main_row.add_child(_close_button)
	_extra_buttons.append(_close_button)

	_held_view = ItemSlotView.new({"kind": "held"})
	_held_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_view.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_held_view.visible = false
	_root.add_child(_held_view)


func _build_station_areas() -> void:
	# --- crafting (2x2 player grid) and table (3x3) share one row layout ---
	_craft_area = HBoxContainer.new()
	_craft_area.alignment = BoxContainer.ALIGNMENT_CENTER
	_craft_area.add_theme_constant_override("separation", 14)
	_station_area.add_child(_craft_area)

	_craft_grid_container = _make_grid(2, 2, "craft", _craft_views)
	_craft_area.add_child(_craft_grid_container)

	_table_grid_container = _make_grid(3, 3, "table", _table_views)
	_table_grid_container.visible = false
	_craft_area.add_child(_table_grid_container)

	var arrow := Label.new()
	arrow.text = "->"
	arrow.add_theme_font_size_override("font_size", 22)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_craft_area.add_child(arrow)

	_result_view = ItemSlotView.new({"kind": "result"})
	_result_view.slot_clicked.connect(_on_slot_clicked)
	_result_view.custom_minimum_size = Vector2(52, 52)
	_craft_area.add_child(_result_view)

	# --- chest ---
	_chest_box = VBoxContainer.new()
	_chest_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_station_area.add_child(_chest_box)
	var chest_grid := _make_grid(9, 3, "chest", _chest_views)
	_chest_box.add_child(chest_grid)

	# --- recipe book ---
	_book_box = VBoxContainer.new()
	_book_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_station_area.add_child(_book_box)
	var book_scroll := ScrollContainer.new()
	book_scroll.custom_minimum_size = Vector2(430, 190)
	book_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_book_box.add_child(book_scroll)
	var book_list := VBoxContainer.new()
	book_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book_list.add_theme_constant_override("separation", 3)
	book_scroll.add_child(book_list)
	for recipe in CraftingRecipes.RECIPES:
		book_list.add_child(_make_book_row(recipe))

	# --- furnace ---
	_furnace_box = HBoxContainer.new()
	_furnace_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_furnace_box.add_theme_constant_override("separation", 14)
	_station_area.add_child(_furnace_box)
	_furnace_input_view = ItemSlotView.new({"kind": "furnace_in"})
	_furnace_fuel_view = ItemSlotView.new({"kind": "furnace_fuel"})
	for indicator in [_furnace_input_view, _furnace_fuel_view]:
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_furnace_box.add_child(indicator)
	var furnace_arrow := Label.new()
	furnace_arrow.text = "->"
	furnace_arrow.add_theme_font_size_override("font_size", 22)
	_furnace_box.add_child(furnace_arrow)
	_furnace_output_view = ItemSlotView.new({"kind": "furnace_out"})
	_furnace_output_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_furnace_box.add_child(_furnace_output_view)

	var smelt_buttons := VBoxContainer.new()
	smelt_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	smelt_buttons.add_theme_constant_override("separation", 4)
	for batch in [1, 8]:
		var smelt_button := _make_button("SMELT x%d" % batch, 110)
		smelt_button.pressed.connect(_on_smelt_pressed.bind(batch))
		smelt_buttons.add_child(smelt_button)
		_extra_buttons.append(smelt_button)
	_furnace_box.add_child(smelt_buttons)


# ---------------------------------------------------------------- modes

func _set_mode(mode: int) -> void:
	_mode = mode
	_craft_area.visible = mode == Mode.CRAFT or mode == Mode.TABLE
	if _craft_grid_container != null:
		_craft_grid_container.visible = mode == Mode.CRAFT
	if _table_grid_container != null:
		_table_grid_container.visible = mode == Mode.TABLE
	if _book_box != null:
		_book_box.visible = mode == Mode.BOOK
	_chest_box.visible = mode == Mode.CHEST
	_furnace_box.visible = mode == Mode.FURNACE
	match mode:
		Mode.INVENTORY:
			_title.text = "INVENTORY"
			_craft_button.text = "CRAFT"
		Mode.CRAFT:
			_title.text = "CRAFTING"
			_craft_button.text = "BACK"
		Mode.TABLE:
			_title.text = "CRAFTING TABLE"
			_craft_button.text = "BACK"
		Mode.FURNACE:
			_title.text = "FURNACE"
			_craft_button.text = "BACK"
		Mode.CHEST:
			_title.text = "CHEST"
			_craft_button.text = "BACK"
		Mode.BOOK:
			_title.text = "RECIPE BOOK"
			_craft_button.text = "BACK"
	_refresh()


func _on_craft_pressed() -> void:
	if _mode == Mode.CRAFT or _mode != Mode.INVENTORY:
		_set_mode(Mode.INVENTORY)
	else:
		_set_mode(Mode.CRAFT)


func _set_open(open: bool) -> void:
	if _is_open == open:
		return
	_is_open = open
	visible = open
	if open:
		_refresh()
	inventory_visibility_changed.emit(open)


func _reset_table_grid() -> void:
	_table_grid.clear()
	for _index in range(9):
		_table_grid.append({"block_id": 0, "count": 0})


func _return_transient_items() -> void:
	# Anything left in grids, held on the cursor, or on the table goes back
	# to the player inventory. Nothing may vanish at close time.
	if player_inventory == null:
		return
	if not _held.is_empty() and int(_held.get("count", 0)) > 0:
		if not player_inventory.add_item(int(_held["block_id"]), int(_held["count"])):
			push_warning("Held item lost on close: %s" % [_held])
		_held = {}
	# The player craft grid is transient regardless of which mode the screen
	# is in when it closes: leftover grid items always go home.
	if not player_inventory.get_craft_grid().is_empty():
		player_inventory.return_craft_grid_to_inventory()
	for index in range(_table_grid.size()):
		var stack: Dictionary = _table_grid[index]
		if int(stack.get("count", 0)) > 0:
			if not player_inventory.add_item(int(stack["block_id"]), int(stack["count"])):
				push_warning("Crafting table grid item lost on close: %s" % [stack])
			_table_grid[index] = {"block_id": 0, "count": 0}


# ---------------------------------------------------------------- rendering

func _refresh() -> void:
	if player_inventory == null:
		return
	var slots := player_inventory.get_slots()
	var hotbar_count := player_inventory.get_hotbar_slot_count()
	for index in range(_storage_views.size()):
		var slot_index := hotbar_count + index
		_storage_views[index].set_stack(slots[slot_index] if slot_index < slots.size() else {})
	for index in range(_hotbar_views.size()):
		_hotbar_views[index].set_stack(slots[index] if index < slots.size() else {})
	for index in range(_craft_views.size()):
		_craft_views[index].set_stack(player_inventory.get_craft_slot(index))
	for index in range(_table_views.size()):
		_table_views[index].set_stack(_table_grid[index] if index < _table_grid.size() else {})
	for index in range(_chest_views.size()):
		if stations != null and stations.has_chest(_station_coord):
			var chest: BlockInventory = stations.get_chest_inventory(_station_coord)
			_chest_views[index].set_stack(chest.get_slot(index))
		else:
			_chest_views[index].set_stack({})
	_refresh_result_view()
	_refresh_furnace_views()
	_refresh_book()
	_held_view.visible = not _held.is_empty() and int(_held.get("count", 0)) > 0
	_held_view.set_stack(_held)


func _refresh_result_view() -> void:
	var recipe := _current_recipe()
	if recipe.is_empty():
		_result_view.set_stack({})
	else:
		_result_view.set_stack(recipe.get("output", {}))


func _current_recipe() -> Dictionary:
	if _mode == Mode.CRAFT:
		return CraftingRecipes.find_recipe(player_inventory.get_craft_grid(), CraftingRecipes.RECIPES, false)
	if _mode == Mode.TABLE:
		return CraftingRecipes.find_recipe(_table_grid, CraftingRecipes.RECIPES, true)
	return {}


func _refresh_furnace_views() -> void:
	if player_inventory == null:
		return
	var input_id := 0
	var input_count := 0
	for candidate in FurnaceRecipes.SMELT_MAP.keys():
		var found := player_inventory.get_item_count(int(candidate))
		if found > 0:
			input_id = int(candidate)
			input_count = found
			break
	var fuel_id := 0
	var fuel_count := 0
	for candidate in FurnaceRecipes.FUEL_SET:
		var found := player_inventory.get_item_count(int(candidate))
		if found > 0:
			fuel_id = int(candidate)
			fuel_count = found
			break
	_furnace_input_view.set_stack({"block_id": input_id, "count": input_count})
	_furnace_fuel_view.set_stack({"block_id": fuel_id, "count": fuel_count})
	_furnace_output_view.set_stack(_last_smelt_output)


# ---------------------------------------------------------------- clicks

func _on_slot_clicked(view: ItemSlotView, mouse_button_index: int, shift_held: bool) -> void:
	var kind := String(view.context.get("kind", ""))
	match kind:
		"storage":
			# Storage views are numbered relative to the storage half; item
			# operations need the absolute player-inventory slot index.
			var absolute_index := player_inventory.get_hotbar_slot_count() 				+ int(view.context.get("index", 0)) if player_inventory != null 				else int(view.context.get("index", 0))
			_click_inventory_slot(absolute_index, mouse_button_index, shift_held)
		"hotbar":
			_click_inventory_slot(int(view.context.get("index", 0)), mouse_button_index, shift_held)
		"craft":
			_click_craft_slot(int(view.context.get("index", 0)), mouse_button_index)
		"table":
			_click_table_slot(int(view.context.get("index", 0)), mouse_button_index)
		"result":
			_click_result(mouse_button_index)
		"chest":
			_click_chest_slot(int(view.context.get("index", 0)), mouse_button_index, shift_held)
	_refresh()


func _click_inventory_slot(slot_index: int, mouse_button_index: int, shift_held: bool) -> void:
	if player_inventory == null:
		return
	if shift_held:
		if _mode == Mode.CHEST and stations != null and stations.has_chest(_station_coord):
			var stack := player_inventory.take_from_slot(slot_index)
			if int(stack.get("count", 0)) > 0:
				var chest := stations.get_chest_inventory(_station_coord)
				if not chest.add_item(int(stack["block_id"]), int(stack["count"])):
					player_inventory.add_item(int(stack["block_id"]), int(stack["count"]))
			return
		player_inventory.quick_move_slot(slot_index)
		return
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = player_inventory.take_from_slot(slot_index)
		else:
			_held = player_inventory.put_stack_into_slot(slot_index, _held)
	else:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = player_inventory.split_from_slot(slot_index)
		else:
			_held = player_inventory.put_stack_into_slot(slot_index, _held, true)


func _click_craft_slot(craft_index: int, mouse_button_index: int) -> void:
	if player_inventory == null:
		return
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = player_inventory.take_craft_slot(craft_index)
		else:
			_held = player_inventory.set_craft_slot(craft_index, _held)
	else:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = player_inventory.split_craft_slot(craft_index)
		else:
			_held = player_inventory.set_craft_slot(craft_index, _held, true)


func _click_table_slot(table_index: int, mouse_button_index: int) -> void:
	if table_index < 0 or table_index >= _table_grid.size():
		return
	var slot: Dictionary = _table_grid[table_index]
	var slot_count := int(slot.get("count", 0))
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = slot
			_table_grid[table_index] = {"block_id": 0, "count": 0}
		elif int(slot.get("count", 0)) <= 0:
			_table_grid[table_index] = _held
			_held = {}
		elif int(slot["block_id"]) == int(_held["block_id"]):
			var merged := mini(MAX_STACK - int(slot["count"]), int(_held["count"]))
			slot["count"] = int(slot["count"]) + merged
			_table_grid[table_index] = slot
			_held = _remainder_of(_held, merged)
		else:
			_table_grid[table_index] = _held
			_held = slot
	else:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			if slot_count <= 0:
				return
			var take := ceili(float(slot_count) / 2.0)
			_held = {"block_id": int(slot["block_id"]), "count": take}
			_table_grid[table_index] = _remainder_of(slot, take)
		else:
			_table_grid[table_index] = {"block_id": int(_held["block_id"]), "count": int(slot["count"]) + 1}
			_held = _remainder_of(_held, 1)


func _click_result(mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var recipe := _current_recipe()
	if recipe.is_empty():
		return
	var output: Dictionary = recipe.get("output", {})
	var out_id := int(output.get("block_id", 0))
	var out_count := int(output.get("count", 0))
	if out_id <= 0 or out_count <= 0:
		return
	if _held.is_empty() or int(_held.get("count", 0)) <= 0:
		_held = {"block_id": out_id, "count": out_count}
	elif int(_held["block_id"]) == out_id and int(_held["count"]) + out_count <= MAX_STACK:
		_held["count"] = int(_held["count"]) + out_count
	elif player_inventory != null and player_inventory.add_item(out_id, out_count):
		_consume_inputs(recipe)
		return
	else:
		return
	_consume_inputs(recipe)


func _consume_inputs(recipe: Dictionary) -> void:
	if _mode == Mode.CRAFT:
		player_inventory.consume_grid_inputs(recipe)
		return
	for req in recipe.get("inputs", []):
		var need := int(req.get("count", 0))
		for index in range(_table_grid.size()):
			if need <= 0:
				break
			var slot: Dictionary = _table_grid[index]
			if int(slot.get("block_id", 0)) != int(req.get("block_id", 0)):
				continue
			var take := mini(int(slot.get("count", 0)), need)
			_table_grid[index] = _remainder_of(slot, take)
			need -= take


func _click_chest_slot(chest_index: int, mouse_button_index: int, shift_held: bool) -> void:
	if stations == null or not stations.has_chest(_station_coord):
		return
	var chest := stations.get_chest_inventory(_station_coord)
	if shift_held:
		var stack := chest.take_from_slot(chest_index)
		if int(stack.get("count", 0)) > 0:
			if not player_inventory.add_item(int(stack["block_id"]), int(stack["count"])):
				chest.add_item(int(stack["block_id"]), int(stack["count"]))
		return
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = chest.take_from_slot(chest_index)
		else:
			_held = chest.put_stack_into_slot(chest_index, _held)
	else:
		if _held.is_empty() or int(_held.get("count", 0)) <= 0:
			_held = chest.split_from_slot(chest_index)
		else:
			_held = chest.put_stack_into_slot(chest_index, _held, true)


func _on_smelt_pressed(batch: int) -> void:
	if player_inventory == null:
		return
	for _index in range(batch):
		var report := FurnaceRecipes.smelt_once(player_inventory)
		if not bool(report.get("ok", false)):
			break
		_last_smelt_output = {"block_id": int(report.get("output", 0)), "count": 1}
	_refresh()


static func _remainder_of(stack: Dictionary, taken: int) -> Dictionary:
	var left := maxi(int(stack.get("count", 0)) - taken, 0)
	if left <= 0:
		return {}
	return {"block_id": int(stack["block_id"]), "count": left}


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- recipe book

func _make_book_row(recipe: Dictionary) -> Control:
	var output: Dictionary = recipe.get("output", {})
	var out_id := int(output.get("block_id", 0))
	var out_count := int(output.get("count", 0))

	var row := PanelContainer.new()
	row.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.16, 0.16, 0.19))
	)
	row.custom_minimum_size = Vector2(420, 52)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var out_view := ItemSlotView.new({"kind": "book_out"})
	out_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out_view.set_stack({"block_id": out_id, "count": out_count})
	hbox.add_child(out_view)

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.add_theme_constant_override("separation", 0)
	hbox.add_child(labels)
	var name_label := Label.new()
	name_label.text = "%s x%d" % [ItemRegistry.display_name(out_id), out_count]
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 3)
	labels.add_child(name_label)
	var parts: Array[String] = []
	for req in recipe.get("inputs", []):
		parts.append("%dx %s" % [
			int(req.get("count", 0)),
			ItemRegistry.display_name(int(req.get("block_id", 0))),
		])
	var inputs_label := Label.new()
	inputs_label.text = " + ".join(parts)
	if bool(recipe.get("table_only", false)):
		inputs_label.text += "   [TABLE]"
	inputs_label.add_theme_font_size_override("font_size", 12)
	inputs_label.modulate = Color(0.85, 0.85, 0.85)
	labels.add_child(inputs_label)

	var craft_button := _make_button("CRAFT x0", 96)
	craft_button.disabled = true
	craft_button.pressed.connect(_on_book_craft_pressed.bind(recipe))
	hbox.add_child(craft_button)
	_extra_buttons.append(craft_button)

	_book_rows.append({
		"recipe": recipe,
		"button": craft_button,
	})
	return row


func _on_book_pressed() -> void:
	if _mode == Mode.BOOK:
		_set_mode(Mode.INVENTORY)
	else:
		# Remember whether the book was opened while standing at a table.
		_book_table_mode = _mode == Mode.TABLE
		_set_mode(Mode.BOOK)


func _on_book_craft_pressed(recipe: Dictionary) -> void:
	_craft_from_inventory(recipe)


## Fast craft: consume inputs from the player inventory and add every copy
## the inventory can produce and hold. Table-only recipes need table mode.
func _craft_from_inventory(recipe: Dictionary) -> void:
	if player_inventory == null or recipe.is_empty():
		return
	if not CraftingRecipes.can_craft_from_inventory(recipe, player_inventory, _book_table_mode):
		return
	var output: Dictionary = recipe.get("output", {})
	var out_id := int(output.get("block_id", 0))
	var out_count := int(output.get("count", 0))
	if out_id <= 0 or out_count <= 0:
		return
	var crafted := 0
	while crafted < 999 \
			and CraftingRecipes.can_craft_from_inventory(recipe, player_inventory, _book_table_mode) \
			and player_inventory.can_add_item(out_id, out_count):
		var removed_all := true
		for req in recipe.get("inputs", []):
			if not player_inventory.remove_item(int(req.get("block_id", 0)), int(req.get("count", 0))):
				removed_all = false
				break
		if not removed_all:
			# Roll back whatever this iteration removed by restoring from the
			# recipe definition is impossible generically; break safely. The
			# can_craft pre-check makes this path unreachable in practice.
			break
		if not player_inventory.add_item(out_id, out_count):
			break
		crafted += 1
	_refresh()


func _refresh_book() -> void:
	if player_inventory == null:
		return
	var slots := player_inventory.get_slots()
	for entry in _book_rows:
		var recipe: Dictionary = entry["recipe"]
		var button: Button = entry["button"]
		var allowed := not bool(recipe.get("table_only", false)) or _book_table_mode
		var count := CraftingRecipes.max_craftable(recipe, slots) if allowed else 0
		button.text = "CRAFT x%d" % count
		button.disabled = count <= 0


# ---------------------------------------------------------------- touch input
# The project disables mouse-emulation-from-touch
# (input_devices/pointing/emulate_mouse_from_touch=false), so plain Buttons
# never see taps. Route raw ScreenTouch presses into the same handlers the
# mouse uses, exactly like the previous screen did.

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		_handle_screen_touch(touch)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_handle_screen_drag(drag)


func _handle_screen_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _active_touch_index != -1:
			return # one interacting finger at a time
		# Recipe book: taps on row buttons still work; everything else pans.
		var button := _button_at(touch.position)
		if _mode == Mode.BOOK and button == null \
				and _book_box != null and _book_box.visible \
				and _book_box.get_global_rect().has_point(touch.position):
			_book_pan_active = true
			_book_pan_last_y = touch.position.y
			_active_touch_index = touch.index
			get_viewport().set_input_as_handled()
			return
		if button != null:
			button.pressed.emit()
			get_viewport().set_input_as_handled()
			return
		var view := _slot_view_at(touch.position)
		if view != null:
			# Defer routing: quick tap = full-stack action, holding = split.
			_pending_press = {
				"view": view,
				"pos": touch.position,
				"time": Time.get_ticks_msec(),
				"long_done": false,
			}
			_active_touch_index = touch.index
			get_viewport().set_input_as_handled()
	else:
		if touch.index == _active_touch_index:
			if not _pending_press.is_empty() and not bool(_pending_press["long_done"]):
				_on_slot_clicked(_pending_press["view"], MOUSE_BUTTON_LEFT, false)
			_pending_press = {}
			_book_pan_active = false
			_active_touch_index = -1


func _handle_screen_drag(drag: InputEventScreenDrag) -> void:
	if _mode == Mode.BOOK and _book_pan_active and _book_box != null:
		var scroll_container: ScrollContainer = _book_box.get_child(0)
		scroll_container.scroll_vertical -= int(drag.relative.y)
		get_viewport().set_input_as_handled()
		return
	if drag.index == _active_touch_index and not _pending_press.is_empty():
		var moved: float = (_pending_press["pos"] as Vector2 - drag.position).length()
		if moved > TAP_MOVE_CANCEL_PX and not bool(_pending_press["long_done"]):
			_pending_press = {} # swiped away: not a tap


func _process(delta: float) -> void:
	if _is_open and _held_view.visible:
		_held_view.global_position = _root.get_global_mouse_position() + Vector2(-23, -23)
	if not _pending_press.is_empty() and not bool(_pending_press["long_done"]):
		if Time.get_ticks_msec() - int(_pending_press["time"]) >= LONG_PRESS_MSEC:
			_pending_press["long_done"] = true
			# Long press splits: same action as a right-click.
			_on_slot_clicked(_pending_press["view"], MOUSE_BUTTON_RIGHT, false)


func _slot_view_at(position: Vector2) -> ItemSlotView:
	for view in _interactive_slot_views():
		if view.is_visible_in_tree() and view.get_global_rect().has_point(position):
			return view
	return null


func _button_at(position: Vector2) -> Button:
	for button in _extra_buttons:
		if button != null and button.is_visible_in_tree() 				and button.get_global_rect().has_point(position):
			return button
	return null


func _interactive_slot_views() -> Array[ItemSlotView]:
	var views: Array[ItemSlotView] = []
	views.append_array(_storage_views)
	views.append_array(_hotbar_views)
	views.append_array(_craft_views)
	views.append_array(_table_views)
	views.append(_result_view)
	views.append_array(_chest_views)
	return views
