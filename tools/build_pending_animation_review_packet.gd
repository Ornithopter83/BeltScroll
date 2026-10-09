extends SceneTree
"""Builds a visual-only animation review packet; it never edits approval data."""

const OUTPUT := "res://assets/art/review/pending_animation_review_packet.png"
const PLAYER_DIR := "res://assets/art/player/"
const PAGE_SIZE := Vector2i(3160, 5000)
const CARD_SIZE := Vector2i(1500, 780)
const COLS := 2

const ITEMS := [
	{"id":"idle_v8", "title":"기준 · 승인 idle v8", "source":"elven_fighter_reference_v8_clean_candidate_1254x1254.png", "safe":"elven_fighter_reference_v8_safe_1254x1254.png", "status":"기존 승인 정지 원화 · 애니메이션 시퀀스 아님", "kind":"reference"},
	{"id":"attack1_contact", "title":"기준 · 승인 attack1 contact", "source":"elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png", "status":"기존 승인 접촉 1/3 · 0.105 s", "kind":"approved"},
	{"id":"attack2_contact", "title":"기준 · 승인 attack2 contact", "source":"elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png", "status":"기존 승인 접촉 2/3 · 0.120 s", "kind":"approved"},
	{"id":"attack3_contact", "title":"기준 · 승인 attack3 contact", "source":"elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png", "status":"기존 승인 접촉 3/3 · 0.140 s", "kind":"approved"},
	{"id":"attack1_startup", "title":"미승인 후보 · attack1 startup", "source":"elven_fighter_attack1_startup_v1_candidate_1254x1254.png", "safe":"elven_fighter_attack1_startup_v1_safe_candidate_1254x1254.png", "status":"전환·실루엣·잘림·identity 검토", "kind":"candidate"},
	{"id":"attack3_startup", "title":"미승인 후보 · attack3 startup", "source":"elven_fighter_attack3_startup_v1_candidate_1254x1254.png", "safe":"elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png", "status":"전환·실루엣·잘림·identity 검토", "kind":"candidate"},
	{"id":"run_v1", "title":"미승인 후보 · run stride v1", "source":"elven_fighter_run_stride_v1_candidate_1254x1254.png", "safe":"elven_fighter_run_stride_v1_safe_candidate_1254x1254.png", "status":"지지발 후보·좌우 주기·identity 검토", "kind":"candidate"},
	{"id":"run_v2", "title":"미승인 후보 · run stride v2 opposite", "source":"elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png", "safe":"elven_fighter_run_stride_v2_safe_candidate_1254x1254.png", "status":"v1 반대 위상 후보 · 지지발·전환 검토", "kind":"candidate"},
	{"id":"run_v3", "title":"미승인 후보 · run stride v3 left lead", "source":"elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png", "status":"v1/v2와 위상·좌우 미러 검토", "kind":"candidate"},
	{"id":"jump_rise", "title":"미승인 후보 · jump rise", "source":"elven_fighter_jump_rise_v1_candidate_1254x1254.png", "safe":"elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png", "status":"도약/상승 전환·발 이탈·잘림 검토", "kind":"candidate"},
	{"id":"num4_skill1", "title":"미승인 후보 · Num4 전방 돌진 접촉", "source":"elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png", "safe":"elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png", "status":"skill1 접촉·방향·잘림·identity 검토", "kind":"candidate"}
]

var _errors: Array[String] = []
var _baseline_anchor := Vector2.ZERO

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var output := OUTPUT if args.is_empty() else args[0]
	if args.size() > 1:
		_fail("사용법: godot --headless --path . --script res://tools/build_pending_animation_review_packet.gd [output.png]")
		return
	var visible_items: Array[Dictionary] = []
	for item in ITEMS:
		if _exists(str(item.source)):
			visible_items.append(item)
		else:
			_errors.append("필수 이미지 누락: " + str(item.source))
	var optional_v4 := PLAYER_DIR + "elven_fighter_reference_v4_1254x1254.png"
	if FileAccess.file_exists(optional_v4):
		visible_items.append({"id":"optional_v4", "title":"선택 비교 · v4 (파일 존재로만 포함)", "source":"elven_fighter_reference_v4_1254x1254.png", "safe":"elven_fighter_reference_v4_safe_1254x1254.png", "status":"비교용 원화 · 승인 또는 후보 판정 아님", "kind":"reference"})
	if not _errors.is_empty():
		_fail("; ".join(_errors))
		return
	var baseline_image := _load_image("elven_fighter_reference_v8_clean_candidate_1254x1254.png")
	_baseline_anchor = _alpha_anchor(baseline_image, _alpha_bounds(baseline_image))
	var svg := _build_svg(visible_items)
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK or image.get_size() != PAGE_SIZE:
		_fail("SVG에서 검수 패킷 이미지 생성 실패: " + str(image.get_size()))
		return
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		_fail("패킷 PNG 저장 실패: " + error_string(err))
		return
	var annotation_status := _annotate_png(absolute, visible_items)
	if annotation_status != 0:
		_fail("PowerShell 한글 라벨 합성 실패 (exit %d)" % annotation_status)
		return
	print("pending_animation_review_packet: saved %dx%d; human review required; registry unchanged" % [PAGE_SIZE.x, PAGE_SIZE.y])
	quit(0)

