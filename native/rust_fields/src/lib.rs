//! teknik_rust_fields: deterministic simulation fields for TEKNIK 0.1.
//!
//! Step 7 bootstrap: TeknikRustProbe proves cross-language loading.
//! Step 8 contract: TeknikRustFieldEvaluator mirrors
//! scripts/world/cave_field_reference.gd bit-for-bit. The GDScript file is
//! the behavioral reference; tests/cave_field_parity_gate.gd compares both
//! implementations live with exact double equality. Any change here must be
//! mirrored there in the same commit.
//!
//! Integer semantics: i64 wrapping multiply, arithmetic shift right, xor,
//! and masking only. Float semantics: f64 only, fixed expression trees.

// godot 0.1.3 generated call shims return a large CallError by value.
// The size is fixed by the upstream crate, not by extension code.
#![allow(clippy::result_large_err)]

use godot::prelude::*;

// ---- shared constants (keep byte-identical with the GDScript reference) ----

const CAVE_C1: i64 = -7046029254386353131;
const CAVE_C2: i64 = -4417276556811493921;
const CAVE_C3: i64 = 5504942323413186691;
const CAVE_C4: i64 = -6321507891823812219;
const CAVE_C5: i64 = 6321507891823812219;

const TUNNEL_SEED_A: i64 = 1372009017;
const TUNNEL_SEED_B: i64 = 729942611;
const CHEESE_SEED: i64 = 2048153539;
const ENTRANCE_SEED: i64 = 491651065;

const TUNNEL_SCALE: f64 = 1.0 / 28.0;
const CHEESE_SCALE: f64 = 1.0 / 48.0;
const ENTRANCE_SCALE: f64 = 1.0 / 16.0;
const TUNNEL_BAND: f64 = 0.058;
const CHEESE_THRESHOLD: f64 = 0.72;
const ENTRANCE_THRESHOLD: f64 = 0.78;
const FBM_GAIN: f64 = 0.5;
const FBM_LACUNARITY: f64 = 2.0;
const FRACTION_SCALE: f64 = 1.0 / 9007199254740992.0; // 2^-53
const FRACTION_MASK: i64 = 9007199254740991; // 2^53 - 1

fn cave_hash01(x: i64, y: i64, z: i64, seed: i64) -> f64 {
    let mut h: i64 = seed;
    h ^= x.wrapping_mul(CAVE_C1);
    h ^= y.wrapping_mul(CAVE_C2);
    h ^= z.wrapping_mul(CAVE_C3);
    h = (h ^ (h >> 30)).wrapping_mul(CAVE_C4);
    h = (h ^ (h >> 27)).wrapping_mul(CAVE_C5);
    h ^= h >> 31;
    ((h >> 11) & FRACTION_MASK) as f64 * FRACTION_SCALE
}

fn cave_value_noise(fx: f64, fy: f64, fz: f64, seed: i64) -> f64 {
    let ix = fx.floor() as i64;
    let iy = fy.floor() as i64;
    let iz = fz.floor() as i64;
    let tx = fx - ix as f64;
    let ty = fy - iy as f64;
    let tz = fz - iz as f64;
    let sx = tx * tx * (3.0 - 2.0 * tx);
    let sy = ty * ty * (3.0 - 2.0 * ty);
    let sz = tz * tz * (3.0 - 2.0 * tz);
    let c000 = cave_hash01(ix, iy, iz, seed);
    let c100 = cave_hash01(ix + 1, iy, iz, seed);
    let c001 = cave_hash01(ix, iy, iz + 1, seed);
    let c101 = cave_hash01(ix + 1, iy, iz + 1, seed);
    let c010 = cave_hash01(ix, iy + 1, iz, seed);
    let c110 = cave_hash01(ix + 1, iy + 1, iz, seed);
    let c011 = cave_hash01(ix, iy + 1, iz + 1, seed);
    let c111 = cave_hash01(ix + 1, iy + 1, iz + 1, seed);
    let n00 = c000 + (c100 - c000) * sx;
    let n10 = c001 + (c101 - c001) * sx;
    let n01 = c010 + (c110 - c010) * sx;
    let n11 = c011 + (c111 - c011) * sx;
    let n0 = n00 + (n10 - n00) * sy;
    let n1 = n01 + (n11 - n01) * sy;
    n0 + (n1 - n0) * sz
}

fn cave_fbm(fx: f64, fy: f64, fz: f64, seed: i64, octaves: i64, scale: f64) -> f64 {
    let mut total = 0.0f64;
    let mut amp = 1.0f64;
    let mut norm = 0.0f64;
    let mut x = fx * scale;
    let mut y = fy * scale;
    let mut z = fz * scale;
    for octave in 0..octaves.max(0) {
        total += cave_value_noise(x, y, z, seed + octave * 1013) * amp;
        norm += amp;
        amp *= FBM_GAIN;
        x *= FBM_LACUNARITY;
        y *= FBM_LACUNARITY;
        z *= FBM_LACUNARITY;
    }
    if norm <= 0.0 {
        return 0.5;
    }
    total / norm
}

