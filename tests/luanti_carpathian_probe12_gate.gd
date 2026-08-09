extends SceneTree

const Prototype = preload("res://scripts/world/reference/luanti_carpathian_probe12_prototype.gd")
const GRID := 128
const STEP := 16
const CHUNK_SIZE := 16


func _init() -> void:
	var out_dir := "res://artifacts/carpathian-probe12"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var seeds: PackedInt32Array = PackedInt32Array([734921, 19088743, 11235813])
	for seed in seeds:
		var result := _audit_seed(seed, out_dir)
		print("CARPATHIAN_PROBE12_SEED=%d height_min=%d height_max=%d height_mean=%.4f height_p05=%d height_p50=%d height_p95=%d slope_le_1_pct=%.4f slope_le_2_pct=%.4f largest_low_relief_equiv_width_blocks=%.4f elapsed_ms=%.3f" % [
			seed, result["min"], result["max"], result["mean"], result["p05"],
			result["p50"], result["p95"], result["slope1"], result["slope2"],
			result["equiv_width"], result["elapsed_ms"]
		])
	var timings := _benchmark_chunk()
	print("CARPATHIAN_PROBE12_CHUNK_MS min=%.4f mean=%.4f p95=%.4f max=%.4f samples=%d" % [
		timings["min"], timings["mean"], timings["p95"], timings["max"], timings["count"]
	])
	print("LUANTI_CARPATHIAN_PROBE12_COMPLETE")
	quit(0)


func _audit_seed(seed: int, out_dir: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var gen := Prototype.new(seed)
	var count := GRID * GRID
	var heights := PackedInt32Array()
	heights.resize(count)
	var half: int = GRID >> 1
	var min_h := 999999
	var max_h := -999999
	var sum_h := 0.0
	for z in range(GRID):
		for x in range(GRID):
			var h := gen.surface_height_probe12((x - half) * STEP, (z - half) * STEP)
			var i := z * GRID + x
			heights[i] = h
			min_h = mini(min_h, h)
			max_h = maxi(max_h, h)
			sum_h += h

	var sorted: Array = []
	sorted.resize(count)
	for i in range(count):
		sorted[i] = heights[i]
	sorted.sort()
	var p05 := int(sorted[int(floor((count - 1) * 0.05))])
	var p50 := int(sorted[int(floor((count - 1) * 0.50))])
	var p95 := int(sorted[int(floor((count - 1) * 0.95))])

	var low := PackedByteArray()
	low.resize(count)
	var slope1_count := 0
	var slope2_count := 0
	for z in range(GRID):
		for x in range(GRID):
			var i := z * GRID + x
			var slope := 0
			if x > 0: slope = maxi(slope, absi(heights[i] - heights[i - 1]))
			if x + 1 < GRID: slope = maxi(slope, absi(heights[i] - heights[i + 1]))
			if z > 0: slope = maxi(slope, absi(heights[i] - heights[i - GRID]))
			if z + 1 < GRID: slope = maxi(slope, absi(heights[i] - heights[i + GRID]))
			if slope <= 1:
				slope1_count += 1
				low[i] = 1
			if slope <= 2: slope2_count += 1

	var seen := PackedByteArray()
	seen.resize(count)
	var queue := PackedInt32Array()
	var largest := 0
	for start in range(count):
		if low[start] == 0 or seen[start] != 0: continue
		queue.clear()
		queue.append(start)
		seen[start] = 1
		var head := 0
		var component := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			component += 1
			var x := i % GRID
			var z := floori(float(i) / float(GRID))
			if x > 0: _try_add(i - 1, low, seen, queue)
			if x + 1 < GRID: _try_add(i + 1, low, seen, queue)
			if z > 0: _try_add(i - GRID, low, seen, queue)
			if z + 1 < GRID: _try_add(i + GRID, low, seen, queue)
		largest = maxi(largest, component)

	var image := Image.create(GRID, GRID, false, Image.FORMAT_L8)
	var denom := maxf(1.0, float(max_h - min_h))
	for z in range(GRID):
		for x in range(GRID):
			var value := clampf(float(heights[z * GRID + x] - min_h) / denom, 0.0, 1.0)
			image.set_pixel(x, z, Color(value, value, value))
	image.save_png("%s/height_seed_%d.png" % [out_dir, seed])
	var ended := Time.get_ticks_usec()
	return {
		"min": min_h, "max": max_h, "mean": sum_h / float(count),
		"p05": p05, "p50": p50, "p95": p95,
		"slope1": 100.0 * float(slope1_count) / float(count),
		"slope2": 100.0 * float(slope2_count) / float(count),
		"equiv_width": sqrt(float(largest) * float(STEP * STEP)),
		"elapsed_ms": float(ended - started) / 1000.0,
	}


func _try_add(index: int, low: PackedByteArray, seen: PackedByteArray, queue: PackedInt32Array) -> void:
	if low[index] != 0 and seen[index] == 0:
		seen[index] = 1
		queue.append(index)


func _benchmark_chunk() -> Dictionary:
	var gen := Prototype.new(734921)
	var samples := PackedFloat64Array()
	for _warmup in range(3):
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				gen.surface_height_probe12(x, z)
	for rep in range(20):
		var started := Time.get_ticks_usec()
		var x0 := rep * 37
		var z0 := rep * -29
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				gen.surface_height_probe12(x0 + x, z0 + z)
		var ended := Time.get_ticks_usec()
		samples.append(float(ended - started) / 1000.0)
	samples.sort()
	var total := 0.0
	for value in samples: total += value
	var p95_index := mini(samples.size() - 1, int(ceil(float(samples.size()) * 0.95)) - 1)
	return {
		"min": samples[0], "mean": total / float(samples.size()),
		"p95": samples[p95_index], "max": samples[samples.size() - 1],
		"count": samples.size(),
	}
