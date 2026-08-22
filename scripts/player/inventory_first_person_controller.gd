extends "res://scripts/player/first_person_controller.gd"
class_name InventoryFirstPersonController

const BLOCK_INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const INVENTORY_HOTBAR_SCRIPT := preload("res://scripts/ui/inventory_hotbar.gd")
const INVENTORY_SCREEN_SCRIPT := preload("res://scripts/ui/minecraft_inventory_screen.gd")
const FurnaceRecipes := preload("res://scripts/smelting/furnace_recipes.gd")
const MECHANICAL_MANAGER_SCRIPT := preload("res://scripts/mechanical/mechanical_manager.gd")
const HOTBAR_SLOT_COUNT := 9
const HOTBAR_SLOT_ACTIONS := [
	"select_hotbar_1",
	"select_hotbar_2",
	"select_hotbar_3",
	"select_hotbar_4",
	"select_hotbar_5",
	"select_hotbar_6",
	"select_hotbar_7",
	"select_hotbar_8",
	"select_hotbar_9",
]
const INVENTORY_LOCK_ACTIONS := [
	"move_left",
	"move_right",
	"move_forward",
	"move_backward",
	"jump",
	"look_left",
	"look_right",
	"look_up",
	"look_down",
	"mine_block",
	"place_block",
]
const TEST_RECIPE_INPUT_BLOCK_ID := BLOCK_DIRT
const TEST_RECIPE_INPUT_COUNT := 4
const TEST_RECIPE_OUTPUT_BLOCK_ID := BLOCK_STONE
const TEST_RECIPE_OUTPUT_COUNT := 1

var _inventory: BlockInventory = BLOCK_INVENTORY_SCRIPT.new()
var _selected_inventory_slot: int = 0
var _hotbar: InventoryHotbar
var _inventory_screen: MinecraftInventoryScreen
var _inventory_input_locked := false
var _mechanical_manager: MechanicalManager


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pitch_radians = camera.rotation.x
	_configure_target_highlight()
	_inventory.changed.connect(_refresh_hotbar)
	call_deferred("_configure_hotbar")
	call_deferred("_configure_inventory_screen")


func _unhandled_input(event: InputEvent) -> void:
	if _inventory_input_locked:
		return
	super(event)


func _physics_process(delta: float) -> void:
	if _inventory_input_locked:
		velocity = Vector3.ZERO
		return
	super(delta)


func _process(delta: float) -> void:
	if _inventory_input_locked:
		return
	var action_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	if not action_look.is_zero_approx():
		apply_look_delta(action_look * action_look_speed * delta)
	_update_hotbar_selection()
	_update_block_target()
	if Input.is_action_just_pressed("mine_block"):
		mine_targeted_block()
	if Input.is_action_just_pressed("place_block"):
		place_targeted_block()
	if Input.is_action_just_pressed("craft_test_recipe"):
		craft_test_recipe()


func apply_look_delta(look_delta: Vector2) -> void:
	if _inventory_input_locked:
		return
	super(look_delta)


func get_inventory() -> BlockInventory:
	return _inventory


func get_hotbar() -> InventoryHotbar:
	return _hotbar


func get_inventory_screen() -> MinecraftInventoryScreen:
	return _inventory_screen


func is_inventory_input_locked() -> bool:
	return _inventory_input_locked


func get_selected_inventory_slot() -> int:
	return _selected_inventory_slot


func get_selected_inventory_item() -> Dictionary:
	return _inventory.get_slot(_selected_inventory_slot) as Dictionary


func select_inventory_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= HOTBAR_SLOT_COUNT:
		return false
	_selected_inventory_slot = slot_index
	_refresh_hotbar()
	return true


func craft_test_recipe() -> bool:
	return _inventory.craft_item(
		TEST_RECIPE_INPUT_BLOCK_ID,
		TEST_RECIPE_INPUT_COUNT,
		TEST_RECIPE_OUTPUT_BLOCK_ID,
		TEST_RECIPE_OUTPUT_COUNT
	)


func mine_targeted_block() -> bool:
	var target: Dictionary = get_block_target()
	if target.is_empty() or _chunk_manager == null:
		return false

	var mined_coord: Vector3i = target["block_coord"] as Vector3i
	var mined_block_id: int = _chunk_manager.get_block_world(mined_coord)
	if mined_block_id == BLOCK_AIR:
		return false

	# Check if this is a mechanical block
	if _mechanical_manager != null and _mechanical_manager.is_mechanical_block(mined_block_id):
		if not _inventory.can_add_item(mined_block_id, 1):
			return false
		if not _mechanical_manager.break_mechanical_block(mined_coord):
			return false
		if not _inventory.add_item(mined_block_id, 1):
			# Rollback: re-place the mechanical block
			_mechanical_manager.place_mechanical_block(mined_coord, mined_block_id)
			return false
		_clear_block_target()
		return true

	var drop_block_id := FurnaceRecipes.mining_drop_for(mined_block_id)
	if not _inventory.can_add_item(drop_block_id, 1):
		return false
	if not _chunk_manager.mine_block_world(mined_coord):
		return false

	if not _inventory.add_item(drop_block_id, 1):
		var restored: bool = bool(_chunk_manager.set_block_world(mined_coord, mined_block_id))
		if not restored:
			push_error("Inventory mining rollback failed at %s" % mined_coord)
		return false

	_clear_block_target()
	return true


