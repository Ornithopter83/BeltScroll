extends SceneTree

const REVIEW_SCENE := "res://scenes/review/player_reference_review.tscn"
const REVIEW_SCRIPT := "res://scripts/review/player_reference_review.gd"
const V3_SAFE := "res://assets/art/player/elven_fighter_reference_v3_safe_1254x1254.png"
const V4_SAFE := "res://assets/art/player/elven_fighter_reference_v4_safe_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const TARGET_SCREEN_HEIGHT := 192.0
const FOOT_BASELINE_WORLD_Y := 850.0
const PREVIEW_NAMES := ["PreviewFaceEar", "PreviewHands", "PreviewLeftFoot", "PreviewRightFoot"]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script := load(REVIEW_SCRIPT) as Script
	var packed := load(REVIEW_SCENE) as PackedScene
	_check(script != null, "standalone player reference review script loads")
	_check(packed != null, "standalone player reference review scene loads")
	if packed == null:
		_finish()
		return
	var review := packed.instantiate() as Node2D
	_check(review != null, "review scene instantiates independently as Node2D")
	if review == null:
		_finish()
		return
	root.add_child(review)
	await process_frame

	var background := review.get_node_or_null("ForestRuinsBackground") as Sprite2D
	_check(background != null and background.texture != null and background.texture.resource_path == FOREST,
		"review uses the existing Forest Ruins normalized background")
	var camera := review.get_node_or_null("Camera2D") as Camera2D
	_check(camera != null and camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "review camera zoom is 1.2")
	var candidate_sprite := review.get_node_or_null("CandidateSprite") as Sprite2D
	_check(candidate_sprite != null, "review has a dedicated full silhouette sprite")
	if candidate_sprite != null and candidate_sprite.texture != null and camera != null:
		var rendered_height := candidate_sprite.texture.get_height() * candidate_sprite.scale.y * camera.zoom.y
		_check(absf(rendered_height - TARGET_SCREEN_HEIGHT) <= 1.0, "full silhouette renders about 192 screen pixels tall at camera zoom 1.2")
		_check(absf(candidate_sprite.position.y + candidate_sprite.texture.get_height() * candidate_sprite.scale.y * 0.5 - FOOT_BASELINE_WORLD_Y) <= 0.1,
			"full silhouette bottom aligns with the world foot baseline")

	var script_constants: Dictionary = script.get_script_constant_map()
	_check(script_constants.get("CANDIDATE_PATHS", []) == [V3_SAFE, V4_SAFE], "candidate list is exactly v3_safe then v4_safe")
	_check(script_constants.get("CAMERA_ZOOM", Vector2.ZERO) == Vector2(1.2, 1.2), "review script documents the required zoom")
	var overlay := review.get_node_or_null("ReviewCanvas/ReviewOverlay") as Control
	_check(overlay != null, "review-only labels and previews stay on their own canvas layer")
	if overlay != null:
		_check(overlay.find_child("CandidateName", true, false) is Label, "candidate filename is displayed")
		var status := overlay.find_child("ApprovalStatus", true, false) as Label
		_check(status != null and "미승인" in status.text, "approval state is explicitly marked unapproved")
		_check(overlay.find_child("FootBaseline", true, false) is ColorRect, "a visible foot baseline is provided")
		for preview_name in PREVIEW_NAMES:
			var preview := overlay.find_child(preview_name, true, false) as TextureRect
			_check(preview != null and preview.texture != null, "%s close-up preview is populated" % preview_name)

	var change := InputEventKey.new()
	change.keycode = KEY_2
	change.pressed = true
	review.call("_unhandled_key_input", change)
	_check(int(review.get("selected_candidate")) == 1 and "v4_safe" in (overlay.find_child("CandidateName", true, false) as Label).text,
		"pressing 2 selects the v4_safe candidate")
	change = InputEventKey.new()
	change.keycode = KEY_1
	change.pressed = true
	review.call("_unhandled_key_input", change)
	_check(int(review.get("selected_candidate")) == 0 and "v3_safe" in (overlay.find_child("CandidateName", true, false) as Label).text,
		"pressing 1 selects the v3_safe candidate")
	_check("미승인" in (overlay.find_child("ApprovalStatus", true, false) as Label).text,
		"candidate switching never marks a candidate approved")
	review.queue_free()
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_reference_review_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_reference_review_smoke: " + failure)
		quit(1)
