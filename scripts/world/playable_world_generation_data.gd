extends "res://scripts/world/playable_world_carpathian_data.gd"

# Stable public generation-data facade. Stage-specific historical implementations
# live in playable_world_stage{N}_*.gd files. The shipping facade adds the native
# Carpathian terrain adapter when that extension is present, with an exact Stage
# 13 fallback for normal historical/headless regression runs.
