extends RefCounted

# Main-thread spatial index for persistent player edits. The save format remains
# unchanged (string cell keys in data.overrides); this helper only avoids deep-
# copying the entire world edit dictionary every time one chunk is dispatched.

var _buckets: Dictionary = {}
var _chunk_size := 12


func rebuild(source_overrides: Dictionary, chunk_size: int) -> void:
	_chunk_size = maxi(chunk_size, 1)
	_buckets.clear()
	for key_value: Variant in source_overrides.keys():
		var parsed: Variant = _parse_cell_key(key_value)
		if parsed == null:
			continue
		var cell: Vector3i = parsed
		_set_bucket_value(cell, int(source_overrides.get(key_value, 0)))


func set_override(cell: Vector3i, block_id: int) -> void:
	_set_bucket_value(cell, block_id)


func snapshot_for_chunk(coord: Vector2i, chunk_size: int, padding: int) -> Dictionary:
	var size := maxi(chunk_size, 1)
	var pad := maxi(padding, 0)
	var min_x := coord.x * size - pad
	var min_z := coord.y * size - pad
	var max_x := coord.x * size + size + pad - 1
	var max_z := coord.y * size + size + pad - 1
	var min_bucket_x := floori(float(min_x) / float(_chunk_size))
	var min_bucket_z := floori(float(min_z) / float(_chunk_size))
	var max_bucket_x := floori(float(max_x) / float(_chunk_size))
	var max_bucket_z := floori(float(max_z) / float(_chunk_size))
	var snapshot: Dictionary = {}
	for bucket_z in range(min_bucket_z, max_bucket_z + 1):
		for bucket_x in range(min_bucket_x, max_bucket_x + 1):
			var bucket_coord := Vector2i(bucket_x, bucket_z)
			var bucket: Dictionary = _buckets.get(bucket_coord, {})
			for cell_value: Variant in bucket.keys():
				var cell: Vector3i = cell_value
				if cell.x < min_x or cell.x > max_x or cell.z < min_z or cell.z > max_z:
					continue
				snapshot[_cell_key(cell)] = int(bucket.get(cell, 0))
	return snapshot


func bucket_count() -> int:
	return _buckets.size()


func _set_bucket_value(cell: Vector3i, block_id: int) -> void:
	var bucket_coord := Vector2i(
		floori(float(cell.x) / float(_chunk_size)),
		floori(float(cell.z) / float(_chunk_size))
	)
	var bucket: Dictionary = _buckets.get(bucket_coord, {})
	bucket[cell] = block_id
	_buckets[bucket_coord] = bucket


static func _parse_cell_key(key_value: Variant) -> Variant:
	var parts := String(key_value).split(",")
	if parts.size() != 3:
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


static func _cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]
