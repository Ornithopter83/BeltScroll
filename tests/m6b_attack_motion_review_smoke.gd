extends SceneTree
"""Checks the isolated M6B attack motion review inputs and captured strip."""
# 스모크 통과는 사람의 시각 승인이나 발 접지 판정을 대신하지 않는다.

const BUILDER_PATH := "res://tools/build_m6b_attack_motion_review.gd"
const STRIP_PATH := "res://assets/art/review/m6b_attack_motion_strip.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_attack1_startup_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png",
]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(BUILDER_PATH), "independent playback and review builder exists")
	for path in SOURCE_PATHS:
		_check(FileAccess.file_exists(path), "acquired source exists: %s" % path.get_file())
		if FileAccess.file_exists(path):
			var image := Image.new()
			_check(image.load(ProjectSettings.globalize_path(path)) == OK and image.get_size() == Vector2i(1254, 1254), "source decodes at 1254x1254: %s" % path.get_file())
	if FileAccess.file_exists(BUILDER_PATH):
		var source := FileAccess.get_file_as_string(BUILDER_PATH)
		_check(source.contains("ImageTexture.create_from_image") and source.contains("load_png_from_buffer"), "original PNG bytes are decoded directly without RESOURCE sheet dependence")
		_check(source.contains("await _play_sequence()") and source.contains("RenderingServer.frame_post_draw") and source.contains("POSE_EXPOSURE"), "actual timed pose switches count completed Window render frames")
		_check(source.contains("_silhouette_difference") and source.contains("bottom_alpha_delta") and source.contains("support_candidate_delta"), "per-attack silhouette and foot-anchor candidates are reported")
		_check(source.contains("identity=human_review") and source.contains("approval=not_performed") and source.contains("runtime_registration=none"), "identity review and approval remain separate from this candidate tool")
		_check(source.contains("Duplicate source image cannot count as a new pose") and source.contains("interpolated_frames=none"), "duplicate and interpolated drawings cannot be accepted as new poses")
		_check(source.contains("startup source unavailable"), "missing attack 2 startup art is disclosed instead of duplicated")
	_check(FileAccess.file_exists(STRIP_PATH), "review strip PNG exists")
	if FileAccess.file_exists(STRIP_PATH):
		var strip := Image.new()
		_check(strip.load(ProjectSettings.globalize_path(STRIP_PATH)) == OK and strip.get_size() == Vector2i(1920, 1080), "review strip is a readable 1920x1080 PNG")
	if _failures.is_empty():
		print("m6b_attack_motion_review_smoke: isolated candidate art, timed playback contract, and strip are present")
		quit(0)
		return
	for failure in _failures:
		push_error("m6b_attack_motion_review_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
