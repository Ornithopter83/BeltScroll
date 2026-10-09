# Editor publish binary untrack gate

## Purpose

`tools/untrack_editor_publish_binary.ps1` is a Worker Git finalize helper for
`.qa_logs/editor-publish-current/BeltScrollEditor.exe`. Its default `Check`
mode reads the real index with `git ls-files` and the selected baseline (by
default `origin/main`) with `git ls-tree`. It reports tracking and the known
71,625,289-byte size violation. A local-only copy does not count as tracked.

The tool returns failure while either the index or `origin/main` still contains
the executable. Therefore the hygiene result cannot be PASS between removing
the index entry and pushing the removal to the remote baseline.

## Ordinary WORK and QA

Ordinary work must use only the default read-only check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/untrack_editor_publish_binary.ps1
```

Do not run Apply during ordinary WORK or QA. The smoke test creates a separate
temporary Git fixture and tests Apply only there:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/editor_publish_untrack_smoke.ps1
```

The smoke fixture starts with a 71,625,289-byte tracked executable, verifies
that Check blocks, verifies Apply removes only its fixture index entry and
preserves its local file, then verifies Check remains blocked until the
fixture's `origin/main` ref is updated to the removal commit. It does not run
Apply against the project repository.

## Authorized Worker Git finalize

Only the authorized Worker Git finalize may perform the repository mutation.
From the project root, apply the cached-only removal, then use the existing
Worker commit and push flow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/untrack_editor_publish_binary.ps1 -Mode Apply
# Perform the existing Worker Git finalize commit and push here.
git fetch origin
powershell -NoProfile -ExecutionPolicy Bypass -File tools/untrack_editor_publish_binary.ps1
```

The only mutating Git command in `Apply` is `git rm --cached -- .qa_logs/editor-publish-current/BeltScrollEditor.exe`, and it runs only when the path is indexed. The tool checks that an existing local executable retains its presence and byte length. The Worker finalize remains responsible for committing and pushing the index change. Fetching and checking after push refreshes `origin/main`; hygiene PASS is valid only when both `git ls-files` and that refreshed `git ls-tree origin/main` report the path absent.

Do not report hygiene PASS before the push and remote recheck. Do not use this
tool to delete the local executable or to bulk-delete `.qa_logs` history.
