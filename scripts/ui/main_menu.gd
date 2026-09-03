extends Control

# First screen the player sees. Previously the game always resumed the
# last save silently -- no way to start fresh, no way to even know a save
# existed before it got loaded over. This adds the missing choice.
#
# WorldSeed._ready() (autoload) already runs before this scene loads and
# picks current_seed from SaveManager's save if one exists, or a random
# value if not. That's exactly right for Continue. For New Game we have
# to explicitly override it with a fresh seed and wipe the old save,
# since otherwise the "new" world would silently reuse the old one.

const MAIN_SCENE := "res://scenes/main.tscn"

var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = TeknikTheme.COLOR_PANEL_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_CENTER)
	layout.custom_minimum_size = Vector2(280, 0)
	layout.add_theme_constant_override("separation", 18)
	add_child(layout)
	layout.position -= layout.custom_minimum_size * 0.5

	var title := Label.new()
	title.text = "TEKNIK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	TeknikTheme.style_label(title, 40, TeknikTheme.COLOR_ACCENT, true)
	layout.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	layout.add_child(spacer)

	if SaveManager.has_save():
		var continue_button := Button.new()
		continue_button.text = "Continue"
		continue_button.custom_minimum_size = Vector2(0, 56)
		TeknikTheme.style_button(continue_button)
		continue_button.pressed.connect(_on_continue_pressed)
		layout.add_child(continue_button)

	var new_game_button := Button.new()
	new_game_button.text = "New Game"
	new_game_button.custom_minimum_size = Vector2(0, 56)
	TeknikTheme.style_button(new_game_button)
	new_game_button.pressed.connect(_on_new_game_pressed)
	layout.add_child(new_game_button)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Starting a new game erases your current save. Continue?"
	_confirm_dialog.ok_button_text = "Erase and start new"
	_confirm_dialog.confirmed.connect(_start_new_game)
	add_child(_confirm_dialog)


func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_new_game_pressed() -> void:
	if SaveManager.has_save():
		_confirm_dialog.popup_centered()
	else:
		_start_new_game()


func _start_new_game() -> void:
	SaveManager.clear_save()
	randomize()
	WorldSeed.set_seed(randi())
	get_tree().change_scene_to_file(MAIN_SCENE)
