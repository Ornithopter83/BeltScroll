# M6E 저장소 위생 게이트

## 대상과 보존 범위

이 게이트의 추적 제거 대상은 `.qa_logs/editor-publish-current/BeltScrollEditor.exe` 하나입니다. 현재 알려진 Git blob과 로컬 실행 파일은 각각 71,625,289바이트입니다. `.gitignore`의 기존 `.qa_logs/` 및 `*.exe` 규칙을 그대로 활용합니다. 규칙을 추가하거나 과거 QA 로그·캡처를 정리하지 않습니다.

일반 WORK는 실행 파일을 삭제하거나 수정하지 않습니다. Git index 제거와 commit/push는 Worker Git finalize 절차에서만 수행합니다. finalize는 정확한 대상 경로만 index에서 제거해야 하며, 캐시 전용 제거(`git rm --cached -- <대상 경로>`)로 로컬 파일을 보존합니다.

## finalize 전 기준선 — 2026-10-10 확인

확인한 `origin/main`과 `HEAD`는 모두 `f0acb432e8593c1f47ff4070b8f2fbbd216b3323`입니다.

| 검사 | 결과 |
| --- | --- |
| 로컬 파일 | 존재, 71,625,289바이트 |
| `git ls-files --stage -- <대상 경로>` | 추적 중, blob `c7f635e2d701d7b70deea5a81dd13bcd0cfdf129` |
| `git ls-tree -r --long origin/main -- <대상 경로>` | 추적 중, blob `c7f635e2d701d7b70deea5a81dd13bcd0cfdf129`, 71,625,289바이트 |
| 위생 검사 `tools/untrack_editor_publish_binary.ps1` 기본 Check | FAIL, 종료 코드 1: index 및 `origin/main`에 대상이 남아 있음 |
| 무시 규칙 `git check-ignore -v --no-index -- <대상 경로>` | `.gitignore`의 `.qa_logs/` 규칙과 일치 |

이는 push 전 기준선입니다. 이 상태를 완료 또는 PASS로 기록하지 않습니다.

## Worker Git finalize 순서

Worker Git finalize 인계 사항: 아래 기존 도구의 `Apply` 모드가 대상 경로 하나에 `git rm --cached -- <대상 경로>`를 수행합니다. Worker는 이 도구를 사용하고 다음 순서의 실제 출력과 종료 코드를 기록합니다.

1. 아래 읽기 전용 사전 확인을 실행합니다. index와 `origin/main` 모두에 대상이 있고 위생 Check가 실패하는 것이 현재 예상 결과입니다.
2. 정확한 대상 경로만 index에서 제거합니다. 로컬 실행 파일의 존재와 크기를 확인합니다.
3. Worker 절차로 변경을 commit하고 `origin/main`에 push합니다.
4. push 이후 `origin/main`을 갱신하고 동일한 검사를 다시 실행합니다. push 전후 결과를 별도 기록합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/untrack_editor_publish_binary.ps1 -Mode Apply
```

```powershell
$target = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
git ls-files --stage -- $target
git ls-tree -r --long origin/main -- $target
powershell -NoProfile -ExecutionPolicy Bypass -File tools/untrack_editor_publish_binary.ps1
git check-ignore -v --no-index -- $target
```

index 제거와 commit/push는 이 문서의 실행 예시로 호출하지 않습니다. Worker finalize에서 수행합니다. finalize 전에 기본 Check가 실패하는 것은 의도된 기준선이며, index에서만 제거한 뒤에도 원격 ref에 남아 있는 동안 Check가 실패해야 합니다.

## push 이후 기준선 — Worker 기록 필요

push 완료 및 `origin/main` 갱신 후 아래 세 항목을 다시 기록합니다. 현재는 Worker finalize 전이라 실제 원격 push 후 결과는 미실행입니다.

| 검사 | push 전 | push 후 기대 결과 | push 후 실제 결과 |
| --- | --- | --- | --- |
| `git ls-files --stage -- <대상 경로>` | 대상 존재 | 출력 없음 | 미실행 — Worker finalize 후 기록 |
| `git ls-tree -r --long origin/main -- <대상 경로>` | 대상 존재 | 출력 없음 | 미실행 — Worker finalize 후 기록 |
| 위생 Check | FAIL, 종료 코드 1 | PASS, 종료 코드 0 | 미실행 — Worker finalize 후 기록 |

push 후 검증 명령:

```powershell
$target = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
git ls-files --stage -- $target
git ls-tree -r --long origin/main -- $target
powershell -NoProfile -ExecutionPolicy Bypass -File tools/untrack_editor_publish_binary.ps1
```

최종 위생 PASS는 index의 `git ls-files`와 갱신된 `origin/main`의 `git ls-tree` 양쪽에서 대상이 모두 사라진 경우에만 유효합니다. 로컬 파일이 남아 있는 것은 정상입니다. 과거 QA 자료는 대상 경로가 아닌 `.qa_logs` 파일들을 보존합니다.

## 스모크 검사

격리된 임시 Git 저장소에서 큰 대상 파일, ignore 규칙, 과거 로그를 구성하여 index 제거 전, index만 제거한 뒤, 원격 기준 ref 갱신 뒤의 `ls-files`, `ls-tree`, 위생 결과를 각각 확인합니다. 실제 저장소 index, 파일 및 ref는 변경하지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/m6e_repository_hygiene_smoke.ps1
```

## 실행 기록

2026-10-10: 격리 fixture 스모크 종료 코드 0. 사전 상태는 `ls-files`/`ls-tree` 모두 대상 존재와 위생 FAIL, index만 제거한 상태는 `ls-files` 부재·`ls-tree` 존재와 위생 FAIL, 원격 기준 ref 갱신 후는 양쪽 부재와 위생 PASS였습니다. 로컬 fixture EXE 크기와 과거 QA 로그 보존도 확인했습니다. 실제 프로젝트에서는 index와 `origin/main` 모두 대상이 남아 있고 위생 Check가 종료 코드 1입니다. 실제 push 후 검증은 Worker Git finalize가 끝나야 기록할 수 있습니다.
