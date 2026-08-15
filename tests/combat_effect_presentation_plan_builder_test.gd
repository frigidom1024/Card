extends SceneTree

var _failures := 0
var _builder := CombatEffectPresentationPlanBuilder.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_one_batch_builds_one_plan_per_effect()
	_test_action_semantics_come_from_effect_tags()
	_test_player_damage_clip_order_and_fact_payloads()
	_test_monster_damage_clip_order()
	_test_chain_split_and_lifecycle_filtering()
	quit(1 if _failures > 0 else 0)


func _test_one_batch_builds_one_plan_per_effect() -> void:
	var result := _result("operation", CombatEffectBatch.Type.PLAYER_OPERATION, [
		_event(CombatEventTypes.PLAYER_OPERATION_STARTED, "", 0),
		_effect_applied("spend", 1, CombatEffectTypes.SPEND_GOLD, [], "player", ["player"]),
		_event(
			CombatEventTypes.GOLD_CHANGED,
			"spend",
			2,
			{"path": ["player", "gold"], "before": 10, "after": 7, "delta": -3},
			"player",
			["player"]
		),
		_effect_applied(
			"shield",
			3,
			CombatEffectTypes.MODIFY_SHIELD,
			[],
			"card_a",
			["card_a"]
		),
		_event(
			CombatEventTypes.SHIELD_CHANGED,
			"shield",
			4,
			{"path": ["cards", "card_a", "shield"], "before": 0, "after": 3, "delta": 3},
			"card_a",
			["card_a"]
		),
		_event(CombatEventTypes.PLAYER_OPERATION_FINISHED, "", 5),
	])
	var plans := _builder.build_effect_plans(result, 0.6, 1.0)
	_expect(plans.size() == 2, "一个 Batch 的两个 Effect 生成两个 Plan")
	if plans.size() != 2:
		return
	_expect(plans[0].effect_key == "operation/spend", "第一个 Effect 身份正确")
	_expect(plans[1].effect_key == "operation/shield", "第二个 Effect 身份正确")
	_expect(
		plans[1].starts_after_effect_keys == [plans[0].effect_key],
		"同 Batch Effect 默认通过 Effect 依赖串行"
	)
	_expect(is_equal_approx(plans[0].recommended_duration, 0.3), "时长预算按 Effect 平分")
	_expect(is_equal_approx(plans[1].requested_battle_speed, 1.0), "记录请求时战斗速度")
	_expect(_types(plans[0]) == [CombatPresentationClipTypes.GOLD_CHANGE], "金币事实生成 HUD Clip")
	_expect(
		_types(plans[1]) == [CombatPresentationClipTypes.CARD_SHIELD_CHANGE],
		"护盾事实生成卡牌数字 Clip"
	)


func _test_action_semantics_come_from_effect_tags() -> void:
	var tagged_attack := _damage_result(
		"tagged",
		CombatEffectBatch.Type.PLAYER_ATTACK,
		[CombatEffectTags.PRESENTATION_CARD_ATTACK]
	)
	var untagged_attack := _damage_result(
		"untagged",
		CombatEffectBatch.Type.PLAYER_ATTACK,
		[]
	)
	var operation_attack := _damage_result(
		"operation",
		CombatEffectBatch.Type.PLAYER_OPERATION,
		[CombatEffectTags.PRESENTATION_CARD_ATTACK]
	)
	_expect(
		_types(_builder.build_effect_plans(tagged_attack, 1.0, 1.0)[0]).has(
			CombatPresentationClipTypes.CARD_ATTACK
		),
		"带动作标签的 Damage Effect 生成卡牌攻击"
	)
	_expect(
		not _types(_builder.build_effect_plans(untagged_attack, 1.0, 1.0)[0]).has(
			CombatPresentationClipTypes.CARD_ATTACK
		),
		"相同 batch_type 没有标签时不生成卡牌攻击"
	)
	_expect(
		_types(_builder.build_effect_plans(operation_attack, 1.0, 1.0)[0]).has(
			CombatPresentationClipTypes.CARD_ATTACK
		),
		"PLAYER_OPERATION 中带标签的 Effect 仍生成卡牌攻击"
	)


