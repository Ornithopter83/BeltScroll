extends SceneTree

const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const DEFAULT_SOURCE := "res://assets/art/player/elven_fighter_reference_v4_safe_1254x1254.png"
const DEFAULT_OUTPUT := "res://assets/art/player/elven_fighter_reference_v4_retouch_1254x1254.png"
const DEFAULT_REVIEW := "res://assets/art/review/player_v4_retouch_comparison.png"
const PANEL_SIZE := Vector2i(430, 445)

func _initialize() -> void:
    call_deferred("_run_cli")

func _run_cli() -> void:
    var args := OS.get_cmdline_user_args()
    if args.has("--help") or args.has("-h"):
        print("사용법: godot --headless --script res://tools/clean_player_art_fringe.gd [입력 PNG 출력 PNG 비교 PNG]")
        quit(0)
        return
    if args.size() != 0 and args.size() != 3:
        printerr("사용법: godot --headless --script res://tools/clean_player_art_fringe.gd [입력 PNG 출력 PNG 비교 PNG]")
        quit(2)
        return
    var source_path := _resolve_path(args[0] if args.size() == 3 else DEFAULT_SOURCE)
    var output_path := _resolve_path(args[1] if args.size() == 3 else DEFAULT_OUTPUT)
    var review_path := _resolve_path(args[2] if args.size() == 3 else DEFAULT_REVIEW)
    var error := retouch_file(source_path, output_path)
    if error != OK:
        printerr("player-art-fringe 실패: %s (%d)" % [error_string(error), error])
        quit(1)
        return
    error = build_comparison(source_path, output_path, review_path)
    if error != OK:
        printerr("player-art-fringe 비교 이미지 실패: %s (%d)" % [error_string(error), error])
        quit(1)
        return
    print("player-art-fringe: 후보 PNG 및 전후 비교 이미지 생성 완료")
    quit(0)

static func retouch_file(input_path: String, output_path: String) -> Error:
    if not FileAccess.file_exists(input_path):
        return ERR_FILE_NOT_FOUND
    if _canonical_path(input_path) == _canonical_path(output_path):
        return ERR_INVALID_PARAMETER
    var bytes := FileAccess.get_file_as_bytes(input_path)
    if not _has_png_signature(bytes):
        return ERR_FILE_UNRECOGNIZED
    var source := Image.new()
    var decode_error := source.load_png_from_buffer(bytes)
    if decode_error != OK or source.is_empty():
        return decode_error if decode_error != OK else ERR_FILE_CORRUPT
    if source.get_width() != TARGET_SIZE or source.get_height() != TARGET_SIZE:
        return ERR_INVALID_DATA
    if source.get_format() != Image.FORMAT_RGBA8:
        source.convert(Image.FORMAT_RGBA8)
    var result := retouch_image(source)
    var output: Image = result["image"]
    var output_dir := output_path.get_base_dir()
    if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
        var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
        if dir_error != OK:
            return dir_error
    return output.save_png(output_path)

# Only recolors chromatic outliers touching the alpha edge. Alpha and all pixel
# positions are preserved, so the silhouette and fine strands remain unchanged.
static func retouch_image(source: Image) -> Dictionary:
    var output := source.duplicate()
    var changed := 0
    for y in range(1, source.get_height() - 1):
        for x in range(1, source.get_width() - 1):
            var pixel := source.get_pixel(x, y)
            if pixel.a < 0.08 or not _is_fringe_hue(pixel):
                continue
            var touches_transparency := false
            var transparent_neighbors := 0
            for ny in range(maxi(0, y - 2), mini(source.get_height(), y + 3)):
                for nx in range(maxi(0, x - 2), mini(source.get_width(), x + 3)):
                    if nx == x and ny == y:
                        continue
                    if source.get_pixel(nx, ny).a < 0.03:
                        touches_transparency = true
                        transparent_neighbors += 1
            if not touches_transparency:
                continue

            var normal_sum := Vector3.ZERO
            var normal_weight := 0.0
            for ny in range(maxi(0, y - 4), mini(source.get_height(), y + 5)):
                for nx in range(maxi(0, x - 4), mini(source.get_width(), x + 5)):
                    if nx == x and ny == y:
                        continue
                    var neighbor := source.get_pixel(nx, ny)
                    if neighbor.a < 0.82 or _is_fringe_hue(neighbor):
                        continue
                    var distance := Vector2(float(nx - x), float(ny - y)).length()
                    var weight := neighbor.a / (distance * distance)
                    normal_sum += Vector3(neighbor.r, neighbor.g, neighbor.b) * weight
                    normal_weight += weight
            if normal_weight < 0.25:
                continue
            var local_color := normal_sum / normal_weight
            var distance_from_normal := Vector3(pixel.r, pixel.g, pixel.b).distance_to(local_color)
            # Genuine gold/skin/hair transitions are retained unless they are a
            # pronounced saturated color outlier against nearby opaque colors.
            if distance_from_normal < 0.34:
                continue
            var strength := clampf(0.88 + float(transparent_neighbors) * 0.02, 0.88, 0.96)
            var corrected := Color(
                lerpf(pixel.r, local_color.x, strength),
                lerpf(pixel.g, local_color.y, strength),
                lerpf(pixel.b, local_color.z, strength),
                pixel.a)
            output.set_pixel(x, y, corrected)
            changed += 1
    return {"image": output, "changed": changed}

