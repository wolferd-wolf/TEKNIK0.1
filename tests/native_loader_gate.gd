extends SceneTree

## NativeLoader gate (build plan step 2).
## Proves the native-availability contract:
##  - is_native_available() returns a bool and is stable across calls.
##  - The reported value matches the engine truth (ClassDB).
##  - NATIVE_LOADER_EXPECT_NATIVE env var ("1" lib present / "0" lib absent)
##    must match the detected mode, proving both paths of rule 1.

const NATIVE_CLASS := &"TeknikVoxelMesher"

var failures: Array[String] = []


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _init() -> void:
	var loader := Node.new()
	loader.set_script(load("res://scripts/core/native_loader.gd"))
	root.add_child(loader)
	var native_loader: Node = loader

	var available: bool = native_loader.is_native_available()
	if available != native_loader.is_native_available():
		_fail("is_native_available() is not stable across calls")

	var truth: bool = ClassDB.class_exists(NATIVE_CLASS)
	if available != truth:
		_fail("reported availability does not match ClassDB truth")

	var expected := OS.get_environment("NATIVE_LOADER_EXPECT_NATIVE")
	if expected == "1" and not available:
		_fail("native library expected but not detected")
	elif expected == "0" and available:
		_fail("native library absent but still detected")

	native_loader.reset_cache_for_testing()
	if native_loader.is_native_available() != available:
		_fail("reset_cache_for_testing() changed the detected mode")

	var payload := {
		"gate": "native_loader",
		"native_available": available,
		"classdb_truth": truth,
		"expectation_env": expected,
		"failures": failures,
	}
	print("NATIVE_LOADER_GATE_JSON=", JSON.stringify(payload))
	if failures.is_empty():
		print("NATIVE_LOADER_GATE_PASS")
	else:
		print("NATIVE_LOADER_GATE_FAIL")
	quit(0 if failures.is_empty() else 1)
