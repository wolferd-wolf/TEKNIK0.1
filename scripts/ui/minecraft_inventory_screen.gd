extends CanvasLayer
class_name MinecraftInventoryScreen

signal inventory_visibility_changed(is_open: bool)

const THEME := preload("res://scripts/ui/teknik_theme.gd")
const RECIPE_REGISTRY := preload("res://scripts/inventory/recipe_registry.gd")
const TOGGLE_ACTION := StringName("toggle_inventory")
const HOTBAR_SLOT_COUNT := 9
const STORAGE_SLOT_COUNT := 27
const STORAGE_START_INDEX := HOTBAR_SLOT_COUNT
const LONG_PRESS_SECONDS := 0.45

var _inventory: BlockInventory
var _player: Node
var _root: Control
var _overlay: Control
var _inventory_panel: PanelContainer
var _toggle_button: Button
var _close_button: Button
var _cursor_label: Label
var _long_press_timer: Timer
var _storage_labels: Array[Label] = []
var _hotbar_labels: Array[Label] = []
var _storage_swatches: Array[Panel] = []
var _hotbar_swatches: Array[Panel] = []
var _slot_buttons: Dictionary = {}
var _craft_buttons: Dictionary = {}
var _craft_cost_labels: Dictionary = {}
var _cursor_stack: Dictionary = {"block_id": 0, "count": 0}
var _active_touch_index := -1
var _active_touch_slot := -1
var _long_press_consumed := false
var _is_open := false


func _ready() -> void:
	layer = 60
	_build_screen()
	_set_open(false)
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


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _control_contains(_toggle_button, touch.position):
				get_viewport().set_input_as_handled()
				toggle_inventory()
				return
			if not _is_open:
				return
			if _control_contains(_close_button, touch.position):
				get_viewport().set_input_as_handled()
				close_inventory()
				return
			var slot_index := _slot_at_position(touch.position)
			if slot_index >= 0:
				_begin_touch_slot(touch.index, slot_index)
			get_viewport().set_input_as_handled()
		else:
			if touch.index == _active_touch_index:
				_finish_touch_slot()
				get_viewport().set_input_as_handled()
			elif _is_open:
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _is_open or drag.index == _active_touch_index:
			get_viewport().set_input_as_handled()


func is_inventory_open() -> bool:
	return _is_open


func toggle_inventory() -> void:
	if _is_open:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	_set_open(true)


func close_inventory() -> bool:
	_cancel_active_touch()
	if not return_cursor_stack():
		return false
	_set_open(false)
	return true


func return_cursor_stack() -> bool:
	if _is_stack_empty(_cursor_stack):
		return true
	if _inventory == null:
		return false
	var block_id := int(_cursor_stack.get("block_id", 0))
	var count := int(_cursor_stack.get("count", 0))
	if not _inventory.add_item(block_id, count):
		push_error("Inventory could not return carried stack before closing")
		return false
	_cursor_stack = {"block_id": 0, "count": 0}
	_refresh()
	return true


func get_inventory_panel() -> PanelContainer:
	return _inventory_panel


func get_toggle_button() -> Button:
	return _toggle_button


func get_close_button() -> Button:
	return _close_button


func get_cursor_label() -> Label:
	return _cursor_label


func get_cursor_stack() -> Dictionary:
	return _cursor_stack.duplicate(true)


func get_slot_button(slot_index: int) -> Button:
	return _slot_buttons.get(slot_index) as Button


func get_storage_slot_label(storage_index: int) -> Label:
	if storage_index < 0 or storage_index >= _storage_labels.size():
		return null
	return _storage_labels[storage_index]


func get_hotbar_slot_label(slot_index: int) -> Label:
	if slot_index < 0 or slot_index >= _hotbar_labels.size():
		return null
	return _hotbar_labels[slot_index]


func get_storage_slot_count() -> int:
	return _storage_labels.size()


func get_hotbar_slot_count() -> int:
	return _hotbar_labels.size()


func interact_slot_primary(slot_index: int) -> void:
	if not _is_open or _inventory == null:
		return
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = _inventory.take_from_slot(slot_index)
	else:
		_cursor_stack = _inventory.put_stack_into_slot(slot_index, _cursor_stack)
	_refresh()


