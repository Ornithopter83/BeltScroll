extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const BACKGROUND_PATH := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const EXPECTED_ARENA_BOUNDS := Rect2(Vector2(160, 100), Vector2(1600, 880))
const TEMPORARY_VISUALS := ["Backdrop", "Arena", "FloorMarkings", "CenterLine", "CenterCircle"]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var background_image := Image.new()
	var image_error := background_image.load(BACKGROUND_PATH)
	_check(image_error == OK, "normalized stage background PNG loads")
	if image_error == OK:
		_check(background_image.get_width() == 1920 and background_image.get_height() == 1080, "stage background image is exactly 1920x1080")

	var packed_main := load(MAIN_SCENE) as PackedScene
	_check(packed_main != null, "main scene resource loads")
	if packed_main == null:
		_finish()
		return
	var main := packed_main.instantiate() as Node2D
	_check(main != null, "main scene instantiates as Node2D")
	if main == null:
		_finish()
		return
	root.add_child(main)

	var stage_background := main.get_node_or_null("StageBackground") as Sprite2D
	_check(stage_background != null, "main scene has a StageBackground Sprite2D")
	if stage_background != null:
		_check(stage_background.texture != null and stage_background.texture.resource_path == BACKGROUND_PATH, "main scene connects the normalized forest ruins texture")
		if stage_background.texture != null and image_error == OK:
			var loaded_image := stage_background.texture.get_image()
			_check(loaded_image.get_pixel(960, 540).is_equal_approx(background_image.get_pixel(960, 540)), "scene background texture is loaded from the normalized PNG")
		_check(stage_background.position == Vector2(960, 540), "background is centered over the 1920x1080 world")
		_check(stage_background.z_index < 0, "background renders behind gameplay actors")
	for node_name in TEMPORARY_VISUALS:
		_check(main.find_child(node_name, true, false) == null, "%s temporary stage visual was removed" % node_name)

	var actors := main.get_node_or_null("YSortActors") as Node2D
	_check(actors != null and actors.y_sort_enabled, "YSortActors remains enabled")
	if actors != null:
		var player := actors.get_node_or_null("Player") as CharacterBody2D
		_check(player != null, "Player remains in YSortActors")
		if player != null:
			_check(player.get_node_or_null("CollisionShape2D") is CollisionShape2D, "Player collision remains present")
			_check(player.get_node_or_null("Camera2D") is Camera2D, "Player camera remains present")
			_check(player.get("arena_bounds") == EXPECTED_ARENA_BOUNDS, "logical arena bounds remain 160,100 to 1760,980")
		var dummy := actors.get_node_or_null("TrainingDummy") as CharacterBody2D
		_check(dummy != null and dummy.get_node_or_null("CollisionShape2D") is CollisionShape2D, "TrainingDummy and its collision remain present")
		var raider_count := 0
		for child in actors.get_children():
			if child.name == "ForestRaider1" or child.name == "ForestRaider2" or child.name == "ForestRaider3":
				raider_count += 1
				_check(child is CharacterBody2D and child.get_node_or_null("CollisionShape2D") is CollisionShape2D, "%s and its collision remain present" % child.name)
		_check(raider_count == 3, "all three ForestRaiders remain in the main scene")

	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("stage_integration_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("stage_integration_smoke: " + failure)
		quit(1)
