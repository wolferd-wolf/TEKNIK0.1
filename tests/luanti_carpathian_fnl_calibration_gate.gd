extends SceneTree

const Prototype = preload("res://scripts/world/reference/luanti_carpathian_probe12_prototype.gd")
const GRID := 96
const STEP := 16
const ALPHAS: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

# Exact Luanti-reference targets from the 2048-block three-seed study.
# These are behavioral anchors, not pass thresholds for the calibration scan.
const TARGET_P95: Array[float] = [16.0, 28.0, 26.0]
const TARGET_SLOPE1: Array[float] = [76.4252, 66.3467, 62.0941]


func _init() -> void:
	var seeds: Array[int] = [734921, 19088743, 11235813]
	var best_alpha := -1.0
	var best_score := INF
	for alpha in ALPHAS:
		var score := 0.0
		for seed_index in range(seeds.size()):
			var gen := Prototype.new(seeds[seed_index])
			_apply_restoration_alpha(gen, alpha)
			var metrics := _metrics(gen)
			var p95_error: float = absf(float(metrics["p95"]) - TARGET_P95[seed_index]) / maxf(TARGET_P95[seed_index], 1.0)
			var slope_error: float = absf(float(metrics["slope1"]) - TARGET_SLOPE1[seed_index]) / 100.0
			score += p95_error + slope_error
			print("CARPATHIAN_FNL_CAL alpha=%.2f seed=%d p95=%d slope_le1_pct=%.4f max=%d mean=%.4f target_p95=%.1f target_slope=%.4f" % [
				alpha, seeds[seed_index], metrics["p95"], metrics["slope1"], metrics["max"], metrics["mean"],
				TARGET_P95[seed_index], TARGET_SLOPE1[seed_index]
			])
		score /= float(seeds.size())
		print("CARPATHIAN_FNL_CAL_SCORE alpha=%.2f score=%.6f" % [alpha, score])
		if score < best_score:
			best_score = score
			best_alpha = alpha
	print("CARPATHIAN_FNL_CAL_BEST alpha=%.2f score=%.6f" % [best_alpha, best_score])
	print("LUANTI_CARPATHIAN_FNL_CALIBRATION_COMPLETE")
	quit(0)


func _apply_restoration_alpha(gen: Object, alpha: float) -> void:
	var layers: Array = [
		gen.height1, gen.height2, gen.height3, gen.height4,
		gen.hills_terrain, gen.ridge_terrain, gen.step_terrain,
		gen.hills, gen.ridge_mnt, gen.step_mnt, gen.mnt_var,
	]
	for layer in layers:
		var full_sum: float = float(layer.amplitude_sum)
		layer.amplitude_sum = 1.0 + alpha * (full_sum - 1.0)


func _metrics(gen: Object) -> Dictionary:
	var count := GRID * GRID
	var heights := PackedInt32Array()
	heights.resize(count)
	var half: int = GRID >> 1
	var max_h := -999999
	var sum_h := 0.0
	for z in range(GRID):
		for x in range(GRID):
			var h: int = gen.surface_height_probe12((x - half) * STEP, (z - half) * STEP)
			var i := z * GRID + x
			heights[i] = h
			max_h = maxi(max_h, h)
			sum_h += h
	var sorted: Array = []
	sorted.resize(count)
	for i in range(count): sorted[i] = heights[i]
	sorted.sort()
	var p95 := int(sorted[int(floor((count - 1) * 0.95))])
	var slope1 := 0
	for z in range(GRID):
		for x in range(GRID):
			var i := z * GRID + x
			var slope := 0
			if x > 0: slope = maxi(slope, absi(heights[i] - heights[i - 1]))
			if x + 1 < GRID: slope = maxi(slope, absi(heights[i] - heights[i + 1]))
			if z > 0: slope = maxi(slope, absi(heights[i] - heights[i - GRID]))
			if z + 1 < GRID: slope = maxi(slope, absi(heights[i] - heights[i + GRID]))
			if slope <= 1: slope1 += 1
	return {
		"p95": p95,
		"slope1": 100.0 * float(slope1) / float(count),
		"max": max_h,
		"mean": sum_h / float(count),
	}
