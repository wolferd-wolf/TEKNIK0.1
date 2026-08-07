extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")

const MAP_CENTER := Vector2i(157, -16)
const MAP_HALF_SPAN := 96
const MAP_SAMPLE_STEP := 2

var failures: Array[String] = []


func _init() -> void:
	var data = WORLD_DATA.new()
	_validate_height_contract(data)
	var terrain_report: Dictionary = _measure_terrain_shape(data)
	print("WORLD_HEIGHT_60_GATE_JSON=%s" % JSON.stringify({"terrain": terrain_report, "failures": failures}))
	if failures.is_empty():
		print("WORLD_HEIGHT_60_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_height_contract(data) -> void:
	if WORLD_DATA.WORLD_HEIGHT != 60:
		_fail("WORLD_HEIGHT must be exactly 60")
	if WORLD_DATA.TERRAIN_SHAPE_HEIGHT_SCALE < 4.5:
		_fail("Terrain-shape contribution was not increased proportionally from the 40-block profile")
	if WORLD_DATA.ROCKY_MOUNTAIN_BASE_RISE < 6.0:
		_fail("Rocky base rise did not scale with the added vertical headroom")
	if WORLD_DATA.ROCKY_MOUNTAIN_RUGGEDNESS < 16.5:
		_fail("Rocky ruggedness did not scale with the added vertical headroom")
	var synthetic_peak: int = data.terrain_height_from_samples(Vector4(1.0, 1.0, -1.0, -1.0))
	if synthetic_peak < 45:
		_fail("Synthetic rocky peak does not use the new 60-block vertical range: %d" % synthetic_peak)
	if synthetic_peak > WORLD_DATA.WORLD_HEIGHT - 3:
		_fail("Synthetic rocky peak clips the world safety margin")


func _measure_terrain_shape(data) -> Dictionary:
	var width: int = int((MAP_HALF_SPAN * 2) / MAP_SAMPLE_STEP) + 1
	var heights := PackedInt32Array()
	heights.resize(width * width)
	var minimum: int = WORLD_DATA.WORLD_HEIGHT
	var maximum := 0
	var legacy_maximum := 0
	for row in range(width):
		var z: int = MAP_CENTER.y - MAP_HALF_SPAN + row * MAP_SAMPLE_STEP
		for column in range(width):
			var x: int = MAP_CENTER.x - MAP_HALF_SPAN + column * MAP_SAMPLE_STEP
			var samples: Vector4 = data.sample_column_noise(x, z)
			var height: int = data.terrain_height_from_samples(samples)
			var index: int = row * width + column
			heights[index] = height
			minimum = mini(minimum, height)
			maximum = maxi(maximum, height)
			legacy_maximum = maxi(legacy_maximum, _legacy_40_height(samples))

	var sorted: Array[int] = []
	for value in heights:
		sorted.append(int(value))
	sorted.sort()
	var median: int = sorted[int(sorted.size() * 0.50)]
	var p90: int = sorted[clampi(ceili(float(sorted.size()) * 0.90) - 1, 0, sorted.size() - 1)]
	var p95: int = sorted[clampi(ceili(float(sorted.size()) * 0.95) - 1, 0, sorted.size() - 1)]
	var compared_edges := 0
	var slope_edges := 0
	var steep_edges := 0
	var ridge_cells := 0
	var upper_slope_cells := 0
	for row in range(1, width - 1):
		for column in range(1, width - 1):
			var index: int = row * width + column
			var center: int = int(heights[index])
			var north: int = int(heights[index - width])
			var south: int = int(heights[index + width])
			var west: int = int(heights[index - 1])
			var east: int = int(heights[index + 1])
			var neighbors: Array[int] = [north, south, west, east]
			var local_min := center
			var local_max := center
			for neighbor in neighbors:
				local_min = mini(local_min, neighbor)
				local_max = maxi(local_max, neighbor)
			for neighbor in [east, south]:
				compared_edges += 1
				var difference := absi(center - int(neighbor))
				if difference >= 1:
					slope_edges += 1
				if difference >= 2:
					steep_edges += 1
			if center >= p90 and center >= local_max and center > local_min:
				ridge_cells += 1
			if center >= p90 and local_max - local_min >= 2:
				upper_slope_cells += 1
	var slope_edge_ratio: float = float(slope_edges) / float(maxi(compared_edges, 1))
	var steep_edge_ratio: float = float(steep_edges) / float(maxi(compared_edges, 1))
	if maximum - minimum < 18:
		_fail("The real map-scale terrain range is still too flat: %d blocks" % (maximum - minimum))
	if p95 - median < 5:
		_fail("Upper terrain distribution lacks meaningful peaks above its median: median=%d p95=%d" % [median, p95])
	if maximum < legacy_maximum + 8:
		_fail("The 60-block profile does not materially exceed the former 40-block peak: new=%d legacy=%d" % [maximum, legacy_maximum])
	if slope_edge_ratio < 0.08:
		_fail("Map-scale terrain lacks enough visible slopes: %.6f" % slope_edge_ratio)
	if steep_edge_ratio < 0.01:
		_fail("Map-scale terrain lacks enough two-block ridge/step edges: %.6f" % steep_edge_ratio)
	if ridge_cells < 4:
		_fail("Map-scale terrain contains too few upper local ridge cells: %d" % ridge_cells)
	if upper_slope_cells < 20:
		_fail("High terrain does not contain enough sloped ridge cells: %d" % upper_slope_cells)
	return {
		"sample_spacing_blocks": MAP_SAMPLE_STEP,
		"sample_width": width,
		"sample_count": heights.size(),
		"minimum_height": minimum,
		"median_height": median,
		"p90_height": p90,
		"p95_height": p95,
		"maximum_height": maximum,
		"legacy_40_maximum_height": legacy_maximum,
		"height_range": maximum - minimum,
		"slope_edge_ratio": slope_edge_ratio,
		"steep_edge_ratio": steep_edge_ratio,
		"ridge_cells": ridge_cells,
		"upper_slope_cells": upper_slope_cells,
	}


func _legacy_40_height(samples: Vector4) -> int:
	var base_height: float = 10.0 + samples.x * 6.4 + samples.y * 3.0
	var cold_t: float = clampf((samples.z - (WORLD_DATA.BIOME_COLD_THRESHOLD - WORLD_DATA.BIOME_BLEND_WIDTH)) / (WORLD_DATA.BIOME_BLEND_WIDTH * 2.0), 0.0, 1.0)
	cold_t = cold_t * cold_t * (3.0 - 2.0 * cold_t)
	var wet_t: float = clampf((samples.w - (WORLD_DATA.BIOME_WET_THRESHOLD - WORLD_DATA.BIOME_BLEND_WIDTH)) / (WORLD_DATA.BIOME_BLEND_WIDTH * 2.0), 0.0, 1.0)
	wet_t = wet_t * wet_t * (3.0 - 2.0 * wet_t)
	var rocky_weight: float = (1.0 - cold_t) * (1.0 - wet_t)
	var land_factor: float = clampf((base_height - 6.0) / 3.0, 0.0, 1.0)
	land_factor = land_factor * land_factor * (3.0 - 2.0 * land_factor)
	var peak_strength: float = clampf((samples.y + 1.0) * 0.5, 0.0, 1.0)
	peak_strength *= peak_strength
	return clampi(roundi(base_height + rocky_weight * land_factor * (4.0 + peak_strength * 11.0)), 3, 37)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
