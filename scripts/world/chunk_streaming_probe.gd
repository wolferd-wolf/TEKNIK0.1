extends Node

@export var chunk_manager_path: NodePath
@export var streaming_anchor_path: NodePath


func _ready() -> void:
	var manager := get_node_or_null(chunk_manager_path) as ChunkManager
	var anchor := get_node_or_null(streaming_anchor_path) as Node3D
	if manager == null or anchor == null:
		push_error("Chunk streaming probe could not resolve its required nodes.")
		return

	manager.refresh_streaming(anchor.global_position)
	var initial_count := manager.chunk_count()
	assert(initial_count == manager.expected_chunk_count())

	anchor.global_position = Vector3(ChunkManager.CHUNK_SIZE, 0.0, 0.0)
	manager.refresh_streaming(anchor.global_position)
	assert(manager.chunk_count() == initial_count)
	assert(manager.last_center_chunk == Vector3i(1, 0, 0))

	anchor.global_position = Vector3(-0.1, 0.0, 0.0)
	manager.refresh_streaming(anchor.global_position)
	assert(manager.chunk_count() == initial_count)
	assert(manager.last_center_chunk == Vector3i(-1, 0, 0))

	print("TEKNIK_CHUNK_STREAMING_SMOKE_PASS count=%d" % manager.chunk_count())
