package unlucky_dungeon

import rl "vendor:raylib"
import "core:strings"

/////////////////////////////////////////////////////////////////////
// Helpers related
/////////////////////////////////////////////////////////////////////
// ---------- RNG: tiny LCG (single source per run) ----------
Rng :: struct {
    state: u64,
}

rng_init :: proc(seed: u64) -> Rng {
    res := seed
    if res == 0 { res = 0x9E3779B97F4A7C15 } // avoid zero
    return Rng{ res }
}

// LCG: state = state * A + C (64-bit), output upper 32 bits
rng_u32 :: proc(rng: ^Rng) -> u32 {
    rng.state = rng.state * 6364136223846793005 + 1
    return cast(u32)(rng.state >> 32)
}

rng_between_i :: proc(rng: ^Rng, min, max: int) -> int {
    // inclusive min..max
    val := rng_u32(rng)
    span := (max - min + 1)
    return min + cast(int)(val % cast(u32)span)
}

rng_between_f01 :: proc(rng: ^Rng) -> f32 {
    // [0,1)
    return cast(f32)(rng_u32(rng)) / cast(f32)(0x1_0000_0000) // 2^32
}

// ---------- Helpers ----------
lerp :: proc(a, b, t: f32) -> f32 {
    return a + (b - a)*t
}

clamp_f01 :: proc(x: f32) -> f32 {
    if x < 0.0 { return 0.0 }
    if x > 1.0 { return 1.0 }
    return x
}
norm_t :: proc(row_idx: int) -> f32 {
    // 1..13 -> 0..1
    return cast(f32)(row_idx - 1) / cast(f32)(ROWS - 1)
}

//measure and center text on x axis
center_x :: proc(w: i32, text: string, size: i32) -> i32 {
    cstr := strings.clone_to_cstring(text, context.temp_allocator)

    return w / 2 - rl.MeasureText(cstr, size) / 2
}
