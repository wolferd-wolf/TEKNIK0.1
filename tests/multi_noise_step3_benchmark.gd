extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const INTEGRATION := preload("res://tests/multi_noise_step3_integration.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2
const WARMUPS := 4
const REPEATS := 20

static func run(data, failures: Array[String]) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-4, 4):
			coords.append(Vector2i(x, z))
	for _warmup in range(WARMUPS):
		for coord in coords:
			INTEGRATION.consume_height(INTEGRATION.build_height_only(data, coord))
			INTEGRATION.consume_both(INTEGRATION.build_caches(data, coord))
	var old_times: Array[int] = []
	var new_times: Array[int] = []
	var old_checksum := 0
	var new_checksum := 0
	var biome_checksum := 0
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord := coords[index]
			if (repetition + index) % 2 == 0:
				var old := _measure_height(data, coord)
				var new := _measure_both(data, coord)
				old_times.append(old["usec"])
				old_checksum += old["height"]
				new_times.append(new["usec"])
				new_checksum += new["height"]
				biome_checksum += new["biome"]
			else:
				var new := _measure_both(data, coord)
				var old := _measure_height(data, coord)
				new_times.append(new["usec"])
				new_checksum += new["height"]
				biome_checksum += new["biome"]
				old_times.append(old["usec"])
				old_checksum += old["height"]
	if old_checksum != new_checksum:
		_fail(failures, "Step 3 changed the accepted Step 2 height output")
	var old_stats := _stats(old_times)
	var new_stats := _stats(new_times)
	if int(new_stats["p95_usec"]) >= 1000:
		_fail(failures, "Combined height+biome cache exceeded the committed 1.0 ms p95 threshold")
	var old_mean := float(old_stats["mean_usec"])
	var new_mean := float(new_stats["mean_usec"])
	return {
		"runner": {"os_name": OS.get_name(), "processor_name": OS.get_processor_name(), "processor_count": OS.get_processor_count(), "godot_version": str(Engine.get_version_info().get("string", "unknown"))},
		"benchmark_contract": {"chunk_size": CHUNK_SIZE, "cache_padding": PADDING, "sampled_columns_per_chunk": WIDTH * WIDTH, "measured_chunks_per_path": coords.size() * REPEATS, "base_noise_samples_per_column": WORLD_DATA.NOISE_SAMPLES_PER_COLUMN, "included_work": "cache allocation, one four-noise sample vector per column, height and biome calculation, cache writes", "excluded_work": ["meshing", "rendering", "collision generation", "scene-tree mutation", "file I/O"]},
		"step2_height_only": old_stats,
		"step3_height_and_biome": new_stats,
		"absolute_mean_cost_usec": new_mean - old_mean,
		"relative_cost_percent": ((new_mean / old_mean) - 1.0) * 100.0 if old_mean > 0.0 else 0.0,
		"height_only_checksum": old_checksum,
		"combined_height_checksum": new_checksum,
		"biome_checksum": biome_checksum,
		"raw_height_only_usec": old_times,
		"raw_height_and_biome_usec": new_times,
	}

static func _measure_height(data, coord: Vector2i) -> Dictionary:
	var start := Time.get_ticks_usec()
	var cache := INTEGRATION.build_height_only(data, coord)
	return {"usec": maxi(1, Time.get_ticks_usec() - start), "height": INTEGRATION.consume_height(cache)}

static func _measure_both(data, coord: Vector2i) -> Dictionary:
	var start := Time.get_ticks_usec()
	var caches := INTEGRATION.build_caches(data, coord)
	var sums := INTEGRATION.consume_both(caches)
	return {"usec": maxi(1, Time.get_ticks_usec() - start), "height": sums["height"], "biome": sums["biome"]}

static func _stats(values: Array[int]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count := sorted.size()
	var mean := float(total) / float(count)
	var middle := int(count / 2)
	var median := float(sorted[middle])
	if count % 2 == 0:
		median = (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
	var p95_index := clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)
	return {"sample_count": count, "minimum_usec": sorted[0], "maximum_usec": sorted[count - 1], "mean_usec": mean, "median_usec": median, "p95_usec": sorted[p95_index], "total_usec": total, "minimum_ms": float(sorted[0]) / 1000.0, "maximum_ms": float(sorted[count - 1]) / 1000.0, "mean_ms": mean / 1000.0, "median_ms": median / 1000.0, "p95_ms": float(sorted[p95_index]) / 1000.0, "total_ms": float(total) / 1000.0}

static func _fail(failures: Array[String], message: String) -> void:
	if not failures.has(message):
		failures.append(message)
