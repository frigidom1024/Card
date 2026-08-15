extends SceneTree

const FlowScript = preload("res://scripts/combatv2/runtime/combat_linear_chain_flow_provider.gd")
const OutcomeScript = preload("res://scripts/combatv2/protocol/combat_battle_outcome.gd")
const SessionScript = preload("res://scripts/combatv2/runtime/combat_battle_session.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_selects_chain_head_for_player_attack()
	_test_monster_counter_is_separate_and_uses_raw_attack()
	_test_standard_outcomes_stop_the_flow()
	_test_retreat_between_attacks_skips_detached_target()
	_test_shield_operation_changes_pending_counter_resolution()
	_test_surviving_card_repeats_and_dead_card_advances()
	_test_next_round_reloads_card_points_from_latest_snapshot()
	_test_session_runs_lazy_batches_and_accepts_operations()
	_test_session_battle_speed_controls_settlement_interval()
	_test_session_reports_outcome_and_scaled_presentation_duration()
	quit(1 if _failure_count > 0 else 0)


func _test_selects_chain_head_for_player_attack() -> void:
	var initial_data := CombatStateSchema.create_initial_state(
		{"entity_id": "player", "hp": 10, "gold": 0},
		{"entity_id": "monster", "hp": 12, "shield": 0},
		{
			"root": {"points": 3, "shield": 0},
			"head": {"points": 7, "shield": 0},
		},
		["root", "head"]
	)
	var processor := CombatStandardEffectLibrary.create_processor(initial_data, &"combat")
	var flow := FlowScript.new()
	var snapshot := processor.create_snapshot()
	flow.start(snapshot)
	var batch := flow.build_next_batch(snapshot, null)

	_expect(batch != null, "存在可战斗卡牌时应生成玩家攻击批次")
	if batch == null:
		return
	_expect(batch.batch_type == CombatEffectBatch.Type.PLAYER_ATTACK, "一轮必须先生成玩家攻击批次")
	_expect(batch.source_entity_id == "head", "牌链按根部到头部保存，流程应从末尾头部卡牌开始")
	_expect(batch.effects.size() == 1, "基础玩家攻击只生成一个伤害效果")
	if batch.effects.size() == 1:
		var effect := batch.effects[0]
		_expect(effect.effect_type == CombatEffectTypes.DAMAGE, "玩家基础攻击生成 damage 效果")
		_expect(int(effect.get_parameter("amount", -1)) == 7, "攻击力取本轮开始时卡牌 points")
		_expect(effect.target_entity_ids == ["monster"], "玩家攻击目标是当前怪物")


func _test_monster_counter_is_separate_and_uses_raw_attack() -> void:
	var initial_data := CombatStateSchema.create_initial_state(
		{"entity_id": "player", "hp": 10, "gold": 0},
		{"entity_id": "monster", "hp": 6, "shield": 20},
		{"head": {"points": 8, "shield": 0}},
		["head"]
	)
	var processor := CombatStandardEffectLibrary.create_processor(initial_data, &"combat")
	var flow := FlowScript.new()
	flow.start(processor.create_snapshot())
	var player_batch := flow.build_next_batch(processor.create_snapshot(), null)
	processor.enqueue(player_batch)
	var player_result := processor.process_next()
	flow.on_batch_finished(player_result, processor.create_snapshot())

	_expect(processor.create_snapshot().get_value(["monster", "hp"], -1) == 6, "怪物护盾吸收玩家攻击时生命值可以完全不变")
	var monster_batch := flow.build_next_batch(processor.create_snapshot(), player_result)
	_expect(monster_batch != null, "怪物存活时应在后续单独生成反击批次")
	if monster_batch == null:
		return
	_expect(monster_batch.batch_type == CombatEffectBatch.Type.MONSTER_ATTACK, "怪物反击必须使用独立 MONSTER_ATTACK 批次")
	_expect(monster_batch.source_entity_id == "monster", "怪物反击来源为当前怪物")
	_expect(monster_batch.effects.size() == 1, "基础怪物反击只生成一个伤害效果")
	if monster_batch.effects.size() == 1:
		var effect := monster_batch.effects[0]
		_expect(effect.target_entity_ids == ["head"], "怪物反击目标是本轮攻击卡牌")
		_expect(int(effect.get_parameter("amount", -1)) == 6, "反击力取 min(原始卡牌 points, 玩家攻击前怪物 HP)，不读取有效伤害")


func _test_standard_outcomes_stop_the_flow() -> void:
	var victory_processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 3},
			{"head": {"points": 5}},
			["head"]
		),
		&"combat"
	)
	var victory_flow := FlowScript.new()
	victory_flow.start(victory_processor.create_snapshot())
	var lethal_batch := victory_flow.build_next_batch(victory_processor.create_snapshot(), null)
	victory_processor.enqueue(lethal_batch)
	var lethal_result := victory_processor.process_next()
	victory_flow.on_batch_finished(lethal_result, victory_processor.create_snapshot())
	_expect(victory_flow.is_finished(victory_processor.create_snapshot()), "怪物死亡后流程立即结束")
	_expect(victory_flow.get_outcome(victory_processor.create_snapshot()) == OutcomeScript.VICTORY, "怪物生命归零得到 victory")
	_expect(victory_flow.build_next_batch(victory_processor.create_snapshot(), lethal_result) == null, "胜利后不生成怪物反击")

	var defeat_processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 0, "max_hp": 10},
			{"entity_id": "monster", "hp": 5},
			{"head": {"points": 5}},
			["head"]
		),
		&"combat"
	)
	var defeat_flow := FlowScript.new()
	defeat_flow.start(defeat_processor.create_snapshot())
	_expect(defeat_flow.get_outcome(defeat_processor.create_snapshot()) == OutcomeScript.DEFEAT, "玩家生命归零得到 defeat")
	_expect(defeat_flow.build_next_batch(defeat_processor.create_snapshot(), null) == null, "失败状态不生成攻击")

	var retreat_processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 5},
			{"spent": {"points": 0}},
			["spent"]
		),
		&"combat"
	)
	var retreat_flow := FlowScript.new()
	retreat_flow.start(retreat_processor.create_snapshot())
	_expect(retreat_flow.get_outcome(retreat_processor.create_snapshot()) == OutcomeScript.RETREAT, "没有可战斗卡牌得到 retreat")
	_expect(retreat_flow.is_finished(retreat_processor.create_snapshot()), "撤退结果是终止状态")



