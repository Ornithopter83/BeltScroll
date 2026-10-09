# Repository hygiene gate

## Scope

`tools/check_repository_hygiene.ps1` inspects paths in the Git index. It flags
tracked build/cache directories (`.godot`, `.vs`, `.cache`, `bin`, `obj`,
`build`, `publish`, and `artifacts`), newly tracked generated logs and scratch
files relative to `origin/main`, tracked executables at or above 10 MiB, and
new executable/ZIP outputs under QA or distribution directories. The default
comparison ref is `origin/main`; use `-BaselineRef` when checking another
target branch. The checker fails clearly if that ref cannot be read.

Run on Windows PowerShell 5.1 from the repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_repository_hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/repository_hygiene_smoke.ps1
```

## Removal and retention policy

- Remove `.qa_logs/editor-publish-current/BeltScrollEditor.exe` from Git
  tracking; it is a generated editor publish binary. Its observed working-copy
  size is 71,625,289 bytes (about 68.3 MiB). Keep the local file when possible
  by removing only its index entry with `git rm --cached` during Git finalize.
- Ignore future `.qa_logs`, distribution/build output, executables, ZIP
  packages, and generated logs/scratch files through `.gitignore`.
- Do not bulk-delete `.qa_logs` history. Existing tracked QA logs and image
  captures are historical evidence and remain in the repository unless a
  separate reviewed change identifies a specific obsolete artifact.
- Keep intentional evidence in `assets/art/review/` and game resources in
  `assets/`, `data/`, `scenes/`, and related runtime resource directories.
  The ignore rules do not target these locations or file types used by the
  game.
- Existing historical files present in `origin/main` are grandfathered by the
  generated-log comparison. The gate focuses that check on newly tracked
  generated outputs, so it does not erase or demand cleanup of old evidence.

## Current worktree observation

At implementation time, the editor EXE was tracked in the index and present
locally. The local file remains intact. The Worker finalize step must remove
its index entry; this work item does not run repository-mutating Git commands.
