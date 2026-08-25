class_name Shaft
extends Node3D

## Shaft — a rotational power TRANSMISSION.
## Transmits SU between connected faces (6-way). Rotates visually.

const BLOCK_SHAFT := 8
const MECHANICAL_NODE := preload("res://scripts/mechanical/mechanical_node.gd")
const MECHANICAL_NETWORK := preload("res://scripts/mechanical/mechanical_network.gd")

signal su_changed(su: float)

@export var stress_capacity: float = 256.0

var _mesh: MeshInstance3D
var _node: MECHANICAL_NODE
var _network: MECHANICAL_NETWORK
var _world_coord: Vector3i
var _rotation_angle: float = 0.0


func _init() -> void:
	_node = MECHANICAL_NODE.new(
		MECHANICAL_NODE.NodeKind.SHAFT,
		Vector3i.ZERO,
		0.0,
		stress_capacity,
		0.0
	)
	# Connect all faces by default
	for i in range(MECHANICAL_NODE.FACE_DIRECTIONS.size()):
		_node.connect_face(i)


func _ready() -> void:
	_build_visual()
	_rotation_angle = randf() * TAU


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)

	# Create shaft mesh: square rod with rotation marker along X axis
	var surf_tool := SurfaceTool.new()
	surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)  # iron color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var size := 0.3
	var length := 1.0
	var half_l := length * 0.5

	# Main shaft box
	var corners := [
		Vector3(-half_l, -size, -size),  # 0
		Vector3(-half_l,  size, -size),  # 1
		Vector3(-half_l,  size,  size),  # 2
		Vector3(-half_l, -size,  size),  # 3
		Vector3( half_l, -size, -size),  # 4
		Vector3( half_l,  size, -size),  # 5
		Vector3( half_l,  size,  size),  # 6
		Vector3( half_l, -size,  size),  # 7
	]

	var faces := [
		[0, 1, 2, 0, 2, 3],  # -X
		[4, 7, 6, 4, 6, 5],  # +X
		[0, 3, 7, 0, 7, 4],  # -Y
		[1, 5, 6, 1, 6, 2],  # +Y
		[3, 2, 6, 3, 6, 7],  # +Z
		[0, 4, 5, 0, 5, 1],  # -Z
	]

	for face in faces:
		surf_tool.add_vertex(corners[face[0]])
		surf_tool.add_vertex(corners[face[1]])
		surf_tool.add_vertex(corners[face[2]])
		surf_tool.add_vertex(corners[face[0]])
		surf_tool.add_vertex(corners[face[2]])
		surf_tool.add_vertex(corners[face[3]])

	# Rotation marker (a thin fin on +Y face)
	var marker_size := 0.05
	var marker_half_l := length * 0.5 - 0.05
	var marker_corners := [
		Vector3(-marker_half_l, size, -marker_size),
		Vector3(-marker_half_l, size,  marker_size),
		Vector3( marker_half_l, size,  marker_size),
		Vector3( marker_half_l, size, -marker_size),
	]
	# Both sides
	surf_tool.add_vertex(marker_corners[0])
	surf_tool.add_vertex(marker_corners[1])
	surf_tool.add_vertex(marker_corners[2])
	surf_tool.add_vertex(marker_corners[0])
	surf_tool.add_vertex(marker_corners[2])
	surf_tool.add_vertex(marker_corners[3])

	surf_tool.add_vertex(marker_corners[3])
	surf_tool.add_vertex(marker_corners[2])
	surf_tool.add_vertex(marker_corners[1])
	surf_tool.add_vertex(marker_corners[3])
	surf_tool.add_vertex(marker_corners[1])
	surf_tool.add_vertex(marker_corners[0])

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


func _process(delta: float) -> void:
	if _node.network_rpm > 0.0:
		_rotation_angle += _node.network_rpm / 60.0 * TAU * delta
		_mesh.rotation = Vector3(_rotation_angle, 0, 0)


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