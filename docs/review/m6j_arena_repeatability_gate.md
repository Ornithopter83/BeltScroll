# M6J combat arena repeatability gate

## F6 practice flow

Open `scenes/review/m6i_combat_test_arena.tscn` in Godot and press **F6**. The arena instantiates the existing Player and ForestRaider scenes. Its HUD reports live HP, Player basic attack stage and phase, Num4/Num5 skill phase and cooldown, both hitstun timers, Raider attack phase, relative direction/distance/depth lane, and the latest combat event.

Use WASD to change horizontal position and depth. J performs the basic combo. Use the numeric keypad **Num4** for the dash skill, **Num5** for the spin skill, and **Num3** to guard; the HUD names the skills separately. Observe Raider's windup and use movement or guard to avoid or block its counterattack. Move along the depth axis to check when hitboxes and the Raider's attack lane connect.

The session record counts round outcomes and observed attack/skill attempts, hits, and misses. Raider KO records success; Player KO records failure. Press **R** to reload both combatants and start another trial. The record lives in SceneTree metadata, so it survives scene reloads in that running Godot process and resets when the process exits.

## Isolation contract

The arena only reads the saved editor combat override file and applies the approved values to its live Player and Raider instances. The readout observes actor state and combat signals. The HUD and retry controls do not set health, hitstun, attack results, or cooldowns; cooldown overrides are applied only from the saved editor data when the real skill-start signal fires. No production settings or approved art assets are written.

## Automated smoke

`tests/m6j_arena_repeatability_smoke.gd` checks that the existing actor scenes, live-state readouts, numeric keypad bindings, retry handler, and same-session outcome record are wired. It emits each KO outcome signal twice on one arena instance and checks that it is counted once; after scene recreation it emits the next result and checks that the new round is counted while session totals remain. It does not change actor health or hitstun. This structural smoke does not simulate a human combat playthrough or replace visual review.

Run in PowerShell from the project root with the installed Godot executable:

```powershell
& '.\Godot\Godot_v4.4.1-stable_win64_console.exe' --headless --path . --script tests/m6j_arena_repeatability_smoke.gd
```

If the executable filename differs, substitute the local console executable path. For the manual gate, play the arena through both a Raider KO and a Player KO, confirm the outcome counters, then press R and verify that both actors return at full configured health while the session totals remain visible.
