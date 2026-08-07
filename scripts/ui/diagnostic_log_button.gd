extends CanvasLayer
class_name DiagnosticLogButton

const BUTTON_SIZE := Vector2(124.0, 48.0)
const RIGHT_MARGIN := 16.0
const TOP_MARGIN := 16.0
const RESET_DELAY_SEC := 1.4

var _root: Control
var _copy_button: Button
var _label_revision := 0


func _ready() -> void:
	layer = 90
	_build_ui()


func get_copy_button() -> Button:
	return _copy_button


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "DiagnosticLogRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_copy_button = Button.new()
	_copy_button.name = "CopyDiagnosticLogButton"
	_copy_button.text = "COPY LOG"
	_copy_button.focus_mode = Control.FOCUS_NONE
	_copy_button.custom_minimum_size = BUTTON_SIZE
	_copy_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_copy_button.offset_left = -RIGHT_MARGIN - BUTTON_SIZE.x
	_copy_button.offset_top = TOP_MARGIN
	_copy_button.offset_right = -RIGHT_MARGIN
	_copy_button.offset_bottom = TOP_MARGIN + BUTTON_SIZE.y
	_copy_button.tooltip_text = "Copy TEKNIK runtime diagnostics"
	_copy_button.pressed.connect(_copy_log)
	_root.add_child(_copy_button)


func _copy_log() -> void:
	var capture := get_node_or_null("/root/DiagnosticLogCapture")
	var copied := false
	if capture != null and capture.has_method("copy_to_clipboard"):
		copied = bool(capture.copy_to_clipboard())
	_label_revision += 1
	var revision := _label_revision
	_copy_button.text = "COPIED" if copied else "NO LOG"
	var timer := get_tree().create_timer(RESET_DELAY_SEC)
	timer.timeout.connect(_restore_label.bind(revision))


func _restore_label(revision: int) -> void:
	if revision != _label_revision or not is_instance_valid(_copy_button):
		return
	_copy_button.text = "COPY LOG"
