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
	var skill_slots: Array = hud.get("skill_slots")
	_check(health_label.text == "5 / 5" and is_equal_approx(health_bar.value, 5.0), "initial Player health is displayed")
	_check(combo_label.text == "—", "idle combo has no active stage")
	_check(raider_label.text == "03", "initial remaining ForestRaider count is three")
	_check(skill_slots.size() == 2, "Num4 and Num5 have separate skill slots")
	if skill_slots.size() == 2:
		_check(skill_slots[0]["title"].text.contains("NUM4") and skill_slots[0]["title"].text.contains("돌진"), "Num4 slot names the dash skill")
		_check(skill_slots[1]["title"].text.contains("NUM5") and skill_slots[1]["title"].text.contains("회전"), "Num5 slot names the spin skill")
		_check(skill_slots[0]["status"].text == "사용 가능" and skill_slots[1]["status"].text == "사용 가능", "both skills start ready")
		var cooldowns: Array = player.get("skill_cooldowns")
		cooldowns[0] = 0.9
		player.set("skill_cooldowns", cooldowns)
		hud.refresh()
		_check(skill_slots[0]["status"].text == "재사용 대기  ·  0.9초" and float(skill_slots[0]["meter"].value) > 0.0, "dash cooldown time and progress read the live Player cooldown")
		_check(skill_slots[1]["status"].text == "사용 가능", "spin remains available while dash cools down")
		cooldowns[0] = 1.35
		player.set("skill_cooldowns", cooldowns)
		player.set("skill_id", 1)
		player.set("skill_phase", "startup")
		player.set("skill_phase_remaining", 0.12)
		hud.refresh()
		_check(skill_slots[0]["status"].text.contains("준비 동작") and skill_slots[0]["status"].text.contains("0.1초"), "dash startup state and remaining phase time are displayed")
		player.set("skill_phase", "active")
		player.set("skill_phase_remaining", 0.08)
		hud.refresh()
		_check(skill_slots[0]["status"].text.contains("사용 중"), "dash active state is distinct")
		player.set("skill_phase", "recovery")
		player.set("skill_phase_remaining", 0.2)
		hud.refresh()
		_check(skill_slots[0]["status"].text.contains("회복"), "skill recovery state is distinct")
		player.set("skill_phase", "idle")
		player.set("skill_id", 0)
		player.set("skill_phase_remaining", 0.0)
		cooldowns[0] = 0.0
		cooldowns[1] = 1.2
		player.set("skill_cooldowns", cooldowns)
		hud.refresh()
		_check(skill_slots[0]["status"].text == "사용 가능" and skill_slots[1]["status"].text.contains("재사용 대기"), "dash returns ready and spin cooldown restores independently")
		paused = true
		hud.refresh()
		_check(skill_slots[1]["status"].text.contains("재사용 대기"), "HUD retains the same skill state while the tree is paused")
		paused = false
		cooldowns[1] = 0.0
		player.set("skill_cooldowns", cooldowns)
		hud.refresh()

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
	_check(is_equal_approx(health_bar.value, 4.0), "partial healing updates the Player bar immediately")
	_check(is_equal_approx(health_damage_bar.value, 4.0), "partial healing removes the rendered damage tail immediately")

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

	raiders[0].receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(first_indicator["label"].text == "1 / 3" and second_indicator["label"].text == "3 / 3", "damage is shown on the correct individual Raider")
	_check(is_equal_approx(first_indicator["bar"].value, 3.0), "Raider bar retains its prior value at the damage frame")
	hud.call("_advance_health_bars", 0.1)
	_check(float(first_indicator["bar"].value) < 3.0 and float(first_indicator["bar"].value) > 1.0, "Raider bar interpolates from real health")
	_check(is_equal_approx(second_indicator["bar"].value, 3.0), "unharmed Raider bar remains independent")
	raiders[0].set("health", 2)
	hud.refresh()
	_check(first_indicator["label"].text == "2 / 3", "Raider recovery updates the displayed number immediately")
	_check(is_equal_approx(first_indicator["bar"].value, 2.0) and is_equal_approx(first_indicator["damage_bar"].value, 2.0), "Raider recovery clears the rendered damage tail immediately")
	raiders[0].receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(not first_indicator["root"].visible and raider_label.text == "02", "KO Raider indicator hides and remaining count updates")

	var camera: Camera2D = player.get_node("Camera2D")
	camera.make_current()
	var moved_raider: Node2D = raiders[1]
	moved_raider.global_position = player.global_position + Vector2(250.0, 0.0)
	camera.global_position = moved_raider.global_position
	camera.zoom = Vector2.ONE
	camera.rotation = 0.0
	await process_frame
	hud.refresh()
	var before_camera_move: Vector2 = second_indicator["root"].position
	camera.global_position += Vector2(50.0, 0.0)
	camera.zoom = Vector2(1.1, 1.1)
	camera.rotation = 0.05
	raiders[1].get_node("VisualRoot").scale.x *= -1.0
	await process_frame
	hud.refresh()
	var after_camera_move: Vector2 = second_indicator["root"].position
	_check(not before_camera_move.is_equal_approx(after_camera_move) and second_indicator["root"].visible and _indicator_tracks_head(moved_raider, second_indicator), "Raider indicator follows camera movement, zoom, rotation, and sprite mirroring")
	_check(not second_indicator["root"].visible or not _indicator_overlaps_player(second_indicator, player), "near-combat Raider indicator stays clear of the Player silhouette")
	raiders[1].global_position = Vector2(-1000.0, -1000.0)
	hud.refresh()
	_check(not second_indicator["root"].visible, "off-screen Raider indicator hides instead of pinning to the viewport edge")

	var detached_hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	main.remove_child(hud)
	hud.queue_free()
	main.add_child(detached_hud)
	detached_hud.queue_free()
	_check(player.get("health") == 0 and player.has_method("receive_hit"), "Player combat state remains independent of HUD lifetime")
	current_scene = main
	main.call("_restart_session")
	await process_frame
	await process_frame
	var restarted_hud := current_scene.get_node_or_null("CombatHUD") if is_instance_valid(current_scene) else null
	_check(is_instance_valid(current_scene) and current_scene != main, "game restart creates a fresh combat HUD")
	if restarted_hud != null:
		var restarted_slots: Array = restarted_hud.get("skill_slots")
		_check(restarted_slots[0]["status"].text == "사용 가능" and restarted_slots[1]["status"].text == "사용 가능", "restart restores both skill slots to ready")
		_check(restarted_hud.get("health_value_label").text == "5 / 5", "restart restores the Player health HUD")
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = null
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

