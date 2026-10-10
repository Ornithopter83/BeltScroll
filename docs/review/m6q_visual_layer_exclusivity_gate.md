# M6Q visual layer exclusivity gate

## Rendering contract

`PlayerVisualAnimator` is the sole owner of full-body visibility. For each rendered frame it selects exactly one source: `PlayerArt`, the integrated `PoseBlender` layer, or the debug walk candidate. `WalkMotion` reports candidate readiness and updates its frame and ground anchor; it does not hide `PlayerArt` or enable its own body sprite. `PoseBlender` owns only which one registered pose sprite is selected inside its layer.

Source changes are atomic. No source opacity handoff is used, and a pose frame change immediately hides the previous sprite before the next frame is drawn. Startup, active/contact, recovery, combo hold, interruptions, and locomotion return therefore cannot leave a second silhouette or a semitransparent echo. Pose registration, phase clock selection, support-foot anchors, facing, and controller hitbox windows remain unchanged.

## Review checks

Run `tests/m6q_visual_layer_exclusivity_window_smoke.gd` in a Window build. It captures idle, attack startup, active, recovery, combo hold, and walk return after rendered frames, counts all three possible body sources, and checks that exactly one is visible. It also verifies that the PoseBlender reports no more than one registered texture and that the controller's attack active-duration table remains present.

The earlier M6L alpha-transition contract expected both the outgoing and incoming full-body layers to fade across 105 ms. That expectation is retired because it contradicts the single-silhouette rendering contract. Re-review source selection and the registered frame's timing and foot anchor at phase boundaries; do not use composite-alpha continuity as a pass criterion.

## Gate status

Implementation updates source visibility in `PlayerVisualAnimator` after `WalkMotion` has updated its candidate state. `PoseBlender` retains its two reusable Sprite nodes for compatibility, but only one node can be visible at a time.

## Execution (2026-10-10)

- `m6q_visual_layer_exclusivity_window_smoke.gd`: PASS in a Windows renderer on Godot 4.7.2. Initial idle, attack1 startup/active/recovery/combo_hold, walk return, and idle return each rendered exactly one full-body sprite. Effective alpha included every CanvasItem ancestor.
- `m6o_walk_four_phase_window_smoke.gd`: PASS in a Windows renderer. The walk candidate remained the sole visible body through the independent contact/passing frames; attack handoff hid it on the attack frame, and walking selected it again on return.
- `m6q_visual_collision_regression_smoke.gd`: PASS with 72 captured gameplay Window frames; every frame recorded exactly one effectively visible full-body source. The requested MP4 hash matched and F10 ON/OFF were captured.
- Original MP4 timestamp comparison remains **UNVERIFIED** because ffmpeg/ffprobe are unavailable. Input used by capture was synthetic, and human visual approval remains **PENDING**.
