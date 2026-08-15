extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_duplicate_effect_id_is_rejected()
	_test_effect_applied_exposes_type_and_tags()
	_test_flow_damage_effects_have_action_tags()
	_test_card_trigger_marks_only_first_visible_effect()
	_test_effect_plan_identity_and_deep_copy()
	_test_batch_barrier_waits_for_all_effects_once()
	await _test_empty_batch_barrier_completes_deferred()
	_test_animation_handle_is_idempotent()
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


func _test_effect_plan_identity_and_deep_copy() -> void:
	var clip := CombatPresentationClip.new()
	clip.clip_id = "shield"
	clip.clip_type = CombatPresentationClipTypes.CARD_SHIELD_CHANGE
	clip.source_entity_id = "card_a"
	clip.target_entity_ids = ["card_a"]
	clip.resource_locks = [CombatPresentationClipTypes.entity_lock("card_a")]
	clip.start_after = ["trigger"]
	clip.payload = {"before": 0, "after": 2, "nested": {"value": 1}}

	var plan := CombatEffectPresentationPlan.new()
	plan.batch_id = "batch_a"
	plan.effect_id = "effect_a"
	plan.effect_key = CombatEffectPresentationPlan.make_effect_key(plan.batch_id, plan.effect_id)
	plan.effect_tags = [CombatEffectTags.PRESENTATION_CARD_TRIGGER]
	plan.target_entity_ids = ["card_a"]
	plan.starts_after_effect_keys = ["batch_a/previous"]
	plan.add_clip(clip)

	var copy := plan.duplicate_plan()
	_expect(plan.effect_key == "batch_a/effect_a", "Effect 使用 batch_id/effect_id 复合键")
	_expect(plan.get_clip("shield") == clip, "可以按 clip_id 查询 Clip")
	_expect(plan.get_clip("missing") == null, "不存在的 clip_id 返回 null")
	_expect(copy != plan, "Plan 副本是独立对象")
	_expect(copy.clips[0] != clip, "Plan 副本不共享 Clip")

	copy.effect_tags.append(&"copy_tag")
	copy.target_entity_ids.append("card_b")
	copy.starts_after_effect_keys.append("batch_a/other")
	copy.clips[0].target_entity_ids.append("card_b")
	copy.clips[0].resource_locks.append(&"entity:card_b")
	copy.clips[0].start_after.append("other")
	copy.clips[0].payload["nested"]["value"] = 99
	_expect(plan.effect_tags.size() == 1, "Plan 副本不共享标签数组")
	_expect(plan.target_entity_ids.size() == 1, "Plan 副本不共享目标数组")
	_expect(plan.starts_after_effect_keys.size() == 1, "Plan 副本不共享 Effect 依赖数组")
	_expect(clip.target_entity_ids.size() == 1, "Clip 副本不共享目标数组")
	_expect(clip.resource_locks.size() == 1, "Clip 副本不共享资源锁数组")
	_expect(clip.start_after.size() == 1, "Clip 副本不共享 Clip 依赖数组")
	_expect(clip.payload["nested"]["value"] == 1, "Clip payload 必须深复制")

	var property_names: Array[String] = []
	for property in plan.get_property_list():
		property_names.append(str(property["name"]))
	_expect(not property_names.has("batch_type"), "Effect Plan 不携带 batch_type")


func _test_batch_barrier_waits_for_all_effects_once() -> void:
	var completed_batches: Array[String] = []
	var barrier := CombatBatchPresentationBarrier.new()
	barrier.completed.connect(
		func(batch_id: String) -> void:
			completed_batches.append(batch_id)
	)
	barrier.configure("batch_a", ["batch_a/a", "batch_a/a", "batch_a/b"])
	barrier.mark_effect_finished("batch_a/unknown")
	barrier.mark_effect_finished("batch_a/a")
	_expect(completed_batches.is_empty(), "未知或单个 Effect 完成不能确认 Batch")
	barrier.mark_effect_finished("batch_a/a")
	barrier.mark_effect_finished("batch_a/b")
	barrier.mark_effect_finished("batch_a/b")
	barrier.cancel_and_complete()
	_expect(completed_batches == ["batch_a"], "全部 Effect 完成后只完成一次")
	_expect(barrier.is_completed(), "完成后的屏障必须暴露完成状态")


func _test_empty_batch_barrier_completes_deferred() -> void:
	var completed_batches: Array[String] = []
	var barrier := CombatBatchPresentationBarrier.new()
	barrier.configure("empty_batch", [])
	barrier.complete_empty_deferred()
	barrier.completed.connect(
		func(batch_id: String) -> void:
			completed_batches.append(batch_id)
	)
	_expect(completed_batches.is_empty(), "空屏障不能同步完成导致信号丢失")
	await process_frame
	_expect(completed_batches == ["empty_batch"], "空屏障必须在下一帧完成")
	barrier.cancel_and_complete()
	_expect(completed_batches.size() == 1, "空屏障完成后取消仍然幂等")


func _test_animation_handle_is_idempotent() -> void:
	var completed_markers: Array[bool] = []
	var handle := CombatAnimationHandle.new()
	handle.finished.connect(func() -> void: completed_markers.append(true))
	handle.set_speed_scale(2.5)
	_expect(is_equal_approx(handle.get_speed_scale(), 2.5), "句柄保存战斗速度倍率")
	handle.complete()
	handle.cancel()
	_expect(completed_markers.size() == 1, "句柄完成和取消幂等")
	_expect(handle.is_finished(), "句柄暴露完成状态")


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