func _indicator_tracks_head(raider: Node2D, indicator: Dictionary) -> bool:
	var art := raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	var bounds := art.texture.get_image().get_used_rect()
	var local_head := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.y) - Vector2(art.texture.get_size()) * 0.5
	var screen_head: Vector2 = art.get_global_transform_with_canvas() * local_head
	var control: Control = indicator["root"]
	return absf(control.position.y + control.size.y + 12.0 - screen_head.y) < 1.0 and absf(control.position.x + control.size.x * 0.5 - screen_head.x) <= 168.0

func _indicator_overlaps_player(indicator: Dictionary, player: Node) -> bool:
	var rect := Rect2(indicator["root"].position, indicator["root"].size)
	for sprite in player.find_children("*", "Sprite2D", true, false):
		var art := sprite as Sprite2D
		if art == null or not art.is_visible_in_tree() or art.texture == null:
			continue
		var alpha := art.texture.get_image().get_used_rect()
		if alpha.size == Vector2i.ZERO:
			continue
		var half := Vector2(art.texture.get_size()) * 0.5
		var local := Rect2(Vector2(alpha.position) - half, Vector2(alpha.size))
		var transform := art.get_global_transform_with_canvas()
		var points: Array[Vector2] = [transform * local.position, transform * Vector2(local.end.x, local.position.y), transform * local.end, transform * Vector2(local.position.x, local.end.y)]
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points.slice(1):
			bounds = bounds.expand(point)
		if rect.intersects(bounds):
			return true
	return false
