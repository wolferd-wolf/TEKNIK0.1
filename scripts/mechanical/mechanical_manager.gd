class_name MechanicalManager
extends Node

## Central manager for the rotational power network.
## Handles placement/breaking of mechanical blocks and network solving.

const MECHANICAL_NODE := preload("res://scripts/mechanical/mechanical_node.gd")
const MECHANICAL_NETWORK := preload("res://scripts/mechanical/mechanical_network.gd")
const WATER_WHEEL_SCRIPT := preload("res://scripts/mechanical/water_wheel.gd")
const SHAFT_SCRIPT := preload("res://scripts/mechanical/shaft.gd")
const MECHANICAL_DRILL_SCRIPT := preload("res://scripts/mechanical/mechanical_drill.gd")

const BLOCK_WATER_WHEEL := 7
const BLOCK_SHAFT := 8
const BLOCK_MECHANICAL_DRILL := 9

signal mechanical_block_placed(coord: Vector3i, block_id: int)
signal mechanical_block_broken(coord: Vector3i, block_id: int)

var network: MECHANICAL_NETWORK = MECHANICAL_NETWORK.new()
var _mechanical_entities: Dictionary = {}  # Vector3i -> {block_id, node_ref}


func _ready() -> void:
	add_to_group("mechanical_manager")
	# Watch for chunk manager
	call_deferred("_connect_chunk_manager")


func _connect_chunk_manager() -> void:
	var chunk_manager := get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager != null:
		# Chunk manager may emit signals when blocks are placed/mined
		# We'll hook into the player controller's placement instead
		pass


func place_mechanical_block(world_coord: Vector3i, block_id: int) -> bool:
	if _mechanical_entities.has(world_coord):
		return false

	var entity_node: Node3D
	var mechanical_node: MECHANICAL_NODE

	match block_id:
		BLOCK_WATER_WHEEL:
			entity_node = WATER_WHEEL_SCRIPT.new()
			(entity_node as WaterWheel).setup(network, world_coord)
			mechanical_node = (entity_node as WaterWheel).get_mechanical_node()
		BLOCK_SHAFT:
			entity_node = SHAFT_SCRIPT.new()
			(entity_node as Shaft).setup(network, world_coord)
			mechanical_node = (entity_node as Shaft).get_mechanical_node()
		BLOCK_MECHANICAL_DRILL:
			entity_node = MECHANICAL_DRILL_SCRIPT.new()
			(entity_node as MechanicalDrill).setup(network, world_coord)
			mechanical_node = (entity_node as MechanicalDrill).get_mechanical_node()
		_:
			return false

	# Add to scene tree at world position (only if in a scene tree)
	if is_inside_tree() and get_tree() != null:
		var chunk_manager := get_tree().get_first_node_in_group("chunk_manager")
		if chunk_manager != null:
			# Find the chunk node at this coordinate
			var chunk_coord: Vector3i = chunk_manager.world_to_chunk_coord(Vector3(world_coord.x, world_coord.y, world_coord.z))
			var chunk_key: String = "%d,%d" % [chunk_coord.x, chunk_coord.z]
			var chunk_entry: Dictionary = chunk_manager.chunks.get(chunk_key)
			if chunk_entry != null and is_instance_valid(chunk_entry.chunk):
				chunk_entry.chunk.add_child(entity_node)
			else:
				# Add to root if chunk not found
				get_tree().root.add_child(entity_node)
		else:
			get_tree().root.add_child(entity_node)

		entity_node.global_position = Vector3(world_coord.x + 0.5, world_coord.y + 0.5, world_coord.z + 0.5)

	_mechanical_entities[world_coord] = {
		"block_id": block_id,
		"node": entity_node,
		"mechanical_node": mechanical_node
	}

	mechanical_block_placed.emit(world_coord, block_id)
	return true


func break_mechanical_block(world_coord: Vector3i) -> bool:
	var entity: Dictionary = _mechanical_entities.get(world_coord)
	if entity == null:
		return false

	var block_id: int = entity.block_id
	var node: Node3D = entity.node

	if is_instance_valid(node):
		match block_id:
			BLOCK_WATER_WHEEL:
				(node as WaterWheel).on_break()
			BLOCK_SHAFT:
				(node as Shaft).on_break()
			BLOCK_MECHANICAL_DRILL:
				(node as MechanicalDrill).on_break()
		node.queue_free()

	_mechanical_entities.erase(world_coord)
	mechanical_block_broken.emit(world_coord, block_id)
	return true


func get_mechanical_node_at(world_coord: Vector3i) -> MECHANICAL_NODE:
	var entity: Dictionary = _mechanical_entities.get(world_coord)
	if entity == null:
		return null
	return entity.mechanical_node as MECHANICAL_NODE


func is_mechanical_block(block_id: int) -> bool:
	return block_id >= BLOCK_WATER_WHEEL and block_id <= BLOCK_MECHANICAL_DRILL


func get_network() -> MECHANICAL_NETWORK:
	return network


func refresh_network() -> void:
	network.refresh_connectivity()
	network.solve()


func debug_lines() -> Array[String]:
	var lines = network.debug_lines()
	lines.insert(0, "Mechanical Network (%d nodes)" % network.node_count())
	return lines