func _test_retreat_between_attacks_skips_detached_target() -> void:
	var processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 20},
			{"root": {"points": 3}, "head": {"points": 5}},
			["root", "head"]
		),
		&"combat"
	)
	var flow := FlowScript.new()
	flow.start(processor.create_snapshot())
	var player_batch := flow.build_next_batch(processor.create_snapshot(), null)
	processor.enqueue(player_batch)
	var player_result := processor.process_next()
	flow.on_batch_finished(player_result, processor.create_snapshot())

	var retreat := CombatOperationBatchFactory.create_retreat_batch(
		"retreat_head",
		"retreat_card",
		"head",
		processor.create_snapshot().chain_revision
	)
	processor.enqueue(retreat)
	var retreat_result := processor.process_next()
	flow.on_batch_finished(retreat_result, processor.create_snapshot())
	var next_batch := flow.build_next_batch(processor.create_snapshot(), retreat_result)
	_expect(next_batch != null, "拆掉头部后仍有根部卡牌时战斗继续")
	if next_batch != null:
		_expect(next_batch.batch_type == CombatEffectBatch.Type.PLAYER_ATTACK, "离链目标不会再收到原本待生成的怪物攻击")
		_expect(next_batch.source_entity_id == "root", "撤退后从最新牌链头部重新选择卡牌")


func _test_shield_operation_changes_pending_counter_resolution() -> void:
	var processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10, "gold": 2},
			{"entity_id": "monster", "hp": 10},
			{"head": {"points": 5, "shield": 0}},
			["head"]
		),
		&"combat"
	)
	var flow := FlowScript.new()
	flow.start(processor.create_snapshot())
	var player_batch := flow.build_next_batch(processor.create_snapshot(), null)
	processor.enqueue(player_batch)
	var player_result := processor.process_next()
	flow.on_batch_finished(player_result, processor.create_snapshot())

	var reinforce := CombatOperationBatchFactory.create_gold_shield_batch(
		"reinforce_head",
		"shield_card",
		"head",
		1,
		3,
		processor.create_snapshot().chain_revision
	)
	processor.enqueue(reinforce)
	var reinforce_result := processor.process_next()
	flow.on_batch_finished(reinforce_result, processor.create_snapshot())
	var monster_batch := flow.build_next_batch(processor.create_snapshot(), reinforce_result)
	processor.enqueue(monster_batch)
	var monster_result := processor.process_next()
	flow.on_batch_finished(monster_result, processor.create_snapshot())
	var snapshot := processor.create_snapshot()
	_expect(snapshot.get_value(["player", "gold"], -1) == 1, "操作批次正常支付金币")
	_expect(snapshot.get_value(["cards", "head", "shield"], -1) == 0, "新增护盾被随后怪物攻击优先消耗")
	_expect(snapshot.get_value(["cards", "head", "points"], -1) == 3, "怪物反击在最新护盾状态上结算，只剩余伤害扣 points")