func interact_slot_secondary(slot_index: int) -> void:
	if not _is_open or _inventory == null:
		return
	if _is_stack_empty(_cursor_stack):
		_cursor_stack = _inventory.split_from_slot(slot_index)
	else:
		_cursor_stack = _inventory.put_stack_into_slot(slot_index, _cursor_stack, true)
	_refresh()


func _set_open(value: bool) -> void:
	_is_open = value
	if is_instance_valid(_overlay):
		_overlay.visible = value
	if is_instance_valid(_toggle_button):
		_toggle_button.text = "CLOSE" if value else "INVENTORY"
	if value:
		_refresh()
	inventory_visibility_changed.emit(value)


func _refresh() -> void:
	if _inventory != null:
		for slot_index in range(HOTBAR_SLOT_COUNT):
			if slot_index < _hotbar_labels.size():
				_hotbar_labels[slot_index].text = _slot_text(slot_index, true)
				_style_slot_swatch(_hotbar_swatches[slot_index], _inventory.get_slot(slot_index))
		for storage_index in range(STORAGE_SLOT_COUNT):
			if storage_index < _storage_labels.size():
				var inventory_index := STORAGE_START_INDEX + storage_index
				_storage_labels[storage_index].text = _slot_text(inventory_index, false)
				_style_slot_swatch(_storage_swatches[storage_index], _inventory.get_slot(inventory_index))
	if is_instance_valid(_cursor_label):
		_cursor_label.text = _cursor_text()
	_refresh_crafting_panel()


func _style_slot_swatch(swatch: Panel, slot: Dictionary) -> void:
	if not is_instance_valid(swatch):
		return
	var block_id := int(slot.get("block_id", 0))
	var count := int(slot.get("count", 0))
	var occupied := block_id > 0 and count > 0
	swatch.add_theme_stylebox_override(
		"panel",
		THEME.block_swatch_style(THEME.block_color(block_id if occupied else 0))
	)
	swatch.visible = occupied


func _refresh_crafting_panel() -> void:
	for recipe in RECIPE_REGISTRY.get_recipes():
		var recipe_id: String = recipe["id"]
		var button := _craft_buttons.get(recipe_id) as Button
		if not is_instance_valid(button):
			continue
		var affordable := RECIPE_REGISTRY.can_craft(_inventory, recipe)
		button.disabled = not affordable
		button.modulate = Color(1, 1, 1, 1) if affordable else Color(1, 1, 1, 0.45)
		var cost_label := _craft_cost_labels.get(recipe_id) as Label
		if is_instance_valid(cost_label):
			var have := _inventory.get_item_count(int(recipe["input_block_id"])) if _inventory != null else 0
			cost_label.text = "%dx %s  (have %d)" % [
				int(recipe["input_count"]),
				THEME.block_name(int(recipe["input_block_id"])),
				have,
			]
			cost_label.add_theme_color_override(
				"font_color",
				THEME.COLOR_TEXT_SECONDARY if affordable else Color(0.7, 0.4, 0.35, 1.0)
			)


func _slot_text(slot_index: int, include_number: bool) -> String:
	var slot := _inventory.get_slot(slot_index)
	var block_id := int(slot.get("block_id", 0))
	var count := int(slot.get("count", 0))
	var block_name := THEME.block_name(block_id)
	if include_number:
		return "%d\n%s x%d" % [slot_index + 1, block_name, count]
	return "%s x%d" % [block_name, count]


func _cursor_text() -> String:
	var block_id := int(_cursor_stack.get("block_id", 0))
	var count := int(_cursor_stack.get("count", 0))
	var block_name := THEME.block_name(block_id)
	return "CARRIED: %s x%d" % [block_name, count]


func _is_stack_empty(stack: Dictionary) -> bool:
	return int(stack.get("block_id", 0)) <= 0 or int(stack.get("count", 0)) <= 0


func _control_contains(control: Control, position: Vector2) -> bool:
	return control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(position)


func _slot_at_position(position: Vector2) -> int:
	for key in _slot_buttons.keys():
		var button := _slot_buttons[key] as Button
		if _control_contains(button, position):
			return int(key)
	return -1


func _begin_touch_slot(touch_index: int, slot_index: int) -> void:
	_cancel_active_touch()
	_active_touch_index = touch_index
	_active_touch_slot = slot_index
	_long_press_consumed = false
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


