extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_duplicate_effect_id_is_rejected()
	_test_effect_applied_exposes_type_and_tags()
	_test_flow_damage_effects_have_action_tags()
	_test_card_trigger_marks_only_first_visible_effect()
	quit(1 if _failures > 0 else 0)


func _test_duplicate_effect_id_is_rejected() -> void:
	var processor := CombatStandardEffectLibrary.create_processor(_initial_state())
	var first := CombatBatchEffect.new(
		CombatEffectTypes.MODIFY_SHIELD,
		"same",
		"card_a",
		["card_a"],
		{"amount": 1}
	)
	var second := CombatBatchEffect.new(
		CombatEffectTypes.MODIFY_CARD_POINTS,
		"same",
		"card_a",
		["card_a"],
		{"amount": 1}
	)
	var effects: Array[CombatBatchEffect] = [first, second]
	var batch := CombatBatchFactory.create_player_operation("duplicate", "operation", effects)
	processor.enqueue(batch)
	var result := processor.process_next()
	_expect(
		result.status == CombatEffectBatchResult.Status.CANCELED,
		"重复 effect_id 必须在提交前被拒绝"
	)
	_expect(result.reason_code == &"duplicate_effect_id", "重复 effect_id 使用稳定错误码")


func _test_effect_applied_exposes_type_and_tags() -> void:
	var processor := CombatStandardEffectLibrary.create_processor(_initial_state())
	var effect := CombatBatchEffect.new(
		CombatEffectTypes.MODIFY_SHIELD,
		"shield",
		"card_a",
		["card_a"],
		{"amount": 2}
	)
	effect.add_tag(CombatEffectTags.PRESENTATION_CARD_TRIGGER)
	var effects: Array[CombatBatchEffect] = [effect]
	processor.enqueue(CombatBatchFactory.create_player_operation("operation", "operation", effects))
	var result := processor.process_next()
	var applied := _find_event(result.events, CombatEventTypes.EFFECT_APPLIED)
	_expect(applied != null, "提交后必须存在 EFFECT_APPLIED")
	if applied == null:
		return
	_expect(applied.effect_id == "shield", "EFFECT_APPLIED 保留 effect_id")
	_expect(applied.payload["effect_type"] == CombatEffectTypes.MODIFY_SHIELD, "暴露 effect_type")
	_expect(
		applied.payload.get("effect_tags", []) == [CombatEffectTags.PRESENTATION_CARD_TRIGGER],
		"暴露 effect_tags"
	)


func _test_flow_damage_effects_have_action_tags() -> void:
	var processor := CombatStandardEffectLibrary.create_processor(_initial_state())
	var flow := CombatLinearChainFlowProvider.new()
	var snapshot := processor.create_snapshot()
	flow.start(snapshot)

	var player_batch := flow.build_next_batch(snapshot, null)
	_expect(player_batch != null, "必须生成玩家攻击 Batch")
	if player_batch == null:
		return
	_expect(player_batch.effects.size() == 1, "基础玩家攻击只有一个 Damage Effect")
	_expect(
		player_batch.effects[0].tags.has(CombatEffectTags.PRESENTATION_CARD_ATTACK),
		"玩家 Damage Effect 声明卡牌攻击表现"
	)

	processor.enqueue(player_batch)
	var player_result := processor.process_next()
	snapshot = processor.create_snapshot()
	flow.on_batch_finished(player_result, snapshot)

	var monster_batch := flow.build_next_batch(snapshot, player_result)
	_expect(monster_batch != null, "必须独立生成怪物攻击 Batch")
	if monster_batch == null:
		return
	_expect(monster_batch.effects.size() == 1, "基础怪物攻击只有一个 Damage Effect")
	_expect(
		monster_batch.effects[0].tags.has(CombatEffectTags.PRESENTATION_MONSTER_ATTACK),
		"怪物 Damage Effect 声明怪物攻击表现"
	)


func _test_card_trigger_marks_only_first_visible_effect() -> void:
	var first := CombatBatchEffect.new(
		CombatEffectTypes.MODIFY_SHIELD,
		"trigger:shield",
		"card_a",
		["card_a"],
		{"amount": 1}
	)
	var second := CombatBatchEffect.new(
		CombatEffectTypes.MODIFY_CARD_POINTS,
		"trigger:points",
		"card_a",
		["card_a"],
		{"amount": 1}
	)
	var effects: Array[CombatBatchEffect] = [first, second]
	var batch := CombatBatchFactory.create_card_trigger(
		"trigger_batch",
		"card_a",
		"cause_event",
		effects
	)
	_expect(
		batch.effects[0].tags.has(CombatEffectTags.PRESENTATION_CARD_TRIGGER),
		"首个 Effect 声明一次卡牌触发表现"
	)
	_expect(
		not batch.effects[1].tags.has(CombatEffectTags.PRESENTATION_CARD_TRIGGER),
		"同一触发 Batch 的后续 Effect 不重复触发卡牌抖动"
	)


func _find_event(events: Array[CombatStateEvent], event_type: StringName) -> CombatStateEvent:
	for event in events:
		if event.event_type == event_type:
			return event
	return null


func _initial_state() -> Dictionary:
	return CombatStateSchema.create_initial_state(
		{"entity_id": "player", "hp": 10, "gold": 10},
		{"entity_id": "monster", "hp": 10, "shield": 0},
		{"card_a": {"points": 3, "shield": 0}},
		["card_a"]
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
