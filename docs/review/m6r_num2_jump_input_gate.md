# M6R Num2 jump input timing gate

## Finding

The M6Q `display_num_input_window_smoke` sequence sent Num2 directly after the Num1 attack probe. The old probe waited only one render frame and one physics frame before releasing Num1, then did the same before testing Num2. A basic attack remains in startup/active/recovery across that interval. When a one-stage attack reaches recovery, it continues into `combo_hold` for the combo link window. The Player's jump start condition explicitly requires `attack_phase == "idle"`, so the jump is intentionally rejected during those phases. The old check incorrectly treated this rejected attack-window input as an idle jump failure.

This is a verification-order defect. The gameplay contract remains: Num2 is mapped to jump, attack recovery and combo_hold block jump initiation, and jump starts when the player is otherwise eligible and idle.

## Gate procedure

`tools/capture_display_num_input.gd` now exercises the live Player in a real Window run:

1. It confirms Num1 starts an attack and the keypad mapping matches InputMap.
2. After Num1, it waits until `recovery`, presses synthetic Num2, and verifies InputMap receives it while the Player stays grounded.
3. It observes the attack continue into `combo_hold`, verifies the Player is still grounded, releases Num2, and waits for the attack to return completely to `idle`.
4. It presses Num2 from idle and samples Player jump height, vertical velocity, and `is_jumping` at physics-frame boundaries. The gate requires ascent, descent, and landing.
5. It repeats the idle jump cycle five times to expose timing flakiness.
6. It retains Num1–Num5 physical keypad versus top-row-key distinction checks, and existing Num6–Num9 action/reservation checks.

`tests/m6r_num2_jump_input_timing_smoke.gd` invokes that Window capture and checks its result report and image evidence. The tool reports synthetic `InputEventKey` input explicitly; this does not validate a real keyboard's OS event delivery.

## Acceptance evidence

- `attack_num2_probe=recovery_pressed_and_combo_hold_blocked`
- Five report entries `num2_run_1` through `num2_run_5`, each with `rise:true,fall:true,land:true`
- `physical_keyboard_status=NOT_TESTED`

Evidence files are written under the OS temporary directory as `display_num_input_window.txt` and `display_num_input_window.png`.

## Execution note

The M6R smoke was launched with Godot 4.7.2 in a Window run. The capture stopped before gameplay checks because the current `scripts/player/player_controller.gd` fails to load: Godot reports that it cannot infer the type of `direction` at line 444, followed by an undeclared `BASIC_ATTACK_CONTACT_X` parse error at line 618. Other live scene scripts then report runtime errors. Those files are outside this work item's write paths, so this change does not alter them. The capture now reports the missing live Player state immediately instead of proceeding with invalid state and flooding the run with errors. The five-cycle rise/fall/landing evidence remains pending a build where the Player script loads.
