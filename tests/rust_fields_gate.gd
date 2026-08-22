extends SceneTree

## Rust fields bootstrap gate (build plan step 7).
## Proves the Rust GDExtension loads into Godot 4.3 and its probe class
## answers a cross-language call. Runs after an editor scan.

const PROBE_CLASS := &"TeknikRustProbe"

var failures: Array[String] = []


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _init() -> void:
	if not ClassDB.class_exists(PROBE_CLASS):
		_fail("TeknikRustProbe class not registered; extension missing or failed to load")
	else:
		var probe: Object = ClassDB.instantiate(PROBE_CLASS)
		if probe == null:
			_fail("TeknikRustProbe could not be instantiated")
		else:
			var answer: Variant = probe.call("ping")
			if typeof(answer) != TYPE_INT or int(answer) != 42:
				_fail("ping() returned unexpected value: %s" % [answer])
			probe.unreference()

	var payload := {
		"gate": "rust_fields_bootstrap",
		"probe_registered": ClassDB.class_exists(PROBE_CLASS),
		"failures": failures,
	}
	print("RUST_FIELDS_GATE_JSON=", JSON.stringify(payload))
	if failures.is_empty():
		print("RUST_FIELDS_GATE_PASS")
	else:
		print("RUST_FIELDS_GATE_FAIL")
	quit(0 if failures.is_empty() else 1)
