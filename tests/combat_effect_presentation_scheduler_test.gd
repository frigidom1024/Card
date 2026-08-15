extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_same_batch_effects_follow_effect_dependency()
	_test_different_batches_run_when_locks_do_not_conflict()
	_test_same_entity_lock_serializes_across_batches()
	_test_clips_follow_internal_dependencies_and_duration_weights()
	await _test_empty_effect_finishes_deferred()
	_test_missing_presenter_and_duplicate_completion_are_safe()
	_test_cancel_all_completes_effects_and_releases_locks()
	_test_active_handles_receive_battle_speed_changes()
	await _test_dependency_cycles_complete_safely()
	quit(1 if _failures > 0 else 0)


func _test_same_batch_effects_follow_effect_dependency() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var finished: Array[String] = []
	scheduler.effect_plan_finished.connect(
		func(_batch_id: String, _effect_id: String, effect_key: String) -> void:
			finished.append(effect_key)
	)
	var first := _plan("batch", "first", "clip_first", [&"entity:card_a"])
	var second := _plan("batch", "second", "clip_second", [&"entity:monster"])
	second.starts_after_effect_keys = [first.effect_key]
	scheduler.enqueue_effect_plan(first)
	scheduler.enqueue_effect_plan(second)
	_expect(bridge.started_clip_ids == ["clip_first"], "后一个 Effect 尚未启动")
	bridge.finish("clip_first")
	_expect(
		bridge.started_clip_ids == ["clip_first", "clip_second"],
		"前一个 Effect 完成后启动后一个 Effect"
	)
	_expect(finished == [first.effect_key], "Effect 逐个独立完成")
	bridge.finish("clip_second")
	_expect(finished == [first.effect_key, second.effect_key], "两个 Effect 分别发出完成")


func _test_different_batches_run_when_locks_do_not_conflict() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var attack := _plan("attack_batch", "damage", "attack", [&"entity:monster"])
	var gold := _plan("operation_batch", "spend_gold", "gold", [&"hud:gold"])
	scheduler.enqueue_effect_plan(attack)
	scheduler.enqueue_effect_plan(gold)
	_expect(bridge.started_clip_ids.has("attack"), "主战斗 Effect 已启动")
	_expect(bridge.started_clip_ids.has("gold"), "操作 Effect 可跨 Batch 并行")


func _test_same_entity_lock_serializes_across_batches() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var damage := _plan("attack_batch", "damage", "damage", [&"entity:card_a"])
	var shield := _plan("operation_batch", "shield", "shield", [&"entity:card_a"])
	scheduler.enqueue_effect_plan(damage)
	scheduler.enqueue_effect_plan(shield)
	_expect(not bridge.started_clip_ids.has("shield"), "同实体 Effect 等待资源锁")
	bridge.finish("damage")
	_expect(bridge.started_clip_ids.has("shield"), "锁释放后启动等待的 Effect")


func _test_clips_follow_internal_dependencies_and_duration_weights() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var plan := CombatEffectPresentationPlan.new()
	plan.batch_id = "batch"
	plan.effect_id = "multi"
	plan.effect_key = CombatEffectPresentationPlan.make_effect_key(plan.batch_id, plan.effect_id)
	plan.recommended_duration = 3.0
	var first := _clip("first", [&"entity:card_a"], 1.0)
	var parallel := _clip("parallel", [&"entity:monster"], 1.0)
	var after := _clip("after", [&"hud:gold"], 1.0)
	after.start_after = ["first"]
	plan.add_clip(first)
	plan.add_clip(parallel)
	plan.add_clip(after)
	scheduler.enqueue_effect_plan(plan)
	_expect(bridge.started_clip_ids.has("first"), "无依赖 Clip 立即启动")
	_expect(bridge.started_clip_ids.has("parallel"), "同 Effect 无锁冲突 Clip 可并行")
	_expect(not bridge.started_clip_ids.has("after"), "内部依赖未完成前不启动")
	_expect(is_equal_approx(bridge.durations["first"], 1.0), "按权重分配推荐时长")
	bridge.finish("first")
	_expect(bridge.started_clip_ids.has("after"), "内部依赖完成后启动 Clip")


func _test_empty_effect_finishes_deferred() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var finished: Array[String] = []
	var empty := _empty_plan("batch", "empty")
	scheduler.enqueue_effect_plan(empty)
	scheduler.effect_plan_finished.connect(
		func(_batch_id: String, _effect_id: String, effect_key: String) -> void:
			finished.append(effect_key)
	)
	_expect(finished.is_empty(), "空 Effect 不同步完成")
	await process_frame
	_expect(finished == [empty.effect_key], "空 Effect 下一帧完成")