func _test_surviving_card_repeats_and_dead_card_advances() -> void:
	var surviving_processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 20},
			{"root": {"points": 2}, "head": {"points": 5, "shield": 5}},
			["root", "head"]
		),
		&"combat"
	)
	var surviving_flow := FlowScript.new()
	surviving_flow.start(surviving_processor.create_snapshot())
	var first_player := surviving_flow.build_next_batch(surviving_processor.create_snapshot(), null)
	surviving_processor.enqueue(first_player)
	var first_player_result := surviving_processor.process_next()
	surviving_flow.on_batch_finished(first_player_result, surviving_processor.create_snapshot())
	var first_monster := surviving_flow.build_next_batch(surviving_processor.create_snapshot(), first_player_result)
	surviving_processor.enqueue(first_monster)
	var first_monster_result := surviving_processor.process_next()
	surviving_flow.on_batch_finished(first_monster_result, surviving_processor.create_snapshot())
	var repeated_player := surviving_flow.build_next_batch(surviving_processor.create_snapshot(), first_monster_result)
	_expect(repeated_player != null and repeated_player.source_entity_id == "head", "当前卡牌仍存活时下一轮继续使用当前头部卡牌")

	var dying_processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 20},
			{"root": {"points": 2}, "head": {"points": 4, "shield": 0}},
			["root", "head"]
		),
		&"combat"
	)
	var dying_flow := FlowScript.new()
	dying_flow.start(dying_processor.create_snapshot())
	var dying_player := dying_flow.build_next_batch(dying_processor.create_snapshot(), null)
	dying_processor.enqueue(dying_player)
	var dying_player_result := dying_processor.process_next()
	dying_flow.on_batch_finished(dying_player_result, dying_processor.create_snapshot())
	var lethal_counter := dying_flow.build_next_batch(dying_processor.create_snapshot(), dying_player_result)
	dying_processor.enqueue(lethal_counter)
	var lethal_counter_result := dying_processor.process_next()
	dying_flow.on_batch_finished(lethal_counter_result, dying_processor.create_snapshot())
	var root_player := dying_flow.build_next_batch(dying_processor.create_snapshot(), lethal_counter_result)
	_expect(not bool(dying_processor.create_snapshot().get_value(["cards", "head", "alive"], true)), "点数归零的头部卡牌被死亡规则标记")
	_expect(root_player != null and root_player.source_entity_id == "root", "当前卡牌死亡后下一轮向根部选择下一张存活卡牌")




func _test_next_round_reloads_card_points_from_latest_snapshot() -> void:
	var processor := CombatStandardEffectLibrary.create_processor(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 30},
			{"head": {"points": 5, "shield": 5}},
			["head"]
		),
		&"combat"
	)
	var flow := FlowScript.new()
	flow.start(processor.create_snapshot())
	var player_batch := flow.build_next_batch(processor.create_snapshot(), null)
	processor.enqueue(player_batch)
	var player_result := processor.process_next()
	flow.on_batch_finished(player_result, processor.create_snapshot())
	var monster_batch := flow.build_next_batch(processor.create_snapshot(), player_result)
	processor.enqueue(monster_batch)
	var monster_result := processor.process_next()
	flow.on_batch_finished(monster_result, processor.create_snapshot())

	var point_effect := CombatBatchEffect.new(
		CombatEffectTypes.MODIFY_CARD_POINTS,
		"boost_points_effect",
		"boost_card",
		["head"],
		{"amount": 3}
	)
	var point_effects: Array[CombatBatchEffect] = [point_effect]
	var boost_operation := CombatBatchFactory.create_player_operation(
		"boost_points_operation",
		"boost_card",
		point_effects
	)
	processor.enqueue(boost_operation)
	var boost_result := processor.process_next()
	flow.on_batch_finished(boost_result, processor.create_snapshot())
	var next_player := flow.build_next_batch(processor.create_snapshot(), boost_result)
	_expect(next_player != null and next_player.batch_type == CombatEffectBatch.Type.PLAYER_ATTACK, "新一轮仍生成玩家攻击")
	if next_player != null and next_player.effects.size() == 1:
		_expect(int(next_player.effects[0].get_parameter("amount", -1)) == 8, "新一轮攻击重新读取操作后的最新 points，不缓存上一轮伤害")


