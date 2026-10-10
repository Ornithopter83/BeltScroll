# M6R Player fist contact gate

## Implemented contract

- Basic attacks 1–3 and Num4/Num5 use authored hand points in their attack drawings. The points are expressed in the 1254 × 1254 source-image coordinate space and follow the visible `Sprite2D` through its current transform, frame, and horizontal mirror.
- Contact moves along attack-specific paths during the live phase clock: an extending straight punch, a transverse hook arc, a rising punch, the Num4 advancing fist, and the Num5 backfist arc. Num4 and Num5 do not use the VFX center or the player ground origin as their contact point.
- The controller updates each enabled hitbox from that world-space fist point on every active physics check. The actual collision resource is a compact circle sized for fist contact.
- Collision-space queries use the configured target mask and the real `Shape2D`. Body and `ReceiveArea` results are normalized to the hit receiver root and deduplicated before damage. Basic attacks and skills reject receiver roots outside the existing 42-unit belt-depth tolerance.
- Existing phase durations, damage, combo buffering/linking, skill cooldowns, knockback, and hit reactions remain owned by the controller's existing constants and handlers.

## Coordinate notes

The authored points target the visible glove/fist in the currently approved attack key drawings: attack 1 `(510, -253)`, attack 2 `(440, -147)`, and attack 3 `(319, -491)`, relative to the source image center. Their phase paths use those points as contact endpoints. Skill drawings are not approved key art, so Num4/Num5 use authored hand points over the displayed procedural pose and animate those points along their own contact paths.

The contact point is transformed from the currently visible sprite rather than inferred from `AttackFlash`, a skill effect, or the floor support anchor. Shape dimensions are 13–16 world units in radius.

## Smoke coverage

`tests/m6r_player_fist_skill_contact_window_smoke.gd` checks all five attacks against their live sprite-derived contact point, verifies the compact shape, checks left-facing mirroring, and puts both the body and `ReceiveArea` at the contact point to assert one damage event per target.

The smoke script was added but not run in this work item.
