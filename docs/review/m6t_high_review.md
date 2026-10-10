# M6T HIGH 검토 · #674 / #675

검토일: 2026-10-10. 실행 환경: Godot 4.7.2.stable.mono.official.ed1daf0bf. Window 검사는 DisplayServer Windows/OpenGL이며 headless가 아니다. 아래 headless 검사는 별도로 구분한다. 종료 코드는 각 스크립트의 quit 결과이며 `--quit-after`는 안전망이다.

## 원인과 보완

1. WORK의 주먹별 보정과 X 60~132 클램프는 손이 플레이어 뒤에 놓여도 Shape만 전방으로 옮겼다. 이를 제거했다. 앞발을 루트 중심에 붙여 몸 전체가 뒤로 밀리던 승인 공격 원화 배치를 stance 중심으로 수정했다. M6R의 손/Shape 계약을 유지했고 인터페이스 시그니처도 유지했다.
2. 기존 승인 그림의 팔·무릎·발을 국소 삼각형 메시로 움직인다. 주먹 좌표는 실제 표시된 삼각형에서 보간한다. 기본 Shape 반경 13/14/15px, 스킬 16/15px를 유지하며, 물리 `intersect_shape`의 실제 겹침만 피해를 발생시킨다. 거리와 방향/깊이는 접근 이동 제한 또는 미명중 거부에만 사용한다.
3. 현재 위상·방향을 물리 쿼리 전에 시간 진행 없이 동기화하고, 전투의 중복 render-delta 보간을 제거했다. 초기 보완 후 확장 검사에서 Boss J3가 한 번 미명중했던 문제를 재현하여 수정했다. 최종 게이트에는 남은 명중 실패가 없다.
4. Raider 원은 y=-326/반경44px다. 48개 외곽점 모두 원화 상체 알파 안에 들어간다. Boss는 발 위치를 유지하며 VisualRoot 2.2배/y=-114.4, ReceiveArea y=-320/반경45px/높이160px로 맞췄다. 기존 54px/260px 캡슐은 빈 공간을 포함했다. 새 캡슐의 원호·직선 외곽 108개 표본 모두 실제 Head/Torso 안에 들어간다. Boss AI와 피해 처리 코드는 수정하지 않았다.
5. 본편 보행은 지지 발을 월드 anchor에 유지하고 반대 발·무릎을 들어 passing을 만든다. 최종 Window 입력에서 실제 메시 삼각형 기준 접지 오차 0.1240px, 골반 높이 변화 13.08px다(실제 렌더 샘플 간 작은 변동 있음). 네 위상과 좌우 지지가 실제 물리 이동 입력 중 교대한다. 보행 cadence는 이동 속도에 비례한다.
6. J1 뻗기/J2 가로 궤적/J3 올려치기는 각기 다른 기존 승인 접촉 원화의 팔을 움직인다. 준비·타격·복귀·유지 동안 단계 원화를 유지한다. combo_hold에서 IDLE/전신 중첩을 금지하고 복귀 끝에서 유지로 다시 크게 뻗는 전이도 제거했다. Num4는 팔을 뻗고 전진하며 Num5는 전완을 팔꿈치 주위로 돌리고 허리를 중심으로 상체를 되감는다. Num5 전신 기울기를 -0.78에서 -0.32rad로 줄여 다리가 크게 들리는 정지 원화 회전도 완화했다. 최종 비교 캡처에서는 스킬 VFX의 process와 표시를 끄고 몸만 비교했다.
7. 미승인 보행 PNG는 명시적 DEBUG preview만 선택한다. 일반 gameplay에서 자동 선택하지 않으며 manifest/allowlist를 변경하지 않았다. 본편은 기존 승인 idle/접촉 그림을 사용한다.
8. M6S 후보 보행 실패는 수동 샘플링과 자동 process의 중복 진행을 제거하고 남은 시간을 다음 위상으로 넘기도록 고쳤다. F10 캡슐의 반원 방향/연결이 틀려 오른쪽 아래·왼쪽 위 외곽이 빠지던 실제 렌더러 버그도 수정했다. F10 검사에서는 객체를 제대로 정지시키고 Shape 전체를 카메라에 넣는다.

## 최종 검증

