# TEKNIK — Project Instructions

## Tech Stack
- Godot **4.7.1**, GDScript, target platform Android ARM64 (dev device: Vivo T3x, 6GB RAM — treat this as the perf ceiling, not a desktop dev machine's specs).
- Native layer: `native/carpathian/` — a C++ GDExtension (`teknik_carpathian.cpp`, `teknik_voxel_mesher.hpp`). This clone is shallow (`--depth 1`) and found no Rust sources or `Cargo.toml` — if a Rust layer exists, verify it's actually present before assuming it (don't trust prior session summaries on this point without checking).
- Voxel world: 32³ chunks, Jolt Physics.
- No package manager / build manifest at the root — this is a pure Godot project, not driven by npm/cargo/etc.

## Autoloads (project.godot)
`SaveManager`, `WorldSeed`, `DiagnosticLogCapture` — in that order. SaveManager must load before WorldSeed (its save file has to be read before WorldSeed decides whether to randomize or reuse a seed).

## Critical Gotcha: headless `--script` entry files and autoloads
Root cause, fully confirmed (not theory): when Godot boots with `--script X.gd`, that script is compiled as the MainLoop implementation **before** ProjectSettings autoloads get registered as known global identifiers. Any *other* script that's a compile-time dependency of the entry file (`const Y := preload("...")` at the top) gets compiled in that same early pass — so it inherits the same failure, regardless of how deeply nested it is. This is not about scene-tree structure; it's about **when the script gets compiled**.

Confirmed empirically:
- `Engine.has_singleton("SaveManager")` → `false` from the entry script.
- Bare `SaveManager` identifier in the entry script, or in anything it `preload()`s → `SCRIPT ERROR: Compile Error: Identifier not found`.
- Bare `SaveManager` identifier in a script obtained via `load()` **at runtime**, inside a deferred call (e.g. `call_deferred("_run_gate")` → `load("res://...").new()`) → **works fine**, because by that point the engine has finished registering autoloads and this script is only now being compiled.
- `root.get_node_or_null("SaveManager")` also always works (the node genuinely exists under root the whole time) — use this in the entry script itself, where you can't avoid early compilation.

**Practical rule for gate tests:** in the `--script` entry file, never `preload()` a script that (transitively) references a bare autoload identifier. Either `load()` it at runtime inside the deferred callback, or fetch the autoload via `root.get_node_or_null(...)` instead of the bare name. `Engine.get_singleton(...)` calls are always syntactically valid (no compile error) but still return null/false in this mode — same practical effect, different failure shape.

This resolved a real, tested risk from the previous version of this note: `playable_world_runtime.gd`'s own mechanical-block save/load methods use the bare `SaveManager` identifier (matching the rest of the codebase's convention) and were verified, via `load()` at runtime in a gate test, to work correctly. `playable_world_data.gd`'s `save_world()`/`load_save()`/`_resolve_default_world_seed()` still use `Engine.get_singleton(...)` instead — unverified whether that path works in a real (non-`--script`) game boot; no existing test proves voxel override persistence. Flagged, not fixed — out of scope so far.

## Running Godot headless (no binary ships in the repo/container)
```bash
curl -sL -o godot.zip "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip"
unzip -q godot.zip -d godot_bin && chmod +x godot_bin/Godot_v4.7.1-stable_linux.x86_64
mv godot_bin/Godot_v4.7.1-stable_linux.x86_64 /usr/local/bin/godot
```
Whole-project parse check (run this after any change, before trusting a gate test result):
```bash
xvfb-run -a godot --headless --path . --editor --quit 2>&1 | grep -E "SCRIPT ERROR: Parse Error|Failed to load script"
# no output = clean
```
Running a gate test — flags matter, copied from `.github/workflows/acceptance-gate.yml`:
```bash
xvfb-run -a godot --headless --audio-driver Dummy --path . --script res://tests/<name>_gate.gd
```
`--path .` and `--audio-driver Dummy` are not optional; omitting `--path .` breaks autoload wiring, and `--script` alone was never verified to work without it.

## Project Structure
```
scripts/world/    world gen (staged: playable_world_stageN_*.gd), SaveManager, WorldSeed, chunk/mesh code
scripts/player/    first-person controller, input
scripts/ui/        menus, hotbar, touch controls
scripts/inventory/ inventory/crafting model
scripts/android/   Android-specific glue
native/carpathian/ C++ GDExtension (terrain/mesh acceleration)
tests/             gate tests, see convention below
docs/               stage-completion writeups, evidence docs
tools/reference/   reference material, not shipped code
acceptance/         one step_N_passed.md per completed build-plan step
```

## Test Convention
- File name: `<feature>_gate.gd` (or `_benchmark.gd`, `_diagnostic.gd` for non-pass/fail runs).
- `extends SceneTree`, `_initialize()` → `call_deferred("_run_gate")`.
- Collect failures in an `Array[String]`, `_fail(msg)` appends + `push_error`.
- `_finish()`: `quit(0)` on empty failures; on failure, `print("<NAME>_GATE_FAIL")` then each `FAILURE=...`, `quit(1)`.
- Print a `<NAME>_GATE_PASS` marker on success — CI greps for this string, not just the exit code.

## Save File Convention (`save_manager.gd`)
- `user://teknik_save.json`, plain `JSON.stringify`/`parse_string`, no schema library.
- New fields are **additive**: read with `.get(key, default)` and a type check (`is Dictionary` / `is Array`), so an old save missing the key degrades to an empty default instead of crashing. Don't bump `version` for additive fields — it's only bumped for breaking format changes.
- `"x,y,z"` string keys (`cell_key()`, `"%d,%d,%d" % [x,y,z]`) are the standard way to key a `Vector3i` in a JSON-safe Dictionary — reuse this, don't invent a new key scheme.

## Working Conventions (from TEKNIK_BUILD_PLAN.md)
- One numbered plan item = one commit. Don't bundle unrelated changes.
- If a design decision has to be guessed mid-build, write it down (a `## Decisions` section in the relevant plan doc) in the same commit as the code.
- GDScript first for new systems; native C++/Rust is a later optimization pass once a system is proven, not the default starting point.
- Input is always routed through `InputMap` actions, never hardcoded to keyboard/mouse checks — touch controls have to be swappable in without rewriting gameplay code.

## Before Starting Any Task
Re-run this skill's reconnaissance (or at minimum re-read this file) rather than re-deriving conventions from scratch — this file exists specifically to avoid repeating the trial-and-error that produced it.