static func build_comparison(before_path: String, after_path: String, output_path: String) -> Error:
    var before := _load_png(before_path)
    var after := _load_png(after_path)
    if before == null or after == null:
        return ERR_FILE_NOT_FOUND
    if before.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE) or after.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE):
        return ERR_INVALID_DATA
    var canvas := Image.create(1000, 1840, false, Image.FORMAT_RGBA8)
    canvas.fill(Color("#171b20"))
    var row_y := [40, 500, 960, 1420]
    var bar_colors := [Color("#e05b54"), Color("#69b8a2")]
    for row in range(4):
        for side in range(2):
            var x := 45 + side * 475
            canvas.fill_rect(Rect2i(x, row_y[row], 430, 5), bar_colors[side])
            _draw_checker(canvas, Rect2i(x, row_y[row] + 5, PANEL_SIZE.x, PANEL_SIZE.y - 5))
            var crop := _comparison_crop(before if side == 0 else after, row)
            var fitted := _fit(crop, Vector2i(PANEL_SIZE.x - 20, PANEL_SIZE.y - 20)) if row < 3 else crop
            var position := Vector2i(x + (PANEL_SIZE.x - fitted.get_width()) / 2,
                row_y[row] + 5 + (PANEL_SIZE.y - 5 - fitted.get_height()) / 2)
            canvas.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), position)
    var output_dir := output_path.get_base_dir()
    if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
        var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
        if dir_error != OK:
            return dir_error
    return canvas.save_png(output_path)

static func _comparison_crop(image: Image, row: int) -> Image:
    var bounds := _alpha_bounds(image)
    if row == 0:
        return image.get_region(bounds)
    if row == 1:
        return _crop_relative(image, bounds, Rect2(0.24, 0.00, 0.48, 0.30))
    if row == 2:
        return _crop_relative(image, bounds, Rect2(0.00, 0.00, 0.53, 0.44))
    var silhouette := image.get_region(bounds)
    var height := 192
    var width := maxi(1, int(round(float(silhouette.get_width()) * height / silhouette.get_height())))
    silhouette.resize(width, height, Image.INTERPOLATE_LANCZOS)
    return silhouette
static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
    var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
    var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
    var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
    var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
    var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
    return image.get_region(rect)
static func _fit(source: Image, target: Vector2i) -> Image:
    var scale := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
    var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
    var fitted := source.duplicate()
    if fitted.get_size() != size:
        fitted.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
    return fitted

static func _is_fringe_hue(color: Color) -> bool:
    if color.a < 0.08 or color.s < 0.56:
        return false
    var hue := color.h
    return hue < 0.045 or hue > 0.96 or (hue >= 0.085 and hue <= 0.155)

static func _load_png(path: String) -> Image:
    if not FileAccess.file_exists(path):
        return null
    var image := Image.new()
    if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
        return null
    if image.get_format() != Image.FORMAT_RGBA8:
        image.convert(Image.FORMAT_RGBA8)
    return image
static func _alpha_bounds(image: Image) -> Rect2i:
    var min_x := image.get_width()
    var min_y := image.get_height()
    var max_x := -1
    var max_y := -1
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            if image.get_pixel(x, y).a > 0.0:
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func _draw_checker(image: Image, rect: Rect2i) -> void:
    var tile := 20
    for y in range(rect.position.y, rect.end.y, tile):
        for x in range(rect.position.x, rect.end.x, tile):
            var shade := Color("#3d4247") if ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2 == 0 else Color("#292e33")
            image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), shade)

static func _has_png_signature(bytes: PackedByteArray) -> bool:
    var signature := [137, 80, 78, 71, 13, 10, 26, 10]
    if bytes.size() < signature.size():
        return false
    for index in range(signature.size()):
        if bytes[index] != signature[index]:
            return false
    return true

static func _canonical_path(path: String) -> String:
    var resolved := path
    if path.begins_with("res://") or path.begins_with("user://"):
        resolved = ProjectSettings.globalize_path(path)
    elif not path.is_absolute_path():
        resolved = ProjectSettings.globalize_path("res://" + path)
    return resolved.replace("\\", "/").simplify_path().to_lower()

func _resolve_path(path: String) -> String:
    if path.begins_with("res://") or path.begins_with("user://"):
        return ProjectSettings.globalize_path(path)
    if path.is_absolute_path():
        return path
    return ProjectSettings.globalize_path("res://" + path)






