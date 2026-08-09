// Reference-only simplification study. Not linked into TEKNIK.
// Includes the exact Carpathian reference harness in the same translation unit
// so this study uses the identical Luanti-derived noise/equation implementation.
#define main luanti_carpathian_reference_original_main
#include "luanti_carpathian_reference.cpp"
#undef main

#include <array>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <vector>

namespace {

struct FastColumn {
    int height = 0;
    float mountains = 0.0f;
};

FastColumn sample_column_single_probe(int x, int z, int32_t world_seed, int probe_y) {
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
    const float step_mask = ster * ster * ster * steps(nstep);

    const float mv = fractal3d(NP_MNT_VAR, static_cast<float>(x),
        static_cast<float>(probe_y), static_cast<float>(z), world_seed);
    const float hill1 = lerp(h1, h2, mv);
    const float hill2 = lerp(h3, h4, mv);
    const float hill3 = lerp(h3, h2, mv);
    const float hill4 = lerp(h1, h4, mv);
    const float hilliness = std::max(std::min(hill1, hill2), std::min(hill3, hill4));
    const float mountains = (hill_mask + ridge_mask + step_mask) * hilliness;

    // Above water the exact Carpathian solid predicate is:
    // y < BASE_LEVEL + mountains + 1 - y.
    // With mountain variation frozen at one representative surface y, solve it
    // analytically instead of scanning every vertical node.
    const float threshold = (BASE_LEVEL + mountains + 1.0f) * 0.5f;
    int top = static_cast<int>(std::ceil(threshold)) - 1;
    top = std::clamp(top, 0, 255);
    return {top, mountains};
}

struct CompareResult {
    int seed = 0;
    int probe_y = 0;
    double mae = 0.0;
    int p95_abs_error = 0;
    double exact_pct = 0.0;
    double within1_pct = 0.0;
    int fast_min = 999;
    int fast_max = -999;
    int fast_p95 = 0;
    double fast_slope_le1_pct = 0.0;
    size_t largest_low_relief_cells = 0;
    double largest_low_relief_equiv_width = 0.0;
};

CompareResult compare_seed(int seed, int probe_y, int grid, int step) {
    const size_t count = static_cast<size_t>(grid) * grid;
    std::vector<int> exact(count), fast(count), errors(count);
    const int half = grid / 2;
    double error_sum = 0.0;
    size_t exact_count = 0, within1 = 0;

    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int wx = (x - half) * step;
            const int wz = (z - half) * step;
            const int i = z * grid + x;
            exact[i] = sample_column(wx, wz, seed).height;
            fast[i] = sample_column_single_probe(wx, wz, seed, probe_y).height;
            const int e = std::abs(exact[i] - fast[i]);
            errors[i] = e;
            error_sum += e;
            if (e == 0) ++exact_count;
            if (e <= 1) ++within1;
        }
    }

    CompareResult r;
    r.seed = seed;
    r.probe_y = probe_y;
    r.mae = error_sum / static_cast<double>(count);
    std::sort(errors.begin(), errors.end());
    r.p95_abs_error = errors[static_cast<size_t>(0.95 * static_cast<double>(count - 1))];
    r.exact_pct = 100.0 * exact_count / count;
    r.within1_pct = 100.0 * within1 / count;
    r.fast_min = *std::min_element(fast.begin(), fast.end());
    r.fast_max = *std::max_element(fast.begin(), fast.end());
    std::vector<int> sorted_fast = fast;
    std::sort(sorted_fast.begin(), sorted_fast.end());
    r.fast_p95 = sorted_fast[static_cast<size_t>(0.95 * static_cast<double>(count - 1))];

    auto idx = [grid](int x, int z) { return z * grid + x; };
    std::vector<uint8_t> low(count, 0), seen(count, 0);
    size_t slope1 = 0;
    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int i = idx(x, z);
            int slope = 0;
            if (x > 0) slope = std::max(slope, std::abs(fast[i] - fast[idx(x - 1, z)]));
            if (x + 1 < grid) slope = std::max(slope, std::abs(fast[i] - fast[idx(x + 1, z)]));
            if (z > 0) slope = std::max(slope, std::abs(fast[i] - fast[idx(x, z - 1)]));
            if (z + 1 < grid) slope = std::max(slope, std::abs(fast[i] - fast[idx(x, z + 1)]));
            if (slope <= 1) {
                ++slope1;
                low[i] = 1;
            }
        }
    }
    r.fast_slope_le1_pct = 100.0 * slope1 / count;

    constexpr std::array<int, 4> DX{1, -1, 0, 0};
    constexpr std::array<int, 4> DZ{0, 0, 1, -1};
    for (int z = 0; z < grid; ++z) {
        for (int x = 0; x < grid; ++x) {
            const int start = idx(x, z);
            if (!low[start] || seen[start]) continue;
            std::queue<std::pair<int, int>> q;
            q.push({x, z});
            seen[start] = 1;
            size_t component = 0;
            while (!q.empty()) {
                auto [cx, cz] = q.front(); q.pop();
                ++component;
                for (int d = 0; d < 4; ++d) {
                    int nx = cx + DX[d], nz = cz + DZ[d];
                    if (nx < 0 || nz < 0 || nx >= grid || nz >= grid) continue;
                    int ni = idx(nx, nz);
                    if (low[ni] && !seen[ni]) {
                        seen[ni] = 1;
                        q.push({nx, nz});
                    }
                }
            }
            r.largest_low_relief_cells = std::max(r.largest_low_relief_cells, component);
        }
    }
    r.largest_low_relief_equiv_width =
        std::sqrt(static_cast<double>(r.largest_low_relief_cells) * step * step);
    return r;
}

} // namespace

int main() {
    constexpr std::array<int, 3> seeds{734921, 19088743, 11235813};
    constexpr std::array<int, 4> probes{4, 6, 8, 12};
    constexpr int GRID = 128;
    constexpr int STEP = 8;

    std::cout << std::fixed << std::setprecision(4);
    std::cout << "CARPATHIAN_SURFACE_ADAPTER_STUDY grid=" << GRID
              << " step=" << STEP << "\n";
    for (int probe : probes) {
        double total_mae = 0.0;
        double total_within1 = 0.0;
        for (int seed : seeds) {
            CompareResult r = compare_seed(seed, probe, GRID, STEP);
            total_mae += r.mae;
            total_within1 += r.within1_pct;
            std::cout << "SURFACE_ADAPTER seed=" << seed
                      << " probe_y=" << probe
                      << " mae=" << r.mae
                      << " p95_abs_error=" << r.p95_abs_error
                      << " exact_pct=" << r.exact_pct
                      << " within1_pct=" << r.within1_pct
                      << " fast_min=" << r.fast_min
                      << " fast_max=" << r.fast_max
                      << " fast_p95=" << r.fast_p95
                      << " slope_le1_pct=" << r.fast_slope_le1_pct
                      << " largest_low_relief_equiv_width=" << r.largest_low_relief_equiv_width
                      << "\n";
        }
        std::cout << "SURFACE_ADAPTER_SUMMARY probe_y=" << probe
                  << " mean_mae=" << total_mae / seeds.size()
                  << " mean_within1_pct=" << total_within1 / seeds.size() << "\n";
    }
    std::cout << "CARPATHIAN_SURFACE_ADAPTER_STUDY_COMPLETE\n";
    return 0;
}
