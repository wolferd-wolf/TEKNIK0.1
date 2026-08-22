#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <unordered_map>
#include <vector>

using namespace godot;

class TeknikVoxelMesher : public RefCounted {
	GDCLASS(TeknikVoxelMesher, RefCounted);

	static constexpr int BLOCK_AIR = 0;
	static constexpr int BLOCK_GRASS = 1;
	static constexpr int BLOCK_DIRT = 2;
	static constexpr int BLOCK_STONE = 3;
	static constexpr int BLOCK_SAND = 4;
	static constexpr int BLOCK_LOG = 5;
	static constexpr int BLOCK_LEAVES = 6;
	static constexpr int BLOCK_COAL_ORE = 10;
	static constexpr int BLOCK_IRON_ORE = 11;
	static constexpr int BLOCK_COPPER_ORE = 12;
	static constexpr int BLOCK_FURNACE = 13;
	static constexpr int BLOCK_IRON_INGOT = 14;
	static constexpr int BLOCK_COPPER_INGOT = 15;
	static constexpr int BLOCK_COAL = 16;
	static constexpr int BLOCK_GLASS = 17;
	static constexpr int BLOCK_CHARCOAL = 18;
	static constexpr int BLOCK_CRAFTING_TABLE = 19;
	static constexpr int BLOCK_CHEST = 20;
	static constexpr int WORLD_SEED = 734921;
	static constexpr int TREE_SPACING = 7;
	static constexpr int TREE_OFFSET = 3;
	static constexpr int FOREST_TREE_SPACING = 5;
	static constexpr int FOREST_TREE_OFFSET = 1;
	static constexpr int TREE_TRUNK_HEIGHT = 4;
	static constexpr int BIOME_PLAINS = 0;
	static constexpr int BIOME_FOREST = 1;
	static constexpr int BIOME_DESERT = 2;
	static constexpr int BIOME_ROCKY = 3;
	static constexpr int MAX_SKY_LIGHT = 15;
	static constexpr double MIN_SKY_BRIGHTNESS = 0.35;

	static int posmod_i(int value, int modulus) {
		const int remainder = value % modulus;
		return remainder < 0 ? remainder + modulus : remainder;
	}

	static int volume_index(int x, int y, int z, int width, int world_height) {
		return (z * width + x) * world_height + y;
	}

	static int biome_at_cache(int cache_x, int cache_z, const uint8_t *biomes, int biome_count, int width) {
		if (biome_count != width * width || cache_x < 0 || cache_x >= width || cache_z < 0 || cache_z >= width) {
			return BIOME_PLAINS;
		}
		return static_cast<int>(biomes[cache_z * width + cache_x]);
	}

