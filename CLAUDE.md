# TEKNIK — Project Instructions

## Tech Stack
- Godot **4.7.1**, GDScript, target platform Android ARM64 (dev device: Vivo T3x, 6GB RAM — treat this as the perf ceiling, not a desktop dev machine's specs).
- Native layer: `native/carpathian/` — a C++ GDExtension (`teknik_carpathian.cpp`, `teknik_voxel_mesher.hpp`). This clone is shallow (`--depth 1`) and found no Rust sources or `Cargo.toml` — if a Rust layer exists, verify it's actually present before assuming it (don't trust prior session summaries on this point without checking).
- Voxel world: 32³ chunks, Jolt Physics.
- No package manager / build manifest at the root — this is a pure Godot project, not driven by npm/cargo/etc.

## Autoloads (project.godot)
`SaveManager`, `WorldSeed`, `DiagnosticLogCapture` — in that order. SaveManager must load before WorldSeed (its save file has to be read before WorldSeed decides whether to randomize or reuse a seed).

## Critical Gotcha: headless test autoload access
Running a test as the direct `--script res://tests/whatever.gd` entry point (a `SceneTree` main-loop override) means **that script itself is parsed before autoloads are registered as global identifiers/singletons** — neither the bare identifier (`SaveManager.foo()`) nor `Engine.get_singleton("SaveManager")` resolves from *that specific file*, even though the autoload node genuinely exists as a child of `root` by the time `_initialize()`/`call_deferred` runs. Confirmed empirically:
- `Engine.has_singleton("SaveManager")` → `false` in this context.
- Bare `SaveManager` identifier → `SCRIPT ERROR: Compile Error: Identifier not found`.
- `root.get_node_or_null("SaveManager")` → **works**, since the node is really there.

So for a bare `--script` entry file, fetch it via:
```gdscript
var save_manager := root.get_node_or_null("SaveManager")
```
This does **not** apply to scripts that run as part of a loaded scene (e.g. `inventory_vanilla_baseline_gate.gd` loads `main.tscn` as a child first) — those are parsed after autoload setup completes, so bare identifiers work normally there, matching how the rest of the game's scripts (`main_menu.gd`, `playable_world_port.gd`, `world_seed.gd`, `inventory_first_person_controller.gd`) actually call `SaveManager`/`WorldSeed`.

**Known risk, not yet fixed:** `playable_world_data.gd`'s own `save_world()` / `load_save()` / `_resolve_default_world_seed()` guard on `Engine.has_singleton(...)` — the pattern just shown to fail for a bare entry script. Whether it also fails in a real, normally-booted game (main.tscn as entry point, not `--script`) is **unverified** — no existing test proves voxel block-edit persistence actually round-trips. Every other working save/load call site in the codebase uses the bare identifier instead. Worth a real gate test before trusting this path; don't silently assume it works.

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
