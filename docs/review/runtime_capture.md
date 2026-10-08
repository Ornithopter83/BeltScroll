# Actual gameplay capture

`run_game.cmd actual-game-capture` starts the real `scenes/game/main.tscn` in a windowed Godot process. The tool keeps the scene's Player camera, `YSortActors`, Forest Ruins background, Raider instances, and CombatHUD, adds a real combat impact node to the scene, waits for four completed draw frames, and reads the Window Viewport texture into a 1920x1080 PNG. The default output is `assets/art/review/actual_gameplay_capture.png`; an optional output path can be passed after the mode.

The capture is made only from `ViewportTexture.get_image()` after `RenderingServer.frame_post_draw`. The tool does not composite or draw a replacement image. It exits with code 1 and an `actual-game-capture:` diagnostic when no windowed renderer is available, required gameplay nodes are missing, the viewport image is empty, the frame size or visible-content check fails, or PNG saving fails. Usage errors exit with code 2.

Run `run_game.cmd actual-game-capture-smoke` to capture the default PNG and then check that it loads, has the expected dimensions, and contains varied scene pixels. The smoke process propagates capture failures and returns nonzero for image validation failures. The existing `run_game.cmd smoke` suite remains separate and unchanged.
