extends "res://scripts/world/playable_world_stage11_water_biome_data.gd"

# Stage 13 diagnostic-only seed adapter. Shipping world generation remains fixed
# to WORLD_SEED; this subclass exists only so the statistical audit can exercise
# several deterministic seed variants without changing production behavior.
var audit_seed: int = WORLD_SEED


func configure_audit_seed(seed_value: int) -> void:
	audit_seed = seed_value
	continentalness_noise.seed = audit_seed
	terrain_shape_noise.seed = audit_seed ^ 0x5f3759df
	temperature_noise.seed = audit_seed ^ 0x68bc21eb
	moisture_noise.seed = audit_seed ^ 0x02e5be93
	biome_temperature_noise.seed = audit_seed ^ 0x68bc21eb
	biome_moisture_noise.seed = audit_seed ^ 0x02e5be93


func _stage3_hash01(lattice_x: int, lattice_z: int, salt: int) -> float:
	var value := (
		(lattice_x * 73856093)
		^ (lattice_z * 19349663)
		^ (audit_seed * 83492791)
		^ salt
	)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(posmod(value, STAGE3_HASH_MODULUS)) * STAGE3_HASH_RECIPROCAL


func _stage8_hash(x: int, z: int, salt: int = 0) -> int:
	var value: int = (x * 73856093) ^ (z * 19349663) ^ (audit_seed * 83492791) ^ salt
	value = (value ^ (value >> 13)) * 1274126177
	return value ^ (value >> 16)