	static bool is_tree_origin(int x, int z, int surface, int world_height, int sea_level, int biome) {
		if (biome == BIOME_DESERT || biome == BIOME_ROCKY) {
			return false;
		}
		if (surface <= sea_level + 1 || surface + TREE_TRUNK_HEIGHT + 1 >= world_height) {
			return false;
		}
		const bool baseline_grid = posmod_i(x, TREE_SPACING) == TREE_OFFSET && posmod_i(z, TREE_SPACING) == TREE_OFFSET;
		const bool forest_grid = biome == BIOME_FOREST
			&& posmod_i(x, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
			&& posmod_i(z, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET;
		if (!baseline_grid && !forest_grid) {
			return false;
		}
		const int64_t mixed = (static_cast<int64_t>(x) * 73856093LL)
			^ (static_cast<int64_t>(z) * 19349663LL)
			^ static_cast<int64_t>(WORLD_SEED);
		const int64_t hash_value = std::llabs(mixed);
		if (forest_grid && !baseline_grid) {
			return hash_value % 3 != 0;
		}
		return hash_value % 4 != 0;
	}

	static int terrain_block(int y, int height, int sea_level, int biome) {
		if (y == height) {
			if (height <= sea_level + 1 || biome == BIOME_DESERT) {
				return BLOCK_SAND;
			}
			if (biome == BIOME_ROCKY) {
				return BLOCK_STONE;
			}
			return BLOCK_GRASS;
		}
		if (y >= height - 3) {
			if (height <= sea_level + 1 || biome == BIOME_DESERT) {
				return BLOCK_SAND;
			}
			if (biome == BIOME_ROCKY) {
				return BLOCK_STONE;
			}
			return BLOCK_DIRT;
		}
		return BLOCK_STONE;
	}

	static int generated_tree_block(
		int cell_x,
		int cell_y,
		int cell_z,
		int origin_x,
		int origin_z,
		const int32_t *heights,
		const uint8_t *tree_origins,
		int width,
		int padding) {
		for (int tree_z = cell_z - 1; tree_z <= cell_z + 1; ++tree_z) {
			for (int tree_x = cell_x - 1; tree_x <= cell_x + 1; ++tree_x) {
				const int cache_x = tree_x - origin_x + padding;
				const int cache_z = tree_z - origin_z + padding;
				if (cache_x < 0 || cache_x >= width || cache_z < 0 || cache_z >= width) {
					continue;
				}
				const int column_index = cache_z * width + cache_x;
				if (tree_origins[column_index] == 0) {
					continue;
				}
				const int surface = heights[column_index];
				const int trunk_top = surface + TREE_TRUNK_HEIGHT;
				if (cell_x == tree_x && cell_z == tree_z && cell_y > surface && cell_y <= trunk_top) {
					return BLOCK_LOG;
				}
				if (cell_y >= trunk_top - 1 && cell_y <= trunk_top + 1) {
					return BLOCK_LEAVES;
				}
			}
		}
		return BLOCK_AIR;
	}

	static int block_at(const uint8_t *blocks, int x, int y, int z, int width, int world_height) {
		if (y < 0) {
			return BLOCK_STONE;
		}
		if (y >= world_height) {
			return BLOCK_AIR;
		}
		if (x < 0 || x >= width || z < 0 || z >= width) {
			return BLOCK_AIR;
		}
		return static_cast<int>(blocks[volume_index(x, y, z, width, world_height)]);
	}

	static int sky_at(const uint8_t *sky, int x, int y, int z, int width, int world_height) {
		if (y >= world_height) {
			return MAX_SKY_LIGHT;
		}
		if (y < 0) {
			return 0;
		}
		if (x < 0 || x >= width || z < 0 || z >= width) {
			return MAX_SKY_LIGHT;
		}
		return static_cast<int>(sky[volume_index(x, y, z, width, world_height)]);
	}

	static void axis_direction(int axis, bool positive, int &dx, int &dy, int &dz) {
		dx = 0;
		dy = 0;
		dz = 0;
		const int amount = positive ? 1 : -1;
		if (axis == 0) {
			dx = amount;
		} else if (axis == 1) {
			dy = amount;
		} else {
			dz = amount;
		}
	}

	static double ao_brightness(int level) {
		switch (level) {
			case 0: return 0.55;
			case 1: return 0.70;
			case 2: return 0.85;
			default: return 1.0;
		}
	}

	static double face_shade(int face_index) {
		if (face_index == 0) return 1.0;
		if (face_index == 1) return 0.5;
		if (face_index == 2 || face_index == 3) return 0.6;
		return 0.8;
	}

	static Color block_color(int block, int world_x, int y, int world_z, int face_index, double light_factor) {
		Color base;
		switch (block) {
			case BLOCK_GRASS:
				base = face_index == 0 ? Color(0.34, 0.68, 0.25) : Color(0.38, 0.48, 0.23);
				break;
			case BLOCK_DIRT: base = Color(0.50, 0.34, 0.20); break;
			case BLOCK_STONE: base = Color(0.56, 0.58, 0.60); break;
			case BLOCK_SAND: base = Color(0.82, 0.75, 0.54); break;
			case BLOCK_LOG: base = Color(0.48, 0.30, 0.14); break;
			case BLOCK_LEAVES: base = Color(0.22, 0.52, 0.18); break;
			case BLOCK_COAL_ORE: base = Color(0.30, 0.30, 0.32); break;
			case BLOCK_IRON_ORE: base = Color(0.72, 0.58, 0.45); break;
			case BLOCK_COPPER_ORE: base = Color(0.44, 0.72, 0.60); break;
			case BLOCK_FURNACE: base = Color(0.38, 0.34, 0.31); break;
			case BLOCK_IRON_INGOT: base = Color(0.78, 0.78, 0.80); break;
			case BLOCK_COPPER_INGOT: base = Color(0.80, 0.48, 0.26); break;
			case BLOCK_COAL: base = Color(0.12, 0.12, 0.13); break;
			case BLOCK_GLASS: base = Color(0.78, 0.88, 0.92); break;
			case BLOCK_CHARCOAL: base = Color(0.20, 0.19, 0.18); break;
			case BLOCK_CRAFTING_TABLE: base = Color(0.58, 0.42, 0.24); break;
			case BLOCK_CHEST: base = Color(0.45, 0.31, 0.16); break;
			default: base = Color(1.0, 1.0, 1.0); break;
		}
		const int64_t mixed = (static_cast<int64_t>(world_x) * 73856093LL)
			^ (static_cast<int64_t>(y) * 83492791LL)
			^ (static_cast<int64_t>(world_z) * 19349663LL);
		const int64_t hash_value = std::llabs(mixed);
		const double variation = 0.97 + static_cast<double>(hash_value % 7) * 0.01;
		const double factor = light_factor * variation;
		return Color(
			std::clamp(static_cast<double>(base.r) * factor, 0.0, 1.0),
			std::clamp(static_cast<double>(base.g) * factor, 0.0, 1.0),
			std::clamp(static_cast<double>(base.b) * factor, 0.0, 1.0),
			1.0);
	}

protected:
	static void _bind_methods() {
		ClassDB::bind_method(
			D_METHOD("build", "coord", "heights", "overrides", "chunk_size", "world_height", "sea_level", "biomes"),
			&TeknikVoxelMesher::build);
	}

public:
	Dictionary build(
		Vector2i coord,
		PackedInt32Array heights,
		Dictionary overrides,
		int64_t chunk_size_value,
		int64_t world_height_value,
		int64_t sea_level_value,
		PackedByteArray biomes) const {
		const int chunk_size = std::max(1, static_cast<int>(chunk_size_value));
		const int world_height = std::max(1, static_cast<int>(world_height_value));
		const int sea_level = static_cast<int>(sea_level_value);
		const int height_count = heights.size();
		int cache_width = static_cast<int>(std::lround(std::sqrt(static_cast<double>(height_count))));
		if (cache_width * cache_width != height_count) {
			cache_width = chunk_size + 2;
		}
		const int cache_padding = std::max(static_cast<int>(std::floor(static_cast<double>(cache_width - chunk_size) * 0.5)), 1);
		const int origin_x = coord.x * chunk_size;
		const int origin_z = coord.y * chunk_size;
		const int volume_size = cache_width * cache_width * world_height;

		const int32_t *height_ptr = heights.ptr();
		const uint8_t *biome_ptr = biomes.ptr();
		const int biome_count = biomes.size();

		std::unordered_map<int, uint8_t> local_overrides;
		local_overrides.reserve(static_cast<size_t>(overrides.size()));
		const Array override_keys = overrides.keys();
		for (int i = 0; i < override_keys.size(); ++i) {
			const Variant key_variant = override_keys[i];
			const String key = key_variant;
			const PackedStringArray parts = key.split(",");
			if (parts.size() != 3) {
				continue;
			}
			const int wx = static_cast<int>(parts[0].to_int());
			const int y = static_cast<int>(parts[1].to_int());
			const int wz = static_cast<int>(parts[2].to_int());
			if (y < 0 || y >= world_height) {
				continue;
			}
			const int cx = wx - origin_x + cache_padding;
			const int cz = wz - origin_z + cache_padding;
			if (cx < 0 || cx >= cache_width || cz < 0 || cz >= cache_width) {
				continue;
			}
			local_overrides[volume_index(cx, y, cz, cache_width, world_height)] =
				static_cast<uint8_t>(static_cast<int64_t>(overrides[key_variant]));
		}

		std::vector<uint8_t> tree_origins(static_cast<size_t>(cache_width * cache_width), 0);
		for (int cz = 0; cz < cache_width; ++cz) {
			for (int cx = 0; cx < cache_width; ++cx) {
				const int column = cz * cache_width + cx;
				const int biome = biome_at_cache(cx, cz, biome_ptr, biome_count, cache_width);
				const int wx = origin_x + cx - cache_padding;
				const int wz = origin_z + cz - cache_padding;
				tree_origins[column] = is_tree_origin(wx, wz, height_ptr[column], world_height, sea_level, biome) ? 1 : 0;
			}
		}

		std::vector<uint8_t> blocks(static_cast<size_t>(volume_size), 0);
		for (int cz = 0; cz < cache_width; ++cz) {
			for (int cx = 0; cx < cache_width; ++cx) {
				const int column = cz * cache_width + cx;
				const int height = height_ptr[column];
				const int biome = biome_at_cache(cx, cz, biome_ptr, biome_count, cache_width);
				const int wx = origin_x + cx - cache_padding;
				const int wz = origin_z + cz - cache_padding;
				for (int y = 0; y < world_height; ++y) {
					const int index = volume_index(cx, y, cz, cache_width, world_height);
					const auto override_it = local_overrides.find(index);
					if (override_it != local_overrides.end()) {
						blocks[index] = override_it->second;
					} else if (y <= height) {
						blocks[index] = static_cast<uint8_t>(terrain_block(y, height, sea_level, biome));
					} else {
						blocks[index] = static_cast<uint8_t>(generated_tree_block(
							wx, y, wz, origin_x, origin_z, height_ptr, tree_origins.data(), cache_width, cache_padding));
					}
				}
			}
		}

		std::vector<uint8_t> sky(static_cast<size_t>(volume_size), 0);
		for (int cz = 0; cz < cache_width; ++cz) {
			for (int cx = 0; cx < cache_width; ++cx) {
				int light_level = MAX_SKY_LIGHT;
				for (int y = world_height - 1; y >= 0; --y) {
					const int index = volume_index(cx, y, cz, cache_width, world_height);
					const int block = static_cast<int>(blocks[index]);
					if (block == BLOCK_LEAVES) {
						light_level = std::max(light_level - 1, 0);
					} else if (block != BLOCK_AIR) {
						light_level = 0;
					}
					sky[index] = static_cast<uint8_t>(light_level);
				}
			}
		}

		static constexpr int face_dirs[6][3] = {
			{0, 1, 0}, {0, -1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}
		};
		static constexpr double face_vertices[6][4][3] = {
			{{0,1,0},{0,1,1},{1,1,1},{1,1,0}},
			{{0,0,0},{1,0,0},{1,0,1},{0,0,1}},
			{{1,0,0},{1,1,0},{1,1,1},{1,0,1}},
			{{0,0,0},{0,0,1},{0,1,1},{0,1,0}},
			{{0,0,1},{1,0,1},{1,1,1},{0,1,1}},
			{{0,0,0},{0,1,0},{1,1,0},{1,0,0}}
		};
		static constexpr double face_normals[6][3] = {
			{0,1,0},{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}
		};
		static constexpr int tangent_axes[6][2] = {
			{0,2},{0,2},{1,2},{1,2},{0,1},{0,1}
		};

		std::vector<Vector3> out_vertices;
		std::vector<Vector3> out_normals;
		std::vector<Color> out_colors;
		std::vector<int32_t> out_indices;
		out_vertices.reserve(static_cast<size_t>(chunk_size * chunk_size * 12));
		out_normals.reserve(out_vertices.capacity());
		out_colors.reserve(out_vertices.capacity());
		out_indices.reserve(static_cast<size_t>(chunk_size * chunk_size * 18));
		int face_count = 0;

		for (int local_z = 0; local_z < chunk_size; ++local_z) {
			const int center_z = local_z + cache_padding;
			const int world_z = origin_z + local_z;
			for (int local_x = 0; local_x < chunk_size; ++local_x) {
				const int center_x = local_x + cache_padding;
				const int world_x = origin_x + local_x;
				for (int y = 0; y < world_height; ++y) {
					const int block = block_at(blocks.data(), center_x, y, center_z, cache_width, world_height);
					if (block == BLOCK_AIR) {
						continue;
					}
					for (int face = 0; face < 6; ++face) {
						const int nx = center_x + face_dirs[face][0];
						const int ny = y + face_dirs[face][1];
						const int nz = center_z + face_dirs[face][2];
						if (block_at(blocks.data(), nx, ny, nz, cache_width, world_height) != BLOCK_AIR) {
							continue;
						}

						const int32_t base_index = static_cast<int32_t>(out_vertices.size());
						int ao[4] = {0, 0, 0, 0};
						for (int vertex_index = 0; vertex_index < 4; ++vertex_index) {
							const double *vertex = face_vertices[face][vertex_index];
							const int axis_a = tangent_axes[face][0];
							const int axis_b = tangent_axes[face][1];
							const double component_a = vertex[axis_a];
							const double component_b = vertex[axis_b];
							int adx, ady, adz, bdx, bdy, bdz;
							axis_direction(axis_a, component_a > 0.5, adx, ady, adz);
							axis_direction(axis_b, component_b > 0.5, bdx, bdy, bdz);
							const int sx = center_x + face_dirs[face][0];
							const int sy = y + face_dirs[face][1];
							const int sz = center_z + face_dirs[face][2];

							const bool side_a = block_at(blocks.data(), sx + adx, sy + ady, sz + adz, cache_width, world_height) != BLOCK_AIR;
							const bool side_b = block_at(blocks.data(), sx + bdx, sy + bdy, sz + bdz, cache_width, world_height) != BLOCK_AIR;
							const bool corner = block_at(blocks.data(), sx + adx + bdx, sy + ady + bdy, sz + adz + bdz, cache_width, world_height) != BLOCK_AIR;
							ao[vertex_index] = side_a && side_b ? 0 : 3 - static_cast<int>(side_a) - static_cast<int>(side_b) - static_cast<int>(corner);

							int total_light = 0;
							total_light += sky_at(sky.data(), sx, sy, sz, cache_width, world_height);
							total_light += sky_at(sky.data(), sx + adx, sy + ady, sz + adz, cache_width, world_height);
							total_light += sky_at(sky.data(), sx + bdx, sy + bdy, sz + bdz, cache_width, world_height);
							total_light += sky_at(sky.data(), sx + adx + bdx, sy + ady + bdy, sz + adz + bdz, cache_width, world_height);
							const double normalized_light = static_cast<double>(total_light) / static_cast<double>(MAX_SKY_LIGHT * 4);
							const double sky_factor = MIN_SKY_BRIGHTNESS + (1.0 - MIN_SKY_BRIGHTNESS) * normalized_light;
							const double light_factor = face_shade(face) * ao_brightness(ao[vertex_index]) * sky_factor;

							out_vertices.emplace_back(
								static_cast<double>(local_x) + vertex[0],
								static_cast<double>(y) + vertex[1],
								static_cast<double>(local_z) + vertex[2]);
							out_normals.emplace_back(face_normals[face][0], face_normals[face][1], face_normals[face][2]);
							out_colors.emplace_back(block_color(block, world_x, y, world_z, face, light_factor));
						}

						if (ao[0] + ao[2] > ao[1] + ao[3]) {
							out_indices.push_back(base_index);
							out_indices.push_back(base_index + 3);
							out_indices.push_back(base_index + 1);
							out_indices.push_back(base_index + 1);
							out_indices.push_back(base_index + 3);
							out_indices.push_back(base_index + 2);
						} else {
							out_indices.push_back(base_index);
							out_indices.push_back(base_index + 2);
							out_indices.push_back(base_index + 1);
							out_indices.push_back(base_index);
							out_indices.push_back(base_index + 3);
							out_indices.push_back(base_index + 2);
						}
						++face_count;
					}
				}
			}
		}

		PackedVector3Array vertices;
		PackedVector3Array normals;
		PackedColorArray colors;
		PackedInt32Array indices;
		vertices.resize(static_cast<int>(out_vertices.size()));
		normals.resize(static_cast<int>(out_normals.size()));
		colors.resize(static_cast<int>(out_colors.size()));
		indices.resize(static_cast<int>(out_indices.size()));
		Vector3 *vertex_write = vertices.ptrw();
		Vector3 *normal_write = normals.ptrw();
		Color *color_write = colors.ptrw();
		int32_t *index_write = indices.ptrw();
		for (size_t i = 0; i < out_vertices.size(); ++i) vertex_write[i] = out_vertices[i];
		for (size_t i = 0; i < out_normals.size(); ++i) normal_write[i] = out_normals[i];
		for (size_t i = 0; i < out_colors.size(); ++i) color_write[i] = out_colors[i];
		for (size_t i = 0; i < out_indices.size(); ++i) index_write[i] = out_indices[i];

		Dictionary result;
		result["vertices"] = vertices;
		result["normals"] = normals;
		result["colors"] = colors;
		result["indices"] = indices;
		result["face_count"] = face_count;
		return result;
	}
};

inline void register_teknik_voxel_mesher() {
	GDREGISTER_CLASS(TeknikVoxelMesher);
}
