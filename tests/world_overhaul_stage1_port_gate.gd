extends SceneTree

const PORT_PATH := "res://scripts/world/playable_world_port.gd"
const PIPELINE_RUNTIME_PATH := "res://scripts/world/playable_world_generation_runtime.gd"
const PIPELINE_DATA := preload("res://scripts/world/playable_world_generation_data.gd")

var failures: Array[String] = []


func _init() -> void:
	var port_source := FileAccess.get_file_as_string(PORT_PATH)
	var expected_preload := "preload(\"%s\")" % PIPELINE_RUNTIME_PATH
	var legacy_preload := "preload(\"res://scripts/world/playable_world_runtime.gd\")"

	if not port_source.contains(expected_preload):
		_fail("Playable world port is not wired to the Stage 1 generation runtime")
	if port_source.contains(legacy_preload):
		_fail("Playable world port still directly preloads the legacy runtime")
	if PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Playable Stage 1 architecture lost the 150-block world-height contract")

	var report := {
		"runtime_path": PIPELINE_RUNTIME_PATH,
		"world_height_limit": PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE1_PORT_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE1_PORT_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
