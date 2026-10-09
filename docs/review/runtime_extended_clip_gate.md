# Runtime extended clip gate

## Scope

The runtime loader keeps animation manifest and reviewed-frame registry schema v1. It accepts explicit reviewed clips for `run/stride`, `turn/turn`, `jump_rise/rise`, `jump_fall/fall`, `hit/reaction`, and `skill1` or `skill2` with `startup`, `contact`, and `recovery` phases. Skill controller phase `active` maps to the manifest's `contact` phase. `run/stride` may contain multiple frames in manifest order; each frame has its own texture, duration, label, and normalized foot anchor.

## Promotion gate

Each new approved frame must have a matching schema v1 registry entry with the clip, phase, exact project PNG path, PNG SHA-256, duration, normalized foot anchor, non-empty manual review record under `docs/review/records`, and checked-in manifest SHA-256. Registry identities include the texture path, allowing distinct reviewed run frames while rejecting duplicate entries for the same texture. The runtime still validates the full manifest before it registers any new frame. Candidate and review frames remain unregistered. Registry entries with no corresponding approved manifest frame fail closed.

No additional frame was manually approved for this change. `data/art/reviewed_frame_allowlist.json` remains at zero entries, and the existing approved idle and attack contact frames retain their current allowlist, byte checks, and hitbox durations.

## Runtime clocks and fallback

Stride frames play in registration order and loop on the run phase duration, using the animator's movement-state clock. Turn uses the turn transition clock; rise, fall, and reaction use their current state clocks; skills use the controller's startup, active/contact, and recovery timers. Existing attack frames continue to use the combat controller's phase clock. If a phase has no reviewed frames, the pose blender hides and the existing procedural PlayerArt pose remains active. Existing interruption and KO paths clear or hide reviewed poses; the VisualRoot remains responsible for left-facing mirroring.

## Regression coverage

`tests/player_animation_bank_smoke.gd` covers texture-specific multi-frame stride registration and order, timed looping, movement/turn/jump/hit/skill clock integration, procedural fallback, KO interruption, rejection of unreviewed, mismatched, duplicate, and traversal approvals, the empty promotion registry, legacy attack allowlist and timing, and mirrored foot anchoring.
