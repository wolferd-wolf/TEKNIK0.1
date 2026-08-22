class_name WaterWheel
extends Node3D

## Water Wheel — a rotational power SOURCE.
## Emits SU when placed adjacent to flowing water (BLOCK_WATER on any of 6 faces).
## Rotates visually at its base RPM.

const BLOCK_WATER_WHEEL := 7
const BLOCK_WATER := 7
const MECHANICAL_NODE := preload("res://scripts/mechanical/mechanical_node.gd")
const MECHANICAL_NETWORK := preload("res://scripts/mechanical/mechanical_network.gd")

signal su_changed(su: float)

@export var base_rpm: float = 32.0
@export var stress_capacity: float = 64.0

var _mesh: MeshInstance3D
var _node: MECHANICAL_NODE
var _network: MECHANICAL_NETWORK
var _world_coord: Vector3i
var _rotation_angle: float = 0.0
var _is_active: bool = false
var _water_check_timer: float = 0.0
const WATER_CHECK_INTERVAL := 1.0


func _init() -> void:
	_node = MECHANICAL_NODE.new(
		MECHANICAL_NODE.NodeKind.SOURCE,
		Vector3i.ZERO,
		base_rpm,
		stress_capacity,
		0.0
	)
	# Connect all faces by default (shafts can attach on any side)
	for i in range(MECHANICAL_NODE.FACE_DIRECTIONS.size()):
		_node.connect_face(i)


func _ready() -> void:
	_build_visual()
	_rotation_angle = randf() * TAU


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)

	# Create water wheel mesh: central axle + 8 paddles
	var surf_tool := SurfaceTool.new()
	surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.3, 0.2)  # wood color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Central axle (cylinder along X axis)
	var axle_radius := 0.2
	var axle_length := 1.0
	var segments := 12
	for i in range(segments):
		var a1 := float(i) / segments * TAU
		var a2 := float(i + 1) / segments * TAU
		var x1 := axle_length * 0.5
		var x2 := -axle_length * 0.5

		# Face at +X
		surf_tool.add_vertex(Vector3(x1, 0, 0))
		surf_tool.add_vertex(Vector3(x1, sin(a1) * axle_radius, cos(a1) * axle_radius))
		surf_tool.add_vertex(Vector3(x1, sin(a2) * axle_radius, cos(a2) * axle_radius))

		# Face at -X
		surf_tool.add_vertex(Vector3(x2, 0, 0))
		surf_tool.add_vertex(Vector3(x2, sin(a2) * axle_radius, cos(a2) * axle_radius))
		surf_tool.add_vertex(Vector3(x2, sin(a1) * axle_radius, cos(a1) * axle_radius))

		# Sides
		surf_tool.add_vertex(Vector3(x1, sin(a1) * axle_radius, cos(a1) * axle_radius))
		surf_tool.add_vertex(Vector3(x2, sin(a1) * axle_radius, cos(a1) * axle_radius))
		surf_tool.add_vertex(Vector3(x2, sin(a2) * axle_radius, cos(a2) * axle_radius))

		surf_tool.add_vertex(Vector3(x1, sin(a1) * axle_radius, cos(a1) * axle_radius))
		surf_tool.add_vertex(Vector3(x2, sin(a2) * axle_radius, cos(a2) * axle_radius))
		surf_tool.add_vertex(Vector3(x1, sin(a2) * axle_radius, cos(a2) * axle_radius))

	# Paddles (8 paddles around the axle)
	var paddle_count := 8
	var paddle_radius := 1.2
	var paddle_width := 0.1
	var paddle_depth := 0.5
	for i in range(paddle_count):
		var angle := float(i) / paddle_count * TAU
		var dir := Vector3(0, sin(angle), cos(angle))
		var tangent := Vector3(0, cos(angle), -sin(angle))

		var center := dir * (axle_radius + paddle_depth * 0.5)

		var corners := [
			Vector3(-axle_length * 0.5, 0, 0) + dir * axle_radius - tangent * (paddle_width * 0.5),
			Vector3(-axle_length * 0.5, 0, 0) + dir * axle_radius + tangent * (paddle_width * 0.5),
			Vector3(-axle_length * 0.5, 0, 0) + dir * (axle_radius + paddle_depth) + tangent * (paddle_width * 0.5),
			Vector3(-axle_length * 0.5, 0, 0) + dir * (axle_radius + paddle_depth) - tangent * (paddle_width * 0.5),
			Vector3(axle_length * 0.5, 0, 0) + dir * axle_radius - tangent * (paddle_width * 0.5),
			Vector3(axle_length * 0.5, 0, 0) + dir * axle_radius + tangent * (paddle_width * 0.5),
			Vector3(axle_length * 0.5, 0, 0) + dir * (axle_radius + paddle_depth) + tangent * (paddle_width * 0.5),
			Vector3(axle_length * 0.5, 0, 0) + dir * (axle_radius + paddle_depth) - tangent * (paddle_width * 0.5),
		]

		# Front face
		surf_tool.add_vertex(corners[0])
		surf_tool.add_vertex(corners[1])
		surf_tool.add_vertex(corners[2])
		surf_tool.add_vertex(corners[0])
		surf_tool.add_vertex(corners[2])
		surf_tool.add_vertex(corners[3])

		# Back face
		surf_tool.add_vertex(corners[4])
		surf_tool.add_vertex(corners[6])
		surf_tool.add_vertex(corners[5])
		surf_tool.add_vertex(corners[4])
		surf_tool.add_vertex(corners[7])
		surf_tool.add_vertex(corners[6])

		# Side faces
		surf_tool.add_vertex(corners[0])
		surf_tool.add_vertex(corners[3])
		surf_tool.add_vertex(corners[7])
		surf_tool.add_vertex(corners[0])
		surf_tool.add_vertex(corners[7])
		surf_tool.add_vertex(corners[4])

		surf_tool.add_vertex(corners[1])
		surf_tool.add_vertex(corners[5])
		surf_tool.add_vertex(corners[6])
		surf_tool.add_vertex(corners[1])
		surf_tool.add_vertex(corners[6])
		surf_tool.add_vertex(corners[2])

		surf_tool.add_vertex(corners[0])
		surf_tool.add_vertex(corners[4])
		surf_tool.add_vertex(corners[5])
		surf_tool.add_vertex(corners[0])
		surf_tool.add_vertex(corners[5])
		surf_tool.add_vertex(corners[1])

		surf_tool.add_vertex(corners[3])
		surf_tool.add_vertex(corners[2])
		surf_tool.add_vertex(corners[6])
		surf_tool.add_vertex(corners[3])
		surf_tool.add_vertex(corners[6])
		surf_tool.add_vertex(corners[7])

	var mesh := ArrayMesh.new()
	surf_tool.commit(mesh)
	_mesh.mesh = mesh
	_mesh.material_override = mat


