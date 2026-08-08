extends "res://scripts/world/reference/luanti_carpathian_fast_prototype.gd"

# Reference-only fast-surface adapter.
# Probe Y=12 is not an invented tuning value: the exact Luanti-reference study
# measured it against the full vertical Carpathian solver across three seeds.
# It produced mean absolute height error 0.2228 blocks and 97.4589% of sampled
# columns within one block of the exact surface.
const PROBE_Y := 12


func surface_height_probe12(x: int, z: int) -> int:
	var terms := _sample_static_terms(x, z)
	var mountain := _mountain_terms_at_y(x, z, PROBE_Y, terms).w
	var threshold := (BASE_LEVEL + mountain + 1.0) * 0.5
	return clampi(ceili(threshold) - 1, 0, REFERENCE_Y_MAX)


func surface_height_probe12_teknik(x: int, z: int) -> int:
	return clampi(surface_height_probe12(x, z), 3, TEKNIK_SAFE_TOP)
