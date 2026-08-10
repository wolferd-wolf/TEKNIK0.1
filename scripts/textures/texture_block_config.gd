extends Resource
class_name TextureBlockConfig

@export var block_type: String = ""
@export_enum("organic", "cellular") var noise_mode: String = "organic"
@export_enum("generic", "grass", "soil", "rock", "sand", "wood_grain", "foliage") var material_style: String = "generic"
@export var palette: Array[Color] = []
@export_range(0.01, 1.0, 0.01) var frequency: float = 0.2
@export var seed_offset: int = 0
@export_range(0.0, 1.0, 0.01) var detail_density: float = 0.18
@export_range(0.01, 1.0, 0.01) var detail_frequency: float = 0.35
@export_enum("none", "speckle", "vein") var overlay_mode: String = "none"
@export var overlay_palette: Array[Color] = []
@export_range(0.0, 1.0, 0.005) var overlay_density: float = 0.0
@export var overlay_seed_offset: int = 0
@export_range(1, 8, 1) var overlay_cluster_count: int = 3
@export_range(2, 16, 1) var overlay_vein_length: int = 8
@export_range(1, 3, 1) var overlay_vein_width: int = 1
