extends SceneTree

const SOURCE := "res://assets/art/player/elven_fighter_attack_keyposes_v2_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack_keyposes_v2_relayout_1254x1254.png"
const CONTACT := "res://assets/art/review/player_keyposes_v2_relayout_contact.png"
const REFERENCE := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const SIZE := 1254
const CELL := 627
const MIN_MARGIN := 16
const ALPHA_THRESHOLD := 0.05
const MAX_FLOAT_AREA := 2500
const FLOAT_LARGEST_RATIO := 0.025

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := _load_png(SOURCE)
	var reference := _load_png(REFERENCE)
	if source == null or source.get_size() != Vector2i(SIZE, SIZE) or reference == null:
		printerr("v2 원본(1254×1254) 또는 v8 clean 비교 원화를 읽을 수 없습니다.")
		quit(2)
		return
	var source_bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(SOURCE))
	var cells: Array[Image] = []
	var stats: Array[Dictionary] = []
	var max_w := 0
	var max_h := 0
	for index in range(4):
		var cell := source.get_region(Rect2i((index % 2) * CELL, (index / 2) * CELL, CELL, CELL))
		var component_result := _remove_small_detached_components(cell)
		var bounds: Rect2i = _alpha_bounds(cell)
		if bounds.size.x <= 0:
			printerr("%d번 셀에 유효 alpha가 없습니다." % (index + 1))
			quit(1)
			return
		var touched := _touches_source_edge(bounds)
		var crop := cell.get_region(bounds)
		cells.append(crop)
		max_w = maxi(max_w, crop.get_width())
		max_h = maxi(max_h, crop.get_height())
		stats.append({"index": index, "bounds": bounds, "touches": touched, "components": component_result["components"], "component_areas": component_result["areas"], "removed": component_result["removed"], "removed_pixels": component_result["removed_pixels"], "crop": crop})
	var scale := minf(1.0, minf(float(CELL - MIN_MARGIN * 2) / max_w, float(CELL - MIN_MARGIN * 2) / max_h))
	var output := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var placed_feet: Array[int] = []
	for i in range(4):
		var crop: Image = cells[i]
		var w := maxi(1, int(floor(crop.get_width() * scale)))
		var h := maxi(1, int(floor(crop.get_height() * scale)))
		var fitted := crop.duplicate()
		if fitted.get_size() != Vector2i(w, h):
			fitted.resize(w, h, Image.INTERPOLATE_LANCZOS)
		var col := i % 2
		var row := i / 2
		var left := col * CELL + int(floor((CELL - w) * 0.5))
		var top := row * CELL + CELL - MIN_MARGIN - h
		output.blit_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(left, top))
		placed_feet.append((top + h - 1) % CELL)
	var output_abs := ProjectSettings.globalize_path(OUTPUT)
	var save_error := output.save_png(output_abs)
	if save_error != OK:
		printerr("relayout PNG 저장 실패: %s" % error_string(save_error))
		quit(1)
		return
	var candidate_bytes := FileAccess.get_file_as_bytes(output_abs)
	var candidate_contact := _build_comparison(source, output, reference, stats, scale, placed_feet)
	var contact_error := candidate_contact.save_png(ProjectSettings.globalize_path(CONTACT))
	if contact_error != OK:
		printerr("relayout contact 저장 실패: %s" % error_string(contact_error))
		quit(1)
		return
	print("source_preserved=%s" % str(source_bytes == FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(SOURCE))))
	print("candidate=%s; common_scale=%.6f; output=%s" % [OUTPUT, scale, str(output.get_size())])
	print("foot_baselines=%s; spread=%dpx; tolerance=2px" % [str(placed_feet), placed_feet.max() - placed_feet.min()])
	var all_clear := true
	for item in stats:
		print("cell_%d source_bounds=%s component_areas=%s removed_floats=%d removed_pixels=%d source_edge_contact=%s" % [item["index"] + 1, str(item["bounds"]), str(item["component_areas"]), item["removed"], item["removed_pixels"], str(item["touches"])])
		all_clear = all_clear and not item["touches"]
	print("source_edge_contact_unresolved=%s" % str(not all_clear))
	print("candidate_bytes=%d; contact=%s; 192px previews per pose: BEFORE / RELAYOUT / V8 CLEAN" % [candidate_bytes.size(), CONTACT])
	quit(0)

static func _remove_small_detached_components(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue := PackedInt32Array()
	var components: Array[Dictionary] = []
	for y in range(height):
		for x in range(width):
			var start := y * width + x
			if visited[start] != 0 or image.get_pixel(x, y).a < ALPHA_THRESHOLD:
				continue
			visited[start] = 1
			queue.clear()
			queue.append(start)
			var head := 0
			var min_x := x
			var min_y := y
			var max_x := x
			var max_y := y
			while head < queue.size():
				var point: int = queue[head]
				head += 1
				var px := point % width
				var py := point / width
				min_x = mini(min_x, px)
				min_y = mini(min_y, py)
				max_x = maxi(max_x, px)
				max_y = maxi(max_y, py)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oy == 0:
							continue
						var nx := px + ox
						var ny := py + oy
						if nx < 0 or nx >= width or ny < 0 or ny >= height:
							continue
						var neighbor := ny * width + nx
						if visited[neighbor] == 0 and image.get_pixel(nx, ny).a >= ALPHA_THRESHOLD:
							visited[neighbor] = 1
							queue.append(neighbor)
			components.append({"area": queue.size(), "bounds": Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1), "pixels": queue.duplicate()})
	var largest := 0
	for component in components:
		largest = maxi(largest, component["area"])
	var max_float := mini(MAX_FLOAT_AREA, int(largest * FLOAT_LARGEST_RATIO))
	var removed := 0
	var removed_pixels := 0
	for component in components:
		if component["area"] <= max_float:
			removed += 1
			removed_pixels += component["area"]
			for point in component["pixels"]:
				image.set_pixel(point % width, point / width, Color.TRANSPARENT)
	var areas: Array[int] = []
	for component in components:
		areas.append(component["area"])
	areas.sort()
	areas.reverse()
	return {"components": components.size(), "areas": areas, "removed": removed, "removed_pixels": removed_pixels}

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func _touches_source_edge(bounds: Rect2i) -> bool:
	return bounds.position.x <= 1 or bounds.position.y <= 1 or bounds.end.x >= CELL - 1 or bounds.end.y >= CELL - 1

