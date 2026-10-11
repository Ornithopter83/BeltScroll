extends SceneTree
## Supplemental full-Window evidence where the historical crop clips hair/KO.
var player: CharacterBody2D
var frame_number := 0
var rows: Array[Dictionary] = []
const OUTPUT := "res://assets/art/review/m6v_full_reactions"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	Engine.max_fps = 60
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	player = game.get_node("YSortActors/Player")
	for actor in game.get_node("YSortActors").get_children():
		if actor != player and actor is CharacterBody2D:
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			actor.position.x += 10000
	var camera := player.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _capture(12, "idle / InputMap")
	Input.action_press("jump")
	await _capture(18, "jump held / InputMap")
	Input.action_release("jump")
	await _capture(48, "jump released / InputMap")
	player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT, "knockback": 90.0, "hit_stun": 0.24, "attack_stage": 1})
	await _capture(24, "receive_hit fixture; not enemy AI")
	player.call("receive_hit", {"damage": 99, "direction": Vector2.LEFT, "knockback": 90.0, "hit_stun": 0.24, "attack_stage": 3})
	await _capture(72, "lethal receive_hit fixture; not enemy AI")
	var file := FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"human_approval":"UNVERIFIED", "camera_zoom":1.0, "frames":rows}, "\t"))
	file.close()
	print("M6V_FULL_REACTIONS|samples=%d|human_approval=UNVERIFIED" % rows.size())
	quit(0)

func _capture(count: int, stimulus: String) -> void:
	for index in range(count):
		await RenderingServer.frame_post_draw
		frame_number += 1
		if index % 6 != 0 and index != count - 1:
			continue
		var image := root.get_texture().get_image()
		var path := OUTPUT + "/frame_%03d.png" % frame_number
		if image.get_size() != Vector2i(1920, 1080) or image.save_png(ProjectSettings.globalize_path(path)) != OK:
			push_error("full Window frame save failed")
			quit(1)
			return
		rows.append({"frame":frame_number,"window_frame":Engine.get_frames_drawn(),"state":player.get_node("VisualAnimator").call("get_animation_state"),"stimulus":stimulus,"path":path,"sha256":FileAccess.get_sha256(path)})
