extends SceneTree

const CombatScene = preload("res://scenes/game/event_combat.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_steps_render_in_order_and_update_after_snapshots()
	await _test_result_panel_stays_hidden_until_all_steps_finish_then_formats_retreat_penalty()
	await _test_victory_and_defeat_settlement_copy_and_confirmation_signal()
	quit(0 if _failure_count == 0 else 1)


func _test_steps_render_in_order_and_update_after_snapshots() -> void:
	var view := await _make_view()
	if view == null:
		return
	var steps: Array[CombatStep] = [
		_step(CombatStep.Kind.ROOT_CARD, "火种", 10, 10),
		_step(CombatStep.Kind.PLAYER_CARD, "短剑", 8, 3),
	]
	view.call("show_combat", null, _make_mob("森林狼"), _result(CombatResult.Outcome.VICTORY, steps))

	var progress_button := view.find_child("ProgressButton", true, false) as Button
	var combat_log := view.find_child("CombatLog", true, false) as RichTextLabel
	var player_stats := view.find_child("PlayerStatsLabel", true, false) as Label
	var monster_stats := view.find_child("MonsterStatsLabel", true, false) as Label
	_expect(progress_button != null, "combat view exposes ProgressButton for advancing playback")
	_expect(combat_log != null, "combat view exposes CombatLog for step output")
	if progress_button != null:
		progress_button.pressed.emit()
	if combat_log != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		combat_log.gui_input.emit(click)

	var log_text := combat_log.get_parsed_text() if combat_log != null else ""
	_expect(log_text.find("根牌效果：火种") >= 0, "combat log renders root-card step")
	_expect(log_text.find("玩家结算：短剑") >= 0, "combat log renders player-card step")
	_expect(
		log_text.find("根牌效果：火种") < log_text.find("玩家结算：短剑"),
		"combat log keeps CombatResult step order"
	)
	_expect(player_stats != null and player_stats.text.contains("8"), "player stats use the final step after snapshot")
	_expect(monster_stats != null and monster_stats.text.contains("3"), "monster stats use the final step after snapshot")
	_cleanup_view(view)


func _test_result_panel_stays_hidden_until_all_steps_finish_then_formats_retreat_penalty() -> void:
	var view := await _make_view()
	if view == null:
		return
	var penalties: Array[CombatPenalty] = [CombatPenaltyRemoveTailCard.new()]
	view.call(
		"show_combat",
		null,
		_make_mob("森林狼"),
		_result(CombatResult.Outcome.RETREAT, [_step(CombatStep.Kind.PLAYER_CARD, "短剑", 8, 6)], penalties)
	)

	var progress_button := view.find_child("ProgressButton", true, false) as Button
	var result_panel := view.find_child("ResultPanel", true, false) as Control
	var result_title := view.find_child("ResultTitleLabel", true, false) as Label
	var result_body := view.find_child("ResultBodyLabel", true, false) as Label
	var penalty_list := view.find_child("PenaltyList", true, false) as VBoxContainer
	var confirm_button := view.find_child("ConfirmButton", true, false) as Button
	_expect(result_panel != null and not result_panel.visible, "settlement stays hidden before all steps finish")
	if progress_button != null:
		progress_button.pressed.emit()
	_expect(result_panel != null and not result_panel.visible, "finished log waits for explicit settlement view")
	_expect(progress_button != null and progress_button.text == "查看结算", "progress button changes after final step")
	if progress_button != null:
		progress_button.pressed.emit()
	_expect(result_panel != null and result_panel.visible, "explicit settlement action reveals result panel")
	_expect(result_title != null and result_title.text == "撤离", "retreat settlement uses retreat title")
	_expect(result_body != null and result_body.text.contains("未能击败"), "retreat settlement explains unresolved monster")
	_expect(
		penalty_list != null and penalty_list.get_child_count() == 1,
		"retreat settlement renders every combat penalty"
	)
	if penalty_list != null and penalty_list.get_child_count() == 1:
		var penalty_label := penalty_list.get_child(0) as Label
		_expect(
			penalty_label != null and penalty_label.text == penalties[0].description,
			"retreat settlement uses the penalty description"
		)
	_expect(
		confirm_button != null and confirm_button.text == "接受惩罚并继续",
		"retreat settlement names the confirmation action"
	)
	_cleanup_view(view)


func _test_victory_and_defeat_settlement_copy_and_confirmation_signal() -> void:
	var view := await _make_view()
	if view == null:
		return
	var confirmations: Array[bool] = []
	_expect(view.has_signal("settlement_confirmed"), "combat view exposes settlement confirmation signal")
	if view.has_signal("settlement_confirmed"):
		view.connect("settlement_confirmed", func(): confirmations.append(true))

	view.call("show_combat", null, _make_mob("森林狼"), _result(CombatResult.Outcome.VICTORY, []))
	var progress_button := view.find_child("ProgressButton", true, false) as Button
	var result_title := view.find_child("ResultTitleLabel", true, false) as Label
	var confirm_button := view.find_child("ConfirmButton", true, false) as Button
	if progress_button != null:
		progress_button.pressed.emit()
	_expect(result_title != null and result_title.text == "遭遇胜利", "victory settlement uses victory title")
	_expect(confirm_button != null and confirm_button.text == "确认继续", "victory settlement names confirmation action")
	if confirm_button != null:
		confirm_button.pressed.emit()
	_expect(confirmations.size() == 1, "confirmation button only emits the settlement confirmation signal")

	view.call("hide_combat")
	view.call("show_combat", null, _make_mob("森林狼"), _result(CombatResult.Outcome.DEFEAT, []))
	if progress_button != null:
		progress_button.pressed.emit()
	_expect(result_title != null and result_title.text == "远征失败", "defeat settlement uses defeat title")
	_expect(confirm_button != null and confirm_button.text == "确认", "defeat settlement names confirmation action")
	_cleanup_view(view)


func _make_view() -> Control:
	var view := CombatScene.instantiate() as Control
	_expect(view != null, "combat scene instantiates for behavior test")
	if view == null:
		return null
	root.add_child(view)
	await process_frame
	return view


func _cleanup_view(view: Control) -> void:
	if view != null:
		view.queue_free()
	await process_frame


func _step(kind: CombatStep.Kind, source_name: String, player_hp: int, monster_hp: int) -> CombatStep:
	return CombatStep.new(
		kind,
		source_name,
		[],
		_stats(player_hp + 1),
		_stats(player_hp),
		_stats(monster_hp + 1),
		_stats(monster_hp)
	)


func _result(
	outcome: CombatResult.Outcome, steps: Array[CombatStep], penalties: Array[CombatPenalty] = []
) -> CombatResult:
	return CombatResult.new(outcome, _stats(8, 2), _stats(3), steps, steps.size(), penalties)


func _stats(hp: int, defense: int = 0) -> CombatStats:
	var stats := CombatStats.new()
	stats.max_hp = 20
	stats.hp = hp
	stats.attack = 0
	stats.defense = defense
	return stats


func _make_mob(name: String) -> MobInstance:
	var stats_data := CombatStatsData.new()
	stats_data.max_hp = 20
	var mob_data := MobData.new()
	mob_data.mob_name = name
	mob_data.base_stats = stats_data
	return mob_data.create_instance()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
