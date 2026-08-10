extends Resource
class_name TextureBlockConfig

@export var block_type: String = ""
@export_enum("organic", "cellular", "directional", "concentric", "flat") var noise_mode: String = "organic"
@export_enum("generic", "air", "soil", "rock", "sand", "bark", "wood_end", "foliage", "grass_top", "grass_side", "ore") var top_style: String = "generic"
@export_enum("generic", "air", "soil", "rock", "sand", "bark", "wood_end", "foliage", "grass_top", "grass_side", "ore") var side_style: String = "generic"
@export_enum("generic", "air", "soil", "rock", "sand", "bark", "wood_end", "foliage", "grass_top", "grass_side", "ore") var bottom_style: String = "generic"
@export var palette: Array[Color] = []
@export var secondary_palette: Array[Color] = []
@export var accent_palette: Array[Color] = []
@export_range(0.01, 1.0, 0.01) var scale: float = 0.22
@export_range(0.0, 1.0, 0.01) var detail_density: float = 0.18
@export_range(0.0, 1.0, 0.01) var edge_irregularity: float = 0.45
@export var seed_offset: int = 0
@export var variant_offset: int = 0
@export_range(0.0, 1.0, 0.01) var accent_density: float = 0.08
@export_range(0.0, 1.0, 0.01) var vein_density: float = 0.0
@export_range(1, 8, 1) var vein_count: int = 2
@export_range(1, 3, 1) var vein_width: int = 1
