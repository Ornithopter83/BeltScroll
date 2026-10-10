# M6I independent editor combat playtest gate

## Behavior

The WinForms editor launches the game scene (`res://scenes/game/main.tscn`) or the combat practice arena (`res://scenes/review/m6i_combat_test_arena.tscn`) in a separate Godot process. It requires a real `godot*.exe` file and a project directory containing `project.godot` plus both scenes. The practice arena loads the saved Player and ForestRaider combat overrides, including skill cooldowns, for its live actors.

Before launch, the editor validates the saved override JSON and copies the project into a unique temporary directory. The saved JSON is copied into that isolated project's `data/editor/overrides.json`; the original project and its settings file are never written by the playtest launcher. Temporary project copies omit repository/build/cache and editor review directories. The copy is removed when Godot exits; if the editor itself exits while Godot is still running, the temporary directory may remain under the system temp directory.

Valid edits in the form are marked as unsaved. A playtest explicitly reports that it applies the saved file at the displayed path and that unsaved edits are ignored. Save the edits first to apply them. Process start errors are shown in the editor, and process exit code is reported; nonzero exits include captured standard output and error.

## Automated smoke

Run from Windows PowerShell 5.1:

```powershell
.\tests\m6i_editor_combat_playtest_smoke.ps1
```

The smoke invokes the standalone editor's `--self-test`, which covers project-root rejection and isolated-copy behavior, including checking the source override remains byte-for-byte unchanged and `.git` content is excluded. It also checks that the editor source contains the launch/status contract. `tests/m6i_combat_test_arena_window_smoke.gd` separately applies changed temporary Player/Raider values and verifies the resulting stats, AttackArea geometry and skill cooldown. These checks do not launch the WinForms button or claim a human visual review.

## Operator playtest

1. Open the standalone editor and choose the Godot executable and project root.
2. Edit combat fields and save. Confirm the save path shown in the status area.
3. Click **게임 전투 테스트** and confirm the separate game process starts. Check its displayed combat values in play, then close the game and note the reported exit code.
4. Repeat with **전투 연습장 실행** to open the Player/Raider arena and check its displayed saved combat values.
5. Optionally edit a field without saving before launch: the editor must say that unsaved values are ignored and show the saved path being applied.
6. Confirm the source project's `data/editor/overrides.json` was not rewritten by either launch.

No automatic art approval is part of this gate. Any required visual review must be performed and recorded by a human; this document does not fabricate that review.
