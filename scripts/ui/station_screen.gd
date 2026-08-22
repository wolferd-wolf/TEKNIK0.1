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

enum Mode { INVENTORY, CRAFT, TABLE, FURNACE, CHEST }

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

	_craft_button = _make_button("CRAFT", 92)
	_craft_button.name = "CraftButton"
	_craft_button.pressed.connect(_on_craft_pressed)
	main_row.add_child(_craft_button)

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
	_furnace_box.add_child(smelt_buttons)


# ---------------------------------------------------------------- modes

func _set_mode(mode: int) -> void:
	_mode = mode
	_craft_area.visible = mode == Mode.CRAFT or mode == Mode.TABLE
	if _craft_grid_container != null:
		_craft_grid_container.visible = mode == Mode.CRAFT
	if _table_grid_container != null:
		_table_grid_container.visible = mode == Mode.TABLE
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
		"storage", "hotbar":
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

func _process(_delta: float) -> void:
	if _is_open and _held_view.visible:
		_held_view.global_position = _root.get_global_mouse_position() + Vector2(-23, -23)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()
