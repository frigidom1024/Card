extends SceneTree

class FakeCombatBattleSession extends CombatBattleSession:
	var acknowledged_batch_ids: Array[String] = []

	func acknowledge_presentation(batch_id: String) -> void:
		acknowledged_batch_ids.append(batch_id)


class FakeEffectPlanBuilder extends CombatEffectPresentationPlanBuilder:
	var _plans_by_batch: Dictionary = {}

	func set_effects(batch_id: String, effect_ids: Array[String]) -> void:
		var plans: Array[CombatEffectPresentationPlan] = []
		for effect_id in effect_ids:
			var plan := CombatEffectPresentationPlan.new()
			plan.batch_id = batch_id
			plan.effect_id = effect_id
			plan.effect_key = CombatEffectPresentationPlan.make_effect_key(batch_id, effect_id)
			plans.append(plan)
		_plans_by_batch[batch_id] = plans

	func build_effect_plans(
		result: CombatEffectBatchResult,
		_recommended_duration: float,
		_requested_battle_speed: float
	) -> Array[CombatEffectPresentationPlan]:
		var configured: Array = _plans_by_batch.get(result.batch_id, [])
		var plans: Array[CombatEffectPresentationPlan] = []
		for plan: CombatEffectPresentationPlan in configured:
			plans.append(plan.duplicate_plan())
		return plans


class FakeEffectScheduler extends CombatEffectPresentationScheduler:
	var enqueued_effect_keys: Array[String] = []
	var received_speeds: Array[float] = []
	var cancel_count: int = 0

	func enqueue_effect_plan(plan: CombatEffectPresentationPlan) -> void:
		enqueued_effect_keys.append(plan.effect_key)

	func set_battle_speed(speed: float) -> void:
		received_speeds.append(speed)

	func cancel_all() -> void:
		cancel_count += 1

	func finish(batch_id: String, effect_id: String) -> void:
		var effect_key := CombatEffectPresentationPlan.make_effect_key(batch_id, effect_id)
		effect_plan_finished.emit(batch_id, effect_id, effect_key)


var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_batch_ack_waits_for_every_effect_plan()
	await _test_empty_batch_acknowledges_next_frame()
	_test_empty_effect_plan_is_still_part_of_barrier()
	_test_duplicate_effect_completion_does_not_duplicate_ack()
	_test_batch_barriers_are_independent()
	_test_battle_speed_is_clamped_emitted_and_forwarded()
	_test_shutdown_acknowledges_and_clears_pending_barriers()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _test_batch_ack_waits_for_every_effect_plan() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var builder: FakeEffectPlanBuilder = fixture["builder"]
	var scheduler: FakeEffectScheduler = fixture["scheduler"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]
	builder.set_effects("batch_a", ["first", "second"])

	session.presentation_requested.emit(_result("batch_a"), 0.4)
	_expect(
		scheduler.enqueued_effect_keys == ["batch_a/first", "batch_a/second"],
		"Coordinator 必须逐 Effect Plan 入队"
	)

	scheduler.finish("batch_a", "first")
	_expect(session.acknowledged_batch_ids.is_empty(), "一个 Effect 完成不能提前确认 Batch")
	scheduler.finish("batch_a", "second")
	_expect(session.acknowledged_batch_ids == ["batch_a"], "全部 Effect 完成后确认一次 Batch")
	_expect(coordinator.get_pending_batch_ids().is_empty(), "Batch 确认后移除屏障")
	coordinator.shutdown()


func _test_empty_batch_acknowledges_next_frame() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]

	session.presentation_requested.emit(_result("empty_batch"), 0.4)
	_expect(session.acknowledged_batch_ids.is_empty(), "空 Batch 不应在信号栈内同步确认")
	await process_frame
	_expect(session.acknowledged_batch_ids == ["empty_batch"], "空 Batch 必须在下一帧安全确认")
	coordinator.shutdown()


func _test_empty_effect_plan_is_still_part_of_barrier() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var builder: FakeEffectPlanBuilder = fixture["builder"]
	var scheduler: FakeEffectScheduler = fixture["scheduler"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]
	builder.set_effects("empty_effect_batch", ["empty_effect"])

	session.presentation_requested.emit(_result("empty_effect_batch"), 0.4)
	_expect(
		coordinator.get_pending_batch_ids() == ["empty_effect_batch"],
		"没有 Clip 的 Effect Plan 仍必须登记到 Batch 屏障"
	)
	_expect(session.acknowledged_batch_ids.is_empty(), "空 Effect 尚未完成时不能确认 Batch")
	scheduler.finish("empty_effect_batch", "empty_effect")
	_expect(
		session.acknowledged_batch_ids == ["empty_effect_batch"],
		"空 Effect 完成后正常释放 Batch"
	)
	coordinator.shutdown()