func setup(network: MECHANICAL_NETWORK, world_coord: Vector3i) -> void:
	_network = network
	_world_coord = world_coord
	_node.world_coord = world_coord
	_network.add_node(_node)
	_network.refresh_connectivity()
	_network.solve()
	_check_water_adjacency()


func _process(delta: float) -> void:
	if _is_active:
		_rotation_angle += base_rpm / 60.0 * TAU * delta
		_mesh.rotation = Vector3(_rotation_angle, 0, 0)

	_water_check_timer -= delta
	if _water_check_timer <= 0.0:
		_water_check_timer = WATER_CHECK_INTERVAL
		_check_water_adjacency()


func _check_water_adjacency() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var chunk_manager := get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager == null:
		return

	var has_water := false
	for face_index in range(MECHANICAL_NODE.FACE_DIRECTIONS.size()):
		var neighbor: Vector3i = _world_coord + MECHANICAL_NODE.FACE_DIRECTIONS[face_index]
		var block_id: int = chunk_manager.get_block_world(neighbor)
		if block_id == BLOCK_WATER:
			has_water = true
			break

	if has_water != _is_active:
		_is_active = has_water
		_node.base_rpm = base_rpm if _is_active else 0.0
		_network.solve()
		su_changed.emit(_node.network_su)


func get_mechanical_node() -> MECHANICAL_NODE:
	return _node


func on_break() -> void:
	if _network != null:
		_network.remove_node_at(_world_coord)
		_network.refresh_connectivity()
		_network.solve()
	queue_free()


func get_su() -> float:
	return _node.network_su


func is_overstressed() -> bool:
	return _node.overstressed