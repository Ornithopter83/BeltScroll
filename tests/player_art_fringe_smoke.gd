extends SceneTree

const RETOUCH := preload("res://tools/clean_player_art_fringe.gd")
const TARGET_SIZE := 1254
const MIN_MARGIN := 90

var failures: Array[String] = []
var cleanup_paths: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var temp_dir := ProjectSettings.globalize_path("res://temp/player_art_fringe_smoke")
    DirAccess.make_dir_recursive_absolute(temp_dir)
    var source_path := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v4_safe_1254x1254.png")
    var output_path := temp_dir.path_join("retouched.png")
    var bad_path := temp_dir.path_join("malformed.png")
    var no_output := temp_dir.path_join("should_not_exist.png")
    var blocker := temp_dir.path_join("output_blocker")
    cleanup_paths = [output_path, bad_path, no_output, blocker]
    var original_bytes := FileAccess.get_file_as_bytes(source_path)
    var original := _load_png(source_path)
    _check(original != null, "v4_safe input PNG decodes")
    _check(RETOUCH.retouch_file(source_path, output_path) == OK, "retouch candidate writes to a separate PNG")
    _check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "v4_safe source remains byte-for-byte unchanged")
    var candidate := _load_png(output_path)
    _check(_valid_canvas(candidate), "candidate is 1254x1254 RGBA with alpha and at least 90px margins")
    if original != null and candidate != null:
        _check(_same_alpha(original, candidate), "all source alpha values and silhouette pixels are unchanged")
        var changed_count := _changed_pixel_count(original, candidate)
        _check(changed_count > 0, "fringe cleanup changes at least one targeted color")
        print("Retouched pixel count: " + str(changed_count))
        _check(_interior_sample_preserved(original, candidate), "normal interior colors remain unchanged")

    var synthetic := _synthetic_edge_sample()
    var processed: Dictionary = RETOUCH.retouch_image(synthetic)
    var synthetic_result: Image = processed["image"]
    _check(int(processed["changed"]) > 0, "synthetic saturated red alpha-edge fringe is detected")
    _check(synthetic_result.get_pixel(99, 150).a == synthetic.get_pixel(99, 150).a, "edge correction keeps fringe alpha unchanged")
    _check(synthetic_result.get_pixel(110, 150).is_equal_approx(synthetic.get_pixel(110, 150)), "interior gold ornament color is preserved")

    _check(RETOUCH.retouch_file(temp_dir.path_join("missing.png"), no_output) == ERR_FILE_NOT_FOUND, "missing source returns file-not-found")
    _check(not FileAccess.file_exists(no_output), "missing source does not create output")
    var malformed := FileAccess.open(bad_path, FileAccess.WRITE)
    if malformed != null:
        malformed.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
        malformed.close()
    _check(RETOUCH.retouch_file(bad_path, no_output) != OK, "malformed PNG returns an error")
    _check(RETOUCH.retouch_file(source_path, source_path) == ERR_INVALID_PARAMETER, "same input/output path is rejected")
    var blocker_file := FileAccess.open(blocker, FileAccess.WRITE)
    if blocker_file != null:
        blocker_file.store_string("file blocks output directory")
        blocker_file.close()
    _check(RETOUCH.retouch_file(source_path, blocker.path_join("candidate.png")) != OK, "unwritable output path returns an error")
    _check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "source remains byte-identical after error cases")

    for path in cleanup_paths:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
    if DirAccess.dir_exists_absolute(temp_dir):
        DirAccess.remove_absolute(temp_dir)
    if failures.is_empty():
        print("player_art_fringe_smoke: all checks passed")
        quit(0)
    else:
        for failure in failures:
            push_error("player_art_fringe_smoke: " + failure)
        quit(1)

func _valid_canvas(image: Image) -> bool:
    if image == null or image.get_width() != TARGET_SIZE or image.get_height() != TARGET_SIZE or image.get_format() != Image.FORMAT_RGBA8:
        return false
    var bounds := RETOUCH._alpha_bounds(image)
    if bounds.size.x <= 0 or bounds.size.y <= 0:
        return false
    var right := TARGET_SIZE - bounds.end.x
    var bottom := TARGET_SIZE - bounds.end.y
    return mini(mini(bounds.position.x, bounds.position.y), mini(right, bottom)) >= MIN_MARGIN and image.get_pixel(0, 0).a == 0.0

func _same_alpha(first: Image, second: Image) -> bool:
    for y in range(TARGET_SIZE):
        for x in range(TARGET_SIZE):
            if first.get_pixel(x, y).a != second.get_pixel(x, y).a:
                return false
    return true

func _changed_pixel_count(first: Image, second: Image) -> int:
    var count := 0
    for y in range(TARGET_SIZE):
        for x in range(TARGET_SIZE):
            if not first.get_pixel(x, y).is_equal_approx(second.get_pixel(x, y)):
                count += 1
    return count

func _interior_sample_preserved(first: Image, second: Image) -> bool:
    for y in range(150, 1100, 17):
        for x in range(150, 1100, 19):
            var pixel := first.get_pixel(x, y)
            if pixel.a > 0.98 and not RETOUCH._is_fringe_hue(pixel) and pixel.is_equal_approx(second.get_pixel(x, y)):
                return true
    return false

func _synthetic_edge_sample() -> Image:
    var image := Image.create(TARGET_SIZE, TARGET_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 0))
    image.fill_rect(Rect2i(100, 100, 100, 100), Color(0.12, 0.34, 0.38, 1.0))
    image.set_pixel(99, 150, Color(1.0, 0.01, 0.01, 0.62))
    image.set_pixel(110, 150, Color(0.98, 0.72, 0.12, 1.0))
    return image

func _load_png(path: String) -> Image:
    if not FileAccess.file_exists(path):
        return null
    var image := Image.new()
    if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
        return null
    return image

func _check(condition: bool, description: String) -> void:
    if condition:
        print("PASS: " + description)
    else:
        failures.append(description)

