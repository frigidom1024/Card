class_name CombatEventView
extends Control

signal settlement_confirmed()

const AUTO_ADVANCE_SECONDS := 0.7

@onready var _title_label: Label = $CenterContainer/Panel/Content/Header/TitleLabel
@onready var _progress_label: Label = $CenterContainer/Panel/Content/Header/ProgressLabel
@onready var _player_stats_label: Label = $CenterContainer/Panel/Content/StatusRow/PlayerStatus/PlayerStatsLabel
@onready var _monster_stats_label: Label = $CenterContainer/Panel/Content/StatusRow/MonsterStatus/MonsterStatsLabel
@onready var _combat_log: RichTextLabel = $CenterContainer/Panel/Content/CombatLog
@onready var _progress_button: Button = $CenterContainer/Panel/Content/ProgressButton
@onready var _result_panel: PanelContainer = $CenterContainer/Panel/Content/ResultPanel
@onready var _result_title_label: Label = $CenterContainer/Panel/Content/ResultPanel/Content/ResultTitleLabel
@onready var _result_body_label: Label = $CenterContainer/Panel/Content/ResultPanel/Content/ResultBodyLabel
@onready var _penalty_list: VBoxContainer = $CenterContainer/Panel/Content/ResultPanel/Content/PenaltyList
@onready var _confirm_button: Button = $CenterContainer/Panel/Content/ResultPanel/Content/ConfirmButton
@onready var _auto_advance_timer: Timer = $AutoAdvanceTimer

var _result: CombatResult
var _monster: MobInstance
var _next_step_index := 0
var _is_settlement_visible := false


func _ready() -> void:
	_auto_advance_timer.wait_time = AUTO_ADVANCE_SECONDS
	if not _auto_advance_timer.timeout.is_connected(_on_auto_advance_timeout):
		_auto_advance_timer.timeout.connect(_on_auto_advance_timeout)
	if not _progress_button.pressed.is_connected(_on_progress_button_pressed):
		_progress_button.pressed.connect(_on_progress_button_pressed)
	if not _confirm_button.pressed.is_connected(_on_confirm_button_pressed):
		_confirm_button.pressed.connect(_on_confirm_button_pressed)
	if not _combat_log.gui_input.is_connected(_on_combat_log_gui_input):
		_combat_log.gui_input.connect(_on_combat_log_gui_input)


func show_combat(_instance: EventInstance, monster: MobInstance, result: CombatResult) -> void:
	_result = result
	_monster = monster
	_next_step_index = 0
	_is_settlement_visible = false
	_clear_penalty_labels()
	_combat_log.clear()
	_title_label.text = "遭遇战斗"
	_progress_label.text = "0 / 0"
	_result_panel.hide()
	_confirm_button.hide()
	_progress_button.show()
	show()

	if _result == null:
		_progress_button.text = "查看结算"
		return

	var first_step := _first_step()
	if first_step != null:
		_update_stats(first_step.player_before, first_step.monster_before)
	else:
		_update_stats(_result.player_stats_after, _result.monster_stats_after)
	_update_progress_label()
	if _result.steps.is_empty():
		_progress_button.text = "查看结算"
		return
	_progress_button.text = "加速"
	_auto_advance_timer.start()


func hide_combat() -> void:
	_auto_advance_timer.stop()
	hide()
	_result = null
	_monster = null
	_next_step_index = 0
	_is_settlement_visible = false
	_combat_log.clear()
	_clear_penalty_labels()


func _on_auto_advance_timeout() -> void:
	if _has_pending_steps():
		_append_next_step()
	else:
		_auto_advance_timer.stop()
		_progress_button.text = "查看结算"


func _on_progress_button_pressed() -> void:
	if _is_settlement_visible:
		return
	if _has_pending_steps():
		_append_next_step()
		return
	_show_settlement()


func _on_combat_log_gui_input(event: InputEvent) -> void:
	if _is_settlement_visible or not _has_pending_steps():
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_append_next_step()


func _on_confirm_button_pressed() -> void:
	if _is_settlement_visible:
		settlement_confirmed.emit()