func _build_svg(items: Array[Dictionary]) -> String:
	var result := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><rect width="100%%" height="100%%" fill="#101820"/>' % [PAGE_SIZE.x, PAGE_SIZE.y, PAGE_SIZE.x, PAGE_SIZE.y]
	result += _svg_text("플레이어 애니메이션 원화 검수 패킷", 32, 54, 38, "#f3e3b2")
	result += _svg_text("사람 검수 전용 · 자동 생성물은 승인 기록이 아님 · 신규 승인 0건", 36, 96, 21, "#ffca78")
	result += _svg_text("기준 4장(v8 + 승인 접촉 3장) / 미승인 후보 7장 · 원본 / safe / 192px 표시 / 3배 확대 / 좌우 미러", 36, 130, 18, "#d1dfdf")
	result += _svg_text("표식: alpha 하단 중앙 추정점(+) · 기준 대비 anchor 차이는 수치로만 표시 · 실제 지지발 판정은 검수자가 기입", 36, 160, 18, "#b7c8c8")
	for index in range(items.size()):
		result += _svg_card(items[index], index)
	return result + "</svg>"

func _svg_card(spec: Dictionary, index: int) -> String:
	var x := 24 + (index % COLS) * 1520
	var y := 185 + (index / COLS) * 796
	var out := '<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="%s"/>' % [x, y, CARD_SIZE.x, CARD_SIZE.y, "#203039" if index % 2 == 0 else "#26383e"]
	var head := "#9be1bd" if spec.kind == "approved" or spec.kind == "reference" else "#ffbd79"
	out += _svg_text(str(spec.title), x + 18, y + 34, 23, head)
	out += _svg_text(str(spec.status), x + 20, y + 59, 16, "#d1dcda")
	var original := _load_image(str(spec.source))
	var safe := original
	var safe_name := "safe 없음 · 원본 재표시"
	if spec.has("safe") and _exists(str(spec.safe)):
		safe_name = str(spec.safe).replace("elven_fighter_", "")
		safe = _load_image(str(spec.safe))
	if safe == null:
		safe = original
	var bounds := _alpha_bounds(original)
	var safe_bounds := _alpha_bounds(safe)
	var anchor := _alpha_anchor(original, bounds)
	var safe_anchor := _alpha_anchor(safe, safe_bounds)
	var delta := (anchor - _baseline_anchor) * Vector2(original.get_size())
	out += _svg_text("원본 · " + str(spec.source).replace("elven_fighter_", ""), x + 18, y + 81, 12, "#a9bec0")
	out += _svg_text("safe · " + safe_name, x + 210, y + 81, 12, "#a9bec0")
	out += _svg_text("alpha 하단 중앙 추정 (%.4f, %.4f) · v8 대비 Δ(%.1f, %.1f)px · 원본↔safe Δ(%.1f, %.1f)px" % [anchor.x, anchor.y, delta.x, delta.y, (safe_anchor.x-anchor.x)*original.get_width(), (safe_anchor.y-anchor.y)*original.get_height()], x + 18, y + 105, 14, "#f0d68b")
	out += _svg_text("지지발(좌/우/양발/공중): ________   전환: ________   identity: ________   잘림/결손: ________", x + 18, y + 128, 14, "#e4e9df")
	var iy := y + 166
	out += _svg_image(original, x + 18, iy, 180, 180, 0, 0, false)
	out += _svg_image(safe, x + 210, iy, 180, 180, 0, 0, false)
	var game := _game_image(original, bounds, 192)
	var flip := game.duplicate(); flip.flip_x()
	out += _svg_image(game, x + 410, iy, 192, 192, 0.5, 0.94, true)
	out += _svg_image(flip, x + 618, iy, 192, 192, 0.5, 0.94, true)
	# Replace the nearest-neighbor game views with exact 3x presentation pixels.
	var game_data := _png_data_url(game)
	out += '<image href="%s" x="%d" y="%d" width="576" height="576" image-rendering="pixelated"/>' % [game_data, x + 826, iy]
	out += _svg_text("원본 전체 1254²", x + 18, iy - 5, 13, "#d9e5df")
	out += _svg_text("safe 전체", x + 210, iy - 5, 13, "#d9e5df")
	out += _svg_text("게임 표시 192px", x + 410, iy - 5, 13, "#d9e5df")
	out += _svg_text("좌우 미러 192px", x + 618, iy - 5, 13, "#d9e5df")
	out += _svg_text("192px × 3 (최근접 확대)", x + 826, iy - 5, 13, "#d9e5df")
	var marker_y := iy + 576 * 0.94
	out += '<path d="M%d %.1f h18 M%d %.1f v18" stroke="#e53935" stroke-width="3"/>' % [x + 826 + 288 - 9, marker_y, x + 826 + 288, marker_y - 9]
	out += _svg_text("실제 프레임 전환·identity·지지발·잘림은 사람이 시퀀스/게임 맥락에서 판정", x + 18, iy + 610, 14, "#d1dcda")
	out += _svg_text("판정: □ 수용  □ 수정  □ 반려     검수자: __________  일시: __________  근거: __________________________", x + 18, iy + 635, 14, "#ffffff")
	return out