func _test_missing_presenter_and_duplicate_completion_are_safe() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	bridge.missing_clip_types = [CombatPresentationClipTypes.CARD_HIT]
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var finished: Array[String] = []
	scheduler.effect_plan_finished.connect(
		func(_batch_id: String, _effect_id: String, effect_key: String) -> void:
			finished.append(effect_key)
	)
	var missing := _plan("batch", "missing", "missing", [])
	missing.clips[0].clip_type = CombatPresentationClipTypes.CARD_HIT
	scheduler.enqueue_effect_plan(missing)
	_expect(finished == [missing.effect_key], "Bridge 返回 null 时安全完成 Effect")

	var normal := _plan("batch", "normal", "normal", [])
	scheduler.enqueue_effect_plan(normal)
	bridge.finish("normal")
	bridge.finish("normal")
	_expect(finished.count(normal.effect_key) == 1, "重复句柄完成不重复完成 Effect")


func _test_cancel_all_completes_effects_and_releases_locks() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var finished: Array[String] = []
	scheduler.effect_plan_finished.connect(
		func(_batch_id: String, _effect_id: String, effect_key: String) -> void:
			finished.append(effect_key)
	)
	var running := _plan("batch_a", "running", "running", [&"entity:card_a"])
	var waiting := _plan("batch_b", "waiting", "waiting", [&"entity:card_a"])
	scheduler.enqueue_effect_plan(running)
	scheduler.enqueue_effect_plan(waiting)
	scheduler.cancel_all()
	_expect(finished.has(running.effect_key), "取消会完成运行中的 Effect")
	_expect(finished.has(waiting.effect_key), "取消会完成等待中的 Effect")
	_expect(not scheduler.is_presenting_effect(running.effect_key), "取消后不再保留运行状态")

	var next := _plan("batch_c", "next", "next", [&"entity:card_a"])
	scheduler.enqueue_effect_plan(next)
	_expect(bridge.started_clip_ids.has("next"), "取消后资源锁已释放")


func _test_active_handles_receive_battle_speed_changes() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var plan := _plan("batch", "speed", "speed", [])
	plan.requested_battle_speed = 2.0
	scheduler.set_battle_speed(4.0)
	scheduler.enqueue_effect_plan(plan)
	var handle: CombatAnimationHandle = bridge.handles["speed"]
	_expect(is_equal_approx(handle.get_speed_scale(), 2.0), "启动时按战斗速度设置句柄")
	scheduler.set_battle_speed(1.0)
	_expect(is_equal_approx(handle.get_speed_scale(), 0.5), "活动句柄立即收到战斗速度变化")


func _test_dependency_cycles_complete_safely() -> void:
	var bridge := FakeCombatPresentationBridge.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var finished: Array[String] = []
	scheduler.effect_plan_finished.connect(
		func(_batch_id: String, _effect_id: String, effect_key: String) -> void:
			finished.append(effect_key)
	)
	var clip_cycle := CombatEffectPresentationPlan.new()
	clip_cycle.batch_id = "clip_batch"
	clip_cycle.effect_id = "clip_cycle"
	clip_cycle.effect_key = CombatEffectPresentationPlan.make_effect_key(
		clip_cycle.batch_id,
		clip_cycle.effect_id
	)
	var clip_a := _clip("clip_a", [], 1.0)
	var clip_b := _clip("clip_b", [], 1.0)
	clip_a.start_after = ["clip_b"]
	clip_b.start_after = ["clip_a"]
	clip_cycle.add_clip(clip_a)
	clip_cycle.add_clip(clip_b)
	scheduler.enqueue_effect_plan(clip_cycle)
	_expect(finished.has(clip_cycle.effect_key), "Clip 循环依赖安全完成所属 Effect")

	var effect_a := _empty_plan("effect_batch", "effect_a")
	var effect_b := _empty_plan("effect_batch", "effect_b")
	effect_a.starts_after_effect_keys = [effect_b.effect_key]
	effect_b.starts_after_effect_keys = [effect_a.effect_key]
	scheduler.enqueue_effect_plan(effect_a)
	scheduler.enqueue_effect_plan(effect_b)
	await process_frame
	_expect(finished.has(effect_a.effect_key), "Effect 循环依赖安全完成第一个 Effect")
	_expect(finished.has(effect_b.effect_key), "Effect 循环依赖安全完成第二个 Effect")


func _plan(
	batch_id: String,
	effect_id: String,
	clip_id: String,
	locks: Array[StringName]
) -> CombatEffectPresentationPlan:
	var plan := _empty_plan(batch_id, effect_id)
	plan.recommended_duration = 1.0
	plan.add_clip(_clip(clip_id, locks, 1.0))
	return plan


func _empty_plan(batch_id: String, effect_id: String) -> CombatEffectPresentationPlan:
	var plan := CombatEffectPresentationPlan.new()
	plan.batch_id = batch_id
	plan.effect_id = effect_id
	plan.effect_key = CombatEffectPresentationPlan.make_effect_key(batch_id, effect_id)
	return plan


func _clip(
	clip_id: String,
	locks: Array[StringName],
	duration_weight: float
) -> CombatPresentationClip:
	var clip := CombatPresentationClip.new()
	clip.clip_id = clip_id
	clip.clip_type = CombatPresentationClipTypes.CARD_TRIGGER
	clip.resource_locks.assign(locks)
	clip.duration_weight = duration_weight
	return clip


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