static func _load_png(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _build_comparison(before: Image, after: Image, reference: Image, stats: Array[Dictionary], scale: float, feet: Array[int]) -> Image:
	var board := Image.create(1254, 600, false, Image.FORMAT_RGBA8)
	board.fill(Color("#20252b"))
	var labels := ["BEFORE", "RELAYOUT", "V8 CLEAN"]
	for i in range(4):
		var col := i % 2
		var row := i / 2
		var x0 := 8 + col * 623
		var y0 := 8 + row * 296
		board.fill_rect(Rect2i(x0, y0, 615, 288), Color("#303941"))
		for p in range(3):
			_draw_label(board, labels[p], Vector2i(x0 + 12 + p * 201, y0 + 22), Color("#e3e8eb"))
		var src_rect := Rect2i((i % 2) * CELL, (i / 2) * CELL, CELL, CELL)
		var old_cell := before.get_region(src_rect)
		var new_cell := after.get_region(src_rect)
		var old_bounds := _alpha_bounds(old_cell)
		var new_bounds := _alpha_bounds(new_cell)
		var ref_bounds := _alpha_bounds(reference)
		_draw_preview(board, old_cell.get_region(old_bounds), Vector2i(x0 + 8, y0 + 36))
		_draw_preview(board, new_cell.get_region(new_bounds), Vector2i(x0 + 209, y0 + 36))
		_draw_preview(board, reference.get_region(ref_bounds), Vector2i(x0 + 410, y0 + 36))
		board.fill_rect(Rect2i(x0 + 9, y0 + 235, 593, 1), Color("#69747d"))
		var item: Dictionary = stats[i]
		_draw_label(board, "SOURCE EDGE CONTACT" if item["touches"] else "NO SOURCE EDGE TOUCH", Vector2i(x0 + 12, y0 + 259), Color("#f2b66d") if item["touches"] else Color("#91d7a5"))
		_draw_label(board, "SCALE %.3f  FOOT %d" % [scale, feet[i] % CELL], Vector2i(x0 + 12, y0 + 282), Color("#dce3e8"))
	return board

static func _draw_preview(board: Image, sprite: Image, at: Vector2i) -> void:
	var box := Rect2i(at, Vector2i(192, 192))
	for y in range(box.position.y, box.end.y, 16):
		for x in range(box.position.x, box.end.x, 16):
			var dark := ((x - at.x) / 16 + (y - at.y) / 16) % 2 == 0
			board.fill_rect(Rect2i(x, y, 16, 16), Color("#899198") if dark else Color("#bec4c9"))
	if sprite.is_empty():
		return
	var scale := minf(192.0 / sprite.get_width(), 192.0 / sprite.get_height())
	var size := Vector2i(maxi(1, int(round(sprite.get_width() * scale))), maxi(1, int(round(sprite.get_height() * scale))))
	var fitted := sprite.duplicate()
	fitted.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	board.blend_rect(fitted, Rect2i(Vector2i.ZERO, size), at + (Vector2i(192, 192) - size) / 2)

static func _draw_label(image: Image, label: String, position: Vector2i, color: Color) -> void:
	var glyphs := {"A":["010","101","111","101","101"],"B":["110","101","110","101","110"],"C":["011","100","100","100","011"],"D":["110","101","101","101","110"],"E":["111","100","110","100","111"],"F":["111","100","110","100","100"],"G":["011","100","101","101","011"],"H":["101","101","111","101","101"],"I":["111","010","010","010","111"],"L":["100","100","100","100","111"],"M":["101","111","111","101","101"],"N":["101","111","111","111","101"],"O":["010","101","101","101","010"],"P":["110","101","110","100","100"],"R":["110","101","110","101","101"],"S":["011","100","010","001","110"],"T":["111","010","010","010","010"],"U":["101","101","101","101","111"],"V":["101","101","101","101","010"],"W":["101","101","101","111","101"],"Y":["101","101","010","010","010"],"8":["111","101","111","101","111"],"0":["111","101","101","101","111"],"1":["010","110","010","010","111"],"2":["110","001","010","100","111"],"3":["110","001","010","001","110"],"4":["101","101","111","001","001"],"5":["111","100","110","001","110"],"6":["011","100","110","101","010"],"9":["010","101","011","001","110"],".":["000","000","000","000","010"],"-":["000","000","111","000","000"]}
	var cursor := position.x
	for ch in label:
		if glyphs.has(ch):
			var rows: Array = glyphs[ch]
			for gy in range(rows.size()):
				for gx in range(rows[gy].length()):
					if rows[gy].substr(gx, 1) == "1":
						image.fill_rect(Rect2i(cursor + gx * 2, position.y - 10 + gy * 2, 2, 2), color)
		cursor += 8
