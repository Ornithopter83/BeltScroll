extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const HUD_SCENE := "res://scenes/ui/combat_hud.tscn"
const HIT := {"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene containing HUD loads")
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
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
	var slots: Array = hud.get("skill_slots")
	_check(health_label.text == "5 / 5" and is_equal_approx(health_bar.value, 1.0), "Player health starts at 5/5 and a full normalized bar")
	_check(combo_label.text == "—" and raider_label.text == "03", "combo and remaining Raider count start correctly")
	_check(slots.size() == 2, "Num4 and Num5 skill slots are preserved")
	if slots.size() == 2:
		_check(slots[0]["title"].text.contains("돌진") and slots[1]["title"].text.contains("회전"), "both skill names remain visible")
		var cooldowns: Array = player.get("skill_cooldowns")
		cooldowns[0] = 0.9
		player.set("skill_cooldowns", cooldowns)
		hud.refresh()
		_check(slots[0]["status"].text.contains("0.9초") and slots[1]["status"].text == "사용 가능", "skill cooldown state remains independent")
		cooldowns[0] = 0.0
		player.set("skill_cooldowns", cooldowns)
		player.set("skill_id", 1)
		player.set("skill_phase", "recovery")
		player.set("skill_phase_remaining", 0.2)
		hud.refresh()
		_check(slots[0]["status"].text.contains("회복"), "skill recovery state remains visible")
		player.set("skill_id", 0)
		player.set("skill_phase", "idle")
		player.set("skill_phase_remaining", 0.0)

	var raiders := get_nodes_in_group("forest_raiders")
	var indicators: Dictionary = hud.get("_raider_indicators")
	_check(raiders.size() == 3 and indicators.is_empty(), "waiting Raider waves do not occupy the active health list")
	main.call("_set_raider_active", raiders[0], true)
	main.call("_set_raider_active", raiders[1], true)
	hud.refresh()
	indicators = hud.get("_raider_indicators")
	_check(indicators.size() == 2, "active Raider health rows are created")
	var first: Dictionary = indicators[raiders[0].get_instance_id()]
	var second: Dictionary = indicators[raiders[1].get_instance_id()]
	_check(first["label"].text.contains("ForestRaider1") and first["label"].text.contains("3 / 3"), "fixed active Raider row includes name and current/max health")
	_check(is_equal_approx(first["bar"].value, 1.0) and is_equal_approx(first["bar"].max_value, 1.0), "Raider bar uses the normalized full-health ratio")
	_check(first["root"].visible and second["root"].position.y - first["root"].position.y >= 46.0, "fixed Raider rows leave room for the rendered health bars")
	var fixed_position: Vector2 = second["root"].position
	var camera: Camera2D = player.get_node("Camera2D")
	camera.global_position += Vector2(100.0, 40.0)
	camera.zoom = Vector2(1.15, 1.15)
	hud.refresh()
	_check(second["root"].position.is_equal_approx(fixed_position), "Raider health rows stay fixed when the camera moves and zooms")

	player.receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(health_label.text == "3 / 5" and is_equal_approx(health_bar.value, 1.0), "Player number updates before the interpolated bar")
	hud.call("_advance_health_bars", 0.1)
	hud.refresh()
	_check(health_bar.value < 1.0 and health_bar.value > 0.6 and is_equal_approx(health_damage_bar.value, 1.0), "Player damage interpolation retains its delayed tail")
	hud.call("_advance_health_bars", 0.6)
	hud.call("_advance_health_bars", 0.1)
	hud.refresh()
	_check(health_damage_bar.value < 1.0 and health_damage_bar.value > health_bar.value, "Player damage tail animates after its delay")
	player.set("health", 4)
	hud.refresh()
	_check(health_label.text == "4 / 5" and is_equal_approx(health_bar.value, 0.8) and is_equal_approx(health_damage_bar.value, 0.8), "Player recovery updates the 4/5 ratio and clears red tail")
	player.call("_begin_attack", 1)
	hud.refresh()
	_check(combo_label.text == "1 / 3", "combo stage remains visible")
	player.set("health", 0)
	hud.refresh()
	_check(health_label.text == "0 / 5" and hud.get("health_caption_label").text.contains("KO"), "Player KO is explicitly reflected")

	raiders[0].receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(first["label"].text.contains("1 / 3") and is_equal_approx(first["bar"].value, 1.0), "Raider damage updates the ratio from its actual maximum")
	hud.call("_advance_health_bars", 0.1)
	hud.refresh()
	_check(first["bar"].value < 1.0 and first["bar"].value > 0.33, "Raider health ratio interpolates")
	raiders[0].set("health", 2)
	hud.refresh()
	_check(first["label"].text.contains("2 / 3") and is_equal_approx(first["bar"].value, 2.0 / 3.0) and is_equal_approx(first["damage_bar"].value, 2.0 / 3.0), "Raider healing restores the correct ratio without red tail")
	raiders[0].receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(first["root"].visible and first["label"].text.contains("KO") and first["label"].text.contains("0 / 3") and raider_label.text == "02", "KO row identifies the Raider and remaining count updates")

	var detached: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	main.remove_child(hud)
	hud.queue_free()
	main.add_child(detached)
	detached.queue_free()
	_check(player.has_method("receive_hit"), "Player combat state remains independent of HUD lifetime")
	if is_instance_valid(main):
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
