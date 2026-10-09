# Attack 2 v5 contact review gate

## Status

**V5 contact candidate found, mechanically rejected, and unapproved. Human review is pending.** The review tool recognizes `elven_fighter_attack2_contact_v5_identity_candidate_1254x1254.png` and includes it in the fifth comparison slot. It is RGBA8 at 1254×1254, but its nonzero-alpha margins are L/T/R/B 0/20/10/0px, below the 90px requirement. Bright edge contamination and isolated pixels are visible. It must remain disconnected from gameplay.

`assets/art/review/player_attack2_contact_v5_comparison.png` shows, in order:

1. v8 ready pose: `elven_fighter_reference_v8_clean_candidate_1254x1254.png`
2. first hit contact: `elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png`
3. second hit middle pose: `elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png`
4. existing second hit contact: `elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png`
5. new v5 second hit contact: identity candidate; mechanical fail; not approved

Each visible-alpha silhouette is proportionally fitted to 576px high, three times the 192px gameplay sprite height, and aligned to a shared foot baseline. The images are read-only inputs. The comparison is a review aid and does not authorize use in the game.

## Existing-art observations

In the comparison, the four available poses retain recognizable shared character cues: brown high ponytail with a gold tie, pointed ear, teal-and-gold clothing, brown gloves, and brown boots. The first contact keeps the face and extended fist directed to screen right. The middle pose also punches right while turning the torso, with the other arm held in guard. The existing second-hit contact turns the back and shoulders toward the viewer while the head looks over the shoulder; the extended arm remains aimed right.

That change in torso orientation makes the existing second-hit contact read as a stronger rotation than the middle pose. The ponytail remains attached at the crown in both images and its swept silhouette supports the turn. The outfit palette and gold trim remain legible, though the back-facing contact exposes different garment panels. The stances shift from a wide, low base in the middle pose to a rotated split stance in the contact pose. This is a visible support-foot and weight-transfer change that an animator should review in sequence. These are visual review notes, not a mechanical identity or movement pass; a still comparison cannot establish timing, actual balance, or contact quality.

At the 3× gameplay display size, the candidate retains a recognizable face, pointed ear, teal-and-gold costume, rightward extended arm, boots, and high ponytail. The pose reads as a rotated rightward strike. This is a visual comparison only; the alpha fringe is conspicuous on a dark background and tiny detached pixels remain. No approval is granted. Review identity, torso rotation and weight center, support foot, and ponytail attachment against both the middle pose and old contact after the edge and canvas defects are corrected.

## Candidate checks and recognized locations

The builder searches these explicit paths, in order:

- `assets/art/player/elven_fighter_attack2_v5_contact_candidate_1254x1254.png`
- `assets/art/player/elven_fighter_attack2_reference_v5_contact_candidate_1254x1254.png`
- `assets/art/player/elven_fighter_attack2_contact_v5_candidate_1254x1254.png`
- `assets/art/player/elven_fighter_attack2_contact_v5_identity_candidate_1254x1254.png`

If found, the input must decode as RGBA8 at exactly 1254×1254. Its bounding box uses every pixel whose alpha is greater than zero; each canvas margin (left, top, right, bottom) must be at least 90px. The builder reports these values and includes the candidate even when a mechanical condition fails, so visual inspection can still inform revision. The smoke verifies that an unsafe candidate remains in the review gate and is not treated as approved. It does not approve the image.

Reviewers must make and record a separate visual decision for identity, attack direction, rotation/weight center, supporting foot, and ponytail attachment. A mechanically valid image remains unapproved until a human reviewer records acceptance. An unapproved or missing image must not be connected to the player, animation, or runtime resources.

## Rebuild and smoke

```powershell
godot --headless --path . --script res://tools/build_player_attack2_contact_v5_review.gd
godot --headless --path . --script res://tests/player_attack2_contact_v5_smoke.gd
```

The smoke checks the comparison canvas, existing frame sources, candidate decoding, dimensions, format, and safe margins. An unsafe candidate is reported as rejected for approval while the review build remains usable. It cannot judge face/ear identity, clothing continuity, direction, rotation, balance, support foot, ponytail attachment, or final approval.
