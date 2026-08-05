extends CanvasLayer
class_name MinecraftInventoryScreen

signal inventory_visibility_changed(is_open: bool)

const TOGGLE_ACTION := StringName("toggle_inventory")
const HOTBAR_SLOT_COUNT := 9
const STORAGE_SLOT_COUNT := 27
const STORAGE_START_INDEX := HOTBAR_SLOT_COUNT
const BLOCK_NAMES := {
	0: "EMPTY",
	1: "GRASS",
	2: "DIRT",
	3: "STONE",
	4: "SAND",
}

var _inventory: BlockInventory
var _player: Node
var _root: Control
var _overlay: Control
var _inventory_panel: PanelContainer
var _toggle_button: Button
var _close_button: Button
var _storage_labels: Array[Label] = []
var _hotbar_labels: Array[Label] = []
var _is_open := false


func _ready() -> void:
	layer = 60
	_build_screen()
	_set_open(false)
	set_process(true)


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


func is_inventory_open() -> bool:
	return _is_open


func toggle_inventory() -> void:
	_set_open(not _is_open)


func open_inventory() -> void:
	_set_open(true)


func close_inventory() -> void:
	_set_open(false)


func get_inventory_panel() -> PanelContainer:
	return _inventory_panel


func get_toggle_button() -> Button:
	return _toggle_button


func get_close_button() -> Button:
	return _close_button


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
	if _inventory == null:
		return
	for slot_index in range(HOTBAR_SLOT_COUNT):
		if slot_index < _hotbar_labels.size():
			_hotbar_labels[slot_index].text = _slot_text(slot_index, true)
	for storage_index in range(STORAGE_SLOT_COUNT):
		if storage_index < _storage_labels.size():
			_storage_labels[storage_index].text = _slot_text(STORAGE_START_INDEX + storage_index, false)


func _slot_text(slot_index: int, include_number: bool) -> String:
	var slot := _inventory.get_slot(slot_index)
	var block_id := int(slot.get("block_id", 0))
	var count := int(slot.get("count", 0))
	var block_name := String(BLOCK_NAMES.get(block_id, "BLOCK %d" % block_id))
	if include_number:
		return "%d\n%s x%d" % [slot_index + 1, block_name, count]
	return "%s x%d" % [block_name, count]


func _build_screen() -> void:
	_root = Control.new()
	_root.name = "InventoryRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_toggle_button = Button.new()
	_toggle_button.name = "InventoryToggle"
	_toggle_button.text = "INVENTORY"
	_toggle_button.anchor_left = 1.0
	_toggle_button.anchor_right = 1.0
	_toggle_button.offset_left = -190.0
	_toggle_button.offset_top = 18.0
	_toggle_button.offset_right = -18.0
	_toggle_button.offset_bottom = 76.0
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.add_theme_font_size_override("font_size", 18)
	_toggle_button.pressed.connect(toggle_inventory)
	_root.add_child(_toggle_button)

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
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.anchor_left = 0.5
	_inventory_panel.anchor_top = 0.5
	_inventory_panel.anchor_right = 0.5
	_inventory_panel.anchor_bottom = 0.5
	_inventory_panel.offset_left = -500.0
	_inventory_panel.offset_top = -270.0
	_inventory_panel.offset_right = 500.0
	_inventory_panel.offset_bottom = 270.0
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_inventory_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_inventory_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	var storage_title := Label.new()
	storage_title.text = "STORAGE — 27 SLOTS"
	storage_title.add_theme_font_size_override("font_size", 16)
	column.add_child(storage_title)

	var storage_grid := GridContainer.new()
	storage_grid.name = "StorageGrid"
	storage_grid.columns = 9
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(storage_grid)
	for storage_index in range(STORAGE_SLOT_COUNT):
		var label := _create_slot(storage_grid, "StorageSlot%d" % (storage_index + 1))
		_storage_labels.append(label)

	var hotbar_title := Label.new()
	hotbar_title.text = "HOTBAR — 9 SLOTS"
	hotbar_title.add_theme_font_size_override("font_size", 16)
	column.add_child(hotbar_title)

	var hotbar_grid := GridContainer.new()
	hotbar_grid.name = "HotbarGrid"
	hotbar_grid.columns = 9
	hotbar_grid.add_theme_constant_override("h_separation", 6)
	column.add_child(hotbar_grid)
	for slot_index in range(HOTBAR_SLOT_COUNT):
		var label := _create_slot(hotbar_grid, "HotbarSlot%d" % (slot_index + 1))
		_hotbar_labels.append(label)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "CLOSE INVENTORY"
	_close_button.custom_minimum_size = Vector2(0.0, 48.0)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.pressed.connect(close_inventory)
	column.add_child(_close_button)


func _create_slot(parent: Control, slot_name: String) -> Label:
	var panel := PanelContainer.new()
	panel.name = slot_name
	panel.custom_minimum_size = Vector2(98.0, 66.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)

	var label := Label.new()
	label.name = "Content"
	label.text = "EMPTY x0"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label
