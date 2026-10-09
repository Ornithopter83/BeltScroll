# Player v10 fantasy artwork review gate

## Scope and decision

- Current approved game artwork: `assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png`.
- Prior unapproved comparison: `assets/art/player/elven_fighter_reference_v9_fantasy_1254x1254.png`.
- Candidate under review: `assets/art/player/elven_fighter_reference_v10_fantasy_1254x1254.png`.
- Comparison board: `assets/art/review/player_v10_comparison.png` (3000 × 10921 RGBA PNG).
- **Decision: v10 remains unapproved. Keep v8 in the player scene.** Mechanical checks do not grant visual approval.

## Image and alpha-bound checks

The comparison builder checks each source PNG's signature and IHDR directly for 1254 × 1254, 8-bit RGBA, then loads it as RGBA8. Its alpha bounds use every pixel whose alpha is greater than zero; they are measured on the source, before any display resize. The required clear margin is at least 90 source pixels on all four sides.

| Source | Actual alpha bounds (x, y, w, h) | Left / top / right / bottom margin | Nonzero alpha pixels | 90px gate |
|---|---:|---:|---:|---|
| v8 current | (110, 90, 1034, 1074) | 110 / 90 / 110 / 90 px | 268,467 | Pass |
| v9 unapproved | (0, 9, 1248, 1245) | 0 / 9 / 6 / 0 px | 392,392 | Fail |
| v10 candidate | (24, 19, 1214, 1217) | 24 / 19 / 16 / 18 px | 417,596 | Fail |

v10's silhouette is close to every canvas edge and misses the margin gate by 66 to 74 px. The alpha-bound check detects edge risk; it cannot prove whether a pose was intentionally cropped. Visual inspection shows both boots, both arms and fists, the face, ears, and ponytail represented, with no clearly severed body part in the supplied raster. This does not remove the near-edge risk or establish that the source will remain safe in animation, camera framing, or future edits.

## Scale and comparison method

The game's current sprite scale and camera zoom multiply to 0.53631288 screen pixels per source pixel. The board's upper strip shows all three **complete 1254 × 1254 source canvases** at that game scale, on a checker background. It therefore keeps the original transparent margins and texture-space foot position visible rather than cropping each character to its alpha box and silently aligning the feet.

Below the full-canvas row, the board shows face/ears/hair, guard/arms, costume/body, and feet/ground-anchor regions. These are direct crops from the alpha-bounds-relative source regions, enlarged to 1.60893864 pixels per source pixel (three times the gameplay display scale). No crop is fitted down to a small thumbnail. The crops use Lanczos interpolation only for the requested enlargement. They retain each original source's edge pixels; they do not repair alpha or remove colored fringe.

The lower detail rows are intentionally tall. They expose the eye, ear, hairline, fingers, costume edges, boot tips, and ground-relative pose at readable scale. Use the complete source files alongside this board if judging individual pixel edges.

## Visual review notes

- **Face, ears, and hair:** v10 preserves the same broad identity cues seen in v8 and v9: a brown high ponytail with a gold tie, pointed elf ears, and a right-facing face. Its face is rendered more smoothly and realistically than the current illustrated v8. A human reviewer should decide whether the altered facial proportions and finish still belong to the established character.
- **Guard and pose:** v8 has two closed fists in a compact, raised guard. v9 opens and extends one hand, making its silhouette less consistent with the established guard. v10 returns to two closed fists and bent arms, so its read is closer to v8. The fist heights and arm angles still differ, and the wide stance makes the overall pose broader.
- **Costume identity:** the teal-and-gold palette, brown wraps/bracers, waist belt, loose trousers, and boots continue across the candidates. v10 keeps the crossed teal top and exposed midriff while adding a more sculpted, flowing trouser silhouette and heavier gold detailing. Review these changes against the existing attack frames and desired game-art style.
- **Feet and anchor:** all three retain two boots, but v9 and v10 use a much wider base than v8. The full-canvas row preserves the original canvas-space placement, while the feet crop makes boot direction and stance width easier to compare. Confirm the desired root/ground anchor against the gameplay sprite and animation frames.
- **Edges and body completeness:** v10's four margins are all below the 90px requirement. The supplied image visibly includes the hair, hands, and boots, but the small safety region leaves little tolerance for texture filtering, further cropping, or motion. Check for matte fringe and any edge loss at the actual game zoom before considering approval.

These are review observations, not an automated identity or quality score. A reviewer must explicitly accept the face and ear silhouette, hair shape, costume changes, guard pose, foot anchor, alpha edge quality, and intended frame compatibility. Until then, v10 is a comparison candidate only and the game remains on v8.

## Rebuild and smoke commands

```powershell
godot --headless --path . --script res://tools/build_player_v10_comparison.gd
godot --headless --path . --script res://tests/player_v10_art_review_smoke.gd
```

The smoke checks all three PNG headers, actual alpha bounds and 90px margin outcomes, the generated comparison image, and the player scene's continued v8 reference. It deliberately does not turn visual inspection into a pass condition.
