extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const HUD_SCENE := "res://scenes/ui/combat_hud.tscn"

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
	var combo_label: Label = hud.get("combo_value_label")
	var raider_label: Label = hud.get("raider_value_label")
	_check(health_label.text == "5 / 5" and is_equal_approx(health_bar.value, 5.0), "initial Player health is displayed")
	_check(combo_label.text == "—", "idle combo has no active stage")
	_check(raider_label.text == "03", "initial remaining ForestRaider count is three")

	player.receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	_check(health_label.text == "3 / 5" and is_equal_approx(health_bar.value, 3.0), "incoming hit updates Player health display")

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

	var raiders := get_nodes_in_group("forest_raiders")
	if not raiders.is_empty():
		raiders[0].set("health", 0)
	hud.refresh()
	_check(raider_label.text == "02", "defeated Raider is removed from remaining count")

	var detached_hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	main.remove_child(hud)
	hud.queue_free()
	main.add_child(detached_hud)
	detached_hud.queue_free()
	_check(player.get("health") == 3 and player.has_method("receive_hit"), "Player combat state remains independent of HUD lifetime")
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