func _slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not _is_open:
		return
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT
		and (event as InputEventMouseButton).pressed
	):
		interact_slot_secondary(slot_index)
		get_viewport().set_input_as_handled()


func _build_screen() -> void:
	_root = Control.new()
	_root.name = "InventoryRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_long_press_timer = Timer.new()
	_long_press_timer.name = "LongPressTimer"
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = LONG_PRESS_SECONDS
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = THEME.COLOR_DIM_BACKDROP
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.anchor_left = 0.5
	_inventory_panel.anchor_top = 0.5
	_inventory_panel.anchor_right = 0.5
	_inventory_panel.anchor_bottom = 0.5
	_inventory_panel.offset_left = -640.0
	_inventory_panel.offset_top = -300.0
	_inventory_panel.offset_right = 640.0
	_inventory_panel.offset_bottom = 300.0
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_panel.add_theme_stylebox_override("panel", THEME.panel_style(THEME.COLOR_PANEL_BG_RAISED))
	_overlay.add_child(_inventory_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	_inventory_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	THEME.style_label(title, 24, THEME.COLOR_ACCENT)
	header.add_child(title)

	_cursor_label = Label.new()
	_cursor_label.name = "CursorStack"
	_cursor_label.text = "CARRIED: EMPTY x0"
	_cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	THEME.style_label(_cursor_label, 17, THEME.COLOR_ACCENT)
	column.add_child(_cursor_label)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 20)
	column.add_child(body)

	_build_crafting_panel(body)

	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = THEME.COLOR_BORDER
	divider.custom_minimum_size = Vector2(2.0, 0.0)
	body.add_child(divider)

	var storage_column := VBoxContainer.new()
	storage_column.name = "StorageColumn"
	storage_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_column.add_theme_constant_override("separation", 9)
	body.add_child(storage_column)

	var storage_title := Label.new()
	storage_title.text = "STORAGE — 27 SLOTS"
	THEME.style_label(storage_title, 15, THEME.COLOR_TEXT_SECONDARY)
	storage_column.add_child(storage_title)

	var storage_grid := GridContainer.new()
	storage_grid.name = "StorageGrid"
	storage_grid.columns = 9
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)
	storage_column.add_child(storage_grid)
	for storage_index in range(STORAGE_SLOT_COUNT):
		var inventory_index := STORAGE_START_INDEX + storage_index
		var slot_nodes := _create_slot(storage_grid, "StorageSlot%d" % (storage_index + 1), inventory_index)
		_storage_labels.append(slot_nodes["label"] as Label)
		_storage_swatches.append(slot_nodes["swatch"] as Panel)
		_slot_buttons[inventory_index] = slot_nodes["button"]

	var hotbar_title := Label.new()
	hotbar_title.text = "HOTBAR — 9 SLOTS"
	THEME.style_label(hotbar_title, 15, THEME.COLOR_TEXT_SECONDARY)
	storage_column.add_child(hotbar_title)

	var hotbar_grid := GridContainer.new()
	hotbar_grid.name = "HotbarGrid"
	hotbar_grid.columns = 9
	hotbar_grid.add_theme_constant_override("h_separation", 6)
	storage_column.add_child(hotbar_grid)
	for slot_index in range(HOTBAR_SLOT_COUNT):
		var slot_nodes := _create_slot(hotbar_grid, "HotbarSlot%d" % (slot_index + 1), slot_index)
		_hotbar_labels.append(slot_nodes["label"] as Label)
		_hotbar_swatches.append(slot_nodes["swatch"] as Panel)
		_slot_buttons[slot_index] = slot_nodes["button"]

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "CLOSE INVENTORY"
	_close_button.custom_minimum_size = Vector2(0.0, 44.0)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override("font_size", 18)
	THEME.style_button(_close_button)
	_close_button.pressed.connect(close_inventory)
	column.add_child(_close_button)