func _test_duplicate_effect_completion_does_not_duplicate_ack() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var builder: FakeEffectPlanBuilder = fixture["builder"]
	var scheduler: FakeEffectScheduler = fixture["scheduler"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]
	builder.set_effects("dedupe_batch", ["only"])

	session.presentation_requested.emit(_result("dedupe_batch"), 0.4)
	scheduler.finish("dedupe_batch", "only")
	scheduler.finish("dedupe_batch", "only")
	_expect(session.acknowledged_batch_ids == ["dedupe_batch"], "重复 Effect 完成不能重复确认 Batch")
	coordinator.shutdown()


func _test_batch_barriers_are_independent() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var builder: FakeEffectPlanBuilder = fixture["builder"]
	var scheduler: FakeEffectScheduler = fixture["scheduler"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]
	builder.set_effects("batch_left", ["left"])
	builder.set_effects("batch_right", ["right"])

	session.presentation_requested.emit(_result("batch_left"), 0.4)
	session.presentation_requested.emit(_result("batch_right"), 0.4)
	scheduler.finish("batch_right", "right")
	_expect(session.acknowledged_batch_ids == ["batch_right"], "一个 Batch 完成不影响另一个屏障")
	_expect(coordinator.get_pending_batch_ids() == ["batch_left"], "未完成 Batch 仍保持等待")
	scheduler.finish("batch_left", "left")
	_expect(
		session.acknowledged_batch_ids == ["batch_right", "batch_left"],
		"两个 Batch 分别在自己的 Effect 全部完成后确认"
	)
	coordinator.shutdown()


func _test_battle_speed_is_clamped_emitted_and_forwarded() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var scheduler: FakeEffectScheduler = fixture["scheduler"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]
	var emitted: Array[float] = []
	session.battle_speed_changed.connect(
		func(speed: float) -> void:
			emitted.append(speed)
	)

	_expect(scheduler.received_speeds == [1.0], "Coordinator 配置时同步当前战斗速度")
	session.set_battle_speed(4.0)
	_expect(is_equal_approx(session.get_battle_speed(), 4.0), "Session 暴露战斗速度")
	_expect(emitted == [4.0], "战斗速度变化向表现层广播")
	_expect(scheduler.received_speeds == [1.0, 4.0], "Coordinator 即时转发战斗速度")

	session.set_battle_speed(0.0)
	_expect(is_equal_approx(session.get_battle_speed(), 0.05), "Session 返回时钟限制后的真实战斗速度")
	_expect(is_equal_approx(emitted.back(), 0.05), "战斗速度信号发送限制后的真实值")
	_expect(is_equal_approx(scheduler.received_speeds.back(), 0.05), "调度器收到限制后的战斗速度")
	coordinator.shutdown()


func _test_shutdown_acknowledges_and_clears_pending_barriers() -> void:
	var fixture := _fixture()
	var session: FakeCombatBattleSession = fixture["session"]
	var builder: FakeEffectPlanBuilder = fixture["builder"]
	var scheduler: FakeEffectScheduler = fixture["scheduler"]
	var coordinator: CombatPresentationCoordinator = fixture["coordinator"]
	builder.set_effects("shutdown_a", ["a"])
	builder.set_effects("shutdown_b", ["b"])
	session.presentation_requested.emit(_result("shutdown_a"), 0.4)
	session.presentation_requested.emit(_result("shutdown_b"), 0.4)

	coordinator.shutdown()
	var acknowledged := session.acknowledged_batch_ids.duplicate()
	acknowledged.sort()
	_expect(acknowledged == ["shutdown_a", "shutdown_b"], "shutdown 必须释放全部待确认 Batch")
	_expect(coordinator.get_pending_batch_ids().is_empty(), "shutdown 清空全部屏障")
	_expect(scheduler.cancel_count == 1, "shutdown 只取消一次 Scheduler")

	coordinator.shutdown()
	_expect(session.acknowledged_batch_ids.size() == 2, "重复 shutdown 不重复确认 Batch")
	_expect(scheduler.cancel_count == 1, "重复 shutdown 保持幂等")


func _fixture() -> Dictionary:
	var session := FakeCombatBattleSession.new()
	var builder := FakeEffectPlanBuilder.new()
	var scheduler := FakeEffectScheduler.new()
	var coordinator := CombatPresentationCoordinator.new()
	coordinator.configure(session, builder, scheduler)
	return {
		"session": session,
		"builder": builder,
		"scheduler": scheduler,
		"coordinator": coordinator,
	}


func _result(batch_id: String) -> CombatEffectBatchResult:
	var result := CombatEffectBatchResult.new()
	result.status = CombatEffectBatchResult.Status.COMMITTED
	result.batch_id = batch_id
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)

