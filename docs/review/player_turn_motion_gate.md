# Player turn motion review

## Result

Player facing changes now use a 0.13 second procedural turn when the player is in idle or walk. The motion has a short opposing windup, a compressed center, one `VisualRoot` horizontal sign change, and a settle. The controller still reads the same direction and velocity every physics tick; only the visual root's rendered sign is staged by `VisualAnimator`. The sprite pose continues to use the existing alpha-foot anchor correction.

The sequence is generated from transforms on the existing still artwork. No dedicated turn drawings or frame animation were available or added. This is a temporary procedural presentation.

## Priority and interruption

KO, hitstun, skills, attacks, blocking, jumping, and landing preempt the turn pose. A preempting state clears the turn timer and applies the current facing immediately, so existing action poses and control timing keep precedence. A direction change during the turn restarts the short sequence toward the latest horizontal input; movement velocity is never delayed or rewritten.

## Window review

`tools/capture_player_turn_motion.gd` opens a fullscreen Godot Window and captures its rendered Window frames. The strip shows standing and moving left turns through anticipation, compression, and settle, plus a rapid reverse-input case. Capture checks enforce the 1024×900 tile bounds and an alpha-foot-anchor error no greater than 0.08 local units. The screenshot is `assets/art/review/player_turn_motion_strip.png`.

## Verification

`tests/player_visual_animator_smoke.gd` covers standing/moving direction changes, the delayed single facing application, compression, unchanged velocity, anchor retention, rapid reversal, and hitstun interruption. Run it with a visible renderer because it is a Window Viewport smoke. The dedicated capture tool performs the on-screen bounds and foot-anchor checks for every saved panel.