func _build_crafting_panel(body: HBoxContainer) -> void:
	var crafting_panel := PanelContainer.new()
	crafting_panel.name = "CraftingPanel"
	crafting_panel.custom_minimum_size = Vector2(300.0, 0.0)
	crafting_panel.add_theme_stylebox_override("panel", THEME.panel_style())
	body.add_child(crafting_panel)

	var crafting_margin := MarginContainer.new()
	crafting_margin.add_theme_constant_override("margin_left", 14)
	crafting_margin.add_theme_constant_override("margin_top", 12)
	crafting_margin.add_theme_constant_override("margin_right", 14)
	crafting_margin.add_theme_constant_override("margin_bottom", 12)
	crafting_panel.add_child(crafting_margin)

	var crafting_column := VBoxContainer.new()
	crafting_column.name = "CraftingColumn"
	crafting_column.add_theme_constant_override("separation", 10)
	crafting_margin.add_child(crafting_column)

	var crafting_title := Label.new()
	crafting_title.text = "CRAFTING"
	THEME.style_label(crafting_title, 17, THEME.COLOR_ACCENT)
	crafting_column.add_child(crafting_title)

	for recipe in RECIPE_REGISTRY.get_recipes():
		crafting_column.add_child(_build_recipe_row(recipe))


func _build_recipe_row(recipe: Dictionary) -> PanelContainer:
	var recipe_id: String = recipe["id"]

	var row_panel := PanelContainer.new()
	row_panel.name = "Recipe_%s" % recipe_id
	row_panel.add_theme_stylebox_override("panel", THEME.panel_style())
	row_panel.custom_minimum_size = Vector2(0.0, 70.0)

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 10)
	row_margin.add_theme_constant_override("margin_top", 8)
	row_margin.add_theme_constant_override("margin_right", 10)
	row_margin.add_theme_constant_override("margin_bottom", 8)
	row_panel.add_child(row_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row_margin.add_child(row)

	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(40.0, 40.0)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_theme_stylebox_override(
		"panel", THEME.block_swatch_style(THEME.block_color(int(recipe["output_block_id"])))
	)
	row.add_child(swatch)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = "%s x%d" % [String(recipe["name"]), int(recipe["output_count"])]
	THEME.style_label(name_label, 16, THEME.COLOR_TEXT_PRIMARY)
	info.add_child(name_label)

	var cost_label := Label.new()
	THEME.style_label(cost_label, 12, THEME.COLOR_TEXT_SECONDARY)
	info.add_child(cost_label)
	_craft_cost_labels[recipe_id] = cost_label

	var craft_button := Button.new()
	craft_button.text = "CRAFT"
	craft_button.custom_minimum_size = Vector2(72.0, 40.0)
	craft_button.focus_mode = Control.FOCUS_NONE
	THEME.style_button(craft_button)
	craft_button.pressed.connect(_on_craft_pressed.bind(recipe_id))
	row.add_child(craft_button)
	_craft_buttons[recipe_id] = craft_button

	return row_panel


func _on_craft_pressed(recipe_id: String) -> void:
	if _inventory == null:
		return
	for recipe in RECIPE_REGISTRY.get_recipes():
		if recipe["id"] == recipe_id:
			RECIPE_REGISTRY.craft(_inventory, recipe)
			return


func _create_slot(parent: Control, slot_name: String, slot_index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = slot_name
	panel.custom_minimum_size = Vector2(84.0, 56.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", THEME.panel_style())
	parent.add_child(panel)

	# Color swatch fills the slot when occupied; hidden for empty slots so
	# an empty slot reads as visually "nothing here" instead of the same
	# uniform gray box repeated dozens of times. THEME.block_swatch_style
	# already existed for this purpose but had never actually been wired in.
	var swatch_margin := MarginContainer.new()
	swatch_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch_margin.add_theme_constant_override("margin_left", 6)
	swatch_margin.add_theme_constant_override("margin_top", 6)
	swatch_margin.add_theme_constant_override("margin_right", 6)
	swatch_margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(swatch_margin)

	var swatch := Panel.new()
	swatch.name = "Swatch"
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.visible = false
	swatch_margin.add_child(swatch)

	var label := Label.new()
	label.name = "Content"
	label.text = "EMPTY x0"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	THEME.style_label(label, 13, THEME.COLOR_TEXT_PRIMARY, true)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	var button := Button.new()
	button.name = "Interact"
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.flat = true
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(interact_slot_primary.bind(slot_index))
	button.gui_input.connect(_slot_gui_input.bind(slot_index))
	panel.add_child(button)
	return {"label": label, "button": button, "swatch": swatch}
