# M6U collision and overlay regression gate

## Scope

This gate checks the current production scenes and current collision scripts. It keeps visual contact alignment, actual combat damage, and overlay rendering as separate contracts. No collision layer, mask, shape dimensions, gameplay damage, or contact selection was changed for this work.

## Baseline render geometry and correction of the work claim

Comparison with HEAD `37659af` confirms that `combat_collision_overlay.gd` already sweeps the lower cap through `0..PI`. The working-tree difference adds two explanatory comments only. The earlier claim that this work corrected a `PI..TAU` lower-cap bug was inaccurate: no overlay geometry or production collision behavior was changed here. The 6/6 Window results confirm the current outline; they do not prove a newly fixed defect or retrospectively resolve the original QA failure.

The independent Window gate checks all six capsule landmarks against captured Window pixels for slash, slam, camera zoom/scroll, and KO. It also samples a live Player attack area and Raider receive area. For every OFF/ON pair it checks the actual monitor state, Window image change, collision signature, and HP invariance.

## Legacy contact failure classification

The old Boss receive expectation in `m6n_enemy_collision_alignment_smoke.gd` requires `ReceiveArea.position == (0, -48)` and a circle of radius `46`. The current production scene instead authors a capsule of radius `45`, height `160`, at `(0, -320)`. This is an obsolete fixture expectation; changing production collision physics to satisfy it would regress the current Boss hit lane.

The former synthetic contact fixture also placed its receive shape at the feet and asserted a hit at an arbitrary 50px root gap. Those assumptions do not describe the current sprite-authored fist path or current production Receiver. `m6q_fist_contact_hitbox_window_smoke.gd` now delegates to the production-distance damage gate. M6U retains two independent checks: exact displayed-hand to `CollisionShape2D` origin alignment, and real HP damage from normal 120px encounter spacing against Raider and active Boss.

## Run and result

Godot 4.7.2 Mono, Windows OpenGL Window:

- `m6u_f10_boss_receive_independent_window_smoke.gd`: PASS, 36 outline landmarks checked. Boss slash, slam, zoom/scroll, and KO all matched 6/6 cyan points within 4 Window pixels. Player J2 and inactive J2 each matched 4/4; Raider ReceiveArea matched 4/4. Every OFF/ON pair changed captured pixels and preserved collision settings and HP. Boss ReceiveArea monitoring was on for slash/slam, off and unmonitorable at KO; its transform stayed unchanged through camera and KO presentation changes. HIGH removed the test's post-KO physics stop and additionally confirmed that production VisualRoot collapse rotation/scale actually advances while the root-owned receiver remains unchanged (`temp/m6u_high_capsule.log`, exit 0).
- `m6u_legacy_combat_contract_smoke.gd`: PASS. J1/J2/J3, left-facing J1, Num4, and Num5 `CollisionShape2D` origins matched their displayed fist contacts within 0.1 world pixels. The inherited production Window damage cases independently reduced HP at 120px: Raider and Boss each took 6 from J1–3, 3 from Num4, and 2 from Num5.
- Existing `m6q_fist_contact_hitbox_window_smoke.gd`: PASS with the production-distance Window damage gate.
- Existing `m6r_player_fist_skill_contact_window_smoke.gd`: PASS.
- Original `m6n_enemy_collision_alignment_smoke.gd`: QA reproduced two obsolete receive-shape expectations, Raider `(0,-30)`/radius `25` and Boss `(0,-48)`/circle radius `46`. HIGH now explicitly pins the M6S production contracts: Raider `(0,-326)`/circle radius `44`; Boss `(0,-320)`/capsule radius `45`, height `160`. Actual Area2D overlap, attack damage callback, slash/slam reach, depth filtering, and KO disable assertions were retained. The revised test passed in a Windows OpenGL Window (exit 0, `temp/m6u_high_m6n.log`). This is a fixture migration, not a gameplay collision fix. Hand alignment, 120px HP damage, and silhouette/overlay checks remain separate evidence; replacing these expected values cannot establish combat damage.
- `m6q_visual_collision_regression_smoke.gd`: reference MP4 is absent in this checkout. Its SHA256 contract remains unchanged. HIGH added an early check in the capture tool so missing/mismatched input fails before creating a scene or overwriting existing review artifacts. Reference-video regression remains unverified.

F10 input itself is invoked through the overlay callback, so the tests verify rendered OFF/ON state and do not claim physical keyboard routing. Engine startup printed environment warnings about its user log directory and certificate store; the test scripts still completed with the stated exit results. Gameplay collision physics was not edited.
