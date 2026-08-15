extends SceneTree

class IncrementPathHandler:
	extends CombatEffectHandler

	func _init() -> void:
		super(&"increment_path")

	func validate(effect: CombatBatchEffect, snapshot: CombatStateSnapshot) -> CombatValidationResult:
		if not effect.parameters.has("path"):
			return CombatValidationResult.rejected(&"missing_path")
		if not effect.parameters.has("amount"):
			return CombatValidationResult.rejected(&"missing_amount")
		return CombatValidationResult.accepted()

	func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
		writer.increment_value(
			effect.parameters["path"],
			int(effect.parameters["amount"]),
			&"counter_changed",
			effect.target_entity_ids[0] if not effect.target_entity_ids.is_empty() else ""
		)
		return CombatValidationResult.accepted()


class ChainMutationHandler:
	extends CombatEffectHandler

	func _init() -> void:
		super(&"split_chain")

	func apply(effect: CombatBatchEffect, writer: CombatStateWriter) -> CombatValidationResult:
		writer.set_value(["chain", "split_at"], effect.get_parameter("target", ""))
		writer.mark_chain_changed({"target_card_id": effect.get_parameter("target", "")})
		return CombatValidationResult.accepted()


class QueueFlowProvider:
	extends CombatFlowProvider

	var batches: Array[CombatEffectBatch] = []
	var next_index := 0
	var finished_ids: Array[String] = []

	func _init(p_batches: Array[CombatEffectBatch]) -> void:
		batches = p_batches.duplicate()

	func build_next_batch(
		_snapshot: CombatStateSnapshot,
		_last_result: CombatEffectBatchResult
	) -> CombatEffectBatch:
		if next_index >= batches.size():
			return null
		var batch := batches[next_index]
		next_index += 1
		return batch

	func on_batch_finished(
		result: CombatEffectBatchResult,
		_snapshot: CombatStateSnapshot
	) -> void:
		finished_ids.append(result.batch_id)

	func is_finished(_snapshot: CombatStateSnapshot) -> bool:
		return next_index >= batches.size()


class AfterPlayerAttackTriggerRule:
	extends CombatTriggerRule

	func _init() -> void:
		observed_event_type = CombatEventTypes.PLAYER_ATTACK_FINISHED
		priority = 10

	func create_batch(
		event: CombatStateEvent,
		_snapshot: CombatStateSnapshot
	) -> CombatEffectBatch:
		var effect := CombatBatchEffect.new(
			&"increment_path",
			"trigger_effect",
			"card_reactor",
			["card_reactor"],
			{"path": ["trigger_count"], "amount": 1}
		)
		return CombatBatchFactory.create_card_trigger(
			"trigger_after_player_attack",
			"card_reactor",
			event.event_id,
			[effect]
		)


var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_attack_protocols_are_separate()
	_test_processor_applies_effects_in_order_and_commits_once()
	_test_atomic_batch_rolls_back_when_later_effect_fails()
	_test_player_operation_priority_is_higher_than_flow_batch()
	_test_stale_chain_revision_cancels_pending_batch()
	_test_chain_mutation_increments_chain_revision()
	_test_driver_speed_controls_automatic_batch_interval()
	_test_player_operation_enters_processor_without_driver_planning()
	_test_driver_plans_trigger_batches_from_committed_events()
	_test_presentation_gate_keeps_operation_batches_responsive()
	quit(1 if _failure_count > 0 else 0)


func _test_attack_protocols_are_separate() -> void:
	var player := CombatBatchFactory.create_player_attack("player_attack", "card_a", [])
	var monster := CombatBatchFactory.create_monster_attack("monster_attack", "monster_a", [])
	_expect(player.batch_type == CombatEffectBatch.Type.PLAYER_ATTACK, "玩家攻击使用独立批次类型")
	_expect(monster.batch_type == CombatEffectBatch.Type.MONSTER_ATTACK, "怪物攻击使用独立批次类型")
	_expect(player.started_event_type == CombatEventTypes.PLAYER_ATTACK_STARTED, "玩家攻击使用独立开始事件")
	_expect(monster.started_event_type == CombatEventTypes.MONSTER_ATTACK_STARTED, "怪物攻击使用独立开始事件")
	_expect(player.finished_event_type != monster.finished_event_type, "玩家与怪物攻击不能共享完成事件")


