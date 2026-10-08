extends SceneTree

const DEFAULT_IMAGE := "res://assets/art/player/elven_fighter_reference_v1_1254x1254.png"
const EXPECTED_SIZE := 1254
const REQUIRED_MARGIN := 90
const PREVIEW_SIZE := 165
const ZOOM_SIZE := 600

var _image_path := DEFAULT_IMAGE

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var check_only := args.has("--check")
	for arg in args:
		if not arg.begins_with("--"):
			_image_path = arg
			break
	if _image_path.begins_with("res://"):
		_image_path = ProjectSettings.globalize_path(_image_path)
	elif not _image_path.is_absolute_path():
		_image_path = ProjectSettings.globalize_path("res://") + "/" + _image_path

	var result := _inspect_png(_image_path)
	_print_report(result)
	if check_only:
		quit(0 if result.get("passed", false) else 1)
		return
	_show_review(result)

static func _inspect_png(path: String) -> Dictionary:
	var result := {"path": path, "passed": false, "errors": [], "width": 0, "height": 0,
		"has_alpha": false, "has_transparent": false, "bounds": Rect2i()}
	if not FileAccess.file_exists(path):
		result.errors.append("이미지 파일을 찾을 수 없습니다.")
		return result
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		result.errors.append("올바른 PNG 시그니처가 아닙니다.")
		return result

	var width := _u32be(bytes, 16)
	var height := _u32be(bytes, 20)
	var bit_depth := int(bytes[24])
	var color_type := int(bytes[25])
	var interlace := int(bytes[28])
	result.width = width
	result.height = height
	if width <= 0 or height <= 0 or width > 16384 or height > 16384:
		result.errors.append("PNG 크기가 유효하지 않습니다.")
		return result
	if width != EXPECTED_SIZE or height != EXPECTED_SIZE:
		result.errors.append("실제 크기가 %dx%d가 아닙니다 (%dx%d)." % [EXPECTED_SIZE, EXPECTED_SIZE, width, height])
		return result
	if interlace != 0:
		result.errors.append("인터레이스 PNG는 현재 검수기가 지원하지 않습니다.")
		return result
	var channels_by_type := {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
	if not channels_by_type.has(color_type):
		result.errors.append("지원하지 않는 PNG 색상 형식 또는 비트 깊이입니다.")
		return result
	if color_type == 0 and not [1, 2, 4, 8, 16].has(bit_depth):
		result.errors.append("그레이스케일 PNG 비트 깊이가 유효하지 않습니다.")
		return result
	if (color_type == 2 or color_type == 4 or color_type == 6) and not [8, 16].has(bit_depth):
		result.errors.append("색상 형식에 맞지 않는 비트 깊이입니다.")
		return result
	if color_type == 3 and not [1, 2, 4, 8].has(bit_depth):
		result.errors.append("인덱스 색상 PNG 비트 깊이가 유효하지 않습니다.")
		return result

	var palette := PackedByteArray()
	var transparency := PackedByteArray()
	var compressed := PackedByteArray()
	var offset := 8
	var saw_end := false
	while offset + 12 <= bytes.size():
		var chunk_length := _u32be(bytes, offset)
		if chunk_length > bytes.size() - offset - 12:
			result.errors.append("PNG 청크 길이가 파일 범위를 벗어납니다.")
			return result
		var chunk_type := bytes.slice(offset + 4, offset + 8).get_string_from_ascii()
		var chunk_data := bytes.slice(offset + 8, offset + 8 + chunk_length)
		match chunk_type:
			"PLTE": palette = chunk_data
			"tRNS": transparency = chunk_data
			"IDAT": compressed.append_array(chunk_data)
			"IEND":
				saw_end = true
				break
		offset += chunk_length + 12
	if not saw_end or compressed.is_empty():
		result.errors.append("PNG 이미지 데이터가 불완전합니다.")
		return result
	if color_type == 3 and palette.is_empty():
		result.errors.append("인덱스 PNG에 팔레트가 없습니다.")
		return result

	var channels: int = channels_by_type[color_type]
	var bits_per_pixel := channels * bit_depth
	var row_bytes := int((width * bits_per_pixel + 7) / 8)
	var expected_bytes := (row_bytes + 1) * height
	var raw := compressed.decompress_dynamic(expected_bytes, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty() or raw.size() != expected_bytes:
		result.errors.append("PNG 압축 데이터를 예상 크기로 해제하지 못했습니다.")
		return result
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)
	var previous := PackedByteArray()
	previous.resize(row_bytes)
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	var transparent_found := false
	var filter_bpp := maxi(1, int((bits_per_pixel + 7) / 8))
	for y in range(height):
		var row_start := y * (row_bytes + 1)
		var filter := int(raw[row_start])
		var row := raw.slice(row_start + 1, row_start + 1 + row_bytes)
		if not _unfilter_row(row, previous, filter_bpp, filter):
			result.errors.append("지원하지 않거나 손상된 PNG 행 필터입니다.")
			return result
		for x in range(width):
			var sample_index := x * channels
			var red := 0
			var green := 0
			var blue := 0
			var alpha := 255
			if color_type == 0:
				var gray := _sample(row, x, bit_depth)
				red = gray
				green = gray
				blue = gray
				if transparency.size() >= 2 and gray == _u16be(transparency, 0):
					alpha = 0
			elif color_type == 2:
				var r16 := _sample(row, sample_index, bit_depth)
				var g16 := _sample(row, sample_index + 1, bit_depth)
				var b16 := _sample(row, sample_index + 2, bit_depth)
				red = _to_byte(r16, bit_depth)
				green = _to_byte(g16, bit_depth)
				blue = _to_byte(b16, bit_depth)
				if transparency.size() >= 6 and r16 == _u16be(transparency, 0) and g16 == _u16be(transparency, 2) and b16 == _u16be(transparency, 4):
					alpha = 0
			elif color_type == 3:
				var palette_index := _sample(row, x, bit_depth)
				if palette_index * 3 + 2 >= palette.size():
					result.errors.append("팔레트 인덱스가 팔레트 범위를 벗어납니다.")
					return result
				red = int(palette[palette_index * 3])
				green = int(palette[palette_index * 3 + 1])
				blue = int(palette[palette_index * 3 + 2])
				if palette_index < transparency.size():
					alpha = int(transparency[palette_index])
			elif color_type == 4:
				var gray4 := _sample(row, sample_index, bit_depth)
				red = _to_byte(gray4, bit_depth)
				green = red
				blue = red
				alpha = _to_byte(_sample(row, sample_index + 1, bit_depth), bit_depth)
			else:
				red = _to_byte(_sample(row, sample_index, bit_depth), bit_depth)
				green = _to_byte(_sample(row, sample_index + 1, bit_depth), bit_depth)
				blue = _to_byte(_sample(row, sample_index + 2, bit_depth), bit_depth)
				alpha = _to_byte(_sample(row, sample_index + 3, bit_depth), bit_depth)
			if alpha == 0:
				transparent_found = true
			else:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
			var p := (y * width + x) * 4
			pixels[p] = red
			pixels[p + 1] = green
			pixels[p + 2] = blue
			pixels[p + 3] = alpha
		previous = row

	var has_alpha := color_type == 4 or color_type == 6 or (color_type == 3 and not transparency.is_empty()) or (color_type == 0 or color_type == 2) and not transparency.is_empty()
	result.has_alpha = has_alpha
	result.has_transparent = transparent_found
	result["pixels"] = pixels
	if max_x < 0:
		result.errors.append("비투명 픽셀이 없습니다.")
		return result
	var bounds := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	result.bounds = bounds
	if not has_alpha or not transparent_found:
		result.errors.append("투명 알파 픽셀이 필요합니다.")
	if min_x < REQUIRED_MARGIN or min_y < REQUIRED_MARGIN or width - 1 - max_x < REQUIRED_MARGIN or height - 1 - max_y < REQUIRED_MARGIN:
		result.errors.append("비투명 영역 사방에 최소 %dpx 여백이 필요합니다." % REQUIRED_MARGIN)
	result.passed = result.errors.is_empty() and width == EXPECTED_SIZE and height == EXPECTED_SIZE
	return result

static func _unfilter_row(row: PackedByteArray, previous: PackedByteArray, bpp: int, filter: int) -> bool:
	if filter < 0 or filter > 4:
		return false
	for i in range(row.size()):
		var left := int(row[i - bpp]) if i >= bpp else 0
		var up := int(previous[i])
		var upper_left := int(previous[i - bpp]) if i >= bpp else 0
		var predictor := 0
		match filter:
			1: predictor = left
			2: predictor = up
			3: predictor = (left + up) >> 1
			4: predictor = _paeth(left, up, upper_left)
		row[i] = (int(row[i]) + predictor) & 255
	return true

static func _sample(row: PackedByteArray, sample_index: int, depth: int) -> int:
	if depth == 8:
		return int(row[sample_index])
	if depth == 16:
		return (int(row[sample_index * 2]) << 8) | int(row[sample_index * 2 + 1])
	var bit_offset := sample_index * depth
	var shift := 8 - depth - (bit_offset % 8)
	return (int(row[int(bit_offset / 8)]) >> shift) & ((1 << depth) - 1)

static func _to_byte(value: int, depth: int) -> int:
	if depth == 16: return value >> 8
	if depth == 8: return value
	return int(round(value * 255.0 / ((1 << depth) - 1)))

static func _paeth(a: int, b: int, c: int) -> int:
	var p := a + b - c
	var pa := absi(p - a)
	var pb := absi(p - b)
	var pc := absi(p - c)
	if pa <= pb and pa <= pc: return a
	if pb <= pc: return b
	return c

static func _u32be(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

static func _u16be(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 8) | int(bytes[offset + 1])

func _print_report(result: Dictionary) -> void:
	print("art-review: %s" % ("PASS" if result.passed else "FAIL"))
	print("image: %s" % result.path)
	if result.width > 0:
		print("size: %dx%d" % [result.width, result.height])
	if result.bounds.size.x > 0:
		var b: Rect2i = result.bounds
		print("opaque_bounds: x=%d y=%d w=%d h=%d; margins L=%d T=%d R=%d B=%d" % [b.position.x, b.position.y, b.size.x, b.size.y, b.position.x, b.position.y, result.width - b.end.x, result.height - b.end.y])
	print("transparent_alpha: %s" % ("yes" if result.get("has_alpha", false) and result.get("has_transparent", false) else "no"))
	for error in result.errors:
		push_error("art-review: " + error)

func _show_review(result: Dictionary) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scroll)
	var ui := Control.new()
	ui.custom_minimum_size = Vector2(1400, 920)
	scroll.add_child(ui)
	var title := Label.new()
	title.text = "플레이어 PNG 원화 검수"
	title.position = Vector2(40, 24)
	title.add_theme_font_size_override("font_size", 28)
	ui.add_child(title)
	var status := Label.new()
	status.text = "기계 검사: %s    시각적 최종 승인: 검토자 확인 필요" % ("통과" if result.passed else "실패")
	status.position = Vector2(40, 70)
	status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.58) if result.passed else Color(1.0, 0.48, 0.42))
	status.add_theme_font_size_override("font_size", 20)
	ui.add_child(status)
	var path_label := Label.new()
	path_label.text = result.path
	path_label.position = Vector2(40, 106)
	ui.add_child(path_label)
	if result.has("pixels"):
		var image := Image.create_from_data(result.width, result.height, false, Image.FORMAT_RGBA8, result.pixels)
		var bounds: Rect2i = result.bounds
		var silhouette := image.get_region(bounds)
		var sprite_165 := _resize_silhouette(silhouette, PREVIEW_SIZE)
		var sprite_600 := _resize_silhouette(silhouette, ZOOM_SIZE)
		_add_preview(ui, ImageTexture.create_from_image(image), Vector2(40, 190), Vector2(380, 380), "전체 원화 · 투명 체커보드 · %d × %d" % [result.width, result.height])
		_add_preview(ui, ImageTexture.create_from_image(sprite_165), Vector2(460, 250), Vector2(sprite_165.get_width(), PREVIEW_SIZE), "비투명 실루엣 높이 정확히 %dpx · 발끝 기준선" % PREVIEW_SIZE, true)
		_add_preview(ui, ImageTexture.create_from_image(sprite_600), Vector2(680, 220), Vector2(sprite_600.get_width(), ZOOM_SIZE), "확대 보기 · 비투명 실루엣 높이 %dpx · 얼굴/귀/손발/색 번짐 확인" % ZOOM_SIZE, true)
		var bounds_label := Label.new()
		bounds_label.text = "알파 경계 x=%d y=%d w=%d h=%d  |  원본 캔버스 축소가 아닌 비투명 픽셀 경계 기준" % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
		bounds_label.position = Vector2(40, 640)
		ui.add_child(bounds_label)
	else:
		var details := Label.new()
		details.text = "\n".join(result.errors)
		details.position = Vector2(60, 190)
		ui.add_child(details)
	var hint := Label.new()
	hint.text = "발끝을 공통 기준선에 맞췄습니다. 기계 검사 통과와 별개로 검수자가 시각적 최종 승인을 판단하세요."
	hint.position = Vector2(40, 680)
	ui.add_child(hint)

