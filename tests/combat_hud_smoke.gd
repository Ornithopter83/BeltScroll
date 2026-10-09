extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const HUD_SCENE := "res://scenes/ui/combat_hud.tscn"
const HIT := {"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load(MAIN_SCENE) as PackedScene
	_check(main_scene != null, "main scene containing HUD loads")
	if main_scene == null:
		_finish()
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	var hud := main.get_node_or_null("CombatHUD")
	_check(hud != null and hud is CanvasLayer, "combat HUD is a CanvasLayer")
	if hud == null:
		_finish()
		return
	var player := main.get_node("YSortActors/Player")
	var health_label: Label = hud.get("health_value_label")
	var health_bar: ProgressBar = hud.get("health_bar")
	var health_damage_bar: ProgressBar = hud.get("health_damage_bar")
	var combo_label: Label = hud.get("combo_value_label")
	var raider_label: Label = hud.get("raider_value_label")
	_check(health_label.text == "5 / 5" and is_equal_approx(health_bar.value, 5.0), "initial Player health is displayed")
	_check(combo_label.text == "—", "idle combo has no active stage")
	_check(raider_label.text == "03", "initial remaining ForestRaider count is three")

	var raiders := get_nodes_in_group("forest_raiders")
	hud.refresh()
	var indicators: Dictionary = hud.get("_raider_indicators")
	_check(indicators.size() == 3, "each ForestRaider gets its own health indicator")
	var first_id: int = raiders[0].get_instance_id()
	var second_id: int = raiders[1].get_instance_id()
	var first_indicator: Dictionary = indicators[first_id]
	var second_indicator: Dictionary = indicators[second_id]
	_check(first_indicator["label"].text == "3 / 3" and is_equal_approx(first_indicator["bar"].value, 3.0), "Raider bar starts from that Raider's model health")
	_check(second_indicator["label"].text == "3 / 3", "another Raider displays its own health")
	var second_art := raiders[1].get_node("VisualRoot/RaiderArt") as Sprite2D
	var second_alpha := second_art.texture.get_image().get_used_rect()
	var second_head_local := Vector2(second_alpha.position.x + second_alpha.size.x * 0.5, second_alpha.position.y) - Vector2(second_art.texture.get_size()) * 0.5
	var second_head_screen: Vector2 = second_art.get_global_transform_with_canvas() * second_head_local
	_check(float(second_indicator["root"].position.y + second_indicator["root"].size.y) <= second_head_screen.y - 8.0, "Raider indicator sits above the transformed alpha silhouette head")

	player.receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(health_label.text == "3 / 5", "Player health number updates immediately after damage")
	_check(health_bar.value == 5.0 and health_damage_bar.value == 5.0, "Player bars begin interpolation from prior health")
	hud.call("_advance_health_bars", 0.1)
	hud.refresh()
	_check(health_bar.value < 5.0 and health_bar.value > 3.0 and health_damage_bar.value == 5.0, "Player live bar interpolates while delayed damage bar holds")
	hud.call("_advance_health_bars", 0.6)
	hud.refresh()
	hud.call("_advance_health_bars", 0.1)
	hud.refresh()
	_check(health_damage_bar.value < 5.0 and health_damage_bar.value > health_bar.value, "Player damage bar decreases after its delay")

	player.set("health", 4)
	hud.refresh()
	_check(health_label.text == "4 / 5", "healing updates the displayed number immediately")
	hud.call("_advance_health_bars", 0.1)
	hud.refresh()
	_check(health_bar.value > 3.0 and health_bar.value < 4.0, "healing interpolates the live Player bar")
	_check(health_damage_bar.value <= 4.0 and health_damage_bar.value >= health_bar.value, "partial healing clears the damage trail while the live bar finishes its interpolation")

	player.call("_begin_attack", 1)
	hud.refresh()
	_check(combo_label.text == "1 / 3", "first combo stage is displayed")
	player.call("_begin_attack", 2)
	hud.refresh()
	_check(combo_label.text == "2 / 3", "combo continuation updates displayed stage")
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.set("attack_progress", 0.0)
	hud.refresh()
	_check(combo_label.text == "—", "combo end clears displayed stage")
	player.receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(health_label.text == "0 / 5", "Player KO is reflected immediately in the health number")
	hud.call("_advance_health_bars", 1.0)
	hud.refresh()
	_check(is_equal_approx(health_bar.value, 0.0), "Player KO bar interpolates to zero")

	raiders[0].receive_hit(HIT)
	hud.refresh()
	_check(first_indicator["label"].text == "2 / 3" and second_indicator["label"].text == "3 / 3", "damage is shown on the correct individual Raider")
	_check(is_equal_approx(first_indicator["bar"].value, 3.0), "Raider bar retains its prior value at the damage frame")
	hud.call("_advance_health_bars", 0.1)
	_check(float(first_indicator["bar"].value) < 3.0 and float(first_indicator["bar"].value) > 2.0, "Raider bar interpolates from real health")
	_check(is_equal_approx(second_indicator["bar"].value, 3.0), "unharmed Raider bar remains independent")
	raiders[0].receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(not first_indicator["root"].visible and raider_label.text == "02", "KO Raider indicator hides and remaining count updates")

	var camera: Camera2D = player.get_node("Camera2D")
	camera.make_current()
	await process_frame
	hud.refresh()
	var before_camera_move: Vector2 = second_indicator["root"].position
	camera.global_position += Vector2(100.0, 0.0)
	camera.zoom = Vector2(1.5, 1.5)
	camera.rotation = 0.12
	raiders[1].get_node("VisualRoot").scale.x *= -1.0
	await process_frame
	hud.refresh()
	var after_camera_move: Vector2 = second_indicator["root"].position
	_check(not before_camera_move.is_equal_approx(after_camera_move), "Raider indicator follows camera movement, zoom, rotation, and sprite mirroring")
	raiders[1].global_position = Vector2(-1000.0, -1000.0)
	hud.refresh()
	_check(not second_indicator["root"].visible, "off-screen Raider indicator hides instead of pinning to the viewport edge")

	var detached_hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	main.remove_child(hud)
	hud.queue_free()
	main.add_child(detached_hud)
	detached_hud.queue_free()
	_check(player.get("health") == 0 and player.has_method("receive_hit"), "Player combat state remains independent of HUD lifetime")
	main.queue_free()
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("combat_hud_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("combat_hud_smoke: " + failure)
		push_error("combat_hud_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
