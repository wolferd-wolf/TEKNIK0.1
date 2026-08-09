// TEKNIK reference-only terrain study. Not linked into the game.
//
// Mathematical reference: Luanti 5.16.1 Carpathian mapgen
//   src/mapgen/mapgen_carpathian.cpp / .h
// Noise implementation reference: Luanti 5.16.1 src/noise.cpp / noise.h.
// The Luanti noise.cpp/noise.h implementation carries its own permissive BSD-style notice.
// Carpathian source is LGPL-2.1-or-later; this file is a small independent diagnostic
// translation of the published equations/default parameters and is not shipping game code.

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <queue>
#include <string>
#include <vector>

namespace {

constexpr int WORLD_HEIGHT = 150;
constexpr int WATER_LEVEL = 1;
constexpr float BASE_LEVEL = 12.0f;
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
    bool eased_2d = true;
};

// Luanti 5.16.1 Carpathian defaults.
constexpr NoiseParams NP_HEIGHT1       {0.0f,  5.0f,  251.0f,  9613, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_HEIGHT2       {0.0f,  5.0f,  383.0f,  1949, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_HEIGHT3       {0.0f,  5.0f,  509.0f,  3211, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_HEIGHT4       {0.0f,  5.0f,  631.0f,  1583, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_HILLS_TERRAIN {1.0f,  1.0f, 1301.0f,  1692, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_RIDGE_TERRAIN {1.0f,  1.0f, 1889.0f,  3568, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_STEP_TERRAIN  {1.0f,  1.0f, 1889.0f,  4157, 5, 0.50f, 2.0f};
constexpr NoiseParams NP_HILLS         {0.0f,  3.0f,  257.0f,  6604, 6, 0.50f, 2.0f};
constexpr NoiseParams NP_RIDGE_MNT     {0.0f, 12.0f,  743.0f,  5520, 6, 0.70f, 2.0f};
constexpr NoiseParams NP_STEP_MNT      {0.0f,  8.0f,  509.0f,  2590, 6, 0.60f, 2.0f};
constexpr NoiseParams NP_MNT_VAR       {0.0f,  1.0f,  499.0f,  2490, 5, 0.55f, 2.0f, false};

inline int myfloor(float x) {
    // Matches Luanti's historical macro exactly, including negative integers.
    return x < 0.0f ? static_cast<int>(x) - 1 : static_cast<int>(x);
}

inline float ease_curve(float t) {
    return t * t * t * (t * (6.0f * t - 15.0f) + 10.0f);
}

inline float lerp(float a, float b, float t) {
    return a + (b - a) * t;
}

float noise2d(int x, int y, int32_t seed) {
    uint32_t n = (NOISE_MAGIC_X * static_cast<uint32_t>(x)
        + NOISE_MAGIC_Y * static_cast<uint32_t>(y)
        + NOISE_MAGIC_SEED * static_cast<uint32_t>(seed)) & 0x7fffffffU;
    n = (n >> 13U) ^ n;
    n = (n * (n * n * 60493U + 19990303U) + 1376312589U) & 0x7fffffffU;
    return 1.0f - static_cast<float>(static_cast<int32_t>(n)) / 1073741824.0f;
}

float noise3d(int x, int y, int z, int32_t seed) {
    uint32_t n = (NOISE_MAGIC_X * static_cast<uint32_t>(x)
        + NOISE_MAGIC_Y * static_cast<uint32_t>(y)
        + NOISE_MAGIC_Z * static_cast<uint32_t>(z)
        + NOISE_MAGIC_SEED * static_cast<uint32_t>(seed)) & 0x7fffffffU;
    n = (n >> 13U) ^ n;
    n = (n * (n * n * 60493U + 19990303U) + 1376312589U) & 0x7fffffffU;
    return 1.0f - static_cast<float>(static_cast<int32_t>(n)) / 1073741824.0f;
}

float noise2d_value(float x, float y, int32_t seed, bool eased) {
    const int x0 = myfloor(x);
    const int y0 = myfloor(y);
    float xl = x - static_cast<float>(x0);
    float yl = y - static_cast<float>(y0);
    if (eased) {
        xl = ease_curve(xl);
        yl = ease_curve(yl);
    }
    const float u = lerp(noise2d(x0, y0, seed), noise2d(x0 + 1, y0, seed), xl);
    const float v = lerp(noise2d(x0, y0 + 1, seed), noise2d(x0 + 1, y0 + 1, seed), xl);
    return lerp(u, v, yl);
}

float noise3d_value(float x, float y, float z, int32_t seed, bool eased) {
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
    auto bi = [&](int zz) {
        const float u = lerp(noise3d(x0, y0, zz, seed), noise3d(x0 + 1, y0, zz, seed), xl);
        const float v = lerp(noise3d(x0, y0 + 1, zz, seed), noise3d(x0 + 1, y0 + 1, zz, seed), xl);
        return lerp(u, v, yl);
    };
    return lerp(bi(z0), bi(z0 + 1), zl);
}

float fractal2d(const NoiseParams &np, float x, float z, int32_t world_seed) {
    x /= np.spread;
    z /= np.spread;
    int32_t seed = world_seed + np.seed;
    float a = 0.0f;
    float f = 1.0f;
    float g = 1.0f;
    for (int i = 0; i < np.octaves; ++i) {
        a += g * noise2d_value(x * f, z * f, seed + i, np.eased_2d);
        f *= np.lacunarity;
        g *= np.persist;
    }
    return np.offset + a * np.scale;
}

float fractal3d(const NoiseParams &np, float x, float y, float z, int32_t world_seed) {
    x /= np.spread;
    y /= np.spread;
    z /= np.spread;
    int32_t seed = world_seed + np.seed;
    float a = 0.0f;
    float f = 1.0f;
    float g = 1.0f;
    for (int i = 0; i < np.octaves; ++i) {
        a += g * noise3d_value(x * f, y * f, z * f, seed + i, false);
        f *= np.lacunarity;
        g *= np.persist;
    }
    return np.offset + a * np.scale;
}

float steps(float noise) {
    constexpr float w = 0.5f;
    const float k = std::floor(noise / w);
    const float f = (noise - k * w) / w;
    const float s = std::min(2.0f * f, 1.0f);
    return (k + s) * w;
}

struct ColumnResult {
    int height = 0;
    float mountains = 0.0f;
    float hills = 0.0f;
    float ridges = 0.0f;
    float steps = 0.0f;
};

ColumnResult sample_column(int x, int z, int32_t world_seed) {
    const float height1 = fractal2d(NP_HEIGHT1, x, z, world_seed);
    const float height2 = fractal2d(NP_HEIGHT2, x, z, world_seed);
    const float height3 = fractal2d(NP_HEIGHT3, x, z, world_seed);
    const float height4 = fractal2d(NP_HEIGHT4, x, z, world_seed);

    const float hter = std::fabs(fractal2d(NP_HILLS_TERRAIN, x, z, world_seed));
    const float nhills = fractal2d(NP_HILLS, x, z, world_seed);
    const float hill_mask = hter * hter * hter * nhills * nhills;

    const float rter = std::fabs(fractal2d(NP_RIDGE_TERRAIN, x, z, world_seed));
    const float nridge = fractal2d(NP_RIDGE_MNT, x, z, world_seed);
    const float ridge_mask = rter * rter * rter * (1.0f - std::fabs(nridge));

    const float ster = std::fabs(fractal2d(NP_STEP_TERRAIN, x, z, world_seed));
    const float nstep = fractal2d(NP_STEP_MNT, x, z, world_seed);
    const float step_mask = ster * ster * ster * steps(nstep);

    ColumnResult out;
    out.height = 0;
    for (int y = 0; y < WORLD_HEIGHT; ++y) {
        const float mnt_var = fractal3d(NP_MNT_VAR, static_cast<float>(x), static_cast<float>(y), static_cast<float>(z), world_seed);
        const float hill1 = lerp(height1, height2, mnt_var);
        const float hill2 = lerp(height3, height4, mnt_var);
        const float hill3 = lerp(height3, height2, mnt_var);
        const float hill4 = lerp(height1, height4, mnt_var);
        const float hilliness = std::max(std::min(hill1, hill2), std::min(hill3, hill4));
        const float hills = hill_mask * hilliness;
        const float ridges = ridge_mask * hilliness;
        const float step_mountains = step_mask * hilliness;
        const float grad = (y < WATER_LEVEL)
            ? (1 - WATER_LEVEL) + (WATER_LEVEL - y) * 3.0f
            : 1.0f - static_cast<float>(y);
        const float surface_level = BASE_LEVEL + hills + ridges + step_mountains + grad;
        if (static_cast<float>(y) < surface_level) {
            out.height = y;
            out.hills = hills;
            out.ridges = ridges;
            out.steps = step_mountains;
            out.mountains = hills + ridges + step_mountains;
        }
    }
    return out;
}

struct AuditResult {
    int seed = 0;
    int grid = 0;
    int step = 0;
    int min_h = WORLD_HEIGHT;
    int max_h = 0;
    double mean_h = 0.0;
    int p05 = 0;
    int p50 = 0;
    int p95 = 0;
    double slope_le_1_pct = 0.0;
    double slope_le_2_pct = 0.0;
    double mountain_contrib_lt_1_pct = 0.0;
    size_t largest_low_relief_cells = 0;
    double largest_low_relief_area_blocks2 = 0.0;
    double largest_low_relief_equiv_width_blocks = 0.0;
    double elapsed_ms = 0.0;
};

void write_pgm(const std::filesystem::path &path, const std::vector<int> &heights, int grid, int min_h, int max_h) {
    std::ofstream out(path, std::ios::binary);
    out << "P5\n" << grid << " " << grid << "\n255\n";
    const float denom = static_cast<float>(std::max(1, max_h - min_h));
    for (int h : heights) {
        const uint8_t v = static_cast<uint8_t>(std::clamp((h - min_h) / denom * 255.0f, 0.0f, 255.0f));
        out.write(reinterpret_cast<const char *>(&v), 1);
    }
}

void write_relief_ppm(const std::filesystem::path &path, const std::vector<int> &heights,
                      const std::vector<float> &mountains, int grid) {
    std::ofstream out(path, std::ios::binary);
    out << "P6\n" << grid << " " << grid << "\n255\n";
    auto idx = [grid](int x, int z) { return z * grid + x; };
    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int i = idx(x, z);
            int slope = 0;
            if (x > 0) slope = std::max(slope, std::abs(heights[i] - heights[idx(x - 1, z)]));
            if (x + 1 < grid) slope = std::max(slope, std::abs(heights[i] - heights[idx(x + 1, z)]));
            if (z > 0) slope = std::max(slope, std::abs(heights[i] - heights[idx(x, z - 1)]));
            if (z + 1 < grid) slope = std::max(slope, std::abs(heights[i] - heights[idx(x, z + 1)]));
            uint8_t rgb[3];
            if (slope <= 1 && std::fabs(mountains[i]) < 1.0f) {
                rgb[0] = 70; rgb[1] = 165; rgb[2] = 80; // low-relief/open
            } else if (std::fabs(mountains[i]) >= 8.0f || slope >= 5) {
                rgb[0] = 185; rgb[1] = 185; rgb[2] = 185; // strong mountain
            } else {
                rgb[0] = 170; rgb[1] = 145; rgb[2] = 90; // transitional/hilly
            }
            out.write(reinterpret_cast<const char *>(rgb), 3);
        }
    }
}

AuditResult audit_seed(int seed, int grid, int step, const std::filesystem::path &outdir) {
    const auto started = std::chrono::steady_clock::now();
    const size_t count = static_cast<size_t>(grid) * static_cast<size_t>(grid);
    std::vector<int> heights(count);
    std::vector<float> mountains(count);
    const int half = grid / 2;
    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int wx = (x - half) * step;
            const int wz = (z - half) * step;
            const ColumnResult c = sample_column(wx, wz, seed);
            const size_t i = static_cast<size_t>(z) * grid + x;
            heights[i] = c.height;
            mountains[i] = c.mountains;
        }
    }

    AuditResult r;
    r.seed = seed;
    r.grid = grid;
    r.step = step;
    r.min_h = *std::min_element(heights.begin(), heights.end());
    r.max_h = *std::max_element(heights.begin(), heights.end());
    r.mean_h = std::accumulate(heights.begin(), heights.end(), 0.0) / static_cast<double>(count);
    std::vector<int> sorted = heights;
    std::sort(sorted.begin(), sorted.end());
    auto pct = [&](double p) { return sorted[static_cast<size_t>(p * static_cast<double>(sorted.size() - 1))]; };
    r.p05 = pct(0.05); r.p50 = pct(0.50); r.p95 = pct(0.95);

    auto index = [grid](int x, int z) { return z * grid + x; };
    std::vector<uint8_t> low(count, 0);
    size_t slope_le_1 = 0, slope_le_2 = 0, mountain_lt_1 = 0;
    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int i = index(x, z);
            int max_slope = 0;
            if (x > 0) max_slope = std::max(max_slope, std::abs(heights[i] - heights[index(x - 1, z)]));
            if (x + 1 < grid) max_slope = std::max(max_slope, std::abs(heights[i] - heights[index(x + 1, z)]));
            if (z > 0) max_slope = std::max(max_slope, std::abs(heights[i] - heights[index(x, z - 1)]));
            if (z + 1 < grid) max_slope = std::max(max_slope, std::abs(heights[i] - heights[index(x, z + 1)]));
            if (max_slope <= 1) ++slope_le_1;
            if (max_slope <= 2) ++slope_le_2;
            if (std::fabs(mountains[i]) < 1.0f) ++mountain_lt_1;
            low[i] = (max_slope <= 1 && std::fabs(mountains[i]) < 1.0f) ? 1 : 0;
        }
    }
    r.slope_le_1_pct = 100.0 * slope_le_1 / count;
    r.slope_le_2_pct = 100.0 * slope_le_2 / count;
    r.mountain_contrib_lt_1_pct = 100.0 * mountain_lt_1 / count;

    std::vector<uint8_t> seen(count, 0);
    constexpr std::array<int, 4> DX{1, -1, 0, 0};
    constexpr std::array<int, 4> DZ{0, 0, 1, -1};
    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int start = index(x, z);
            if (!low[start] || seen[start]) continue;
            size_t component = 0;
            std::queue<std::pair<int,int>> q;
            q.push({x, z});
            seen[start] = 1;
            while (!q.empty()) {
                const auto [cx, cz] = q.front(); q.pop();
                ++component;
                for (int d = 0; d < 4; ++d) {
                    const int nx = cx + DX[d], nz = cz + DZ[d];
                    if (nx < 0 || nz < 0 || nx >= grid || nz >= grid) continue;
                    const int ni = index(nx, nz);
                    if (low[ni] && !seen[ni]) {
                        seen[ni] = 1;
                        q.push({nx, nz});
                    }
                }
            }
            r.largest_low_relief_cells = std::max(r.largest_low_relief_cells, component);
        }
    }
    r.largest_low_relief_area_blocks2 = static_cast<double>(r.largest_low_relief_cells) * step * step;
    r.largest_low_relief_equiv_width_blocks = std::sqrt(r.largest_low_relief_area_blocks2);

    std::filesystem::create_directories(outdir);
    write_pgm(outdir / ("height_seed_" + std::to_string(seed) + ".pgm"), heights, grid, r.min_h, r.max_h);
    write_relief_ppm(outdir / ("relief_seed_" + std::to_string(seed) + ".ppm"), heights, mountains, grid);

    const auto ended = std::chrono::steady_clock::now();
    r.elapsed_ms = std::chrono::duration<double, std::milli>(ended - started).count();
    return r;
}

} // namespace