func _svg_image(image: Image, x: int, y: int, w: int, h: int, mark_x: float, mark_y: float, show_mark: bool) -> String:
	var out := '<rect x="%d" y="%d" width="%d" height="%d" fill="#e8e5da"/>' % [x, y, w, h]
	out += '<image href="%s" x="%d" y="%d" width="%d" height="%d" preserveAspectRatio="xMidYMid meet"/>' % [_png_data_url(image), x, y, w, h]
	if show_mark:
		var mx := x + w * mark_x
		var my := y + h * mark_y
		out += '<path d="M%.1f %.1f h14 M%.1f %.1f v14" stroke="#e53935" stroke-width="2"/>' % [mx - 7, my, mx, my - 7]
	return out

func _svg_text(value: String, x: int, y: int, size: int, color: String) -> String:
	return ""

func _png_data_url(image: Image) -> String:
	return "data:image/png;base64," + Marshalls.raw_to_base64(image.save_png_to_buffer())

func _annotate_png(path: String, items: Array[Dictionary]) -> int:
	var quoted_path := path.replace("'", "''")
	var commands := PackedStringArray()
	commands.append("Add-Type -AssemblyName System.Drawing")
	commands.append("$src = [System.Drawing.Image]::FromFile('%s')" % quoted_path)
	commands.append("$bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)")
	commands.append("$g = [System.Drawing.Graphics]::FromImage($bmp)")
	commands.append("$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit")
	commands.append("$g.DrawImage($src, [single]0, [single]0, [single]$src.Width, [single]$src.Height)")
	commands.append("$f = [System.Drawing.Font]::new('Malgun Gothic', 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)")
	commands.append("$fb = [System.Drawing.Font]::new('Malgun Gothic', 30, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)")
	commands.append("$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 235, 241, 235))")
	commands.append("$gold = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 240, 214, 139))")
	commands.append("$green = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 155, 225, 189))")
	commands.append("$orange = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 189, 121))")
	commands.append("$g.DrawString('플레이어 애니메이션 원화 검수 패킷', $fb, $gold, [single]32, [single]18)")
	commands.append("$g.DrawString('사람 검수 전용 · 자동 생성물은 승인 기록이 아님 · 신규 승인 0건', $f, $orange, [single]36, [single]64)")
	commands.append("$g.DrawString('기준 4장(v8 + 승인 접촉 3장) / 미승인 후보 7장 · 원본 / safe / 192px 표시 / 3배 확대 / 좌우 미러', $f, $white, [single]36, [single]100)")
	commands.append("$g.DrawString('alpha 하단 중앙(+)은 바운드 추정치 · 지지발 및 동작 연속성은 검수자가 판정', $f, $white, [single]36, [single]130)")
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var x := 24 + (i % COLS) * 1520
		var y := 185 + (i / COLS) * 796
		var original_image := _load_image(str(item.source))
		var safe_image := _load_image(str(item.safe)) if item.has("safe") and _exists(str(item.safe)) else original_image
		var anchor := _alpha_anchor(original_image, _alpha_bounds(original_image))
		var safe_anchor := _alpha_anchor(safe_image, _alpha_bounds(safe_image))
		var delta := (anchor - _baseline_anchor) * Vector2(original_image.get_size())
		var safe_delta := (safe_anchor - anchor) * Vector2(original_image.get_size())
		var color_name := "$green" if item.kind == "approved" or item.kind == "reference" else "$orange"
		commands.append("$g.DrawString('%s', $fb, %s, [single]%d, [single]%d)" % [_ps_quote(str(item.title)), color_name, x + 18, y + 10])
		commands.append("$g.DrawString('%s', $f, $white, [single]%d, [single]%d)" % [_ps_quote(str(item.status)), x + 20, y + 39])
		var safe_label := "(safe 없음 · 원본 반복)" if not item.has("safe") or not _exists(str(item.safe)) else str(item.safe).replace("elven_fighter_", "")
		commands.append("$g.DrawString('원본: %s', $f, $white, [single]%d, [single]%d)" % [_ps_quote(str(item.source).replace("elven_fighter_", "")), x + 18, y + 62])
		commands.append("$g.DrawString('safe: %s', $f, $white, [single]%d, [single]%d)" % [_ps_quote(safe_label), x + 18, y + 81])
		var anchor_line := "alpha 추정 (%.4f, %.4f) · v8 Δ(%.1f, %.1f)px · 원본↔safe Δ(%.1f, %.1f)px" % [anchor.x, anchor.y, delta.x, delta.y, safe_delta.x, safe_delta.y]
		commands.append("$g.DrawString('%s', $f, $gold, [single]%d, [single]%d)" % [_ps_quote(anchor_line), x + 18, y + 102])
		commands.append("$g.DrawString('지지발(좌/우/양발/공중): ______  전환: ______  identity: ______  잘림: ______', $f, $white, [single]%d, [single]%d)" % [x + 18, y + 122])
		var iy := y + 166
		var captions := ["원본 전체 1254²", "safe 전체", "게임 표시 192px", "좌우 미러 192px", "192px × 3 최근접 확대"]
		var caption_x := [x + 18, x + 210, x + 410, x + 618, x + 826]
		for c in range(captions.size()):
			commands.append("$g.DrawString('%s', $f, $white, [single]%d, [single]%d)" % [captions[c], caption_x[c], iy - 20])
		commands.append("$g.DrawString('실제 전환·identity·지지발·잘림은 사람이 시퀀스/게임 맥락에서 판정', $f, $white, [single]%d, [single]%d)" % [x + 18, iy + 582])
		commands.append("$g.DrawString('판정: □ 수용  □ 수정  □ 반려   검수자: ________  일시: ________  근거: __________________', $f, $white, [single]%d, [single]%d)" % [x + 18, iy + 606])
	commands.append("$src.Dispose(); $g.Dispose(); $bmp.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()" % quoted_path)
	var output: Array = []
	return OS.execute("powershell.exe", ["-NoProfile", "-Command", "\n".join(commands)], output, true)

