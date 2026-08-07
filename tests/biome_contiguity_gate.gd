extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MAP_OVERLAY := preload("res://scripts/ui/world_map_overlay.gd")

const LEGACY_PATCH_SIZE := 3
const MAP_SAMPLE_SPACING := 2
const MAP_PIXEL_DIAMETER := 49
const MICRO_COMPONENT_MAX_CELLS := 8
const TINY_COMPONENT_MAX_CELLS := 2
const MAX_MICRO_CELL_RATIO := 0.08
const MAX_TINY_CELL_RATIO := 0.02
const MAX_TRANSITION_RATIO := 0.12
const MIN_AREA_WEIGHTED_COMPONENT_CELLS := 80.0
const MAX_COMPONENT_COUNT_RATIO_TO_LEGACY := 0.35
const CENTERS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(157, -16),
	Vector2i(512, 512),
	Vector2i(-512, 256),
]

var failures: Array[String] = []


func _init() -> void:
	var data = WORLD_DATA.new()
	_validate_contract()
	var current: Dictionary = _analyze(data, WORLD_DATA.BIOME_BLEND_PATCH_SIZE)
	var legacy: Dictionary = _analyze(data, LEGACY_PATCH_SIZE)
	var current_failures: Array[String] = _metric_failures(current)
	var legacy_failures: Array[String] = _metric_failures(legacy)
	for failure in current_failures:
		_fail("Current 12-block blend failed minimap contiguity: %s" % failure)
	if legacy_failures.is_empty():
		_fail("The 2-block minimap contiguity gate would not have caught the original 3x3 speckle")
	if float(current["transition_ratio"]) >= float(legacy["transition_ratio"]) * 0.70:
		_fail("Biome edge frequency did not improve enough at actual minimap resolution")
	if float(current["micro_cell_ratio"]) >= float(legacy["micro_cell_ratio"]) * 0.60:
		_fail("Small-region area did not improve enough over the original 3x3 blend")
	if float(current["component_count"]) >= float(legacy["component_count"]) * MAX_COMPONENT_COUNT_RATIO_TO_LEGACY:
		_fail("Resolved biome component count did not fall enough versus the original 3x3 blend")
	var report := {
		"sampling_contract": {
			"map_sample_spacing_blocks": MAP_SAMPLE_SPACING,
			"map_pixel_diameter": MAP_PIXEL_DIAMETER,
			"view_count": CENTERS.size(),
			"sampled_points": MAP_PIXEL_DIAMETER * MAP_PIXEL_DIAMETER * CENTERS.size(),
			"current_patch_blocks": WORLD_DATA.BIOME_BLEND_PATCH_SIZE,
			"current_patch_minimap_pixels": float(WORLD_DATA.BIOME_BLEND_PATCH_SIZE) / float(MAP_SAMPLE_SPACING),
			"legacy_patch_blocks": LEGACY_PATCH_SIZE,
			"legacy_patch_minimap_pixels": float(LEGACY_PATCH_SIZE) / float(MAP_SAMPLE_SPACING),
		},
		"thresholds": {
			"micro_component_max_cells": MICRO_COMPONENT_MAX_CELLS,
			"tiny_component_max_cells": TINY_COMPONENT_MAX_CELLS,
			"max_micro_cell_ratio": MAX_MICRO_CELL_RATIO,
			"max_tiny_cell_ratio": MAX_TINY_CELL_RATIO,
			"max_transition_ratio": MAX_TRANSITION_RATIO,
			"min_area_weighted_component_cells": MIN_AREA_WEIGHTED_COMPONENT_CELLS,
			"max_component_count_ratio_to_legacy": MAX_COMPONENT_COUNT_RATIO_TO_LEGACY,
		},
		"current": current,
		"legacy_3x3": legacy,
		"current_failures": current_failures,
		"legacy_failures": legacy_failures,
		"legacy_would_fail_new_gate": not legacy_failures.is_empty(),
	}
	print("BIOME_CONTIGUITY_GATE_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("BIOME_CONTIGUITY_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_contract() -> void:
	if WORLD_MAP_OVERLAY.MAP_SAMPLE_SPACING != MAP_SAMPLE_SPACING:
		_fail("Gate spacing does not match the shipping minimap spacing")
	if WORLD_MAP_OVERLAY.MAP_PIXEL_DIAMETER != MAP_PIXEL_DIAMETER:
		_fail("Gate diameter does not match the shipping minimap diameter")
	if WORLD_DATA.BIOME_BLEND_PATCH_SIZE < MAP_SAMPLE_SPACING * 6:
		_fail("Blend patch is still smaller than six minimap samples")
	if WORLD_DATA.BIOME_BLEND_PATCH_SIZE > MAP_SAMPLE_SPACING * 12:
		_fail("Blend patch is large enough to become a visibly coarse tile")


func _analyze(data, patch_size: int) -> Dictionary:
	var total_points := 0
	var total_edges := 0
	var total_transitions := 0
	var total_components := 0
	var total_micro_cells := 0
	var total_tiny_cells := 0
	var total_component_square_sum := 0
	var largest_component := 0
	var biome_counts := PackedInt32Array()
	biome_counts.resize(WORLD_DATA.BIOME_COUNT)
	var per_view: Array[Dictionary] = []
	for center in CENTERS:
		var field: PackedByteArray = _build_field(data, center, patch_size)
		var view: Dictionary = _component_metrics(field)
		var edge_metrics: Dictionary = _transition_metrics(field)
		for biome in range(WORLD_DATA.BIOME_COUNT):
			biome_counts[biome] += int(view["biome_counts"][biome])
		total_points += int(view["points"])
		total_components += int(view["component_count"])
		total_micro_cells += int(view["micro_cells"])
		total_tiny_cells += int(view["tiny_cells"])
		total_component_square_sum += int(view["component_square_sum"])
		largest_component = maxi(largest_component, int(view["largest_component_cells"]))
		total_edges += int(edge_metrics["edges"])
		total_transitions += int(edge_metrics["transitions"])
		per_view.append({
			"center": [center.x, center.y],
			"component_count": view["component_count"],
			"micro_cell_ratio": float(view["micro_cells"]) / float(view["points"]),
			"transition_ratio": float(edge_metrics["transitions"]) / float(edge_metrics["edges"]),
			"area_weighted_component_cells": float(view["component_square_sum"]) / float(view["points"]),
			"largest_component_cells": view["largest_component_cells"],
		})
	var counts: Array[int] = []
	for biome in range(WORLD_DATA.BIOME_COUNT):
		counts.append(int(biome_counts[biome]))
	return {
		"patch_size_blocks": patch_size,
		"points": total_points,
		"component_count": total_components,
		"components_per_1000_points": float(total_components) * 1000.0 / float(total_points),
		"micro_cells": total_micro_cells,
		"micro_cell_ratio": float(total_micro_cells) / float(total_points),
		"tiny_cells": total_tiny_cells,
		"tiny_cell_ratio": float(total_tiny_cells) / float(total_points),
		"transition_count": total_transitions,
		"edge_count": total_edges,
		"transition_ratio": float(total_transitions) / float(total_edges),
		"component_square_sum": total_component_square_sum,
		"area_weighted_component_cells": float(total_component_square_sum) / float(total_points),
		"largest_component_cells": largest_component,
		"biome_counts": counts,
		"views": per_view,
	}


func _build_field(data, center: Vector2i, patch_size: int) -> PackedByteArray:
	var field := PackedByteArray()
	field.resize(MAP_PIXEL_DIAMETER * MAP_PIXEL_DIAMETER)
	var half := int(MAP_PIXEL_DIAMETER / 2)
	for pixel_z in range(MAP_PIXEL_DIAMETER):
		var world_z: int = center.y + (pixel_z - half) * MAP_SAMPLE_SPACING
		for pixel_x in range(MAP_PIXEL_DIAMETER):
			var world_x: int = center.x + (pixel_x - half) * MAP_SAMPLE_SPACING
			var samples: Vector4 = data.sample_column_noise(world_x, world_z)
			var weights: Vector4 = data.biome_weights_from_samples(samples)
			field[pixel_z * MAP_PIXEL_DIAMETER + pixel_x] = _resolve_with_patch(weights, world_x, world_z, patch_size)
	return field


func _resolve_with_patch(weights: Vector4, x: int, z: int, patch_size: int) -> int:
	var patch_x := floori(float(x) / float(patch_size))
	var patch_z := floori(float(z) / float(patch_size))
	var hash_value := (patch_x * 73856093) ^ (patch_z * 19349663) ^ (WORLD_DATA.WORLD_SEED * 83492791)
	var selector := float(absi(hash_value) % 1000003) / 1000003.0
	var cumulative := weights.x
	if selector < cumulative:
		return WORLD_DATA.BIOME_PLAINS
	cumulative += weights.y
	if selector < cumulative:
		return WORLD_DATA.BIOME_FOREST
	cumulative += weights.z
	if selector < cumulative:
		return WORLD_DATA.BIOME_DESERT
	return WORLD_DATA.BIOME_ROCKY


func _component_metrics(field: PackedByteArray) -> Dictionary:
	var points := field.size()
	var visited := PackedByteArray()
	visited.resize(points)
	var component_count := 0
	var micro_cells := 0
	var tiny_cells := 0
	var component_square_sum := 0
	var largest_component := 0
	var biome_counts := PackedInt32Array()
	biome_counts.resize(WORLD_DATA.BIOME_COUNT)
	for value in field:
		biome_counts[int(value)] += 1
	for start in range(points):
		if visited[start] != 0:
			continue
		component_count += 1
		var biome: int = int(field[start])
		var queue := PackedInt32Array()
		queue.append(start)
		visited[start] = 1
		var cursor := 0
		var size := 0
		while cursor < queue.size():
			var index: int = queue[cursor]
			cursor += 1
			size += 1
			var x := index % MAP_PIXEL_DIAMETER
			var z := int(index / MAP_PIXEL_DIAMETER)
			if x > 0:
				_try_enqueue(index - 1, biome, field, visited, queue)
			if x + 1 < MAP_PIXEL_DIAMETER:
				_try_enqueue(index + 1, biome, field, visited, queue)
			if z > 0:
				_try_enqueue(index - MAP_PIXEL_DIAMETER, biome, field, visited, queue)
			if z + 1 < MAP_PIXEL_DIAMETER:
				_try_enqueue(index + MAP_PIXEL_DIAMETER, biome, field, visited, queue)
		component_square_sum += size * size
		largest_component = maxi(largest_component, size)
		if size <= MICRO_COMPONENT_MAX_CELLS:
			micro_cells += size
		if size <= TINY_COMPONENT_MAX_CELLS:
			tiny_cells += size
	return {
		"points": points,
		"component_count": component_count,
		"micro_cells": micro_cells,
		"tiny_cells": tiny_cells,
		"component_square_sum": component_square_sum,
		"largest_component_cells": largest_component,
		"biome_counts": biome_counts,
	}


func _try_enqueue(index: int, biome: int, field: PackedByteArray, visited: PackedByteArray, queue: PackedInt32Array) -> void:
	if visited[index] != 0 or int(field[index]) != biome:
		return
	visited[index] = 1
	queue.append(index)


func _transition_metrics(field: PackedByteArray) -> Dictionary:
	var transitions := 0
	var edges := 0
	for z in range(MAP_PIXEL_DIAMETER):
		for x in range(MAP_PIXEL_DIAMETER):
			var index := z * MAP_PIXEL_DIAMETER + x
			var biome: int = int(field[index])
			if x + 1 < MAP_PIXEL_DIAMETER:
				edges += 1
				if biome != int(field[index + 1]):
					transitions += 1
			if z + 1 < MAP_PIXEL_DIAMETER:
				edges += 1
				if biome != int(field[index + MAP_PIXEL_DIAMETER]):
					transitions += 1
	return {"transitions": transitions, "edges": edges}


func _metric_failures(metrics: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if float(metrics["micro_cell_ratio"]) > MAX_MICRO_CELL_RATIO:
		result.append("micro-cell ratio %.6f exceeds %.6f" % [float(metrics["micro_cell_ratio"]), MAX_MICRO_CELL_RATIO])
	if float(metrics["tiny_cell_ratio"]) > MAX_TINY_CELL_RATIO:
		result.append("tiny-cell ratio %.6f exceeds %.6f" % [float(metrics["tiny_cell_ratio"]), MAX_TINY_CELL_RATIO])
	if float(metrics["transition_ratio"]) > MAX_TRANSITION_RATIO:
		result.append("transition ratio %.6f exceeds %.6f" % [float(metrics["transition_ratio"]), MAX_TRANSITION_RATIO])
	if float(metrics["area_weighted_component_cells"]) < MIN_AREA_WEIGHTED_COMPONENT_CELLS:
		result.append("area-weighted component size %.3f is below %.3f" % [float(metrics["area_weighted_component_cells"]), MIN_AREA_WEIGHTED_COMPONENT_CELLS])
	return result


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
