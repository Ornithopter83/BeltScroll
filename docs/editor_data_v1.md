# Runtime editor data v1

The game reads `res://data/editor/overrides.json` when the main game scene starts. This file is ordinary UTF-8 JSON and does not depend on the Godot editor. Replacing or saving the file and starting/restarting the game reloads the saved contents.

## Root contract

```json
{
  "schema_version": 1,
  "characters": [],
  "enemies": [],
  "stages": []
}
```

All three arrays are required. A missing or malformed array is diagnosed and treated as empty. An unsupported schema version, unreadable file, or non-object root leaves scene-authored defaults in effect. Each record has a non-empty, case-sensitive `id`. `characters` currently recognizes `Player`; `enemies` recognizes `ForestRaider`; the active stage recognizes `ForestRuins`. Unknown IDs are ignored.

## Character and enemy fields

Records may omit any field; the scene's existing value is retained. Supported numeric fields and accepted ranges are:

| Field | Range | Effect |
|---|---:|---|
| `max_health` | 1–999, integer | Maximum and starting health |
| `walk_speed` | 1–2000 | Movement speed |
| `skill_cooldowns` | two values, each 0–60 | Player skill 1 and skill 2 cooldowns, set when each skill starts |
| `attack_damage` | 0–999, integer | Raider's hit damage |
| `attack_knockback` | 0–3000 | Raider's hit knockback |
| `attack_hit_stun` | 0–10 | Raider's hit stun duration |
| `attack_range` | 1–1200 | Raider pursuit/attack range and attack-area width |
| `windup_duration`, `active_duration` | 0–10 | Raider attack phases |
| `recovery_duration` | 0–30 | Raider recovery/cooldown |

`ai` is an optional object. It accepts `notice_range` (1–3000), `attack_depth_tolerance` (1–500), `separation_radius` (0–1000), and `separation_strength` (0–2000). Unknown fields are ignored. The current Player controller exposes health and movement tuning; its authored combo damage, knockback, hit stun, and skill cooldown constants remain the combat regression baseline.

## Stage fields

A stage accepts optional `left`, `top`, `right`, and `bottom` finite coordinates (absolute value at most 100000) for enemy arena bounds. Supplied opposing edges must have positive width/height. Partial edge sets preserve the corresponding scene edge. An optional `player_bounds` object uses the same four coordinates and leaves unspecified player edges at their scene-authored values; the sample explicitly retains the original HUD-safe player movement lane. Optional `spawns` is an array of `{ "actor_id": string, "x": number, "y": number }`; recognized IDs are `Player`, `ForestRaider`, `ForestRaider2`, and `ForestRaider3`. Invalid placements are skipped independently.

## Validation behavior

The loader checks types, finite values, numeric ranges, integer-only fields, boundary order, and placement coordinates. Invalid fields generate `[EditorData]` warnings and are removed while valid sibling fields remain applicable. Invalid records and unavailable data are skipped, preserving scene defaults. This keeps a partially edited file from introducing out-of-range combat values or invalid arena rectangles.
