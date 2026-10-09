# Repository hygiene gate

## Scope

`tools/check_repository_hygiene.ps1` inspects paths in the Git index and checks
the configured baseline tree (default: `origin/main`). It flags the known
`.qa_logs/editor-publish-current/BeltScrollEditor.exe` as an explicit blocking
finding while either the index or baseline tracks it. The index check uses
`git ls-files`; the baseline check uses `git ls-tree`. A copy that exists only
in the working directory is not a tracking violation. The gate also flags
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

## Worker Git finalize procedure

- The known generated editor publish binary is 71,625,289 bytes (about
  68.3 MiB). Remove only its Git index entry during the authorized Worker Git
  finalize step, retaining the local executable:

  ```powershell
  git rm --cached -- .qa_logs/editor-publish-current/BeltScrollEditor.exe
  ```

- Commit and push that index removal through the Worker finalize process. Until
  `origin/main` is updated, the hygiene checker must continue to fail because
  the baseline still tracks the executable. After the push, verify both sides:

  ```powershell
  git ls-files --stage -- .qa_logs/editor-publish-current/BeltScrollEditor.exe
  git ls-tree -r -l --full-tree origin/main -- .qa_logs/editor-publish-current/BeltScrollEditor.exe
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_repository_hygiene.ps1
  ```

  The first two commands should print no entry, and the hygiene checker should
  no longer report this executable. A local copy may still exist.

## Removal and retention policy

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

At implementation time, `git ls-files --stage` and
`git ls-tree -r -l origin/main` both reported the editor EXE at 71,625,289
bytes. Its local file remains intact. This work item does not run
repository-mutating Git commands; the Worker finalize procedure above removes
the index entry and verifies that the committed remote tree no longer tracks
it.
