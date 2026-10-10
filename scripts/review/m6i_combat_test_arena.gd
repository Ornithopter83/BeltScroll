extends Node2D
"""Isolated manual combat arena; observes the real Player and ForestRaider scenes."""

@onready var _player: CharacterBody2D = $YSortActors/Player
@onready var _raider: CharacterBody2D = $YSortActors/ForestRaider
@onready var _attack_status: Label = $TestHUD/Panel/Margin/Rows/AttackStatus
@onready var _skill_status: Label = $TestHUD/Panel/Margin/Rows/SkillStatus
@onready var _cooldown_status: Label = $TestHUD/Panel/Margin/Rows/CooldownStatus
@onready var _hitstun_status: Label = $TestHUD/Panel/Margin/Rows/HitstunStatus
@onready var _health_status: Label = $TestHUD/Panel/Margin/Rows/HealthStatus
@onready var _raider_status: Label = $TestHUD/Panel/Margin/Rows/RaiderStatus

const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")
const PLAYER_ID := "Player"
const RAIDER_ID := "ForestRaider"

var _player_skill_cooldowns: Array = []

func _ready() -> void:
	_apply_saved_combat_settings()
	if _player.has_signal("skill_started"):
		_player.skill_started.connect(_on_player_skill_started)

func _apply_saved_combat_settings(data_path: String = DATA_LOADER.DATA_PATH) -> void:
	var data: Dictionary = DATA_LOADER.load_data(data_path)
	var player_values := _find_override(data.get("characters", []), PLAYER_ID, "characters")
	var raider_values := _find_override(data.get("enemies", []), RAIDER_ID, "enemies")
	_player_skill_cooldowns = player_values.get("skill_cooldowns", [])

	if not player_values.is_empty():
		DATA_LOADER.apply_properties(_player, player_values, ["max_health", "walk_speed", "attack_damage"])
		if player_values.has("max_health"):
			_player.set("health", int(_player.get("max_health")))

	if not raider_values.is_empty():
		DATA_LOADER.apply_properties(_raider, raider_values, [
			"max_health", "walk_speed", "attack_damage", "attack_knockback",
			"attack_hit_stun", "attack_range", "recovery_duration",
			"windup_duration", "active_duration",
		])
		if raider_values.has("max_health"):
			_raider.set("health", int(_raider.get("max_health")))
		if raider_values.has("ai"):
			DATA_LOADER.apply_properties(_raider, raider_values.ai, [
				"notice_range", "attack_depth_tolerance", "separation_radius", "separation_strength",
			])
		if raider_values.has("attack_range"):
			var attack_shape := _raider.get_node_or_null("AttackArea/CollisionShape2D") as CollisionShape2D
			if attack_shape != null and attack_shape.shape is RectangleShape2D:
				var rect := attack_shape.shape.duplicate() as RectangleShape2D
				rect.size.x = maxf(24.0, float(raider_values.attack_range) * 0.82)
				attack_shape.shape = rect

func _find_override(records: Array, id: String, kind: String) -> Dictionary:
	for index in range(records.size()):
		var record: Dictionary = DATA_LOADER.validate_record(records[index], kind, index)
		if String(record.get("id", "")) == id:
			return record
	return {}

func _on_player_skill_started(skill_id: int) -> void:
	var index := skill_id - 1
	if index < 0 or index >= _player_skill_cooldowns.size():
		return
	var cooldowns: Array = _player.get("skill_cooldowns")
	if index >= cooldowns.size():
		return
	cooldowns[index] = float(_player_skill_cooldowns[index])
	_player.set("skill_cooldowns", cooldowns)

func _process(_delta: float) -> void:
	_update_readout()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()

func _update_readout() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_raider):
		return
	var attack_phase := str(_player.get("attack_phase"))
	var attack_stage := int(_player.get("attack_stage"))
	var attack_remaining := float(_player.get("attack_phase_remaining"))
	var attack_text := "대기" if attack_phase == "idle" else "%d단계 · %s · %.2f초" % [attack_stage, _phase_name(attack_phase), attack_remaining]
	_attack_status.text = "기본 공격: " + attack_text

	var skill_id := int(_player.get("skill_id"))
	var skill_phase := str(_player.get("skill_phase"))
	var skill_remaining := float(_player.get("skill_phase_remaining"))
	var skill_text := "대기" if skill_phase == "idle" else "Num%d · %s · %.2f초" % [skill_id + 3, _phase_name(skill_phase), skill_remaining]
	_skill_status.text = "스킬 phase: " + skill_text

	var cooldowns: Array = _player.get("skill_cooldowns")
	_cooldown_status.text = "쿨다운: Num4 %.2f초 · Num5 %.2f초" % [float(cooldowns[0]), float(cooldowns[1])]
	_hitstun_status.text = "플레이어 경직: %.2f초" % float(_player.get("hitstun_remaining"))
	_health_status.text = "체력: 플레이어 %d / %d · 레이더 %d / %d" % [
		int(_player.get("health")), int(_player.get("max_health")),
		int(_raider.get("health")), int(_raider.get("max_health")),
	]
	var raider_phase := str(_raider.get("attack_phase"))
	var raider_text := "대기" if raider_phase == "idle" else "%s · %.2f초" % [
		_phase_name(raider_phase), float(_raider.get("attack_phase_remaining")),
	]
	_raider_status.text = "레이더 공격: " + raider_text

func _phase_name(phase: String) -> String:
	match phase:
		"startup":
			return "준비"
		"active":
			return "공격 판정"
		"recovery":
			return "후딜"
		"windup":
			return "공격 예고"
		_:
			return phase