func _test_player_damage_clip_order_and_fact_payloads() -> void:
	var events: Array[CombatStateEvent] = [
		_event(CombatEventTypes.PLAYER_ATTACK_STARTED, "", 0),
		_event(
			CombatEventTypes.SHIELD_CHANGED,
			"damage",
			1,
			{"path": ["monster", "shield"], "before": 2, "after": 0, "delta": -2},
			"card_a",
			["monster_a"]
		),
		_event(
			CombatEventTypes.HEALTH_CHANGED,
			"damage",
			2,
			{"path": ["monster", "hp"], "before": 3, "after": 0, "delta": -3},
			"card_a",
			["monster_a"]
		),
		_event(
			CombatEventTypes.DAMAGE_APPLIED,
			"damage",
			3,
			{"incoming": 5, "absorbed": 2, "applied": 3},
			"card_a",
			["monster_a"]
		),
		_effect_applied(
			"damage",
			4,
			CombatEffectTypes.DAMAGE,
			[CombatEffectTags.PRESENTATION_CARD_ATTACK],
			"card_a",
			["monster_a"]
		),
		_event(
			CombatEventTypes.MONSTER_DIED,
			"damage",
			5,
			{"monster_id": "monster_a"},
			"monster_a",
			["monster_a"]
		),
		_event(CombatEventTypes.PLAYER_ATTACK_FINISHED, "", 6),
	]
	var plan := _builder.build_effect_plans(
		_result("player_attack", CombatEffectBatch.Type.PLAYER_ATTACK, events),
		1.0,
		1.0
	)[0]
	var expected: Array[StringName] = [
		CombatPresentationClipTypes.CARD_ATTACK,
		CombatPresentationClipTypes.MONSTER_HIT,
		CombatPresentationClipTypes.MONSTER_SHIELD_CHANGE,
		CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE,
		CombatPresentationClipTypes.MONSTER_DEATH,
	]
	_expect(_types(plan) == expected, "玩家 Damage Effect 使用语义顺序构建 Clip")
	_expect(plan.clips[1].start_after == [plan.clips[0].clip_id], "受击等待卡牌攻击")
	_expect(plan.clips[2].start_after == [plan.clips[1].clip_id], "护盾数字等待受击")
	_expect(plan.clips[3].start_after == [plan.clips[2].clip_id], "生命数字等待护盾数字")
	_expect(plan.clips[4].start_after == [plan.clips[3].clip_id], "死亡等待生命数字")
	_expect(
		plan.clips[2].payload == events[1].payload,
		"护盾数字 payload 直接复制已提交事实"
	)
	_expect(
		plan.clips[3].payload == events[2].payload,
		"生命数字 payload 直接复制已提交事实"
	)
	_expect(_count_type(plan, CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE) == 1, "伤害事实不重复生成数值 Clip")


func _test_monster_damage_clip_order() -> void:
	var events: Array[CombatStateEvent] = [
		_event(
			CombatEventTypes.SHIELD_CHANGED,
			"damage",
			0,
			{"path": ["cards", "card_a", "shield"], "before": 1, "after": 0, "delta": -1},
			"monster_a",
			["card_a"]
		),
		_event(
			CombatEventTypes.CARD_POINTS_CHANGED,
			"damage",
			1,
			{"path": ["cards", "card_a", "points"], "before": 2, "after": 0, "delta": -2},
			"monster_a",
			["card_a"]
		),
		_event(CombatEventTypes.DAMAGE_APPLIED, "damage", 2, {}, "monster_a", ["card_a"]),
		_effect_applied(
			"damage",
			3,
			CombatEffectTypes.DAMAGE,
			[CombatEffectTags.PRESENTATION_MONSTER_ATTACK],
			"monster_a",
			["card_a"]
		),
		_event(
			CombatEventTypes.CARD_DIED,
			"damage",
			4,
			{"card_id": "card_a"},
			"card_a",
			["card_a"]
		),
	]
	var plan := _builder.build_effect_plans(
		_result("monster_attack", CombatEffectBatch.Type.MONSTER_ATTACK, events),
		1.0,
		1.0
	)[0]
	var expected: Array[StringName] = [
		CombatPresentationClipTypes.MONSTER_ATTACK,
		CombatPresentationClipTypes.CARD_HIT,
		CombatPresentationClipTypes.CARD_SHIELD_CHANGE,
		CombatPresentationClipTypes.CARD_POINTS_CHANGE,
		CombatPresentationClipTypes.CARD_DEATH,
	]
	_expect(_types(plan) == expected, "怪物 Damage Effect 独立构建攻击、受击、数字和死亡 Clip")


