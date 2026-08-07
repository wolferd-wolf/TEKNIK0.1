extends Node
class_name DiagnosticLogCaptureService

const ENGINE_LOG_PATH := "user://logs/godot.log"
const DIAGNOSTIC_DIR := "user://diagnostics"
const LATEST_LOG_PATH := "user://diagnostics/runtime_latest.log"
const PREVIOUS_LOG_PATH := "user://diagnostics/runtime_previous.log"
const MAX_BUFFER_CHARS := 262144
const PREVIOUS_IMPORT_CHARS := 98304
const POLL_INTERVAL_SEC := 0.5
const FLUSH_INTERVAL_SEC := 2.0

var _buffer := ""
var _buffer_mutex := Mutex.new()
var _source_log_path := ENGINE_LOG_PATH
var _source_position := 0
var _poll_elapsed := 0.0
var _flush_elapsed := 0.0
var _dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prepare_storage()
	_append_raw(
		"=== TEKNIK DIAGNOSTIC SESSION ===\n"
		+ "started=%s os=%s godot=%s\n"
		% [
			Time.get_datetime_string_from_system(),
			OS.get_name(),
			String(Engine.get_version_info().get("string", "unknown")),
		]
	)
	_poll_source_log()
	_flush_snapshot()


func _process(delta: float) -> void:
	_poll_elapsed += delta
	_flush_elapsed += delta
	if _poll_elapsed >= POLL_INTERVAL_SEC:
		_poll_elapsed = 0.0
		_poll_source_log()
	if _flush_elapsed >= FLUSH_INTERVAL_SEC:
		_flush_elapsed = 0.0
		_flush_snapshot()


func _exit_tree() -> void:
	_poll_source_log()
	_flush_snapshot()


func record_event(category: String, message: String) -> void:
	_append_raw(
		"[%s][%s] %s\n"
		% [Time.get_datetime_string_from_system(), category, message]
	)
	# Worker failures are rare and important. Request a backup on the next frame
	# instead of waiting for the normal periodic flush interval.
	if category.begins_with("WORKER_") or category == "ERROR" or category == "WARNING":
		_flush_elapsed = FLUSH_INTERVAL_SEC


func get_buffer_text() -> String:
	_poll_source_log()
	_buffer_mutex.lock()
	var snapshot := _buffer
	_buffer_mutex.unlock()
	return snapshot


func copy_to_clipboard() -> bool:
	var snapshot := get_buffer_text()
	if snapshot.is_empty():
		return false
	DisplayServer.clipboard_set(snapshot)
	_flush_snapshot()
	return true


func flush_now() -> void:
	_poll_source_log()
	_flush_snapshot()


func get_latest_log_path() -> String:
	return LATEST_LOG_PATH


func get_previous_log_path() -> String:
	return PREVIOUS_LOG_PATH


func _prepare_storage() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIAGNOSTIC_DIR))
	if not FileAccess.file_exists(LATEST_LOG_PATH):
		return
	var previous := FileAccess.get_file_as_string(LATEST_LOG_PATH)
	if previous.is_empty():
		return
	_write_text(PREVIOUS_LOG_PATH, previous)
	var import_start := maxi(previous.length() - PREVIOUS_IMPORT_CHARS, 0)
	_append_raw(
		"=== PREVIOUS SESSION BACKUP ===\n"
		+ previous.substr(import_start)
		+ "\n=== CURRENT SESSION ===\n"
	)


func _poll_source_log() -> void:
	var source := FileAccess.open(_source_log_path, FileAccess.READ)
	if source == null:
		return
	var source_length := source.get_length()
	if _source_position > source_length:
		_source_position = 0
	if _source_position == source_length:
		return
	source.seek(_source_position)
	var appended := ""
	while source.get_position() < source_length:
		appended += source.get_line() + "\n"
	_source_position = source.get_position()
	if appended.is_empty():
		return
	_append_raw(appended)
	# Error/warning streams are the highest-value crash evidence. Once one is
	# observed in Godot's engine log, request a snapshot on the next frame.
	if (
		appended.contains("ERROR:")
		or appended.contains("WARNING:")
		or appended.contains("SCRIPT ERROR:")
		or appended.contains("WORKER_")
	):
		_flush_elapsed = FLUSH_INTERVAL_SEC


func _append_raw(text: String) -> void:
	if text.is_empty():
		return
	_buffer_mutex.lock()
	_buffer += text
	if _buffer.length() > MAX_BUFFER_CHARS:
		var marker := "=== OLDER LOG TEXT TRIMMED ===\n"
		var keep_chars := MAX_BUFFER_CHARS - marker.length()
		var start := maxi(_buffer.length() - keep_chars, 0)
		_buffer = marker + _buffer.substr(start)
	_dirty = true
	_buffer_mutex.unlock()


func _flush_snapshot() -> void:
	_buffer_mutex.lock()
	if not _dirty:
		_buffer_mutex.unlock()
		return
	var snapshot := _buffer
	_dirty = false
	_buffer_mutex.unlock()
	_write_text(LATEST_LOG_PATH, snapshot)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()


# Test-only source redirect used by the permanent gate. Production never calls it.
func _test_set_source_log_path(path: String) -> void:
	_source_log_path = path
	_source_position = 0


func _test_poll_now() -> void:
	_poll_source_log()
