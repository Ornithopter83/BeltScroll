# M6D Full Playthrough Window Gate

## Purpose

`tools/capture_m6d_full_playthrough.gd` opens the real title scene in a non-headless Godot Window and records a reproducible title-to-gameplay run. It sends title `InputEventKey` and mouse events and gameplay `InputEventAction` events through the root Window Viewport and `Input.parse_input_event`; player movement, attacks, enemy AI, hit detection, wave progression, and result scenes remain owned by the shipped game code.

No enemy or player health is written by the harness. It does not call `receive_hit`, invoke the session victory/defeat methods, move actors directly, activate waves directly, or replace a scene to manufacture an outcome. It only reads live positions, health, active-wave state, and result state to decide which input event to send and whether a milestone occurred.

## Run modes

Automated replay (default):

```powershell
godot.exe --path . --script res://tools/capture_m6d_full_playthrough.gd
```

This mode logs every injected action as `M6D|INPUT_AUTO|...` and reports `AUTOMATED_INPUT_EVENT_REPLAY`. It presses Enter at the title, traverses and fights the three Raider waves, attacks the active boss, presses R on the real victory scene, repeats the route, and then stops attacking so the active boss can damage the player into the real defeat flow. There are no forced outcomes; a timeout or unexpected result is recorded as `FAIL` or `UNVERIFIED`.

Physical-input observation mode:

```powershell
godot.exe --path . --script res://tools/capture_m6d_full_playthrough.gd -- --manual
```

This mode does not inject input. The user operates the Window: Enter to start; WASD to move; J to attack; keypad 4/5 for skills; R to restart a result. Observed input edges are logged as `M6D|PHYSICAL_INPUT|...` with `injected=0`. Press F10 to end the observation and print PASS/UNVERIFIED for the milestones reached so far.

## Evidence and gate

Each reached milestone is sampled from the real Window Viewport. The captured title, section changes, active Raider encounters, boss, victory, restart route, player damage, and defeat are composed into `assets/art/review/m6d_full_playthrough_evidence.png`. The smoke gate starts a fresh automated replay and requires explicit PASS rows for the full run plus a decodable contact sheet.

Run the gate in a graphical session:

```powershell
godot.exe --path . --script res://tests/m6d_full_playthrough_window_smoke.gd
```

## Verification record

On 2026-10-10, the graphical smoke gate completed with exit code 0. It observed PASS for title, all three stage sections, all three Raider encounters, boss activation and attacks, victory, fresh-scene restart, player health loss, and defeat. The generated 1920×1520 contact sheet contains 12 checkpoints, including the fresh gameplay scene immediately after restart.

HIGH recheck on 2026-10-10 reran this gate after the section dressing update with Godot 4.7.2 and a non-headless Window. Exit code was 0; all required result rows were PASS. The current log is `.qa_logs/m6d_full_playthrough_high_recheck.log` and the rendered checkpoints are in `assets/art/review/m6d_full_playthrough_evidence.png`. Input was automated gameplay-event injection. The run did not use health writes, outcome functions, or physical keyboard input, and it does not satisfy the separate manual acceptance row.

Headless runs are not evidence of Window behavior. In that environment the smoke gate reports the Window flow as unverified/failing; it does not substitute a scene-only simulation. The contact sheet records actual screenshots at reached checkpoints and does not assert that an unvisited checkpoint occurred.

## Result interpretation

- `PASS`: the named live Window observation happened.
- `FAIL`: an expected transition failed or the replay reached the wrong terminal outcome.
- `UNVERIFIED`: the Window could not be observed, a deadline elapsed, or a physical/manual sequence has not reached that milestone.
- `AUTOMATED_INPUT_EVENT_REPLAY` and `PHYSICAL_INPUT_OBSERVATION` are distinct evidence sources and are always named in the log.

The automated full run is intentionally bounded to 150 seconds per gameplay leg. Normal combat randomness, missed attacks, or a player defeat before the first boss victory can prevent completion; those cases remain visible as FAIL/UNVERIFIED rather than being repaired by changing health or calling a result function.
