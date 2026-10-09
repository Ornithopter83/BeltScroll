# Player skill motion review gate

## Review intent

Num4 dash and Num5 spin use different pose sequences driven by the live
`skill_phase` and `skill_phase_remaining` values. They contain no newly approved
skill drawings. Until such drawings are authored and reviewed, their motion is
explicitly marked as temporary procedural animation in the visual animator and
the smoke output.

| Skill | Startup | Contact | Recovery |
| --- | --- | --- | --- |
| Num4 dash | Forward brace and weight shift | Forward acceleration, impact pose, optional recoil | Counter lean and return to neutral |
| Num5 spin | Wound up stance | Circular torso turn with a radial scale pulse | Unwind and return to neutral |

Both poses rotate and scale around the alpha-foot anchor. `VisualRoot` remains
the facing mirror, and hit, block interruption, and KO take precedence over a
skill pose. Combat hitboxes, damage, phase durations, and cooldowns remain owned
by the player controller.

## Consecutive Window capture

Run `godot --path . --script res://tools/capture_player_skill_motion.gd` with a
visible Window renderer. The capture advances the real Player controller through
both complete skills and saves every rendered frame under
`temp/player_skill_motion_capture/` as `num4_NNN_phase.png` and
`num5_NNN_phase.png`. The gate checks that it captured startup, active contact,
and recovery for each move, and compares the two active Window images to verify
that their rendered silhouettes differ.

The capture requires the actual Window display server; headless rendering is not
accepted as visual evidence. The matching animator and skill smoke scripts also
check phase-clock synchronization, the temporary-art label, mirrored attack
poses, the foot anchor, interruption, and KO priority.

## Captured Window evidence

The Window run captured 27 consecutive frames across both skills and passed the
active-silhouette comparison. These rendered active frames show Num4's forward
dash stance and Num5's rotating body silhouette:

![Num4 dash contact captured from the Window Viewport](../../temp/player_skill_motion_capture/num4_001_active.png)

![Num5 spin contact captured from the Window Viewport](../../temp/player_skill_motion_capture/num5_004_active.png)