func _ps_quote(value: String) -> String:
	return value.replace("'", "''")

func _game_image(source: Image, bounds: Rect2i, target: int) -> Image:
	var cropped := source.get_region(bounds)
	var scale := minf(float(target) / bounds.size.x, float(target) / bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	cropped.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(target, target, false, Image.FORMAT_RGBA8)
	out.fill(Color.TRANSPARENT)
	out.blit_rect(cropped, Rect2i(Vector2i.ZERO, fitted), (Vector2i(target, target) - fitted) / 2)
	return out

func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	var bytes := image.get_data()
	var stride := image.get_width() * 4
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if bytes[y * stride + x * 4 + 3] > 2:
				min_x = mini(min_x, x); min_y = mini(min_y, y)
				max_x = maxi(max_x, x); max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _alpha_anchor(image: Image, bounds: Rect2i) -> Vector2:
	if bounds.size.x <= 0:
		return Vector2.ZERO
	return Vector2((float(bounds.position.x) + float(bounds.size.x - 1) * 0.5) / image.get_width(), float(bounds.end.y - 1) / image.get_height())

func _load_image(path: String) -> Image:
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(PLAYER_DIR + path)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _exists(path: String) -> bool:
	return FileAccess.file_exists(PLAYER_DIR + path)

func _fail(message: String) -> void:
	push_error("pending_animation_review_packet: " + message)
	quit(1)
