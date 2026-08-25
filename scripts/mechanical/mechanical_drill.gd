class_name MechanicalDrill
extends Node3D

## Mechanical Drill — a rotational power CONSUMER.
## Consumes 32 SU, mines a 3×3 area below it once per rotation tick (1 second at 1 RPM).

const BLOCK_MECHANICAL_DRILL := 9
const MECHANICAL_NODE := preload("res://scripts/mechanical/mechanical_node.gd")
const MECHANICAL_NETWORK := preload("res://scripts/mechanical/mechanical_network.gd")

signal su_changed(su: float)
signal mining_tick()

@export var stress_capacity: float = 64.0
@export var stress_cost: float = 32.0
@export var drill_radius: int = 1  # 3×3 area = radius 1
@export var mine_interval: float = 1.0  # seconds between mining operations at 1 RPM

var _mesh: MeshInstance3D
var _node: MECHANICAL_NODE
var _network: MECHANICAL_NETWORK
var _world_coord: Vector3i
var _rotation_angle: float = 0.0
var _drill_head: MeshInstance3D
var _mine_timer: float = 0.0
var _is_powered: bool = false


func _init() -> void:
	_node = MECHANICAL_NODE.new(
		MECHANICAL_NODE.NodeKind.CONSUMER,
		Vector3i.ZERO,
		0.0,
		stress_capacity,
		stress_cost
	)
	# Connect all faces by default (input from any side)
	for i in range(MECHANICAL_NODE.FACE_DIRECTIONS.size()):
		_node.connect_face(i)


func _ready() -> void:
	_build_visual()
	_rotation_angle = randf() * TAU


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)

	var surf_tool := SurfaceTool.new()
	surf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.35)  # dark steel
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Main body: box 1×1×1
	var half := 0.5
	var corners := [
		Vector3(-half, -half, -half),
		Vector3(-half,  half, -half),
		Vector3(-half,  half,  half),
		Vector3(-half, -half,  half),
		Vector3( half, -half, -half),
		Vector3( half,  half, -half),
		Vector3( half,  half,  half),
		Vector3( half, -half,  half),
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

	# Drill head (cone pointing down, on a separate MeshInstance3D for rotation)
	_drill_head = MeshInstance3D.new()
	_mesh.add_child(_drill_head)
	_drill_head.position = Vector3(0, -half, 0)

	var head_tool := SurfaceTool.new()
	head_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cone: 8 segments, height 0.8, base radius 0.4
	var cone_height := 0.8
	var cone_radius := 0.4
	var cone_segments := 8
	var tip := Vector3(0, -cone_height, 0)

	for i in range(cone_segments):
		var a1 := float(i) / cone_segments * TAU
		var a2 := float(i + 1) / cone_segments * TAU
		var v1 := Vector3(sin(a1) * cone_radius, 0, cos(a1) * cone_radius)
		var v2 := Vector3(sin(a2) * cone_radius, 0, cos(a2) * cone_radius)

		# Side face
		head_tool.add_vertex(v1)
		head_tool.add_vertex(tip)
		head_tool.add_vertex(v2)

		# Base face
		head_tool.add_vertex(Vector3(0, 0, 0))
		head_tool.add_vertex(v2)
		head_tool.add_vertex(v1)

	var head_mesh := ArrayMesh.new()
	head_tool.commit(head_mesh)
	_drill_head.mesh = head_mesh

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.2, 0.2, 0.25)  # darker steel
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drill_head.material_override = head_mat

	var body_mesh := ArrayMesh.new()
	surf_tool.commit(body_mesh)
	_mesh.mesh = body_mesh
	_mesh.material_override = mat


func setup(network: MECHANICAL_NETWORK, world_coord: Vector3i) -> void:
	_network = network
	_world_coord = world_coord
	_node.world_coord = world_coord
	_network.add_node(_node)
	_network.refresh_connectivity()
	_network.solve()


func _process(delta: float) -> void:
	var was_powered := _is_powered
	_is_powered = _node.network_su >= stress_cost - 0.001

	if _is_powered and _node.network_rpm > 0.0:
		_rotation_angle += _node.network_rpm / 60.0 * TAU * delta
		_drill_head.rotation = Vector3(_rotation_angle, 0, 0)

		# Mining tick at 1 Hz when powered and rotating
		_mine_timer -= delta
		if _mine_timer <= 0.0:
			_mine_timer = mine_interval
			_attempt_mine()
	else:
		# Reset timer when unpowered
		_mine_timer = mine_interval

	if _is_powered != was_powered:
		su_changed.emit(_node.network_su)


func _attempt_mine() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var chunk_manager := get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager == null:
		return

	# Mine 3×3 area below the drill (Y-1, Y-2, Y-3)
	var mined_any := false
	for dy in range(1, 4):
		for dx in range(-drill_radius, drill_radius + 1):
			for dz in range(-drill_radius, drill_radius + 1):
				var target := _world_coord + Vector3i(dx, -dy, dz)
				var block_id: int = chunk_manager.get_block_world(target)
				if block_id != 0 and block_id != 7:  # not air, not water
					if chunk_manager.mine_block_world(target):
						# Add to player inventory (find nearby player)
						var player := get_tree().get_first_node_in_group("player")
						if player != null and player.has_method("get_inventory"):
							var inventory: BlockInventory = player.get_inventory() as BlockInventory
							if inventory != null:
								inventory.add_item(block_id, 1)
						mined_any = true

	if mined_any:
		mining_tick.emit()


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