func _test_session_runs_lazy_batches_and_accepts_operations() -> void:
	var session := SessionScript.new(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10, "gold": 2},
			{"entity_id": "monster", "hp": 10},
			{"head": {"points": 5, "shield": 0}},
			["head"]
		)
	)
	session.start()
	_expect(session.get_outcome() == OutcomeScript.RUNNING, "会话开始时返回 running")
	session.advance(0.0)
	var after_player := session.create_snapshot()
	_expect(after_player.get_value(["monster", "hp"], -1) == 5, "第一次推进只提交玩家攻击")
	_expect(after_player.get_value(["cards", "head", "points"], -1) == 5, "玩家攻击批次不会同时执行怪物反击")

	var operation := CombatOperationBatchFactory.create_gold_shield_batch(
		"session_reinforce",
		"shield_card",
		"head",
		1,
		3,
		after_player.chain_revision
	)
	_expect(session.submit_player_operation(operation), "会话接受合法玩家操作批次")
	session.advance(0.0)
	_expect(session.create_snapshot().get_value(["cards", "head", "shield"], -1) == 3, "玩家操作直接由处理器优先提交")
	session.advance(1.0)
	var after_monster := session.create_snapshot()
	_expect(after_monster.get_value(["cards", "head", "shield"], -1) == 0, "后续怪物攻击读取玩家操作后的最新护盾")
	_expect(after_monster.get_value(["cards", "head", "points"], -1) == 3, "怪物攻击与玩家攻击保持独立结算")


func _test_session_battle_speed_controls_settlement_interval() -> void:
	var session := SessionScript.new(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 20},
			{"head": {"points": 4, "shield": 0}},
			["head"]
		)
	)
	session.driver.base_batch_interval = 1.0
	session.set_battle_speed(2.0)
	session.start()
	session.advance(0.0)
	session.advance(0.49)
	_expect(session.create_snapshot().get_value(["cards", "head", "points"], -1) == 4, "逻辑间隔未到时怪物攻击尚未结算")
	session.advance(0.01)
	_expect(session.create_snapshot().get_value(["cards", "head", "points"], -1) == 0, "2 倍战斗速度使 1 秒逻辑间隔在 0.5 秒现实时间完成")



func _test_session_reports_outcome_and_scaled_presentation_duration() -> void:
	var session := SessionScript.new(
		CombatStateSchema.create_initial_state(
			{"entity_id": "player", "hp": 10},
			{"entity_id": "monster", "hp": 3},
			{"head": {"points": 5}},
			["head"]
		)
	)
	var presentation_ids: Array[String] = []
	var presentation_durations: Array[float] = []
	var finished_outcomes: Array[StringName] = []
	session.presentation_requested.connect(func(result: CombatEffectBatchResult, duration: float) -> void:
		presentation_ids.append(result.batch_id)
		presentation_durations.append(duration)
	)
	session.battle_finished.connect(func(outcome: StringName, _snapshot: CombatStateSnapshot) -> void:
		finished_outcomes.append(outcome)
	)
	session.driver.require_presentation_acknowledgement = true
	session.driver.base_batch_interval = 1.0
	session.driver.base_presentation_duration = 1.0
	session.set_battle_speed(2.0)
	session.start()
	session.advance(0.0)
	_expect(session.get_outcome() == OutcomeScript.VICTORY, "致命玩家攻击提交后会话立即可查询 victory")
	_expect(presentation_ids.size() == 1, "会话转发批次表现请求")
	if presentation_durations.size() == 1:
		_expect(is_equal_approx(presentation_durations[0], 0.5), "推荐表现时长由同一个战斗速度按比例缩放")
	if presentation_ids.size() == 1:
		session.acknowledge_presentation(presentation_ids[0])
	session.advance(0.5)
	_expect(finished_outcomes == [OutcomeScript.VICTORY], "自动流程结束时会话发出标准 victory 结果")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)