func place_block_at(world_block_coord: Vector3i) -> bool:
	if not can_place_block_at(world_block_coord):
		return false

	var selected_item: Dictionary = get_selected_inventory_item()
	if selected_item.is_empty():
		return false
	var block_id: int = int(selected_item.get("block_id", BLOCK_AIR))
	var count: int = int(selected_item.get("count", 0))
	if block_id == BLOCK_AIR or count <= 0:
		return false

	# Check if this is a mechanical block
	if _mechanical_manager != null and _mechanical_manager.is_mechanical_block(block_id):
		# Place via mechanical manager (which also handles world placement)
		if not _mechanical_manager.place_mechanical_block(world_block_coord, block_id):
			return false
		if not _inventory.remove_from_slot(_selected_inventory_slot, 1):
			_mechanical_manager.break_mechanical_block(world_block_coord)
			return false
		return true

	# Regular block placement
	if not _chunk_manager.place_block_world(world_block_coord, block_id):
		return false

	if not _inventory.remove_from_slot(_selected_inventory_slot, 1):
		var rolled_back: bool = bool(_chunk_manager.set_block_world(world_block_coord, BLOCK_AIR))
		if not rolled_back:
			push_error("Inventory placement rollback failed at %s" % world_block_coord)
		return false
	return true


func _update_hotbar_selection() -> void:
	for slot_index in range(HOTBAR_SLOT_COUNT):
		if Input.is_action_just_pressed(HOTBAR_SLOT_ACTIONS[slot_index]):
			select_inventory_slot(slot_index)
			return

	if Input.is_action_just_pressed("hotbar_next"):
		select_inventory_slot(posmod(_selected_inventory_slot + 1, HOTBAR_SLOT_COUNT))
	elif Input.is_action_just_pressed("hotbar_previous"):
		select_inventory_slot(posmod(_selected_inventory_slot - 1, HOTBAR_SLOT_COUNT))


func _configure_hotbar() -> void:
	var main_root := get_parent()
	if main_root == null:
		return
	_hotbar = main_root.get_node_or_null("InventoryHotbar") as InventoryHotbar
	if _hotbar == null:
		_hotbar = INVENTORY_HOTBAR_SCRIPT.new() as InventoryHotbar
		_hotbar.name = "InventoryHotbar"
		main_root.add_child(_hotbar)
	_refresh_hotbar()


func _configure_inventory_screen() -> void:
	var main_root := get_parent()
	if main_root == null:
		return
	_inventory_screen = main_root.get_node_or_null("MinecraftInventoryScreen") as MinecraftInventoryScreen
	if _inventory_screen == null:
		_inventory_screen = INVENTORY_SCREEN_SCRIPT.new() as MinecraftInventoryScreen
		_inventory_screen.name = "MinecraftInventoryScreen"
		main_root.add_child(_inventory_screen)

	call_deferred("_configure_mechanical_manager")


func _configure_mechanical_manager() -> void:
	var main_root := get_parent()
	if main_root == null:
		return
	_mechanical_manager = main_root.get_node_or_null("MechanicalManager") as MechanicalManager
	if _mechanical_manager == null:
		_mechanical_manager = MECHANICAL_MANAGER_SCRIPT.new() as MechanicalManager
		_mechanical_manager.name = "MechanicalManager"
		main_root.add_child(_mechanical_manager)
	_inventory_screen.setup(_inventory, self)
	if not _inventory_screen.inventory_visibility_changed.is_connected(_on_inventory_visibility_changed):
		_inventory_screen.inventory_visibility_changed.connect(_on_inventory_visibility_changed)
	_on_inventory_visibility_changed(_inventory_screen.is_inventory_open())


func _on_inventory_visibility_changed(is_open: bool) -> void:
	_inventory_input_locked = is_open
	if is_open:
		velocity = Vector3.ZERO
		_clear_block_target()
		for action in INVENTORY_LOCK_ACTIONS:
			Input.action_release(action)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_hotbar() -> void:
	if not is_instance_valid(_hotbar):
		return
	_hotbar.refresh(_inventory.get_slots(), _selected_inventory_slot)
