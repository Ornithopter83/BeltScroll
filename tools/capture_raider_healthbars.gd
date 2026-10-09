extends SceneTree
"""Captures fixed Player, Raider, and Ruins Warden health rows from a rendered Window Viewport."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://temp/raider_healthbars_window.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("A real Window renderer is required for health bar capture.")
		return
	root.size = EXPECTED_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load the combat scene.")
		return
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	await process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var hud := game.get_node_or_null("CombatHUD")
	var boss := game.get_node_or_null("YSortActors/RuinsWardenBoss")
	var raiders := get_nodes_in_group("forest_raiders")
	if player == null or hud == null or boss == null or raiders.size() != 3:
		game.queue_free()
		_fail("Combat scene does not contain the expected Player, HUD, Raiders, and Ruins Warden.")
		return
	player.set_physics_process(false)
	for raider in raiders:
		raider.set_physics_process(false)
	boss.call("set_combat_active", true)
	boss.set_physics_process(false)
	game.call("_set_raider_active", raiders[0], true)
	hud.refresh()
	await _draw_frame()
	var initial := root.get_texture().get_image()
	if not _valid_frame(initial):
		game.queue_free()
		_fail("Initial rendered Window frame is invalid.")
		return

	var indicators: Dictionary = hud.get("_raider_indicators")
	var target: Node2D = raiders[0]
	var row: Dictionary = indicators[target.get_instance_id()]
	var row_position: Vector2 = row["root"].position
	var boss_indicators: Dictionary = hud.get("_boss_indicators")
	if boss_indicators.size() != 1:
		game.queue_free()
		_fail("The real Ruins Warden did not receive a dedicated HUD row.")
		return
	var boss_row: Dictionary = boss_indicators[boss.get_instance_id()]
	var boss_row_position: Vector2 = boss_row["root"].position
	var player_bar: ProgressBar = hud.get("health_bar")
	var player_damage_bar: ProgressBar = hud.get("health_damage_bar")
	player.receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	target.receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	boss.call("receive_hit", {"damage": 12, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	hud.call("_advance_health_bars", 0.1)
	hud.set("_player_damage_delay", 1.0)
	row["damage_delay"] = 1.0
	boss_row["damage_delay"] = 1.0
	hud.refresh()
	await _draw_frame()
	var damage_image := root.get_texture().get_image()
	if hud.get("health_value_label").text != "3 / 5" or row["label"].text.find("1 / 3") < 0 or boss_row["label"].text.find("Ruins Warden") < 0 or boss_row["label"].text.find("8 / 20") < 0:
		game.queue_free()
		_fail("Damage labels did not show current/max health for both actors.")
		return
	if not _bar_has_color(damage_image, player_bar, "yellow") or not _bar_has_color(damage_image, player_bar, "red"):
		game.queue_free()
		_fail("Player damage frame did not render yellow current health and red lost health.")
		return
	if not _row_bar_has_color(damage_image, row, "yellow") or not _row_bar_has_color(damage_image, row, "red"):
		game.queue_free()
		_fail("Fixed Raider damage row did not render yellow current health and red lost health.")
		return
	if not _row_bar_has_color(damage_image, boss_row, "yellow") or not _row_bar_has_color(damage_image, boss_row, "red"):
		game.queue_free()
		_fail("Dedicated boss damage row did not render yellow current health and red lost health.")
		return

	player.set("health", 4)
	target.set("health", 2)
	boss.set("health", 15)
	hud.refresh()
	if not is_equal_approx(player_bar.value, 0.8) or not is_equal_approx(player_damage_bar.value, 0.8):
		game.queue_free()
		_fail("Player recovery left normalized bar values inconsistent with 4/5.")
		return
	if row["label"].text.find("2 / 3") < 0 or not is_equal_approx(row["bar"].value, 2.0 / 3.0) or not is_equal_approx(row["damage_bar"].value, 2.0 / 3.0):
		game.queue_free()
		_fail("Raider recovery left normalized bar values inconsistent with 2/3.")
		return
	if boss_row["label"].text.find("15 / 20") < 0 or not is_equal_approx(boss_row["bar"].value, 0.75) or not is_equal_approx(boss_row["damage_bar"].value, 0.75):
		game.queue_free()
		_fail("Boss recovery left normalized bar values inconsistent with 15/20.")
		return
	await _draw_frame()
	var healed_image := root.get_texture().get_image()
	if not _valid_frame(healed_image) or not _bar_has_color(healed_image, player_bar, "yellow") or _bar_has_color(healed_image, player_bar, "red"):
		game.queue_free()
		_fail("Rendered Player recovery retained red damage pixels or lost yellow health pixels.")
		return
	if not _row_bar_has_color(healed_image, row, "yellow") or _row_bar_has_color(healed_image, row, "red"):
		game.queue_free()
		_fail("Rendered fixed Raider recovery retained red damage pixels or lost yellow health pixels.")
		return
	if not _row_bar_has_color(healed_image, boss_row, "yellow") or _row_bar_has_color(healed_image, boss_row, "red"):
		game.queue_free()
		_fail("Rendered boss recovery retained red damage pixels or lost yellow health pixels.")
		return
	if row["root"].position != row_position or row["label"].text.find("ForestRaider1") < 0:
		game.queue_free()
		_fail("Raider row moved or lost its name while the world changed health state.")
		return
	var combo_panel := hud.get_node("Overlay/ComboPanel") as Control
	var boss_root := boss_row["root"] as Control
	var raider_root := row["root"] as Control
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(EXPECTED_SIZE))
	if boss_row_position != Vector2(57.0, 190.0) or row_position.y < boss_row_position.y + boss_root.size.y:
		game.queue_free()
		_fail("Boss and Raider identification rows overlap or have unexpected ordering.")
		return
	if not viewport_rect.encloses(boss_root.get_global_rect()) or not viewport_rect.encloses(raider_root.get_global_rect()) or boss_root.get_global_rect().intersects(combo_panel.get_global_rect()) or raider_root.get_global_rect().intersects(combo_panel.get_global_rect()):
		game.queue_free()
		_fail("Boss/Raider row is clipped by the Window or overlaps the combo panel.")
		return
	var output_file := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_error := healed_image.save_png(output_file)
	if save_error != OK:
		game.queue_free()
		_fail("Could not save Window capture (Image.save_png error %d)." % save_error)
		return
	var player_rect := _pixel_rect(player_bar)
	var raider_rect := _pixel_rect(row["bar"])
	var boss_rect := _pixel_rect(boss_row["bar"])
	target.receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	if not row["root"].visible or row["label"].text.find("KO") < 0:
		game.queue_free()
		_fail("KO Raider did not remain in the fixed list with a KO label.")
		return
	game.queue_free()
	print("raider-healthbar-window-capture: saved rendered Window frame to %s" % output_file)
	print("raider-healthbar-window-capture: player-bar-rect=%d,%d,%d,%d" % [player_rect.position.x, player_rect.position.y, player_rect.size.x, player_rect.size.y])
	print("raider-healthbar-window-capture: raider-bar-rect=%d,%d,%d,%d" % [raider_rect.position.x, raider_rect.position.y, raider_rect.size.x, raider_rect.size.y])
	print("raider-healthbar-window-capture: boss-bar-rect=%d,%d,%d,%d" % [boss_rect.position.x, boss_rect.position.y, boss_rect.size.x, boss_rect.size.y])
	boss.set("health", 0)
	hud.refresh()
	if not boss_row["root"].visible or boss_row["label"].text.find("KO") < 0:
		_fail("KO boss did not remain visible in the dedicated identification row.")
		return
	print("raider-healthbar-window-capture: verified the real Ruins Warden row, alignment, no overlap/clipping, ratios, yellow/red pixels, recovery, and KO")
	print("raider-healthbar-window-capture: all checks passed")
	quit(0)

func _draw_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func _valid_frame(image: Image) -> bool:
	return image != null and not image.is_empty() and image.get_size() == EXPECTED_SIZE

func _pixel_rect(bar: ProgressBar) -> Rect2i:
	var rect := bar.get_global_rect()
	return Rect2i(Vector2i(roundi(rect.position.x), roundi(rect.position.y)), Vector2i(roundi(rect.size.x), roundi(rect.size.y)))

func _bar_has_color(image: Image, bar: ProgressBar, color: String) -> bool:
	return _rect_has_color(image, _pixel_rect(bar), color)

func _row_bar_has_color(image: Image, row: Dictionary, color: String) -> bool:
	return _bar_has_color(image, row["bar"], color)

func _rect_has_color(image: Image, rect: Rect2i, color: String) -> bool:
	var matches := 0
	for y in range(maxi(0, rect.position.y), mini(image.get_height(), rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(image.get_width(), rect.end.x)):
			var pixel := image.get_pixel(x, y)
			if color == "yellow" and pixel.r > 0.72 and pixel.g > 0.60 and pixel.b < 0.34:
				matches += 1
			elif color == "red" and pixel.r > pixel.g * 1.6 and pixel.r > pixel.b * 1.6:
				matches += 1
	return matches >= 8

func _fail(message: String) -> void:
	push_error("raider-healthbar-window-capture: " + message)
	quit(1)