func _test_chain_split_and_lifecycle_filtering() -> void:
	var split_payload := {
		"target_card_id": "card_b",
		"active_card_ids": ["card_root"],
		"detached_card_ids": ["card_b", "card_head"],
	}
	var result := _result("retreat", CombatEffectBatch.Type.PLAYER_OPERATION, [
		_event(CombatEventTypes.BATCH_STARTED, "", 0),
		_event(CombatEventTypes.PLAYER_OPERATION_STARTED, "", 1),
		_event(CombatEventTypes.CHAIN_SPLIT, "split", 2, split_payload, "card_b", ["card_b"]),
		_effect_applied("split", 3, CombatEffectTypes.SPLIT_CHAIN, [], "card_b", ["card_b"]),
		_event(CombatEventTypes.BATCH_FINISHED, "", 4),
		_event(CombatEventTypes.PLAYER_OPERATION_FINISHED, "", 5),
	])
	var plans := _builder.build_effect_plans(result, 0.5, 1.0)
	_expect(plans.size() == 1, "生命周期和空 effect_id 事件不生成额外 Plan")
	if plans.is_empty():
		return
	_expect(
		_types(plans[0]) == [
			CombatPresentationClipTypes.CHAIN_SPLIT,
			CombatPresentationClipTypes.CHAIN_REFLOW,
		],
		"只根据已提交拆链事实构建拆链和重排"
	)
	_expect(plans[0].clips[0].payload == split_payload, "拆链动画读取正式提交 payload")
	for clip in plans[0].clips:
		var type_text := str(clip.clip_type)
		_expect(not type_text.contains("drag"), "Builder 不生成拖拽 Clip")
		_expect(not type_text.contains("preview"), "Builder 不生成预览 Clip")
		_expect(not type_text.contains("highlight"), "Builder 不生成高亮 Clip")
		_expect(not type_text.contains("target_confirm"), "Builder 不生成目标确认 Clip")


func _damage_result(
	batch_id: String,
	batch_type: CombatEffectBatch.Type,
	tags: Array[StringName]
) -> CombatEffectBatchResult:
	return _result(batch_id, batch_type, [
		_event(
			CombatEventTypes.HEALTH_CHANGED,
			"damage",
			0,
			{"path": ["monster", "hp"], "before": 10, "after": 7, "delta": -3},
			"card_a",
			["monster_a"]
		),
		_event(CombatEventTypes.DAMAGE_APPLIED, "damage", 1, {}, "card_a", ["monster_a"]),
		_effect_applied("damage", 2, CombatEffectTypes.DAMAGE, tags, "card_a", ["monster_a"]),
	])


func _result(
	batch_id: String,
	batch_type: CombatEffectBatch.Type,
	events: Array[CombatStateEvent]
) -> CombatEffectBatchResult:
	var result := CombatEffectBatchResult.new()
	result.status = CombatEffectBatchResult.Status.COMMITTED
	result.batch_id = batch_id
	result.batch_type = batch_type
	result.events = events
	return result


func _effect_applied(
	effect_id: String,
	sequence: int,
	effect_type: StringName,
	effect_tags: Array[StringName],
	source_entity_id: String = "",
	target_entity_ids: Array[String] = []
) -> CombatStateEvent:
	return _event(
		CombatEventTypes.EFFECT_APPLIED,
		effect_id,
		sequence,
		{"effect_type": effect_type, "effect_tags": effect_tags.duplicate()},
		source_entity_id,
		target_entity_ids
	)


func _event(
	event_type: StringName,
	effect_id: String,
	sequence: int,
	payload: Dictionary = {},
	source_entity_id: String = "",
	target_entity_ids: Array[String] = []
) -> CombatStateEvent:
	var event := CombatStateEvent.new(event_type, payload)
	event.effect_id = effect_id
	event.sequence = sequence
	event.source_entity_id = source_entity_id
	event.target_entity_ids.assign(target_entity_ids)
	return event


func _types(plan: CombatEffectPresentationPlan) -> Array[StringName]:
	var result: Array[StringName] = []
	for clip in plan.clips:
		result.append(clip.clip_type)
	return result


func _count_type(plan: CombatEffectPresentationPlan, clip_type: StringName) -> int:
	return _types(plan).count(clip_type)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
