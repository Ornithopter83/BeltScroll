# M6J WinForms live launch verification gate

## Scope and evidence classes

The editor's **게임 전투 테스트** and **전투 연습장 실행** buttons launch separate Godot processes from an isolated temporary project. The launcher reads the active saved `overrides.json`, validates it, copies it to the temporary project's `data/editor/overrides.json`, and reports that unsaved form values are excluded. It reports Godot path/start failures and nonzero exits, and removes the temporary project after process exit. Closing the editor also terminates a remaining playtest process and attempts temporary-copy cleanup.

`--playtest-gui-acceptance` drives both visible WinForms buttons from the editor's GUI message loop. It checks that each launched process exposes a visible main window, that the isolated copy contains saved `Player.max_health = 11` and `ForestRaider.max_health = 23`, and that a dirty unsaved `Player.max_health = 77` edit did not replace the saved values. For each button's scene, it also starts a headless probe against that same temporary project and checks `max_health` and initialized `health` on the actual Player and ForestRaider scene instances. It then confirms that closing the GUI process produces exit code 0 and removes the temporary copy. The probe verifies values in live game objects; its headless run is still automated testing and is not a human visual inspection.

This result is classified as **automated GUI verification**. It is not human mouse/keyboard acceptance. `--self-test` covers code-level preparation only and cannot produce a GUI launch PASS.

## Run automated GUI verification

Use Windows PowerShell 5.1 with a built standalone editor and a real Godot executable:

```powershell
.\tests\m6j_editor_live_launch_smoke.ps1 -EditorPath .\dist\BeltScrollEditor.exe -GodotPath C:\Project\Godot\godot.exe
```

The script runs the editor visibly, invokes both actual button handlers through the WinForms event loop, and waits up to 180 seconds by default. It writes the acceptance report, screenshots, process output, and summary under `%TEMP%\BeltScrollM6JLiveLaunch_*`. The report states `verificationClass: automated_gui`, `actualOsMouseInput: false`, and `humanInputReview: not_performed`.

Invalid Godot paths, process start errors, a process that exits before its window appears, window/exit timeouts, nonzero process exits, incorrect staged or live actor values, or failed temporary-copy cleanup fail the run. Inspect `playtest-gui-acceptance.json`, `m6j-live-launch-summary.json`, the per-scene `*-runtime-probe.stdout.txt` and `*-runtime-probe.stderr.txt` files, and captured editor stdout/stderr for details.

## Separate human review

Human review remains pending until a person opens the editor, uses a physical mouse/keyboard to click each button, confirms each game window is visible and behaves as expected, closes it, and records the observed results here. In particular, inspect the Player and Raider combat values in the practice arena in-game. Automated process/window/data checks must not be recorded as human review.

| Review | Status | Evidence |
|---|---|---|
| Automated GUI launch | PASS · automated_gui · 2026-10-10 | Godot 4.7.2 and Release WinForms editor; both buttons showed windows, exited 0, applied Player=11/ForestRaider=23 to live scene instances, excluded unsaved Player=77, and cleaned temporary copies. Artifacts: `C:\Users\ornit\AppData\Local\Temp\BeltScrollM6JLiveLaunch_b9bea42cc9674b2e916bb9ba247e8e61`. `actualOsMouseInput=false`. |
| Human mouse/keyboard review | Not performed | Pending operator playtest. |
