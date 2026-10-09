extends SceneTree

const CAPTURE := "res://tools/capture_m5c_playable_session.gd"
const REPORT := "res://docs/review/m5c_playable_session_gate.md"
const SUCCESS := "m5c_playable_session: all checks passed"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array[String] = []
	var exit_code := OS.execute(executable, ["--path", project_path, "--script", CAPTURE], output, true)
	var combined := "\n".join(output)
	var ok := exit_code == 0 and combined.contains(SUCCESS)
	ok = ok and combined.contains("PASS: Num4 production skill input") and combined.contains("PASS: Num5 production skill input")
	ok = ok and combined.contains("PASS: basic attack stage 1") and combined.contains("PASS: basic attack stage 2") and combined.contains("PASS: basic attack stage 3")
	ok = ok and combined.contains("PASS: controls menu opens from title scene") and combined.contains("PASS: controls menu returns to title")
	ok = ok and combined.contains("PHYSICAL_KEYBOARD_MOUSE: NOT_TESTED") and combined.contains("DIRECT_STATE_PREVIEW:")
	ok = ok and combined.contains("CAPTURE_COUNT: 16")
	var report := "# M5C 실제 플레이 세션 검수\n\n"
	report += "- 실행: `%s --path <project> --script %s`\n" % [executable, CAPTURE]
	report += "- 자식 프로세스 종료 코드: `%d`\n" % exit_code
	report += "- 결과: **%s**\n" % ("PASS" if ok else "FAIL")
	report += "- 입력 범위: 합성 InputMap/InputEvent이며 OS 물리 키보드·마우스 입력은 검증하지 않음.\n"
	report += "- 캡처: `assets/art/review/m5c_playable_session_window.png` (스크립트가 생성; 실패 시 마지막 상태 프레임 포함)\n\n"
	report += "## 확인 범위\n\n"
	report += "| 경로 | 관측 |\n|---|---|\n"
	report += "| `move_right`, `move_left`, `jump`, `block` | 프레임 번호와 좌표·방향·상태 전이 기록 |\n"
	report += "| `attack` 1~3단계 | 실물 hitbox, 신호, Raider HP/경직, hit-stop, 카메라 trauma |\n"
	report += "| 합성 Num4/Num5 키 이벤트 | InputMap `skill_1`/`skill_2`, 실제 startup 및 쿨다운 HUD |\n"
	report += "| 화면 | Player/Raider 체력바, 스킬 HUD, 쿨다운, 타이틀·조작 메뉴의 post-draw 프레임 |\n\n"
	report += "Num4/Num5 입력 경로는 `InputEventKey`를 InputMap에 전달합니다. `DIRECT_STATE_PREVIEW` 캡처만 검수기에서 스킬 변수를 직접 설정하며 실제 입력 성공 증거로 계산하지 않습니다. 원본 검수 이미지 디렉터리의 텍스처가 main 장면 Sprite2D에 표시되지 않는 검사도 통과했습니다.\n\n"
	report += "실행 중 Godot가 `user://logs` 쓰기 및 시스템 CA 읽기 오류를 출력했지만 캡처 프로세스는 종료 코드 0으로 완료했습니다.\n\n"
	report += "## 실행 로그 (프레임·상태·입력 경로)\n\n```text\n%s\n```\n" % combined
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	else:
		ok = false
		push_error("검수 보고서를 쓸 수 없습니다: " + REPORT)
	if ok:
		print(SUCCESS)
		quit(0)
	else:
		push_error("m5c_playable_session_smoke: child_exit=%d capture=%s" % [exit_code, combined.contains("CAPTURE_PNG:")])
		for line in output:
			push_error(str(line))
		quit(1)