func _test_processor_applies_effects_in_order_and_commits_once() -> void:
	var processor := _make_processor({"counter": 1})
	var first := _increment_effect("first", 2)
	var second := _increment_effect("second", 3)
	var batch := CombatBatchFactory.create_player_attack("ordered_player_attack", "card_a", [first, second])
	processor.enqueue(batch)
	var result := processor.process_next()
	var snapshot := processor.create_snapshot()
	_expect(result != null and result.is_committed(), "有效效果批次可以提交")
	_expect(snapshot.get_value(["counter"], -1) == 6, "批次内效果按顺序读取前一个效果的写入")
	_expect(snapshot.state_revision == 1, "一个原子批次只提交一次状态版本")
	_expect(not result.events.is_empty(), "提交批次会产生协议事件")
	if not result.events.is_empty():
		_expect(result.events.front().event_type == CombatEventTypes.PLAYER_ATTACK_STARTED, "事件包以玩家攻击开始事件开头")
		_expect(result.events.back().event_type == CombatEventTypes.PLAYER_ATTACK_FINISHED, "事件包以玩家攻击完成事件结尾")


func _test_atomic_batch_rolls_back_when_later_effect_fails() -> void:
	var processor := _make_processor({"counter": 4})
	var valid_effect := _increment_effect("valid_first", 5)
	var unsupported := CombatBatchEffect.new(&"missing_handler", "missing")
	var batch := CombatBatchFactory.create_player_attack("rollback_batch", "card_a", [valid_effect, unsupported])
	processor.enqueue(batch)
	var result := processor.process_next()
	var snapshot := processor.create_snapshot()
	_expect(result.status == CombatEffectBatchResult.Status.FAILED, "缺少效果处理器时批次失败")
	_expect(snapshot.get_value(["counter"], -1) == 4, "后续效果失败会回滚之前的草稿写入")
	_expect(snapshot.state_revision == 0, "失败批次不会增加状态版本")


func _test_player_operation_priority_is_higher_than_flow_batch() -> void:
	var processor := _make_processor({"counter": 0})
	var flow := CombatBatchFactory.create_player_attack("flow_batch", "card_a", [_increment_effect("flow", 1)])
	var operation := CombatBatchFactory.create_player_operation("operation_batch", "operation_card", [_increment_effect("operation", 10)])
	processor.enqueue(flow)
	processor.enqueue(operation)
	var first_result := processor.process_next()
	_expect(first_result.batch_id == "operation_batch", "玩家操作批次在批次边界优先于普通战斗流程")
	_expect(processor.create_snapshot().get_value(["counter"], -1) == 10, "优先执行的是玩家操作效果")


func _test_stale_chain_revision_cancels_pending_batch() -> void:
	var processor := _make_processor({})
	var chain_batch := CombatBatchFactory.create_player_operation(
		"split_chain_first",
		"retreat_card",
		[CombatBatchEffect.new(&"split_chain", "split", "retreat_card", [], {"target": "card_b"})]
	)
	processor.enqueue(chain_batch)
	processor.process_next()
	var stale := CombatBatchFactory.create_player_attack("stale_attack", "card_b", [_increment_effect("stale", 1)])
	stale.expected_chain_revision = 0
	processor.enqueue(stale)
	var result := processor.process_next()
	_expect(result.status == CombatEffectBatchResult.Status.CANCELED, "旧牌链版本上的待处理批次会被取消")
	_expect(result.reason_code == &"stale_chain_revision", "取消结果说明牌链版本已经过期")


func _test_chain_mutation_increments_chain_revision() -> void:
	var processor := _make_processor({})
	var batch := CombatBatchFactory.create_player_operation(
		"split_chain",
		"retreat_card",
		[CombatBatchEffect.new(&"split_chain", "split", "retreat_card", [], {"target": "head_card"})]
	)
	processor.enqueue(batch)
	var result := processor.process_next()
	_expect(result.is_committed(), "断链效果通过批次处理器提交")
	_expect(result.chain_revision == 1, "同一批次中的牌链修改只提升一次牌链版本")
	_expect(processor.create_snapshot().get_value(["chain", "split_at"], "") == "head_card", "断链状态由 StateWriter 写入")


