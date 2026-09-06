extends SceneTree

# Structural + visual verification for the inventory redesign: crafting
# panel present (left side), recipe row wired to a real craft button,
# color swatches present and correctly shown/hidden for filled/empty
# slots. Also captures a screenshot to actually look at, since layout/
# visual-hierarchy quality can't be fully verified by assertions alone.

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-crafting-redesign.png"
const MECHANICAL_DATA_SCRIPT := preload("res://scripts/world/mechanical_block_data.gd")
const BLOCK_STONE := 3

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(32)
	print("CHECKPOINT: main loaded")

	var player = main.get_node_or_null("Player")
	if player == null:
		_fail("Player missing from main scene")
		_finish()
		return

	var inventory = player.get_inventory()
	var screen = player.get_inventory_screen()
	if inventory == null or screen == null:
		_fail("Inventory or inventory screen not available")
		_finish()
		return

	# Enough stone to make the shaft recipe affordable and visible, plus a
	# leftover stack and a crafted shaft so filled slots actually render
	# with color instead of every slot being empty.
	inventory.add_item(BLOCK_STONE, 4)
	inventory.add_item(BLOCK_STONE, 6)

	screen.open_inventory()
	print("CHECKPOINT: opened inventory")
	await _wait_frames(3)

	var panel: Node = screen.get_inventory_panel()
	var crafting_panel: Node = panel.find_child("CraftingPanel", true, false)
	print("CHECKPOINT: found crafting_panel? ", crafting_panel != null)
	if crafting_panel == null:
		_fail("CraftingPanel node not found in the rebuilt inventory screen")
		_finish()
		return

	var recipe_row: Node = crafting_panel.find_child("Recipe_shaft", true, false)
	if recipe_row == null:
		_fail("Recipe row for 'shaft' not found in the crafting panel")
	else:
		var craft_button := recipe_row.find_child("*", true, false) as Button
		var found_button: Button = null
		for child in recipe_row.find_children("*", "Button", true, false):
			found_button = child
		if found_button == null:
			_fail("Craft button not found inside the shaft recipe row")
		elif found_button.disabled:
			_fail("Craft button is disabled even though the player has enough stone (10)")

	# Storage slot 1 should show an occupied, visible swatch (10 stone was
	# added and should land in the first storage slot); a still-empty slot
	# should have its swatch hidden.
	var first_storage_slot: Node = screen.find_child("HotbarSlot1", true, false)
	var first_storage_swatch: Node = first_storage_slot.find_child("Swatch", true, false) if first_storage_slot else null
	if first_storage_swatch == null:
		_fail("Could not locate HotbarSlot1's swatch node -- structure may have changed")
	elif not first_storage_swatch.visible:
		_fail("HotbarSlot1's swatch is hidden even though it should hold stone (add_item fills index 0 first)")

	var last_storage_slot: Node = screen.find_child("StorageSlot27", true, false)
	var last_storage_swatch: Node = last_storage_slot.find_child("Swatch", true, false) if last_storage_slot else null
	if last_storage_swatch == null:
		_fail("Could not locate StorageSlot27's swatch node -- structure may have changed")
	elif last_storage_swatch.visible:
		_fail("StorageSlot27's swatch is visible even though that slot should be empty")

	# Craft one for real through the actual button-press path, not by
	# calling the registry directly, so the click wiring itself is proven.
	var count_before: int = inventory.get_item_count(BLOCK_STONE)
	for child in crafting_panel.find_children("*", "Button", true, false):
		child.pressed.emit()
	print("CHECKPOINT: pressed craft button")
	await _wait_frames(2)
	print("CHECKPOINT: waited after craft")
	if inventory.get_item_count(MECHANICAL_DATA_SCRIPT.MECH_SHAFT) != 1:
		_fail("Pressing the craft button did not produce a shaft")
	if inventory.get_item_count(BLOCK_STONE) != count_before - 4:
		_fail("Pressing the craft button did not consume the recipe's stone cost")

	await _capture_screenshot(root)
	print("CHECKPOINT: screenshot step done (best-effort, non-fatal in this sandbox)")

	_finish()


# Best-effort only: this container's headless xvfb+opengl3 setup does not
# reliably produce a populated viewport texture (confirmed: even
# inventory_vanilla_baseline_gate.gd's identical capture pattern never
# reaches a saved PNG in this environment, unrelated to this change). The
# real correctness proof for this gate is the structural/behavioral
# assertions above; a screenshot failure here is logged, not fatal.
func _capture_screenshot(viewport: Viewport) -> void:
	await _wait_frames(5)
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		print("SCREENSHOT_SKIPPED=empty viewport texture in this headless sandbox")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if error != OK:
		print("SCREENSHOT_SKIPPED=save failed with error %d" % error)
		return
	print("INVENTORY_CRAFTING_REDESIGN_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		print("INVENTORY_CRAFTING_REDESIGN_GATE_PASS")
		quit(0)
	else:
		print("INVENTORY_CRAFTING_REDESIGN_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
