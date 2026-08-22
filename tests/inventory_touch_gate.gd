extends SceneTree

## Touch/input wiring gate for the rehauled UI.
## Covers the user-reported breakage: INVENTORY/CRAFT buttons must open and
## close the station screen through TouchActionControls, visible HUD hotbar
## slots must respond to raw taps (mouse emulation from touch is DISABLED in
## this project), and station-screen slots must route taps with correct
## absolute slot indexes.

const MAIN_SCENE := "res://scenes/main.tscn"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)


func _wait(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _tap(pos: Vector2, touch_index := 0) -> void:
	var down := InputEventScreenTouch.new()
	down.index = touch_index
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await process_frame
	await process_frame
	var up := InputEventScreenTouch.new()
	up.index = touch_index
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)
	await process_frame
	await process_frame


func _mark(section: String, before: int) -> void:
	if failures.size() == before:
		print("%s PASS" % section)
	else:
		print("%s FAIL (%d problems)" % [section, failures.size()])


func _run() -> void:
	var before := failures.size()

	var main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _wait(30)

	var player = main.get_node_or_null("Player")
	var screen = player.get_inventory_screen()
	var touch = main.get_node_or_null("TouchActionControls")
	var hud = main.get_node_or_null("HudHotbar")
	_expect(player != null and screen != null and touch != null and hud != null,
		"main scene exposes player, station screen, touch layer, hud hotbar")
	if player == null or screen == null or touch == null or hud == null:
		print("G10_TOGGLE FAIL")
		print("LEDGER %d/%d" % [checks - failures.size(), checks])
		quit(1)
		return

	# --- G10: INVENTORY/CRAFT buttons drive the screen ---
	touch._toggle_inventory_screen()
	await _wait(5)
	_expect(screen.visible and screen.is_inventory_open(), "touch toggle opens the screen")
	touch._toggle_inventory_screen()
	await _wait(5)
	_expect(not screen.visible, "touch toggle closes the screen")
	screen.toggle_crafting()
	await _wait(4)
	_expect(screen.visible and screen._mode == screen.Mode.CRAFT,
		"toggle_crafting opens crafting mode")
	screen.close_screen()
	await _wait(3)

	var inv_button: Button = touch.get_action_button("InventoryButton")
	await _tap(inv_button.get_global_rect().get_center())
	await _wait(6)
	_expect(screen.visible, "tapping the INVENTORY button opens the screen")
	await _tap(inv_button.get_global_rect().get_center())
	await _wait(6)
	_expect(not screen.visible, "tapping the INVENTORY button again closes the screen")

	var craft_button: Button = touch.get_action_button("CraftButton")
	await _tap(craft_button.get_global_rect().get_center())
	await _wait(6)
	_expect(screen.visible and screen._mode == screen.Mode.CRAFT,
		"tapping the CRAFT button opens crafting mode")
	screen.close_screen()
	await _wait(3)
	_mark("G10_TOGGLE", before)

	# --- G11: visible HUD hotbar taps select slots ---
	before = failures.size()
	player.select_inventory_slot(0)
	await _wait(2)
	var aligned := true
	for slot_index in range(9):
		var target: Button = touch.get_hotbar_button(slot_index)
		if target == null or not target.get_global_rect().intersects(
			hud.get_slot_global_rect(slot_index).grow(2)
		):
			aligned = false
	_expect(aligned, "invisible touch targets sit over the visible HUD slots")

	var rect: Rect2 = hud.get_slot_global_rect(4)
	await _tap(rect.get_center())
	await _wait(8)
	_expect(player.get_selected_inventory_slot() == 4,
		"tapping visible hotbar slot 5 selects it (got %d)" % player.get_selected_inventory_slot())

	# alignment must survive a phone-landscape viewport change
	var previous_size: Vector2i = root.get_viewport().size
	root.get_viewport().size = Vector2i(800, 360)
	await _wait(8)
	var still_aligned := true
	for slot_index in range(9):
		if not touch.get_hotbar_button(slot_index).get_global_rect().intersects(
			hud.get_slot_global_rect(slot_index).grow(2)
		):
			still_aligned = false
	root.get_viewport().size = previous_size
	await _wait(8)
	_expect(still_aligned, "touch targets stay glued to the HUD at phone-landscape size")
	_mark("G11_HOTBAR_TAPS", before)

	# --- G12: station-screen slots route taps with absolute indexes ---
	before = failures.size()
	player.get_inventory().set_slot_stack(
		player.get_inventory().get_hotbar_slot_count() + 5,
		{"block_id": 3, "count": 7}
	)
	screen.open_inventory()
	await _wait(4)
	var storage_view = screen._storage_views[5]
	await _tap(storage_view.get_global_rect().get_center())
	await _wait(4)
	_expect(int(screen._held.get("count", 0)) == 7,
		"tapping a storage cell picks up its stack into the cursor")
	var absolute_index: int = player.get_inventory().get_hotbar_slot_count() + 5
	await _tap(storage_view.get_global_rect().get_center())
	await _wait(4)
	_expect(int(screen._held.get("count", 0)) == 0,
		"second tap puts the stack back")
	_expect(int(player.get_inventory().get_slot(absolute_index).get("count", 0)) == 7,
		"returned stack landed in the SAME storage cell (index mapping intact)")
	screen.close_screen()
	await _wait(3)
	_mark("G12_SCREEN_TAPS", before)

	# --- G13: recipe book scroll (touch drag + mouse wheel) ---
	before = failures.size()
	screen.open_inventory()
	await _wait(3)
	screen._on_book_pressed()
	await _wait(6)
	var scroll_container: ScrollContainer = screen._book_box.get_child(0)
	var book_center: Vector2 = scroll_container.get_global_rect().get_center()
	_expect(scroll_container.get_v_scroll_bar().max_value > 0.0,
		"recipe list overflows so scrolling is possible")

	var pan_down := InputEventScreenTouch.new()
	pan_down.index = 0
	pan_down.pressed = true
	pan_down.position = book_center + Vector2(0, 60)
	Input.parse_input_event(pan_down)
	await process_frame
	await process_frame
	for drag_index in range(6):
		var pan_drag := InputEventScreenDrag.new()
		pan_drag.index = 0
		pan_drag.position = book_center + Vector2(0, 60 - drag_index * 20)
		pan_drag.relative = Vector2(0, -20)
		Input.parse_input_event(pan_drag)
		await process_frame
	var pan_up := InputEventScreenTouch.new()
	pan_up.index = 0
	pan_up.pressed = false
	pan_up.position = book_center - Vector2(0, 60)
	Input.parse_input_event(pan_up)
	await process_frame
	await process_frame
	_expect(scroll_container.scroll_vertical > 0,
		"touch drag pans the recipe list")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = book_center
	Input.parse_input_event(wheel)
	await process_frame
	await process_frame
	var wheel_release := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = false
	wheel.position = book_center
	Input.parse_input_event(wheel_release)
	await process_frame
	_expect(scroll_container.scroll_vertical > 0, "mouse wheel also scrolls the recipe list")
	screen.close_screen()
	await _wait(3)
	_mark("G13_BOOK_SCROLL", before)

	# --- G14: touch split via long press; quick tap still moves stacks ---
	before = failures.size()
	var hotbar_count: int = player.get_inventory().get_hotbar_slot_count()
	player.get_inventory().set_slot_stack(hotbar_count + 5, {"block_id": 3, "count": 7})
	screen.open_inventory()
	await _wait(4)
	var split_view = screen._storage_views[5]
	var split_pos: Vector2 = split_view.get_global_rect().get_center()

	var hold := InputEventScreenTouch.new()
	hold.index = 1
	hold.pressed = true
	hold.position = split_pos
	Input.parse_input_event(hold)
	await process_frame
	await process_frame
	var waited_frames := 0
	while waited_frames < 240 and not screen._pending_press.is_empty() and not bool(screen._pending_press["long_done"]):
		await process_frame
		waited_frames += 1
	_expect(int(screen._held.get("count", 0)) == 4,
		"long press splits half into the cursor")
	var hold_up := InputEventScreenTouch.new()
	hold_up.index = 1
	hold_up.pressed = false
	hold_up.position = split_pos
	Input.parse_input_event(hold_up)
	await _wait(4)
	_expect(int(player.get_inventory().get_slot(hotbar_count + 5).get("count", 0)) == 3,
		"split leaves the remainder in the cell")

	# cursor still holds the 4 split items: tapping the same cell merges back
	await _tap(split_pos, 1)
	await _wait(4)
	_expect(int(screen._held.get("count", 0)) == 0
		and int(player.get_inventory().get_slot(hotbar_count + 5).get("count", 0)) == 7,
		"tapping a cell while holding merges the stack back")
	await _tap(split_pos, 1)
	await _wait(4)
	_expect(int(screen._held.get("count", 0)) == 7,
		"quick tap still takes the whole stack")

	# long press on an empty hotbar cell places exactly one item
	var empty_view = screen._hotbar_views[8]
	var empty_pos: Vector2 = empty_view.get_global_rect().get_center()
	var hold2 := InputEventScreenTouch.new()
	hold2.index = 2
	hold2.pressed = true
	hold2.position = empty_pos
	Input.parse_input_event(hold2)
	await process_frame
	await process_frame
	waited_frames = 0
	while waited_frames < 240 and not screen._pending_press.is_empty() and not bool(screen._pending_press["long_done"]):
		await process_frame
		waited_frames += 1
	var hold2_up := InputEventScreenTouch.new()
	hold2_up.index = 2
	hold2_up.pressed = false
	hold2_up.position = empty_pos
	Input.parse_input_event(hold2_up)
	await _wait(4)
	var slot8_count: int = int(player.get_inventory().get_slot(8).get("count", 0))
	_expect(int(screen._held.get("count", 0)) == 6 and slot8_count == 1,
		"long press on an empty cell drops a single item")
	screen.close_screen()
	await _wait(3)
	_mark("G14_TOUCH_SPLIT", before)

	main.queue_free()
	await _wait(2)
	print("LEDGER %d/%d" % [checks - failures.size(), checks])
	if failures.is_empty():
		print("TOUCH_GATE_PASS")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: %s" % failure)
		quit(1)