func _append_next_step() -> void:
	if not _has_pending_steps():
		return
	var step := _result.steps[_next_step_index]
	_next_step_index += 1
	if step != null:
		_combat_log.append_text(_format_step(step) + "\n")
		_update_stats(step.player_after, step.monster_after)
	_update_progress_label()
	if not _has_pending_steps():
		_auto_advance_timer.stop()
		_progress_button.text = "查看结算"


func _show_settlement() -> void:
	if _is_settlement_visible or _result == null:
		return
	_auto_advance_timer.stop()
	_is_settlement_visible = true
	_progress_button.hide()
	_result_panel.show()
	_confirm_button.show()
	_update_stats(_result.player_stats_after, _result.monster_stats_after)
	_populate_penalties()
	match _result.outcome:
		CombatResult.Outcome.VICTORY:
			_result_title_label.text = "遭遇胜利"
			_result_body_label.text = "已击败 %s。\n本次遭遇已解决。" % _monster_name()
			_confirm_button.text = "确认继续"
		CombatResult.Outcome.RETREAT:
			_result_title_label.text = "牌链未能击杀"
			_result_body_label.text = "未能击败 %s。\n已耗尽的卡牌离场；残响已强化。重新布置牌链后可再次挑战。" % _monster_name()
			_confirm_button.text = "重整牌链"
		CombatResult.Outcome.DEFEAT:
			_result_title_label.text = "远征失败"
			_result_body_label.text = "生命降至 0，探索结束。"
			_confirm_button.text = "确认"


func _has_pending_steps() -> bool:
	return _result != null and _next_step_index < _result.steps.size()


func _first_step() -> CombatStep:
	if _result == null:
		return null
	for step in _result.steps:
		if step != null:
			return step
	return null


func _update_progress_label() -> void:
	var step_count := _result.steps.size() if _result != null else 0
	_progress_label.text = "%d / %d" % [_next_step_index, step_count]


func _update_stats(player_stats: CombatStats, monster_stats: CombatStats) -> void:
	_player_stats_label.text = _format_stats("玩家", player_stats)
	_monster_stats_label.text = _format_stats(_monster_name(), monster_stats)


func _format_stats(subject_name: String, stats: CombatStats) -> String:
	if stats == null:
		return "%s  HP - / -   护甲 -" % subject_name
	return "%s  HP %d / %d   护甲 %d" % [subject_name, stats.hp, stats.max_hp, stats.defense]


func _format_step(step: CombatStep) -> String:
	var card_name := _source_name(step.source_name, "卡牌")
	if step.kind == CombatStep.Kind.MONSTER_ACTION:
		return "%s 行动" % card_name
	var headline := "%s：点数 %d → %d" % [
		card_name, step.card_points_before, step.card_points_after
	]
	if step.card_armor_before != step.card_armor_after:
		headline += "，护甲 %d → %d" % [step.card_armor_before, step.card_armor_after]
	if step.monster_before != null and step.monster_after != null:
		headline += "；%s 生命 %d → %d" % [
			_monster_name(), step.monster_before.hp, step.monster_after.hp
		]
	return headline


func _format_effect(effect: CombatEffect) -> String:
	match effect.type:
		CombatEffect.Type.DAMAGE:
			return "造成 %d 点伤害" % effect.value
		CombatEffect.Type.ADD_DEFENSE:
			return "获得 %d 点护甲" % effect.value
		CombatEffect.Type.HEAL:
			return "恢复 %d 点生命" % effect.value
	return "产生效果"


func _populate_penalties() -> void:
	_clear_penalty_labels()
	if _result == null:
		return
	for penalty in _result.penalties:
		if penalty == null or penalty.description.is_empty():
			continue
		var penalty_label := Label.new()
		penalty_label.text = penalty.description
		penalty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_penalty_list.add_child(penalty_label)


func _clear_penalty_labels() -> void:
	for child in _penalty_list.get_children():
		child.free()


func _monster_name() -> String:
	if _monster != null and _monster.data != null and not _monster.data.mob_name.is_empty():
		return _monster.data.mob_name
	return "怪物"


func _source_name(source_name: String, fallback: String) -> String:
	return source_name if not source_name.is_empty() else fallback
