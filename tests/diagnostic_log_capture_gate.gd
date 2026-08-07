extends SceneTree

const CAPTURE_SCRIPT := preload("res://scripts/debug/diagnostic_log_capture.gd")
const PROJECT_PATH := "res://project.godot"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const BUTTON_SOURCE_PATH := "res://scripts/ui/diagnostic_log_button.gd"
const INVENTORY_SCREEN_SOURCE_PATH := "res://scripts/ui/minecraft_inventory_screen.gd"
const TOUCH_ACTION_SOURCE_PATH := "res://scripts/ui/touch_action_controls.gd"
const RUNTIME_SOURCE_PATH := "res://scripts/world/playable_world_runtime.gd"
const TEST_SOURCE_PATH := "user://diagnostic_capture_gate_source.log"
const ROTATED_ENGINE_FIXTURE_PATH := "user://logs/godot-crash-gate.log"

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

	# WORKER_* events must persist synchronously; there is intentionally no
	# explicit flush_now() before this read.
	var persisted := FileAccess.get_file_as_string(capture.get_latest_log_path())
	if persisted.is_empty():
		_fail("Diagnostic snapshot file was not persisted")
	elif not persisted.contains("WORKER_RESULT_MISSING"):
		_fail("Worker failure marker was not crash-safely persisted immediately")

	# A pathological engine-log burst must not cause an unbounded temporary
	# string allocation. The logger is allowed to drop old burst bytes, but it
	# must retain the newest failure evidence and mark the truncation.
	var burst := FileAccess.open(TEST_SOURCE_PATH, FileAccess.WRITE)
	if burst == null:
		_fail("Could not create engine-log burst fixture")
	else:
		burst.store_string(
			"X".repeat(CAPTURE_SCRIPT.ENGINE_POLL_MAX_BYTES + 8192)
			+ "\nERROR: ENGINE_BURST_TAIL_SENTINEL\n"
		)
		burst.flush()
		burst = null
		capture._test_set_source_log_path(TEST_SOURCE_PATH)
		capture._test_poll_now()
		var burst_buffer: String = capture.get_buffer_text()
		if not burst_buffer.contains("ENGINE_BURST_TAIL_SENTINEL"):
			_fail("Bounded engine-log polling lost newest failure evidence")
		if not burst_buffer.contains("ENGINE LOG BURST TRIMMED"):
			_fail("Bounded engine-log polling did not mark skipped burst bytes")

	var clipboard_fixture := (
		"C".repeat(CAPTURE_SCRIPT.CLIPBOARD_MAX_CHARS * 2)
		+ "CLIPBOARD_TAIL_SENTINEL"
	)
	var clipboard_payload: String = capture._test_build_clipboard_payload(
		clipboard_fixture,
		CAPTURE_SCRIPT.CLIPBOARD_RETRY_CHARS
	)
	if clipboard_payload.length() > CAPTURE_SCRIPT.CLIPBOARD_RETRY_CHARS:
		_fail("Android clipboard payload exceeded retry size bound")
	if not clipboard_payload.contains("CLIPBOARD_TAIL_SENTINEL"):
		_fail("Android clipboard payload did not preserve newest log tail")
	if not clipboard_payload.contains("OLDER TEXT OMITTED FOR ANDROID CLIPBOARD"):
		_fail("Android clipboard payload did not mark truncation")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_SCRIPT.ENGINE_LOG_DIR))
	var rotated := FileAccess.open(ROTATED_ENGINE_FIXTURE_PATH, FileAccess.WRITE)
	if rotated == null:
		_fail("Could not create rotated engine-log recovery fixture")
	else:
		rotated.store_string("ERROR: ROTATED_ENGINE_CRASH_SENTINEL\n")
		rotated.flush()
		rotated = null
		var recovery_capture = CAPTURE_SCRIPT.new()
		recovery_capture.name = "DiagnosticLogRecoveryGateService"
		root.add_child(recovery_capture)
		await process_frame
		var recovered: String = recovery_capture.get_buffer_text()
		if not recovered.contains("ROTATED_ENGINE_CRASH_SENTINEL"):
			_fail("Previous rotated Godot engine log was not recovered on relaunch")
		if not recovered.contains("PREVIOUS GODOT ENGINE LOG"):
			_fail("Recovered engine-log tail is missing its session marker")
		recovery_capture.queue_free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROTATED_ENGINE_FIXTURE_PATH))

	capture.record_event("GATE", "X".repeat(CAPTURE_SCRIPT.MAX_BUFFER_CHARS + 4096))
	var bounded: String = capture.get_buffer_text()
	if bounded.length() > CAPTURE_SCRIPT.MAX_BUFFER_CHARS:
		_fail("Diagnostic in-memory buffer exceeded configured bound")
	if not bounded.begins_with("=== OLDER LOG TEXT TRIMMED ==="):
		_fail("Diagnostic buffer did not mark truncation after bound enforcement")

	if failures.is_empty():
		print("DIAGNOSTIC_LOG_CAPTURE_GATE_PASS")
		print("DIAGNOSTIC_LOG_ENGINE_FILE_CAPTURE=warning+error")
		print("DIAGNOSTIC_LOG_ROTATED_ENGINE_RECOVERY=pass")
		print("DIAGNOSTIC_LOG_WORKER_IMMEDIATE_FLUSH=pass")
		print("DIAGNOSTIC_LOG_BOUNDED_ENGINE_POLL_BYTES=%d" % CAPTURE_SCRIPT.ENGINE_POLL_MAX_BYTES)
		print("DIAGNOSTIC_LOG_CLIPBOARD_PRIMARY_CHARS=%d" % CAPTURE_SCRIPT.CLIPBOARD_MAX_CHARS)
		print("DIAGNOSTIC_LOG_CLIPBOARD_RETRY_CHARS=%d" % CAPTURE_SCRIPT.CLIPBOARD_RETRY_CHARS)
		print("DIAGNOSTIC_LOG_TOP_INVENTORY_REMOVED=pass")
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
	for required in [
		"copy_to_clipboard",
		"InputEventScreenTouch",
		"get_global_rect().has_point",
		"COPY FAILED",
	]:
		if not button_source.contains(required):
			_fail("Diagnostic button is missing Android touch/copy behavior: %s" % required)
	var inventory_screen_source := FileAccess.get_file_as_string(INVENTORY_SCREEN_SOURCE_PATH)
	if inventory_screen_source.contains("_toggle_button = Button.new()"):
		_fail("Duplicate top inventory button is still created")
	var touch_action_source := FileAccess.get_file_as_string(TOUCH_ACTION_SOURCE_PATH)
	if not touch_action_source.contains("\"InventoryButton\": INVENTORY_ACTION"):
		_fail("Bottom inventory touch button was removed unexpectedly")
	var capture_source := FileAccess.get_file_as_string("res://scripts/debug/diagnostic_log_capture.gd")
	for required in [
		"DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)",
		"DisplayServer.clipboard_set",
		"DisplayServer.clipboard_get",
		"CLIPBOARD_RETRY_CHARS",
		"ENGINE_POLL_MAX_BYTES",
		"PREVIOUS_LOG_PATH",
		"_import_previous_engine_log",
	]:
		if not capture_source.contains(required):
			_fail("Diagnostic capture hardening is missing: %s" % required)

	var runtime_source := FileAccess.get_file_as_string(RUNTIME_SOURCE_PATH)
	for marker in [
		"WORKER_SUBMIT_FAILURE",
		"WORKER_WAIT_FAILURE",
		"WORKER_RESULT_MISSING",
		"WORKER_TASK_STALL",
	]:
		if not runtime_source.contains(marker):
			_fail("Chunk runtime is missing permanent worker diagnostic marker: %s" % marker)


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			print("DIAGNOSTIC_LOG_CAPTURE_GATE_FAILURE: %s" % failure)
		quit(1)
