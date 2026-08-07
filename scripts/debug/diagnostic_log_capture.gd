extends Node
class_name DiagnosticLogCaptureService

const ENGINE_LOG_PATH := "user://logs/godot.log"
const ENGINE_LOG_DIR := "user://logs"
const DIAGNOSTIC_DIR := "user://diagnostics"
const LATEST_LOG_PATH := "user://diagnostics/runtime_latest.log"
const PREVIOUS_LOG_PATH := "user://diagnostics/runtime_previous.log"
const MAX_BUFFER_CHARS := 262144
const PREVIOUS_IMPORT_CHARS := 98304
const ENGINE_POLL_MAX_BYTES := 65536
const CLIPBOARD_MAX_CHARS := 49152
const CLIPBOARD_RETRY_CHARS := 16384
const POLL_INTERVAL_SEC := 0.5
const FLUSH_INTERVAL_SEC := 2.0

var _buffer := ""
var _buffer_mutex := Mutex.new()
var _source_log_path := ENGINE_LOG_PATH
var _source_position := 0
var _poll_elapsed := 0.0
var _flush_elapsed := 0.0
var _dirty := false
var _last_clipboard_copy_chars := 0
var _last_clipboard_verified := false


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
	if category.begins_with("WORKER_"):
		# Worker failures are rare and are exactly the evidence we cannot afford
		# to lose if Android kills the process immediately afterward.
		_flush_snapshot()
	elif category == "ERROR" or category == "WARNING":
		_flush_elapsed = FLUSH_INTERVAL_SEC


func get_buffer_text() -> String:
	_poll_source_log()
	_buffer_mutex.lock()
	var snapshot := _buffer
	_buffer_mutex.unlock()
	return snapshot


func copy_to_clipboard() -> bool:
	var snapshot := get_buffer_text()
	_last_clipboard_copy_chars = 0
	_last_clipboard_verified = false
	if snapshot.is_empty():
		return false
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		record_event("CLIPBOARD_UNAVAILABLE", "DisplayServer reports no clipboard feature")
		return false

	var payload := _build_clipboard_payload(snapshot, CLIPBOARD_MAX_CHARS)
	DisplayServer.clipboard_set(payload)
	var readback := DisplayServer.clipboard_get()
	if readback == payload:
		_last_clipboard_copy_chars = payload.length()
		_last_clipboard_verified = true
	else:
		# Some Android/OEM clipboard implementations are less reliable with large
		# text. Retry with a much smaller tail that still contains the failure.
		payload = _build_clipboard_payload(snapshot, CLIPBOARD_RETRY_CHARS)
		DisplayServer.clipboard_set(payload)
		readback = DisplayServer.clipboard_get()
		_last_clipboard_verified = readback == payload
		if _last_clipboard_verified:
			_last_clipboard_copy_chars = payload.length()

	_append_raw(
		"[%s][CLIPBOARD_COPY] requested=%d copied=%d verified=%s\n"
		% [
			Time.get_datetime_string_from_system(),
			snapshot.length(),
			_last_clipboard_copy_chars,
			_last_clipboard_verified,
		]
	)
	_flush_snapshot()
	return _last_clipboard_verified


func get_last_clipboard_copy_chars() -> int:
	return _last_clipboard_copy_chars


func was_last_clipboard_verified() -> bool:
	return _last_clipboard_verified


func flush_now() -> void:
	_poll_source_log()
	_flush_snapshot()


func get_latest_log_path() -> String:
	return LATEST_LOG_PATH


func get_previous_log_path() -> String:
	return PREVIOUS_LOG_PATH


func _prepare_storage() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIAGNOSTIC_DIR))
	if FileAccess.file_exists(LATEST_LOG_PATH):
		var previous := FileAccess.get_file_as_string(LATEST_LOG_PATH)
		if not previous.is_empty():
			_write_text(PREVIOUS_LOG_PATH, previous)
			_append_tail("=== PREVIOUS DIAGNOSTIC SNAPSHOT ===", previous)
	_import_previous_engine_log()


func _import_previous_engine_log() -> void:
	var logs := DirAccess.open(ENGINE_LOG_DIR)
	if logs == null:
		return
	var newest_path := ""
	var newest_modified := 0
	for filename in logs.get_files():
		if filename == "godot.log" or not filename.to_lower().ends_with(".log"):
			continue
		var candidate := ENGINE_LOG_DIR.path_join(filename)
		var modified := int(FileAccess.get_modified_time(candidate))
		if modified >= newest_modified:
			newest_modified = modified
			newest_path = candidate
	if newest_path.is_empty():
		return
	var previous_engine_log := FileAccess.get_file_as_string(newest_path)
	if previous_engine_log.is_empty():
		return
	_append_tail("=== PREVIOUS GODOT ENGINE LOG: %s ===" % newest_path, previous_engine_log)


func _append_tail(marker: String, text: String) -> void:
	var import_start := maxi(text.length() - PREVIOUS_IMPORT_CHARS, 0)
	_append_raw(marker + "\n" + text.substr(import_start) + "\n")


func _poll_source_log() -> void:
	var source := FileAccess.open(_source_log_path, FileAccess.READ)
	if source == null:
		return
	var source_length := source.get_length()
	if _source_position > source_length:
		_source_position = 0
	if _source_position == source_length:
		return

	var read_start := _source_position
	var skipped_bytes := 0
	var unread_bytes := source_length - read_start
	if unread_bytes > ENGINE_POLL_MAX_BYTES:
		read_start = source_length - ENGINE_POLL_MAX_BYTES
		skipped_bytes = read_start - _source_position

	source.seek(read_start)
	var appended := source.get_buffer(source_length - read_start).get_string_from_utf8()
	_source_position = source_length
	if skipped_bytes > 0:
		appended = (
			"=== ENGINE LOG BURST TRIMMED: %d BYTES SKIPPED ===\n" % skipped_bytes
			+ appended
		)
	if appended.is_empty():
		return
	_append_raw(appended)
	if (
		appended.contains("ERROR:")
		or appended.contains("WARNING:")
		or appended.contains("SCRIPT ERROR:")
		or appended.contains("WORKER_")
	):
		_flush_elapsed = FLUSH_INTERVAL_SEC


func _build_clipboard_payload(snapshot: String, limit_chars: int) -> String:
	if snapshot.length() <= limit_chars:
		return snapshot
	var marker := "=== TEKNIK LOG TAIL; OLDER TEXT OMITTED FOR ANDROID CLIPBOARD ===\n"
	var keep_chars := maxi(limit_chars - marker.length(), 0)
	return marker + snapshot.substr(snapshot.length() - keep_chars)


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


# Test-only helpers used by the permanent gate. Production never calls them.
func _test_set_source_log_path(path: String) -> void:
	_source_log_path = path
	_source_position = 0


func _test_poll_now() -> void:
	_poll_source_log()


func _test_build_clipboard_payload(snapshot: String, limit_chars: int) -> String:
	return _build_clipboard_payload(snapshot, limit_chars)