fn cave_is_cell(
    wx: i64,
    wy: i64,
    wz: i64,
    surface_y: i64,
    sea_level: i64,
    water_column: bool,
    min_y: i64,
) -> bool {
    if wy < min_y + 2 {
        return false;
    }
    if water_column && wy > surface_y - 8 {
        return false;
    }
    let depth_below = surface_y - wy;
    let mut entrance_ok = false;
    if !water_column && surface_y > sea_level + 3 {
        entrance_ok = cave_value_noise(
            wx as f64 * ENTRANCE_SCALE,
            wy as f64 * ENTRANCE_SCALE,
            wz as f64 * ENTRANCE_SCALE,
            ENTRANCE_SEED,
        ) > ENTRANCE_THRESHOLD;
    }
    if depth_below < 4 && !entrance_ok {
        return false;
    }
    let ta = cave_fbm(
        wx as f64,
        wy as f64,
        wz as f64,
        TUNNEL_SEED_A,
        2,
        TUNNEL_SCALE,
    );
    let tb = cave_fbm(
        wx as f64,
        wy as f64,
        wz as f64,
        TUNNEL_SEED_B,
        2,
        TUNNEL_SCALE,
    );
    if (ta - 0.5).abs() < TUNNEL_BAND && (tb - 0.5).abs() < TUNNEL_BAND {
        return true;
    }
    if depth_below >= 12
        && cave_fbm(
            wx as f64,
            wy as f64,
            wz as f64,
            CHEESE_SEED,
            3,
            CHEESE_SCALE,
        ) > CHEESE_THRESHOLD
    {
        return true;
    }
    false
}

// ---- step 7 bootstrap probe ------------------------------------------------

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct TeknikRustProbe {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for TeknikRustProbe {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl TeknikRustProbe {
    #[func]
    pub fn ping(&self) -> i64 {
        42
    }
}

// ---- step 8 field contract (mirrors CaveFieldReference) --------------------

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct TeknikRustFieldEvaluator {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for TeknikRustFieldEvaluator {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl TeknikRustFieldEvaluator {
    #[func]
    pub fn hash01_3d(&self, x: i64, y: i64, z: i64, seed: i64) -> f64 {
        cave_hash01(x, y, z, seed)
    }

    #[func]
    pub fn value_noise_3d(&self, fx: f64, fy: f64, fz: f64, seed: i64) -> f64 {
        cave_value_noise(fx, fy, fz, seed)
    }

    #[func]
    pub fn fbm3(&self, fx: f64, fy: f64, fz: f64, seed: i64, octaves: i64, scale: f64) -> f64 {
        cave_fbm(fx, fy, fz, seed, octaves, scale)
    }

    #[func]
    pub fn tunnel_a(&self, wx: i64, wy: i64, wz: i64) -> f64 {
        cave_fbm(
            wx as f64,
            wy as f64,
            wz as f64,
            TUNNEL_SEED_A,
            2,
            TUNNEL_SCALE,
        )
    }

    #[func]
    pub fn tunnel_b(&self, wx: i64, wy: i64, wz: i64) -> f64 {
        cave_fbm(
            wx as f64,
            wy as f64,
            wz as f64,
            TUNNEL_SEED_B,
            2,
            TUNNEL_SCALE,
        )
    }

    #[func]
    pub fn cheese_field(&self, wx: i64, wy: i64, wz: i64) -> f64 {
        cave_fbm(
            wx as f64,
            wy as f64,
            wz as f64,
            CHEESE_SEED,
            3,
            CHEESE_SCALE,
        )
    }

    #[func]
    pub fn entrance_value(&self, wx: i64, wy: i64, wz: i64) -> f64 {
        cave_value_noise(
            wx as f64 * ENTRANCE_SCALE,
            wy as f64 * ENTRANCE_SCALE,
            wz as f64 * ENTRANCE_SCALE,
            ENTRANCE_SEED,
        )
    }

    #[allow(clippy::too_many_arguments)] // mirrors the GDScript contract 1:1
    #[func]
    pub fn is_cave_cell(
        &self,
        wx: i64,
        wy: i64,
        wz: i64,
        surface_y: i64,
        sea_level: i64,
        water_column: bool,
        min_y: i64,
    ) -> bool {
        cave_is_cell(wx, wy, wz, surface_y, sea_level, water_column, min_y)
    }
}

struct TeknikRustFieldsExtension;

#[gdextension]
unsafe impl ExtensionLibrary for TeknikRustFieldsExtension {}
