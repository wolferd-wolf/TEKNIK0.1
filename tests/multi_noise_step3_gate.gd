extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const CONTRACT := preload("res://tests/multi_noise_step3_contract.gd")
const DISTRIBUTION := preload("res://tests/multi_noise_step3_distribution.gd")
const INTEGRATION := preload("res://tests/multi_noise_step3_integration.gd")
const BENCHMARK := preload("res://tests/multi_noise_step3_benchmark.gd")
const DIAG_PATH := "res://artifacts/multi-noise-step3-biomes.png"

var failures: Array[String] = []

func _init() -> void:
	var data = WORLD_DATA.new()
	CONTRACT.run(data, failures)
	var distribution: Dictionary = DISTRIBUTION.run(data, failures)
	INTEGRATION.run(data, failures)
	var benchmark: Dictionary = BENCHMARK.run(data, failures)
	if failures.is_empty():
		var report: Dictionary = distribution.duplicate(true)
		report.erase("fixtures")
		print("MULTI_NOISE_STEP3_DISTRIBUTION_JSON=%s" % JSON.stringify(report))
		print("MULTI_NOISE_STEP3_BENCHMARK_JSON=%s" % JSON.stringify(benchmark))
		print("MULTI_NOISE_STEP3_DIAGNOSTIC=%s" % ProjectSettings.globalize_path(DIAG_PATH))
		print("MULTI_NOISE_STEP3_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
