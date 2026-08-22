extends CanvasLayer
class_name HotbarV2

## Read-only hotbar HUD (v2). Subscriber tier of the ownership model:
## it listens to BlockInventory.changed and repaints. It never mutates
## backend state and has no mutating calls in its code path.

const HOTBAR_SLOT_COUNT := 9

var _inventory: BlockInventory
var _slots: Array[ItemSlotV2] = []
var _selected := 0


func _ready() -> void:
	layer = 20
	var total_width := ItemSlotV2.SLOT_SIZE.x * HOTBAR_SLOT_COUNT + 6.0 * (HOTBAR_SLOT_COUNT - 1)
	var root := MarginContainer.new()
	root.name = "HotbarRoot"
	root.anchor_left = 0.5
	root.anchor_top = 1.0
	root.anchor_right = 0.5
	root.anchor_bottom = 1.0
	root.offset_left = -total_width * 0.5
	root.offset_top = -(ItemSlotV2.SLOT_SIZE.y + 14.0)
	root.offset_right = total_width * 0.5
	root.offset_bottom = -16.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var row := HBoxContainer.new()
	row.name = "Slots"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)

	for index in range(HOTBAR_SLOT_COUNT):
		var slot := ItemSlotV2.new()
		slot.configure(index, str(index + 1), true) # display-only
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		_slots.append(slot)


## Bind to an inventory: repaints on every backend change.
func setup(inventory: BlockInventory) -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh_from_inventory):
		_inventory.changed.disconnect(_refresh_from_inventory)
	_inventory = inventory
	if _inventory != null and not _inventory.changed.is_connected(_refresh_from_inventory):
		_inventory.changed.connect(_refresh_from_inventory)
	_refresh_from_inventory()


## Legacy paint entry kept for the player controller until the wiring
## commit swaps it to setup()+set_selected().
func refresh(slots: Array, selected_slot: int) -> void:
	_selected = selected_slot
	for index in range(HOTBAR_SLOT_COUNT):
		var stack := {"block_id": 0, "count": 0}
		if index < slots.size():
			stack = slots[index]
		_paint_slot(index, stack)
	_repaint_selection()


func set_selected(selected_slot: int) -> void:
	_selected = selected_slot
	_repaint_selection()


func _index_of_selected() -> int:
	return clampi(_selected, 0, HOTBAR_SLOT_COUNT - 1)


func index_of_selected() -> int:
	return _index_of_selected()


func _refresh_from_inventory() -> void:
	if _inventory == null:
		return
	for index in range(HOTBAR_SLOT_COUNT):
		_paint_slot(index, _inventory.get_slot(index))
	_repaint_selection()


func _repaint_selection() -> void:
	for index in range(_slots.size()):
		_slots[index].set_selected(index == _index_of_selected())


func _paint_slot(index: int, stack: Dictionary) -> void:
	if index < 0 or index >= _slots.size():
		return
	_slots[index].bind_view(SlotViewBuilder.build(stack))


func get_slot_widget(index: int) -> ItemSlotV2:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]