func _add_preview(parent: Control, texture: Texture2D, position: Vector2, size: Vector2, caption: String, show_foot_baseline := false) -> void:
	var label := Label.new()
	label.text = caption
	label.position = position - Vector2(0, 28)
	parent.add_child(label)
	var checker := Checkerboard.new()
	checker.position = position
	checker.size = size
	parent.add_child(checker)
	var preview := TextureRect.new()
	preview.position = position
	preview.size = size
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(preview)
	if show_foot_baseline:
		var baseline := ColorRect.new()
		baseline.position = Vector2(position.x, position.y + size.y - 2)
		baseline.size = Vector2(size.x, 2)
		baseline.color = Color(1.0, 0.28, 0.18, 0.95)
		parent.add_child(baseline)

func _resize_silhouette(source: Image, target_height: int) -> Image:
	var target_width := maxi(1, int(round(float(source.get_width()) * target_height / source.get_height())))
	var resized := source.duplicate()
	resized.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	return resized

class Checkerboard:
	extends Control
	const TILE := 16
	func _draw() -> void:
		var columns := int(ceil(size.x / TILE))
		var rows := int(ceil(size.y / TILE))
		for y in range(rows):
			for x in range(columns):
				var shade := Color(0.31, 0.33, 0.36) if (x + y) % 2 == 0 else Color(0.20, 0.22, 0.25)
				draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), shade)
