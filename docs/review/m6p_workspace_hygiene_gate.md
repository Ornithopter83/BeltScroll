# M6P Workspace Hygiene Gate

## Scope

`tools/audit_m6p_generated_sidecars.ps1` reports Git index state, available remote tracking refs, sidecar source pairing, and per-file preservation or review decisions. It is read-only: it does not remove, move, stage, or rewrite files. The default remote baseline label is `origin/main`; all locally available remote refs are checked for preservation.

Run from PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/audit_m6p_generated_sidecars.ps1
```

The report is written to standard output so the audit itself does not create a repository artifact. An unavailable baseline is reported; in that case, the index and locally available remote refs remain the available tracking evidence.

## Classification policy

- Remote/index tracked `.import` and `.uid` files are preserved.
- `.uid` sidecars with a source file are intentional-UID review items. Orphan `.uid` files also require reference review. No UID is deleted or globally ignored.
- `.import` paired with `assets/art/review/*.png` is preserved with its review evidence.
- Other paired `.import` files are marked as potentially regenerable candidates, but cleanup is policy-blocked because the sidecar may preserve import settings and no cleanup authorization is encoded in this gate.
- Orphan `.import` files are individually listed as cleanup candidates, blocked pending review and explicit cleanup authority.
- Untracked PNG sources paired with `.import` sidecars are listed as user assets or review evidence and kept.

`.gitignore` continues to ignore only `.godot/` for Godot's disposable local editor/import cache. It deliberately has no blanket `.import` or `.uid` rule: sidecars can carry project settings or stable resource identifiers. Existing user assets, review PNGs, and any Git-tracked sidecars remain visible and preserved.

## Repeated Godot run check

Two initial headless editor runs were performed with Godot 4.7.2 (`--headless --editor --path <project> --quit`). They generated 19 additional untracked sidecars during the first scan (15 `.uid`, 4 `.import`), bringing the audited set from 335 to 354. The sidecars were retained and are classified by the audit. Two more runs after that first scan both exited 0 and produced no `git status --short --untracked-files=all` delta. Godot logged certificate-store and user editor-settings save errors in this environment; repository status remained stable on the repeated runs.

The final audit classified 354 untracked sidecars as 220 UID review items and 134 import sidecars (53 review-PNG sidecars and 81 user-asset sidecars). It also listed 202 untracked PNG sources, plus 131 index-tracked sidecars. All 81 potentially regenerable import sidecars are policy-blocked from cleanup because import settings may be meaningful; no ignore or deletion rule was applied.

## Smoke check

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/m6p_sidecar_policy_smoke.ps1
```

The smoke check verifies that the audit runs, emits per-file classifications, and that `.gitignore` does not blanket-ignore `.import` or `.uid` files. It does not mutate project assets.
