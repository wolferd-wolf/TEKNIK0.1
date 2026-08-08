// SPDX-License-Identifier: LGPL-2.1-or-later
//
// TEKNIK native Carpathian terrain sampler.
// Reference algorithm: Luanti 5.16.1 MapgenCarpathian.
// Reference noise semantics: Luanti 5.16.1 noise.cpp/noise.h.
//
// This library intentionally implements terrain-height sampling only. It does
// not copy Luanti's biome, cave, decoration, lighting, liquid, or voxel-node
// systems. The vertical Carpathian density loop is replaced by a single
// Y=12 mountain-variation probe; TEKNIK's exact-reference study measured this
// shortcut at mean absolute surface-height error 0.2228 blocks with 97.4589%
// of sampled columns within one block of the full vertical solver.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>

using namespace godot;

namespace {

constexpr float BASE_LEVEL = 12.0f;
constexpr int PROBE_Y = 12;
constexpr uint32_t NOISE_MAGIC_X = 1619U;
constexpr uint32_t NOISE_MAGIC_Y = 31337U;
constexpr uint32_t NOISE_MAGIC_Z = 52591U;
constexpr uint32_t NOISE_MAGIC_SEED = 1013U;

struct NoiseParams {
	float offset;
	float scale;
	float spread;
	int32_t seed;
	int octaves;
	float persist;
	float lacunarity;
	bool eased_2d;
};

constexpr NoiseParams NP_HEIGHT1       {0.0f,  5.0f,  251.0f,  9613, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_HEIGHT2       {0.0f,  5.0f,  383.0f,  1949, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_HEIGHT3       {0.0f,  5.0f,  509.0f,  3211, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_HEIGHT4       {0.0f,  5.0f,  631.0f,  1583, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_HILLS_TERRAIN {1.0f,  1.0f, 1301.0f,  1692, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_RIDGE_TERRAIN {1.0f,  1.0f, 1889.0f,  3568, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_STEP_TERRAIN  {1.0f,  1.0f, 1889.0f,  4157, 5, 0.50f, 2.0f, true};
constexpr NoiseParams NP_HILLS         {0.0f,  3.0f,  257.0f,  6604, 6, 0.50f, 2.0f, true};
constexpr NoiseParams NP_RIDGE_MNT     {0.0f, 12.0f,  743.0f,  5520, 6, 0.70f, 2.0f, true};
constexpr NoiseParams NP_STEP_MNT      {0.0f,  8.0f,  509.0f,  2590, 6, 0.60f, 2.0f, true};
constexpr NoiseParams NP_MNT_VAR       {0.0f,  1.0f,  499.0f,  2490, 5, 0.55f, 2.0f, false};

inline int myfloor(float x) {
	return x < 0.0f ? static_cast<int>(x) - 1 : static_cast<int>(x);
}

inline float ease_curve(float t) {
	return t * t * t * (t * (6.0f * t - 15.0f) + 10.0f);
}

inline float lerp_value(float a, float b, float t) {
	return a + (b - a) * t;
}

inline float noise2d(int x, int y, int32_t seed) {
	uint32_t n = (NOISE_MAGIC_X * static_cast<uint32_t>(x)
		+ NOISE_MAGIC_Y * static_cast<uint32_t>(y)
		+ NOISE_MAGIC_SEED * static_cast<uint32_t>(seed)) & 0x7fffffffU;
	n = (n >> 13U) ^ n;
	n = (n * (n * n * 60493U + 19990303U) + 1376312589U) & 0x7fffffffU;
	return 1.0f - static_cast<float>(static_cast<int32_t>(n)) / 1073741824.0f;
}

inline float noise3d(int x, int y, int z, int32_t seed) {
	uint32_t n = (NOISE_MAGIC_X * static_cast<uint32_t>(x)
		+ NOISE_MAGIC_Y * static_cast<uint32_t>(y)
		+ NOISE_MAGIC_Z * static_cast<uint32_t>(z)
		+ NOISE_MAGIC_SEED * static_cast<uint32_t>(seed)) & 0x7fffffffU;
	n = (n >> 13U) ^ n;
	n = (n * (n * n * 60493U + 19990303U) + 1376312589U) & 0x7fffffffU;
	return 1.0f - static_cast<float>(static_cast<int32_t>(n)) / 1073741824.0f;
}

inline float value_noise_2d(float x, float z, int32_t seed, bool eased) {
	const int x0 = myfloor(x);
	const int z0 = myfloor(z);
	float xl = x - static_cast<float>(x0);
	float zl = z - static_cast<float>(z0);
	if (eased) {
		xl = ease_curve(xl);
		zl = ease_curve(zl);
	}
	const float a = lerp_value(noise2d(x0, z0, seed), noise2d(x0 + 1, z0, seed), xl);
	const float b = lerp_value(noise2d(x0, z0 + 1, seed), noise2d(x0 + 1, z0 + 1, seed), xl);
	return lerp_value(a, b, zl);
}

inline float value_noise_3d(float x, float y, float z, int32_t seed, bool eased) {
	const int x0 = myfloor(x);
	const int y0 = myfloor(y);
	const int z0 = myfloor(z);
	float xl = x - static_cast<float>(x0);
	float yl = y - static_cast<float>(y0);
	float zl = z - static_cast<float>(z0);
	if (eased) {
		xl = ease_curve(xl);
		yl = ease_curve(yl);
		zl = ease_curve(zl);
	}
	const auto plane = [&](int zz) {
		const float a = lerp_value(noise3d(x0, y0, zz, seed), noise3d(x0 + 1, y0, zz, seed), xl);
		const float b = lerp_value(noise3d(x0, y0 + 1, zz, seed), noise3d(x0 + 1, y0 + 1, zz, seed), xl);
		return lerp_value(a, b, yl);
	};
	return lerp_value(plane(z0), plane(z0 + 1), zl);
}

inline float fractal2d(const NoiseParams &np, float x, float z, int32_t world_seed) {
	x /= np.spread;
	z /= np.spread;
	const int32_t seed = world_seed + np.seed;
	float sum = 0.0f;
	float frequency = 1.0f;
	float amplitude = 1.0f;
	for (int octave = 0; octave < np.octaves; ++octave) {
		sum += amplitude * value_noise_2d(x * frequency, z * frequency, seed + octave, np.eased_2d);
		frequency *= np.lacunarity;
		amplitude *= np.persist;
	}
	return np.offset + sum * np.scale;
}

inline float fractal3d(const NoiseParams &np, float x, float y, float z, int32_t world_seed) {
	x /= np.spread;
	y /= np.spread;
	z /= np.spread;
	const int32_t seed = world_seed + np.seed;
	float sum = 0.0f;
	float frequency = 1.0f;
	float amplitude = 1.0f;
	for (int octave = 0; octave < np.octaves; ++octave) {
		sum += amplitude * value_noise_3d(x * frequency, y * frequency, z * frequency, seed + octave, false);
		frequency *= np.lacunarity;
		amplitude *= np.persist;
	}
	return np.offset + sum * np.scale;
}

inline float steps_value(float noise) {
	constexpr float width = 0.5f;
	const float k = std::floor(noise / width);
	const float f = (noise - k * width) / width;
	const float s = std::min(2.0f * f, 1.0f);
	return (k + s) * width;
}

inline int surface_height_probe12(int x, int z, int32_t world_seed) {
	const float h1 = fractal2d(NP_HEIGHT1, x, z, world_seed);
	const float h2 = fractal2d(NP_HEIGHT2, x, z, world_seed);
	const float h3 = fractal2d(NP_HEIGHT3, x, z, world_seed);
	const float h4 = fractal2d(NP_HEIGHT4, x, z, world_seed);

	const float hter = std::fabs(fractal2d(NP_HILLS_TERRAIN, x, z, world_seed));
	const float nhills = fractal2d(NP_HILLS, x, z, world_seed);
	const float hill_mask = hter * hter * hter * nhills * nhills;

	const float rter = std::fabs(fractal2d(NP_RIDGE_TERRAIN, x, z, world_seed));
	const float nridge = fractal2d(NP_RIDGE_MNT, x, z, world_seed);
	const float ridge_mask = rter * rter * rter * (1.0f - std::fabs(nridge));

	const float ster = std::fabs(fractal2d(NP_STEP_TERRAIN, x, z, world_seed));
	const float nstep = fractal2d(NP_STEP_MNT, x, z, world_seed);
	const float step_mask = ster * ster * ster * steps_value(nstep);

	const float mv = fractal3d(NP_MNT_VAR, static_cast<float>(x), static_cast<float>(PROBE_Y), static_cast<float>(z), world_seed);
	const float hill1 = lerp_value(h1, h2, mv);
	const float hill2 = lerp_value(h3, h4, mv);
	const float hill3 = lerp_value(h3, h2, mv);
	const float hill4 = lerp_value(h1, h4, mv);
	const float hilliness = std::max(std::min(hill1, hill2), std::min(hill3, hill4));
	const float mountains = (hill_mask + ridge_mask + step_mask) * hilliness;

	const float threshold = (BASE_LEVEL + mountains + 1.0f) * 0.5f;
	return std::clamp(static_cast<int>(std::ceil(threshold)) - 1, 0, 255);
}

} // namespace

class TeknikCarpathianSampler : public RefCounted {
	GDCLASS(TeknikCarpathianSampler, RefCounted);

	int32_t world_seed = 734921;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("set_seed", "seed"), &TeknikCarpathianSampler::set_seed);
		ClassDB::bind_method(D_METHOD("get_seed"), &TeknikCarpathianSampler::get_seed);
		ClassDB::bind_method(D_METHOD("sample_height", "x", "z"), &TeknikCarpathianSampler::sample_height);
		ClassDB::bind_method(D_METHOD("generate_grid", "origin_x", "origin_z", "width", "depth", "step"), &TeknikCarpathianSampler::generate_grid, DEFVAL(1));
		ClassDB::bind_method(D_METHOD("generate_grid_shifted", "origin_x", "origin_z", "width", "depth", "step", "height_offset", "min_height", "max_height"), &TeknikCarpathianSampler::generate_grid_shifted);
		ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
	}

public:
	void set_seed(int64_t p_seed) {
		world_seed = static_cast<int32_t>(p_seed);
	}

	int64_t get_seed() const {
		return world_seed;
	}

	int64_t sample_height(int64_t x, int64_t z) const {
		return surface_height_probe12(static_cast<int>(x), static_cast<int>(z), world_seed);
	}

	PackedInt32Array generate_grid(int64_t origin_x, int64_t origin_z, int64_t width, int64_t depth, int64_t step) const {
		const int w = std::clamp(static_cast<int>(width), 1, 4096);
		const int d = std::clamp(static_cast<int>(depth), 1, 4096);
		const int spacing = std::clamp(static_cast<int>(step), 1, 4096);
		PackedInt32Array result;
		result.resize(w * d);
		int32_t *out = result.ptrw();
		for (int z = 0; z < d; ++z) {
			const int wz = static_cast<int>(origin_z) + z * spacing;
			for (int x = 0; x < w; ++x) {
				const int wx = static_cast<int>(origin_x) + x * spacing;
				out[z * w + x] = surface_height_probe12(wx, wz, world_seed);
			}
		}
		return result;
	}

	PackedInt32Array generate_grid_shifted(
		int64_t origin_x,
		int64_t origin_z,
		int64_t width,
		int64_t depth,
		int64_t step,
		int64_t height_offset,
		int64_t min_height,
		int64_t max_height) const {
		const int w = std::clamp(static_cast<int>(width), 1, 4096);
		const int d = std::clamp(static_cast<int>(depth), 1, 4096);
		const int spacing = std::clamp(static_cast<int>(step), 1, 4096);
		const int offset = static_cast<int>(height_offset);
		int min_h = static_cast<int>(min_height);
		int max_h = static_cast<int>(max_height);
		if (min_h > max_h) {
			std::swap(min_h, max_h);
		}
		PackedInt32Array result;
		result.resize(w * d);
		int32_t *out = result.ptrw();
		for (int z = 0; z < d; ++z) {
			const int wz = static_cast<int>(origin_z) + z * spacing;
			for (int x = 0; x < w; ++x) {
				const int wx = static_cast<int>(origin_x) + x * spacing;
				out[z * w + x] = std::clamp(
					surface_height_probe12(wx, wz, world_seed) + offset,
					min_h,
					max_h
				);
			}
		}
		return result;
	}
};

void initialize_teknik_carpathian(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(TeknikCarpathianSampler);
}

void uninitialize_teknik_carpathian(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT teknik_carpathian_library_init(
	GDExtensionInterfaceGetProcAddress p_get_proc_address,
	GDExtensionClassLibraryPtr p_library,
	GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_teknik_carpathian);
	init_obj.register_terminator(uninitialize_teknik_carpathian);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
