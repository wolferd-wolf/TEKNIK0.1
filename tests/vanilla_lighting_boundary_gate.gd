extends SceneTree

const RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const EXPECTED_CHUNK_SIZE := 12
const EXPECTED_PADDING := 2


func _init() -> void:
	var failures := PackedStringArray()
	var runtime = RUNTIME.new()

	var width := EXPECTED_CHUNK_SIZE + EXPECTED_PADDING * 2
	var heights: PackedInt32Array = runtime._build_height_cache(Vector2i.ZERO)
	_expect(heights.size() == width * width, "Lighting height cache must include a two-cell border", failures)
	if heights.size() == width * width:
		_expect(
			heights[0] == runtime.data.terrain_height(-EXPECTED_PADDING, -EXPECTED_PADDING),
			"Negative cache corner must contain the real terrain height",
			failures
		)
		_expect(
			heights[heights.size() - 1] == runtime.data.terrain_height(
				EXPECTED_CHUNK_SIZE + EXPECTED_PADDING - 1,
				EXPECTED_CHUNK_SIZE + EXPECTED_PADDING - 1
			),
			"Positive cache corner must contain the real terrain height",
			failures
		)

	var expected_chunks: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for coord in expected_chunks:
		runtime.loaded[coord] = {}
	runtime._schedule_affected_rebuilds(Vector3i(EXPECTED_CHUNK_SIZE - 1, 5, EXPECTED_CHUNK_SIZE - 1))
	_expect(runtime.pending_rebuilds.size() == expected_chunks.size(), "Corner edit must schedule exactly four chunks", failures)
	for coord in expected_chunks:
		_expect(runtime.pending_rebuilds.has(coord), "Corner edit must schedule chunk %s" % coord, failures)

	if failures.is_empty():
		print("VANILLA_LIGHTING_CACHE_BORDER_PASS width=%d" % width)
		print("VANILLA_LIGHTING_DIAGONAL_REMESH_PASS chunks=%d" % expected_chunks.size())
		runtime.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	runtime.free()
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
