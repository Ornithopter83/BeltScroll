extends Node2D
"""Isolated manual arena that reports the real Player and ForestRaider state."""

@onready var _player: CharacterBody2D = $YSortActors/Player
@onready var _raider: CharacterBody2D = $YSortActors/ForestRaider
@onready var _attack_status: Label = $TestHUD/Panel/Margin/Rows/AttackStatus
@onready var _skill_status: Label = $TestHUD/Panel/Margin/Rows/SkillStatus
@onready var _cooldown_status: Label = $TestHUD/Panel/Margin/Rows/CooldownStatus
@onready var _hitstun_status: Label = $TestHUD/Panel/Margin/Rows/HitstunStatus
@onready var _health_status: Label = $TestHUD/Panel/Margin/Rows/HealthStatus
@onready var _raider_status: Label = $TestHUD/Panel/Margin/Rows/RaiderStatus
@onready var _position_status: Label = $TestHUD/Panel/Margin/Rows/PositionStatus
@onready var _record_status: Label = $TestHUD/Panel/Margin/Rows/RecordStatus
@onready var _event_status: Label = $TestHUD/Panel/Margin/Rows/EventStatus

const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")
const PLAYER_ID := "Player"
const RAIDER_ID := "ForestRaider"
const RECORD_META := "m6j_arena_repeatability_records"

var _player_skill_cooldowns: Array = []
var _record: Dictionary = {}
var _pending_attack_stage := 0
var _pending_skill_id := 0
var _last_player_attack_phase := "idle"
var _last_player_skill_phase := "idle"
var _last_event := "전투를 시작하세요."
var _round_finished := false

func _ready() -> void:
	_apply_saved_combat_settings()
	_load_record()
	_player.connect("attack_started", _on_player_attack_started)
	_player.connect("attack_hit", _on_player_attack_hit)
	_player.connect("skill_started", _on_player_skill_started)
	_player.connect("skill_hit", _on_player_skill_hit)
	_player.connect("player_hit", _on_player_hit)
	_player.connect("player_ko", _on_player_ko)
	_raider.connect("raider_hit", _on_raider_hit)
	_raider.connect("raider_ko", _on_raider_ko)
	_raider.connect("attack_windup_started", _on_raider_attack_windup)
	_update_readout()

func _apply_saved_combat_settings(data_path: String = DATA_LOADER.DATA_PATH) -> void:
	# The arena reads the editor's saved overrides and applies them only to these
	# live scene instances. It never writes back to the project settings or assets.
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

func _load_record() -> void:
	if get_tree().has_meta(RECORD_META):
		_record = get_tree().get_meta(RECORD_META)
	else:
		_record = {"rounds": 0, "successes": 0, "failures": 0, "attempts": 0, "hits": 0, "misses": 0}
		_save_record()

func _save_record() -> void:
	get_tree().set_meta(RECORD_META, _record)

func _on_player_attack_started(stage: int) -> void:
	_begin_round_if_needed()
	if _pending_attack_stage > 0:
		_record["misses"] = int(_record["misses"]) + 1
	_pending_attack_stage = stage
	_record["attempts"] = int(_record["attempts"]) + 1
	_last_event = "기본 공격 %d단계 시작" % stage
	_save_record()

func _on_player_attack_hit(stage: int) -> void:
	_record["hits"] = int(_record["hits"]) + 1
	_pending_attack_stage = 0
	_last_event = "기본 공격 %d단계 적중" % stage
	_save_record()

func _on_player_skill_started(skill_id: int) -> void:
	_begin_round_if_needed()
	if _pending_skill_id > 0:
		_record["misses"] = int(_record["misses"]) + 1
	_pending_skill_id = skill_id
	_record["attempts"] = int(_record["attempts"]) + 1
	_last_event = "Num%d 스킬 시작" % (skill_id + 3)
	var index := skill_id - 1
	if index >= 0 and index < _player_skill_cooldowns.size():
		var cooldowns: Array = _player.get("skill_cooldowns")
		if index < cooldowns.size():
			cooldowns[index] = float(_player_skill_cooldowns[index])
			_player.set("skill_cooldowns", cooldowns)
	_save_record()

func _on_player_skill_hit(skill_id: int) -> void:
	_record["hits"] = int(_record["hits"]) + 1
	_pending_skill_id = 0
	_last_event = "Num%d 스킬 판정 적중" % (skill_id + 3)
	_save_record()

func _on_player_hit(stage: int) -> void:
	_last_event = "레이더 공격 적중 · Player %d단계 피격" % stage

func _on_raider_hit(stage: int) -> void:
	_last_event = "레이더 피격 · 공격 단계 %d" % stage