int main(int argc, char **argv) {
    const std::filesystem::path outdir = argc > 1 ? argv[1] : "artifacts/carpathian-reference";
    constexpr std::array<int, 3> seeds{734921, 19088743, 11235813};
    // 256 samples at 8-block spacing = 2048 x 2048 block reference window per seed.
    constexpr int GRID = 256;
    constexpr int STEP = 8;

    std::cout << "LUANTI_CARPATHIAN_REFERENCE_VERSION=5.16.1\n";
    std::cout << "LUANTI_CARPATHIAN_REFERENCE_GRID=" << GRID << " step=" << STEP
              << " physical_extent_blocks=" << GRID * STEP << "\n";
    std::cout << std::fixed << std::setprecision(4);

    for (int seed : seeds) {
        const AuditResult r = audit_seed(seed, GRID, STEP, outdir);
        std::cout << "CARPATHIAN_SEED=" << r.seed
                  << " height_min=" << r.min_h
                  << " height_max=" << r.max_h
                  << " height_mean=" << r.mean_h
                  << " height_p05=" << r.p05
                  << " height_p50=" << r.p50
                  << " height_p95=" << r.p95
                  << " slope_le_1_pct=" << r.slope_le_1_pct
                  << " slope_le_2_pct=" << r.slope_le_2_pct
                  << " mountain_contrib_lt_1_pct=" << r.mountain_contrib_lt_1_pct
                  << " largest_low_relief_cells=" << r.largest_low_relief_cells
                  << " largest_low_relief_area_blocks2=" << r.largest_low_relief_area_blocks2
                  << " largest_low_relief_equiv_width_blocks=" << r.largest_low_relief_equiv_width_blocks
                  << " elapsed_ms=" << r.elapsed_ms << "\n";
    }
    std::cout << "LUANTI_CARPATHIAN_REFERENCE_COMPLETE\n";
    return 0;
}
