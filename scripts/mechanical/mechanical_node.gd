class_name MechanicalNode
extends RefCounted

## A single component in a rotational power network.
## Mirrors the SPEC.md SU model: Stress Units = Torque x Speed / 1000.
## Speed is expressed as RPM; torque is derived from the component's capacity.

enum NodeKind {
	SOURCE,      # generates rotation (water wheel, windmill, steam engine)
	SHAFT,       # transmits rotation between faces
	CONSUMER,    # uses rotation to do work (drill, saw, press)
}

enum Face {
	NEG_X,  # -X
	POS_X,  # +X
	NEG_Y,  # -Y
	POS_Y,  # +Y
	NEG_Z,  # -Z
	POS_Z,  # +Z
}

const FACE_DIRECTIONS := [
	Vector3i(-1, 0, 0),  # NEG_X
	Vector3i(1, 0, 0),   # POS_X
	Vector3i(0, -1, 0),  # NEG_Y
	Vector3i(0, 1, 0),   # POS_Y
	Vector3i(0, 0, -1),  # NEG_Z
	Vector3i(0, 0, 1),   # POS_Z
]

var kind: NodeKind = NodeKind.SHAFT
var world_coord: Vector3i = Vector3i.ZERO
var base_rpm: float = 0.0          # source RPM; 0 for shafts/consumers
var stress_capacity: float = 256.0 # max SU this node can pass / draw
var stress_cost: float = 0.0       # SU a consumer needs to run
var connected_faces: Array[bool] = [false, false, false, false, false, false]

var network_rpm: float = 0.0       # resolved by the owning network
var network_su: float = 0.0        # resolved by the owning network
var overstressed: bool = false     # resolved by the owning network

func _init(
	p_kind: NodeKind,
	p_coord: Vector3i,
	p_base_rpm: float = 0.0,
	p_stress_capacity: float = 256.0,
	p_stress_cost: float = 0.0
) -> void:
	kind = p_kind
	world_coord = p_coord
	base_rpm = p_base_rpm
	stress_capacity = p_stress_capacity
	stress_cost = p_stress_cost


func is_source() -> bool:
	return kind == NodeKind.SOURCE


func is_consumer() -> bool:
	return kind == NodeKind.CONSUMER


func face_direction(face_index: int) -> Vector3i:
	return FACE_DIRECTIONS[face_index]


func neighbor_coord(face_index: int) -> Vector3i:
	return world_coord + FACE_DIRECTIONS[face_index]


func connect_face(face_index: int) -> void:
	if face_index >= 0 and face_index < connected_faces.size():
		connected_faces[face_index] = true


func disconnect_face(face_index: int) -> void:
	if face_index >= 0 and face_index < connected_faces.size():
		connected_faces[face_index] = false


func is_face_connected(face_index: int) -> bool:
	if face_index < 0 or face_index >= connected_faces.size():
		return false
	return connected_faces[face_index]
