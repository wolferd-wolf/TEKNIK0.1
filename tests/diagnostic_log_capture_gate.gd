extends SceneTree

const CAPTURE_SCRIPT := preload("res://scripts/debug/diagnostic_log_capture.gd")
const PROJECT_PATH := "res://project.godot"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const BUTTON_SOURCE_PATH := "res://scripts/ui/diagnostic_log_button.gd"
const RUNTIME_SOURCE_PATH := "res://scripts/world/playable_world_runtime.gd"
const TEST_SOURCE_PATH := "user://diagnostic_capture_gate_source.log"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run() -> void:
	_validate_static_wiring()

	var capture = root.get_node_or_null("DiagnosticLogCapture")
	if capture == null:
		capture = CAPTURE_SCRIPT.new()
		capture.name = "DiagnosticLogCaptureGateService"
		root.add_child(capture)
		await process_frame

	# Prove the configured Godot 4.3 file logger really feeds the in-memory
	# service, rather than testing only a synthetic file-reader path.
	capture._test_set_source_log_path(CAPTURE_SCRIPT.ENGINE_LOG_PATH)
	push_warning("DIAGNOSTIC_ENGINE_WARNING_SENTINEL")
	push_error("DIAGNOSTIC_ENGINE_ERROR_SENTINEL")
	await process_frame
	capture._test_poll_now()
	var engine_buffer: String = capture.get_buffer_text()
	for sentinel in ["DIAGNOSTIC_ENGINE_WARNING_SENTINEL", "DIAGNOSTIC_ENGINE_ERROR_SENTINEL"]:
		if not engine_buffer.contains(sentinel):
			_fail("Godot runtime file logging did not reach the in-memory buffer: %s" % sentinel)

	var source := FileAccess.open(TEST_SOURCE_PATH, FileAccess.WRITE)
	if source == null:
		_fail("Could not create diagnostic capture source fixture")
		_finish()
		return
	source.store_string(
		"WARNING: DIAGNOSTIC_WARNING_SENTINEL\n"
		+ "ERROR: DIAGNOSTIC_ERROR_SENTINEL\n"
		+ "SCRIPT ERROR: DIAGNOSTIC_WORKER_SENTINEL\n"
	)
	source.flush()
	source = null

	capture._test_set_source_log_path(TEST_SOURCE_PATH)
	capture._test_poll_now()
	capture.record_event(
		"WORKER_RESULT_MISSING",
		"coord=(7, 0) revision=3 task_id=42 gate_sentinel"
	)
	capture.flush_now()

	var buffer_text: String = capture.get_buffer_text()
	for sentinel in [
		"DIAGNOSTIC_WARNING_SENTINEL",
		"DIAGNOSTIC_ERROR_SENTINEL",
		"DIAGNOSTIC_WORKER_SENTINEL",
		"WORKER_RESULT_MISSING",
		"gate_sentinel",
	]:
		if not buffer_text.contains(sentinel):
			_fail("In-memory diagnostic buffer missed sentinel: %s" % sentinel)

	var persisted := FileAccess.get_file_as_string(capture.get_latest_log_path())
	if persisted.is_empty():
		_fail("Diagnostic snapshot file was not persisted")
	elif not persisted.contains("WORKER_RESULT_MISSING"):
		_fail("Persisted diagnostic snapshot missed worker failure marker")

	capture.record_event("GATE", "X".repeat(CAPTURE_SCRIPT.MAX_BUFFER_CHARS + 4096))
	var bounded: String = capture.get_buffer_text()
	if bounded.length() > CAPTURE_SCRIPT.MAX_BUFFER_CHARS:
		_fail("Diagnostic in-memory buffer exceeded configured bound")
	if not bounded.begins_with("=== OLDER LOG TEXT TRIMMED ==="):
		_fail("Diagnostic buffer did not mark truncation after bound enforcement")

	if failures.is_empty():
		print("DIAGNOSTIC_LOG_CAPTURE_GATE_PASS")
		print("DIAGNOSTIC_LOG_ENGINE_FILE_CAPTURE=warning+error")
		print("DIAGNOSTIC_LOG_BUFFER_MAX_CHARS=%d" % CAPTURE_SCRIPT.MAX_BUFFER_CHARS)
		print("DIAGNOSTIC_LOG_PERSIST_PATH=%s" % capture.get_latest_log_path())
	_finish()


func _validate_static_wiring() -> void:
	var project_source := FileAccess.get_file_as_string(PROJECT_PATH)
	if not project_source.contains("DiagnosticLogCapture=\"*res://scripts/debug/diagnostic_log_capture.gd\""):
		_fail("Diagnostic capture service is not registered as an autoload")
	if not project_source.contains("file_logging/enable_file_logging=true"):
		_fail("Godot file logging is not enabled for exported/mobile builds")
	if not project_source.contains("file_logging/log_path=\"user://logs/godot.log\""):
		_fail("Godot file log is not routed to the expected user:// path")

	var scene_source := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	if not scene_source.contains("DiagnosticLogButton"):
		_fail("Main gameplay scene is missing the diagnostic copy-log UI")

	var button_source := FileAccess.get_file_as_string(BUTTON_SOURCE_PATH)
	if not button_source.contains("copy_to_clipboard"):
		_fail("Diagnostic UI does not invoke clipboard capture")
	var capture_source := FileAccess.get_file_as_string("res://scripts/debug/diagnostic_log_capture.gd")
	if not capture_source.contains("DisplayServer.clipboard_set"):
		_fail("Diagnostic capture service does not use the system clipboard")
	if not capture_source.contains("PREVIOUS_LOG_PATH"):
		_fail("Diagnostic capture service does not retain previous-session backup state")

	var runtime_source := FileAccess.get_file_as_string(RUNTIME_SOURCE_PATH)
	for marker in ["WORKER_SUBMIT_FAILURE", "WORKER_WAIT_FAILURE", "WORKER_RESULT_MISSING"]:
		if not runtime_source.contains(marker):
			_fail("Chunk runtime is missing permanent worker diagnostic marker: %s" % marker)


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			print("DIAGNOSTIC_LOG_CAPTURE_GATE_FAILURE: %s" % failure)
		quit(1)
