# M6O Editor Spawn Order Gate

## Reproduction and cause

`editor_runtime_apply_smoke.gd` checks the saved `ForestRuins` placements against the live `main.tscn` scene. The scene instances are named `ForestRaider1`, `ForestRaider2`, and `ForestRaider3`; the editor records use IDs `ForestRaider`, `ForestRaider2`, and `ForestRaider3`.

The failure source was positional identity: `_raiders` was collected in `get_nodes_in_group()` order, then `_apply_spawns()` assigned editor IDs by array index. The group API does not promise that discovery order is the same as the scene's Raider numbering. A different order therefore applies valid spawn records to the wrong instances. Wave progression also depends on spatial section order, which is a separate concern from actor identity.

## Change

- Resolve each editor ID from the actual `ForestRaider1/2/3` scene node name and set that ID as `editor_id` metadata.
- Apply spawn records through that name-to-ID mapping, independent of `_raiders` array order.
- Sort the Raider collection by stable editor ID and create `_wave_order` separately after spawn application, sorting by world X with editor ID as the tie-breaker.
- Keep the existing data schema, JSON values, AI overrides, combat values, and stage/section behavior unchanged.

## Baseline comparison

The saved `data/editor/overrides.json` baseline remains schema v1 with Player `(960, 780)` and Raider spawns `(1480, 780)`, `(3360, 780)`, `(5160, 780)`. Raider combat baseline remains max health 3, walk speed 118, attack damage 1, range 96, windup 0.34, active 0.16, recovery 0.62; AI values are unchanged. The `ForestRuins` boundaries and Player bounds were not modified. `main.tscn` node names and editor data contract were not changed.

## Verification

- `Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script tests/editor_runtime_apply_smoke.gd` — PASS. Checks all three saved placements, stable metadata IDs, wave section order, initial activation, first-section gate, restart/re-instantiation, saved health overrides, and the existing Player combat geometry baselines.
- `Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script tests/m6o_editor_spawn_order_smoke.gd` — PASS. Reverses `_raiders` before spawn application and repeats the case twice; both runs verify all coordinates, spatial wave order, and section 1→2→3 activation.
- The spawn-order smoke now also separates placement from ordinary AI movement: after confirming the saved position immediately after `_apply_spawns`, it advances two physics-frame signals. The active first Raider then moves `(-1.966675, 0)` per run, while inactive Raider2/3 remain at `(3360, 780)` and `(5160, 780)`. This confirms the JSON position is applied before the active Raider's normal physics step.

Godot printed host-environment messages about its `user://logs` directory and Windows certificate store. Both scripts completed with the indicated exit status; these messages did not affect scene loading or assertions.
