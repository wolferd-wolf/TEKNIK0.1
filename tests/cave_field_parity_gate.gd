extends SceneTree

## Cave field parity gate (build plan step 8).
## Compares the GDScript reference (scripts/world/cave_field_reference.gd)
## against the Rust port (TeknikRustFieldEvaluator) live, in one process,
## using exact double equality over a fixed deterministic coordinate sweep.
## The sweep is the frozen contract: changing either implementation or the
## sweep must be reviewed together.

const REF := preload("res://scripts/world/cave_field_reference.gd")

const X_SAMPLES: Array[int] = [-512, -337, -64, -1, 0, 1, 17, 97, 255, 511]
const Y_SAMPLES: Array[int] = [2, 3, 5, 9, 15, 22, 30, 41, 47, 58]
const Z_SAMPLES: Array[int] = [-512, -256, -7, 0, 3, 64, 128, 400]
const FRACTIONS: Array[float] = [-0.75, -0.25, 0.0, 0.1, 0.5, 0.9, 1.25]

var failures: Array[String] = []
var comparisons := 0
var rust_evaluator: Object = null


func _fail(message: String) -> void:
	if not failures.has(message) and failures.size() < 8:
		failures.append(message)


func _check_f64(label: String, expected: float, actual: float) -> void:
	comparisons += 1
	if expected != actual:
		_fail("%s mismatch: gs=%.17g rust=%.17g" % [label, expected, actual])


func _check_bool(label: String, expected: bool, actual: bool) -> void:
	comparisons += 1
	if expected != actual:
		_fail("%s mismatch: gs=%s rust=%s" % [label, expected, actual])


func _check_range(label: String, value: float) -> void:
	comparisons += 1
	if not (value >= 0.0 and value <= 1.0):
		_fail("%s out of [0,1]: %.17g" % [label, value])


func _init() -> void:
	if not ClassDB.class_exists(&"TeknikRustFieldEvaluator"):
		print("CAVE_FIELD_PARITY_FAIL")
		print("CAVE_FIELD_PARITY_JSON=", JSON.stringify({"error": "TeknikRustFieldEvaluator not registered"}))
		quit(1)
		return
	rust_evaluator = ClassDB.instantiate(&"TeknikRustFieldEvaluator")

	for seed in [0, 1, 734921, -42, 2048153539]:
		for x in X_SAMPLES:
			for y in Y_SAMPLES:
				for z in Z_SAMPLES:
					var gs_hash: float = REF.hash01_3d(x, y, z, seed)
					var rs_hash: float = rust_evaluator.hash01_3d(x, y, z, seed)
					_check_f64("hash(%d,%d,%d,%d)" % [x, y, z, seed], gs_hash, rs_hash)
					_check_range("hash range", gs_hash)
					# Determinism: same inputs, same bits.
					comparisons += 1
					if REF.hash01_3d(x, y, z, seed) != gs_hash:
						_fail("hash not deterministic at (%d,%d,%d,%d)" % [x, y, z, seed])

	for seed in [0, 734921]:
		for x in X_SAMPLES:
			for y in Y_SAMPLES:
				for z in Z_SAMPLES:
					for fx in FRACTIONS:
						var gx := float(x) + fx
						var gy := float(y) + fx * 0.5
						var gz := float(z) - fx
						_check_f64(
							"noise(%g,%g,%g,%d)" % [gx, gy, gz, seed],
							REF.value_noise_3d(gx, gy, gz, seed),
							rust_evaluator.value_noise_3d(gx, gy, gz, seed)
						)
						_check_f64(
							"fbm(%g,%g,%g,%d)" % [gx, gy, gz, seed],
							REF.fbm3(gx, gy, gz, seed, 3, 1.0 / 32.0),
							rust_evaluator.fbm3(gx, gy, gz, seed, 3, 1.0 / 32.0)
						)

	for x in X_SAMPLES:
		for y in Y_SAMPLES:
			for z in Z_SAMPLES:
				_check_f64("tunnel_a(%d,%d,%d)" % [x, y, z], REF.tunnel_a(x, y, z), rust_evaluator.tunnel_a(x, y, z))
				_check_f64("tunnel_b(%d,%d,%d)" % [x, y, z], REF.tunnel_b(x, y, z), rust_evaluator.tunnel_b(x, y, z))
				_check_f64("cheese(%d,%d,%d)" % [x, y, z], REF.cheese_field(x, y, z), rust_evaluator.cheese_field(x, y, z))
				_check_f64("entrance(%d,%d,%d)" % [x, y, z], REF.entrance_value(x, y, z), rust_evaluator.entrance_value(x, y, z))

	var surfaces: Array[int] = [12, 24, 40, 64]
	var sea_levels: Array[int] = [10, 12]
	for x in X_SAMPLES:
		for z in Z_SAMPLES:
			for surface_y in surfaces:
				for water_column in [false, true]:
					for y in Y_SAMPLES:
						var gs_cell: bool = REF.is_cave_cell(x, y, z, surface_y, 12, water_column, 0)
						var rs_cell: bool = rust_evaluator.is_cave_cell(x, y, z, surface_y, 12, water_column, 0)
						_check_bool("cell(%d,%d,%d,s=%d,w=%s)" % [x, y, z, surface_y, water_column], gs_cell, rs_cell)
		for sea_level in sea_levels:
			for surface_y in surfaces:
				var gs_guard: bool = REF.is_cave_cell(x, 3, 5, surface_y, sea_level, false, 0)
				var rs_guard: bool = rust_evaluator.is_cave_cell(x, 3, 5, surface_y, sea_level, false, 0)
				_check_bool("guard(%d,s=%d,sea=%d)" % [x, surface_y, sea_level], gs_guard, rs_guard)

	rust_evaluator.unreference()

	var payload := {
		"gate": "cave_field_parity",
		"comparisons": comparisons,
		"failure_count": failures.size(),
		"failures": failures,
	}
	print("CAVE_FIELD_PARITY_JSON=", JSON.stringify(payload))
	if failures.is_empty():
		print("CAVE_FIELD_PARITY_PASS")
	else:
		print("CAVE_FIELD_PARITY_FAIL")
	quit(0 if failures.is_empty() else 1)