func _test_driver_speed_controls_automatic_batch_interval() -> void:
	var processor := _make_processor({"counter": 0})
	var first := CombatBatchFactory.create_player_attack("driver_first", "card_a", [_increment_effect("first", 1)])
	var second := CombatBatchFactory.create_monster_attack("driver_second", "monster", [_increment_effect("second", 1)])
	var provider := QueueFlowProvider.new([first, second])
	var driver := CombatDriver.new(processor, provider)
	driver.base_batch_interval = 1.0
	driver.set_battle_speed(2.0)
	driver.start()
	driver.advance(0.0)
	_expect(provider.finished_ids == ["driver_first"], "驱动立即提交首个自动批次")
	driver.advance(0.49)
	_expect(provider.finished_ids.size() == 1, "战斗逻辑时间不足时不会提交下一批次")
	driver.advance(0.01)
	_expect(provider.finished_ids == ["driver_first", "driver_second"], "2 倍战斗速度使 1 秒逻辑间隔在 0.5 秒后完成")


func _test_player_operation_enters_processor_without_driver_planning() -> void:
	var processor := _make_processor({"counter": 0})
	var flow := CombatBatchFactory.create_player_attack("planned_flow", "card_a", [_increment_effect("flow", 1)])
	var provider := QueueFlowProvider.new([flow])
	var driver := CombatDriver.new(processor, provider)
	driver.base_batch_interval = 0.0
	driver.start()
	var operation := CombatBatchFactory.create_player_operation("direct_operation", "operation_card", [_increment_effect("operation", 10)])
	processor.enqueue(operation)
	driver.advance(0.0)
	_expect(provider.finished_ids == ["direct_operation"], "玩家操作不经过流程规划，直接由处理器执行")
	_expect(processor.create_snapshot().get_value(["counter"], -1) == 10, "直接插入的操作批次已经写入状态")
	driver.advance(0.0)
	_expect(provider.finished_ids == ["direct_operation", "planned_flow"], "操作完成后驱动继续最新战斗流程")


func _test_driver_plans_trigger_batches_from_committed_events() -> void:
	var processor := _make_processor({"counter": 0, "trigger_count": 0})
	var attack := CombatBatchFactory.create_player_attack("trigger_source", "card_a", [_increment_effect("attack", 1)])
	var provider := QueueFlowProvider.new([attack])
	var planner := CombatTriggerPlanner.new()
	planner.register(AfterPlayerAttackTriggerRule.new())
	var driver := CombatDriver.new(processor, provider, planner)
	driver.base_batch_interval = 0.0
	driver.start()
	driver.advance(0.0)
	_expect(driver.has_planned_triggers(), "驱动根据已提交的玩家攻击完成事件生成触发批次")
	driver.advance(0.0)
	_expect(processor.create_snapshot().get_value(["trigger_count"], -1) == 1, "派生卡牌触发仍由统一批次处理器写入状态")
	_expect(provider.finished_ids == ["trigger_source", "trigger_after_player_attack"], "触发批次在主流程结束前完成")


func _test_presentation_gate_keeps_operation_batches_responsive() -> void:
	var processor := _make_processor({"counter": 0})
	var flow := CombatBatchFactory.create_player_attack("presentation_flow", "card_a", [_increment_effect("flow", 1)])
	var provider := QueueFlowProvider.new([flow])
	var driver := CombatDriver.new(processor, provider)
	driver.base_batch_interval = 0.0
	driver.require_presentation_acknowledgement = true
	driver.start()
	driver.advance(0.0)
	_expect(driver.is_waiting_for_presentation(), "自动批次完成后驱动可以等待表现确认")
	var operation := CombatBatchFactory.create_player_operation("presentation_operation", "operation_card", [_increment_effect("operation", 10)])
	processor.enqueue(operation)
	driver.advance(0.0)
	_expect(processor.create_snapshot().get_value(["counter"], -1) == 11, "等待动画时玩家操作仍可直接进入处理器")
	driver.acknowledge_presentation("presentation_flow")
	_expect(driver.is_waiting_for_presentation(), "确认一个批次不会丢失同时产生的其他表现请求")
	driver.acknowledge_presentation("presentation_operation")
	_expect(not driver.is_waiting_for_presentation(), "所有批次确认后自动流程可以继续")


func _make_processor(initial_data: Dictionary) -> CombatEffectBatchProcessor:
	var state := CombatRuntimeState.new()
	state.initialize(initial_data, &"combat")
	var registry := CombatEffectHandlerRegistry.new()
	registry.register(IncrementPathHandler.new())
	registry.register(ChainMutationHandler.new())
	return CombatEffectBatchProcessor.new(state, registry)


func _increment_effect(effect_id: String, amount: int) -> CombatBatchEffect:
	return CombatBatchEffect.new(
		&"increment_path",
		effect_id,
		"source",
		["target"],
		{"path": ["counter"], "amount": amount}
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