func _on_raider_attack_windup() -> void:
	_begin_round_if_needed()
	_last_event = "레이더 공격 예고 · 회피하거나 가드하세요"

func _on_player_ko() -> void:
	_finish_round(false)

func _on_raider_ko() -> void:
	_finish_round(true)

func _begin_round_if_needed() -> void:
	if bool(_record.get("round_active", false)):
		return
	_record["rounds"] = int(_record.get("rounds", 0)) + 1
	_record["round_active"] = true
	_record["last_result"] = "진행 중"
	_round_finished = false
	_save_record()

func _finish_round(success: bool) -> void:
	if _round_finished:
		return
	if not bool(_record.get("round_active", false)):
		_begin_round_if_needed()
	_record["round_active"] = false
	_round_finished = true
	if success:
		_record["successes"] = int(_record.get("successes", 0)) + 1
		_record["last_result"] = "성공 · Raider KO"
		_last_event = "시험 성공 · 레이더를 쓰러뜨렸습니다. R로 재시작"
	else:
		_record["failures"] = int(_record.get("failures", 0)) + 1
		_record["last_result"] = "실패 · Player KO"
		_last_event = "시험 실패 · 플레이어가 쓰러졌습니다. R로 재시작"
	_pending_attack_stage = 0
	_pending_skill_id = 0
	_save_record()

func _process(_delta: float) -> void:
	_resolve_finished_attempts()
	_update_readout()

func _resolve_finished_attempts() -> void:
	var attack_phase := str(_player.get("attack_phase"))
	if _pending_attack_stage > 0 and _last_player_attack_phase != "idle" and attack_phase == "idle":
		_record["misses"] = int(_record["misses"]) + 1
		_last_event = "기본 공격 %d단계 빗나감 또는 중단" % _pending_attack_stage
		_pending_attack_stage = 0
		_save_record()
	_last_player_attack_phase = attack_phase
	var skill_phase := str(_player.get("skill_phase"))
	if _pending_skill_id > 0 and _last_player_skill_phase != "idle" and skill_phase == "idle":
		_record["misses"] = int(_record["misses"]) + 1
		_last_event = "Num%d 스킬 빗나감 또는 중단" % (_pending_skill_id + 3)
		_pending_skill_id = 0
		_save_record()
	_last_player_skill_phase = skill_phase

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
	_attack_status.text = "Player 기본 공격: " + attack_text

	var skill_id := int(_player.get("skill_id"))
	var skill_phase := str(_player.get("skill_phase"))
	var skill_remaining := float(_player.get("skill_phase_remaining"))
	var skill_text := "대기" if skill_phase == "idle" else "Num%d · %s · %.2f초" % [skill_id + 3, _phase_name(skill_phase), skill_remaining]
	_skill_status.text = "스킬 활성/판정: " + skill_text

	var cooldowns: Array = _player.get("skill_cooldowns")
	_cooldown_status.text = "쿨다운: Num4 돌진 %.2f초 · Num5 회전 %.2f초" % [float(cooldowns[0]), float(cooldowns[1])]
	_hitstun_status.text = "경직: Player %.2f초 · Raider %.2f초" % [float(_player.get("hitstun_remaining")), float(_raider.get("hitstun_remaining"))]
	_health_status.text = "HP: Player %d / %d · Raider %d / %d" % [
		int(_player.get("health")), int(_player.get("max_health")),
		int(_raider.get("health")), int(_raider.get("max_health")),
	]
	var raider_phase := str(_raider.get("attack_phase"))
	var raider_text := "대기" if raider_phase == "idle" else "%s · %.2f초" % [
		_phase_name(raider_phase), float(_raider.get("attack_phase_remaining")),
	]
	_raider_status.text = "Raider 반격: " + raider_text
	var delta := _raider.global_position - _player.global_position
	var horizontal := "오른쪽" if delta.x >= 0.0 else "왼쪽"
	var depth := "같은 라인" if absf(delta.y) <= float(_raider.get("attack_depth_tolerance")) else ("아래쪽" if delta.y > 0.0 else "위쪽")
	_position_status.text = "방향/간격: Raider %s · X %.0fpx · 깊이 %.0fpx(%s)" % [horizontal, absf(delta.x), absf(delta.y), depth]
	_record_status.text = "시험 기록: %d회 · 성공 %d / 실패 %d · 공격·스킬 적중 %d / 시도 %d · 빗나감 %d · 최근 %s" % [
		int(_record.get("rounds", 0)), int(_record.get("successes", 0)), int(_record.get("failures", 0)),
		int(_record.get("hits", 0)), int(_record.get("attempts", 0)), int(_record.get("misses", 0)), String(_record.get("last_result", "대기")),
	]
	_event_status.text = "최근 전투 이벤트: " + _last_event

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
