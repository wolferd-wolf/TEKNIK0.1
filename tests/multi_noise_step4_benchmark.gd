extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const INTEGRATION := preload("res://tests/multi_noise_step4_integration.gd")
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
			INTEGRATION.consume_both(INTEGRATION.build_discrete_caches(data, coord))
			INTEGRATION.consume_both(INTEGRATION.build_blended_caches(data, coord))

	var discrete_times: Array[int] = []
	var blended_times: Array[int] = []
	var discrete_height_checksum := 0
	var blended_height_checksum := 0
	var discrete_biome_checksum := 0
	var blended_biome_checksum := 0
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[index]
			if (repetition + index) % 2 == 0:
				var discrete: Dictionary = _measure_discrete(data, coord)
				var blended: Dictionary = _measure_blended(data, coord)
				discrete_times.append(int(discrete["usec"]))
				discrete_height_checksum += int(discrete["height"])
				discrete_biome_checksum += int(discrete["biome"])
				blended_times.append(int(blended["usec"]))
				blended_height_checksum += int(blended["height"])
				blended_biome_checksum += int(blended["biome"])
			else:
				var blended: Dictionary = _measure_blended(data, coord)
				var discrete: Dictionary = _measure_discrete(data, coord)
				blended_times.append(int(blended["usec"]))
				blended_height_checksum += int(blended["height"])
				blended_biome_checksum += int(blended["biome"])
				discrete_times.append(int(discrete["usec"]))
				discrete_height_checksum += int(discrete["height"])
				discrete_biome_checksum += int(discrete["biome"])

	if discrete_height_checksum != blended_height_checksum:
		_fail(failures, "Step 4 changed the accepted Step 3 height output")
	if blended_biome_checksum == 0:
		_fail(failures, "Step 4 blend cache produced an invalid zero biome checksum")

	var discrete_stats := _stats(discrete_times)
	var blended_stats := _stats(blended_times)
	if int(blended_stats["p95_usec"]) >= 1000:
		_fail(failures, "Blended height+biome cache exceeded the committed 1.0 ms p95 threshold")
	var discrete_mean := float(discrete_stats["mean_usec"])
	var blended_mean := float(blended_stats["mean_usec"])
	return {
		"runner": {
			"os_name": OS.get_name(),
			"processor_name": OS.get_processor_name(),
			"processor_count": OS.get_processor_count(),
			"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		},
		"benchmark_contract": {
			"chunk_size": CHUNK_SIZE,
			"cache_padding": PADDING,
			"sampled_columns_per_chunk": WIDTH * WIDTH,
			"measured_chunks_per_path": coords.size() * REPEATS,
			"base_noise_samples_per_column": WORLD_DATA.NOISE_SAMPLES_PER_COLUMN,
			"included_work": "cache allocation, one four-noise sample vector per column, height calculation, normalized biome weights, deterministic blend selection, cache writes",
			"excluded_work": [
				"meshing",
				"rendering",
				"collision generation",
				"scene-tree mutation",
				"file I/O",
			],
		},
		"step3_discrete_height_and_biome": discrete_stats,
		"step4_blended_height_and_biome": blended_stats,
		"absolute_mean_cost_usec": blended_mean - discrete_mean,
		"relative_cost_percent": ((blended_mean / discrete_mean) - 1.0) * 100.0 if discrete_mean > 0.0 else 0.0,
		"discrete_height_checksum": discrete_height_checksum,
		"blended_height_checksum": blended_height_checksum,
		"discrete_biome_checksum": discrete_biome_checksum,
		"blended_biome_checksum": blended_biome_checksum,
		"raw_discrete_usec": discrete_times,
		"raw_blended_usec": blended_times,
	}


static func _measure_discrete(data, coord: Vector2i) -> Dictionary:
	var start := Time.get_ticks_usec()
	var caches: Dictionary = INTEGRATION.build_discrete_caches(data, coord)
	var sums: Dictionary = INTEGRATION.consume_both(caches)
	return {
		"usec": maxi(1, Time.get_ticks_usec() - start),
		"height": sums["height"],
		"biome": sums["biome"],
	}


static func _measure_blended(data, coord: Vector2i) -> Dictionary:
	var start := Time.get_ticks_usec()
	var caches: Dictionary = INTEGRATION.build_blended_caches(data, coord)
	var sums: Dictionary = INTEGRATION.consume_both(caches)
	return {
		"usec": maxi(1, Time.get_ticks_usec() - start),
		"height": sums["height"],
		"biome": sums["biome"],
	}


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
	return {
		"sample_count": count,
		"minimum_usec": sorted[0],
		"maximum_usec": sorted[count - 1],
		"mean_usec": mean,
		"median_usec": median,
		"p95_usec": sorted[p95_index],
		"total_usec": total,
		"minimum_ms": float(sorted[0]) / 1000.0,
		"maximum_ms": float(sorted[count - 1]) / 1000.0,
		"mean_ms": mean / 1000.0,
		"median_ms": median / 1000.0,
		"p95_ms": float(sorted[p95_index]) / 1000.0,
		"total_ms": float(total) / 1000.0,
	}


static func _fail(failures: Array[String], message: String) -> void:
	if not failures.has(message):
		failures.append(message)
