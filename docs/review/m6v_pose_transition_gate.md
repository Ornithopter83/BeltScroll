# M6V Pose Transition Quality Gate

## Gate scope

This gate covers the full-body pose handoffs owned by `PlayerVisualAnimator` and
`PlayerPoseBlender`: idle/walk, facing reversal, jump rise/fall/landing, hit/KO,
the J1→J2→J3 combo, and Num4/Num5 skill phases. It keeps movement and combat
timers in `PlayerController`; visual pose sampling follows those timers.

## Transition rules

- `PlayerArt` or one `PoseBlender` frame owns the full-body silhouette for a
  rendered frame. Pose image changes are atomic; different full-body images do
  not fade over each other.
- Combat and skill transforms pivot around the shared alpha-foot reference.
  Position, rotation, and scale keys meet at adjacent phase boundaries so the
  body does not snap back to a neutral transform between phases.
- `combo_hold` keeps the last contact drawing selected until the next attack
  phase takes ownership. It does not enable a hitbox or reset the combo clock.
- Num4 uses a forward brace and sustained dash translation. Num5 uses a
  counter-rotation and bounded backfist arc. Neither relies on its effect node
  to communicate the body motion.
- World-space fist and articulated-point queries continue to sample the sprite
  that is currently visible. Attack and skill hitbox windows remain controlled
  by the player controller.

## Window smoke

Run `tests/m6v_pose_transition_quality_window_smoke.gd` with the project Godot
executable. It walks each state gate, checks the one-source rendering rule,
pins the first two combo holds, checks phase-boundary transform deltas for the
strikes and skills, and verifies the contact API and controller-owned active
windows remain present.

The smoke validates deterministic state and transform contracts. Final visual
review should still confirm the enlarged silhouettes and timing at gameplay
scale; this gate does not label temporary procedural movement as approved
animation art.