| 검사 | 실행 방식 | 결과 / 증거 |
|---|---|---|
| M6S 실전 피해 전체 (M6Q 호환 진입점) | 실제 Window, Input.action_press | EXIT 0. Raider/Boss 각각 J1~3 1+2+3 HP, Num4 3 HP, Num5 2 HP. 각 타격 1회. 좌우 120px 피해, J 전체/Num4/Num5 각각 후방·60px 깊이 초과·허공 미명중 PASS. 기존 활성 시간 유지. |
| M6S 저속 렌더 | 실제 Window, --max-fps 15, 최종 축소 리시버 | EXIT 0. 120px Raider/Boss 여섯 피해 사례 6/3/2 HP와 기존 미명중·활성 시간·1회 피해 검사 PASS. |
| M6R 접점 계약 | 실제 Window | EXIT 0. 실제 손/Shape 중심 오차 <0.1px, 작은 반경, 손 궤적 변화, 좌우 반전, 1회 피해, 깊이 거부, 소스 부재 시 비활성 PASS. |
| M6S 모션 | 실제 Window 순차 샘플 | EXIT 0. QA의 보행 실패 4건 해소. 세 공격 고유 원화, combo_hold의 비-IDLE/전신 단일 표시, 보행→공격 소유권, Num4/5 동작 구별 PASS. |
| M6T 본편 몸동작 | 실제 main scene Window + 실제 물리 이동 입력 | EXIT 0. 네 위상/발 교대/메시 접지/골반 상승 PASS. 이전/수정 상태 각각 30프레임 렌더링 비교. |
| M6Q 전신 단일 표시 | 실제 Window | EXIT 0. idle/각 공격 위상/복귀에 정확히 한 전신이 표시됨. 메시 자식의 실제 draw alpha를 계측하도록 보완. |
| M6O DEBUG 후보 preview | 실제 Window | EXIT 0. 기존 PNG 네 위상/분리 anchor/속도 연동/공격 handoff PASS. 승인 승격 없음. |
| M6P F10 Shape 픽셀 | 실제 Window | EXIT 0. Boss slash/slam/KO 캡슐 외곽 6/6, Player/스킬/Raider 외곽도 PASS. HP/충돌 상태 불변. F10 callback 경로 검사이며 OS 물리 키 입력 승인으로 주장하지 않음. |
| M6T 리시버 실루엣 | headless, 실제 원화 알파/Polygon2D 기하 | EXIT 0. Raider 48/48, Boss 외곽 108개 표본 내부. |
| M6I 콤보/스킬 상태 | headless | EXIT 0. 기본/스킬 활성 경계, 버퍼, 쿨다운, guard/피격 중단, 1회 피해 PASS. |
| M6N combo_hold 연결 | headless | EXIT 0. 기존 위상 시간, held pose, 1→2→3, 버퍼/guard/피격/KO 회귀 PASS. |
| M6D Boss AI/HUD | headless, 최종 Boss scene | EXIT 0. 비활성/활성, 추적, slash/slam의 실제 Player 피해, HUD, KO 1회 PASS. |
| AnimationBank | headless | EXIT 0. 승인/해시/manifest 게이트, 기존 등록/타이밍 및 대체 art 계약 PASS. |

주요 최종 로그는 `temp/high_damage_expanded_final.log`, `high_contact_final.log`, `high_motion_final.log`, `high_body_final.log`, `high_exclusivity_final.log`, `high_preview_final.log`, `high_f10_final.log`, `high_silhouette_final.log`이다. 저속 렌더 검사는 별도 `high_damage_15fps_final.log`를 사용한다.

최종 실전 겹침 표본 수는 Raider J123/Num4/Num5 = 18/4/9, Boss = 21/8/11이며 HP는 각각 20→14/17/18이다. 15 FPS 검사에서도 최종 축소 리시버로 동일 피해가 발생했다. M6R의 주먹점에 표적을 옮기는 fixture는 API 계약 검사로만 사용하고, 실전 명중 증명은 이 production 적 입력 게이트로 판단한다.

## Window 프레임 비교

[이전 기준 8e8148e](../../temp/high_body_before.png) / [수정 상태](../../temp/high_body_after.png). 행은 보행/J1/J2/J3/Num4/Num5, 각 행은 다섯 순차 위상이다. 기준 VisualAnimator는 `git show HEAD:...`로 읽어 임시 경로에서 실행했고 저장소/Git을 되돌리지 않았다. 전신 크기·회전뿐 아니라 발의 passing/교대와 J3 팔의 실제 내려감→올려치기가 구별된다. 코드를 함께 검토했으며 사람의 최종 육안 승인은 PENDING이다.

## 기준 및 한계

- 읽기 전용 대조에서 HEAD와 origin/main은 모두 8e8148e28d78b036c907588e2a9c254f6c0f3cd8이다. Git commit/push/reset/rebase 또는 .git 수정은 수행하지 않았다.
- 작업 시작부터 WORK 변경과 다수 미추적 import/uid/파일이 있었다. 범위 밖 파일은 정리·삭제하지 않았다. HIGH 추가 변경은 플레이어/리시버/F10 소스와 관련 게이트·기록에 한정한다.
- 피해 게이트는 실제 production scene의 combat_active 리시버를 사용하며 개별 피해를 격리하기 위해 상대 AI 이동을 정지한다. Boss AI의 활성 동작/실제 Player 피해는 별도 M6D에서 검증했다. 자유 전투 전체의 사람 수동 플레이와 최종 미술 승인으로 확대 해석하지 않는다.
- 기계적 게이트와 Window 프레임 비교를 통과해도 사람의 최종 육안 승인은 별도다. 새 PNG를 승인하거나 manifest/allowlist에 승격한 사실은 없다.
- Windows 인증서 저장소 읽기 오류가 로그에 남지만 스크립트 파싱/플레이어 생성/Window 렌더/종료 코드에는 실패가 없다. 전체 프로젝트 빌드 매니페스트가 없어 Godot 실행 게이트로 검증했다.
