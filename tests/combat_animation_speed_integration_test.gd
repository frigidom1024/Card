extends SceneTree

const OutcomeScript = preload("res://scripts/combat_framework/protocol/combat_battle_outcome.gd")


class RecordingCombatPresentationBridge extends FakeCombatPresentationBridge:
	var clips_by_id: Dictionary = {}

	func execute_clip(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
		clips_by_id[clip.clip_id] = clip.duplicate_clip()
		return super.execute_clip(clip, duration)

	func find_started_clip_id(clip_type: StringName) -> String:
		for clip_id in started_clip_ids:
			var clip: CombatPresentationClip = clips_by_id.get(clip_id)
			if clip != null and clip.clip_type == clip_type:
				return clip_id
		return ""

	func has_started_type(clip_type: StringName) -> bool:
		return not find_started_clip_id(clip_type).is_empty()

	func active_handle_for_type(clip_type: StringName) -> CombatAnimationHandle:
		var clip_id := find_started_clip_id(clip_type)
		var handle: CombatAnimationHandle = handles.get(clip_id)
		if handle != null and not handle.is_finished():
			return handle
		return null


var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_operation_effects_parallel_with_main_battle_and_gate_driver()
	await _test_retreat_uses_committed_chain_facts_and_skips_detached_target()
	await _test_shutdown_releases_pending_presentation()
	quit(1 if _failures > 0 else 0)


func _test_operation_effects_parallel_with_main_battle_and_gate_driver() -> void:
	var session := CombatBattleSession.new(_initial_state(20, 6, 0, 5))
	session.driver.require_presentation_acknowledgement = true
	session.driver.base_batch_interval = 1.0
	session.driver.base_presentation_duration = 1.0
	var bridge := RecordingCombatPresentationBridge.new()
	var builder := CombatEffectPresentationPlanBuilder.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var coordinator := CombatPresentationCoordinator.new()
	var automatic_batches: Array[CombatEffectBatch] = []
	var presentation_results: Dictionary = {}
	session.automatic_batch_submitted.connect(
		func(batch: CombatEffectBatch) -> void:
			automatic_batches.append(batch)
	)
	session.presentation_requested.connect(
		func(result: CombatEffectBatchResult, _duration: float) -> void:
			presentation_results[result.batch_id] = result
	)
	coordinator.configure(session, builder, scheduler)

	session.start()
	session.advance(0.0)
	_expect(automatic_batches.size() == 1, "首次推进只提交一个自动玩家攻击 Batch")
	if automatic_batches.is_empty():
		coordinator.shutdown()
		return
	var player_batch := automatic_batches[0]
	_expect(player_batch.batch_type == CombatEffectBatch.Type.PLAYER_ATTACK, "首个自动 Batch 是玩家攻击")
	_expect(bridge.has_started_type(CombatPresentationClipTypes.CARD_ATTACK), "玩家攻击按 Damage Effect 启动卡牌攻击 Clip")
	var card_attack_handle := bridge.active_handle_for_type(CombatPresentationClipTypes.CARD_ATTACK)
	_expect(card_attack_handle != null, "卡牌攻击具有活动动画句柄")

	var operation := CombatOperationBatchFactory.create_gold_shield_batch(
		"operation:shield",
		"forge_card",
		"card_a",
		2,
		3,
		session.create_snapshot().chain_revision
	)
	_expect(session.submit_player_operation(operation), "主战斗 Effect 播放时允许提交操作 Batch")
	session.advance(0.0)
	var after_operation := session.create_snapshot()
	_expect(after_operation.get_value(["player", "gold"], -1) == 3, "操作 Batch 立即提交金币变化")
	_expect(after_operation.get_value(["cards", "card_a", "shield"], -1) == 3, "操作 Batch 立即提交护盾变化")
	_expect(bridge.has_started_type(CombatPresentationClipTypes.GOLD_CHANGE), "金币 Effect 与主战斗 Effect 并行启动")
	_expect(not bridge.has_started_type(CombatPresentationClipTypes.CARD_SHIELD_CHANGE), "同 Batch 后续护盾 Effect 等待金币 Effect")
	_expect(session.driver.is_waiting_for_presentation(), "存在未完成 Effect 时 Driver 等待表现确认")

	session.set_battle_speed(4.0)
	if card_attack_handle != null:
		_expect(is_equal_approx(card_attack_handle.get_speed_scale(), 4.0), "活动卡牌攻击动画立即响应战斗速度")
	var gold_handle := bridge.active_handle_for_type(CombatPresentationClipTypes.GOLD_CHANGE)
	_expect(gold_handle != null, "金币动画具有活动句柄")
	if gold_handle != null:
		_expect(is_equal_approx(gold_handle.get_speed_scale(), 4.0), "并行操作动画也立即响应战斗速度")
		gold_handle.complete()
	_expect(not bridge.has_started_type(CombatPresentationClipTypes.CARD_SHIELD_CHANGE), "金币完成后护盾 Effect 仍等待卡牌实体锁")

	if card_attack_handle != null:
		card_attack_handle.complete()
	_expect(bridge.has_started_type(CombatPresentationClipTypes.CARD_SHIELD_CHANGE), "卡牌攻击释放实体锁后启动排队护盾 Effect")
	var shield_handle := bridge.active_handle_for_type(CombatPresentationClipTypes.CARD_SHIELD_CHANGE)
	_expect(shield_handle != null, "排队护盾动画已经启动")
	if shield_handle != null:
		_expect(is_equal_approx(shield_handle.get_speed_scale(), 4.0), "排队动画启动时使用最新战斗速度")

	await _finish_batch_presentations(player_batch.batch_id, presentation_results, bridge, coordinator)
	_expect(not coordinator.get_pending_batch_ids().has(player_batch.batch_id), "玩家攻击 Effect 全部完成后只确认玩家攻击 Batch")
	_expect(coordinator.get_pending_batch_ids().has(operation.batch_id), "操作 Batch 的护盾 Effect 未完成时仍保持屏障")
	var automatic_count_before_gate := automatic_batches.size()
	session.advance(0.0)
	_expect(automatic_batches.size() == automatic_count_before_gate, "任一 Batch 未确认时不生成怪物攻击")

	await _finish_batch_presentations(operation.batch_id, presentation_results, bridge, coordinator)
	_expect(not session.driver.is_waiting_for_presentation(), "玩家攻击和操作 Batch 都确认后解除门控")
	session.advance(0.249)
	_expect(automatic_batches.size() == 1, "4 倍战斗速度下逻辑间隔到期前不生成怪物攻击")
	session.advance(0.001)
	_expect(automatic_batches.size() == 2, "战斗速度同时缩短自动结算间隔")
	if automatic_batches.size() < 2:
		coordinator.shutdown()
		return
	var monster_batch := automatic_batches[1]
	_expect(monster_batch.batch_type == CombatEffectBatch.Type.MONSTER_ATTACK, "怪物攻击是独立自动 Batch")
	_expect(bridge.has_started_type(CombatPresentationClipTypes.MONSTER_ATTACK), "怪物攻击具有独立 Monster Attack Effect 表现")

	var player_result: CombatEffectBatchResult = presentation_results.get(player_batch.batch_id)
	var monster_result: CombatEffectBatchResult = presentation_results.get(monster_batch.batch_id)
	_expect(player_result != null and monster_result != null, "玩家与怪物攻击分别产生表现请求")
	if player_result != null:
		var player_plans := builder.build_effect_plans(player_result, 1.0, 4.0)
		_expect(_plans_have_type(player_plans, CombatPresentationClipTypes.CARD_ATTACK), "玩家攻击 Effect Plan 含卡牌攻击 Clip")
		_expect(not _plans_have_type(player_plans, CombatPresentationClipTypes.MONSTER_ATTACK), "玩家攻击 Effect Plan 不混入怪物攻击")
	if monster_result != null:
		var monster_plans := builder.build_effect_plans(monster_result, 1.0, 4.0)
		_expect(_plans_have_type(monster_plans, CombatPresentationClipTypes.MONSTER_ATTACK), "怪物攻击 Effect Plan 含怪物攻击 Clip")
		_expect(not _plans_have_type(monster_plans, CombatPresentationClipTypes.CARD_ATTACK), "怪物攻击 Effect Plan 不混入玩家攻击")
		_assert_monster_damage_facts(monster_result, monster_plans)

	var monster_attack_handle := bridge.active_handle_for_type(CombatPresentationClipTypes.MONSTER_ATTACK)
	_expect(monster_attack_handle != null, "怪物攻击具有活动动画句柄")
	session.set_battle_speed(8.0)
	if monster_attack_handle != null:
		_expect(is_equal_approx(monster_attack_handle.get_speed_scale(), 2.0), "正在播放的怪物攻击动画立即切换到新战斗速度")
	await _finish_batch_presentations(monster_batch.batch_id, presentation_results, bridge, coordinator)
	coordinator.shutdown()


func _test_retreat_uses_committed_chain_facts_and_skips_detached_target() -> void:
	var session := CombatBattleSession.new(_initial_state(20, 5, 0, 0))
	session.driver.require_presentation_acknowledgement = true
	session.driver.base_batch_interval = 0.0
	var bridge := RecordingCombatPresentationBridge.new()
	var builder := CombatEffectPresentationPlanBuilder.new()
	var scheduler := CombatEffectPresentationScheduler.new(bridge)
	var coordinator := CombatPresentationCoordinator.new()
	var automatic_batches: Array[CombatEffectBatch] = []
	var presentation_results: Dictionary = {}
	session.automatic_batch_submitted.connect(
		func(batch: CombatEffectBatch) -> void:
			automatic_batches.append(batch)
	)
	session.presentation_requested.connect(
		func(result: CombatEffectBatchResult, _duration: float) -> void:
			presentation_results[result.batch_id] = result
	)
	coordinator.configure(session, builder, scheduler)

	session.start()
	session.advance(0.0)
	_expect(not bridge.has_started_type(CombatPresentationClipTypes.CHAIN_SPLIT), "撤退提交前不存在拆链动画")
	var retreat := CombatOperationBatchFactory.create_retreat_batch(
		"operation:retreat",
		"retreat_card",
		"card_a",
		session.create_snapshot().chain_revision
	)
	_expect(session.submit_player_operation(retreat), "撤退操作可以在玩家攻击表现期间提交")
	session.advance(0.0)
	_expect(session.get_outcome() == OutcomeScript.RETREAT, "正式拆链提交后自然得到 retreat")
	_expect(bridge.has_started_type(CombatPresentationClipTypes.CHAIN_SPLIT), "仅在正式 CHAIN_SPLIT 事实提交后播放拆链")
	var retreat_result: CombatEffectBatchResult = presentation_results.get(retreat.batch_id)
	_expect(retreat_result != null, "撤退 Batch 产生独立表现请求")
	if retreat_result != null:
		_assert_chain_payload_matches_committed_fact(retreat_result, builder)

	for batch in automatic_batches.duplicate():
		await _finish_batch_presentations(batch.batch_id, presentation_results, bridge, coordinator)
	await _finish_batch_presentations(retreat.batch_id, presentation_results, bridge, coordinator)
	session.advance(0.0)
	_expect(automatic_batches.size() == 1, "拆掉当前卡牌后不再生成攻击已离链目标的怪物 Batch")
	_expect(session.get_outcome() == OutcomeScript.RETREAT, "牌链为空时会话保持 retreat")
	coordinator.shutdown()


func _test_shutdown_releases_pending_presentation() -> void:
	var session := CombatBattleSession.new(_initial_state(20, 4, 0, 0))
	session.driver.require_presentation_acknowledgement = true
	var bridge := RecordingCombatPresentationBridge.new()
	var coordinator := CombatPresentationCoordinator.new()
	coordinator.configure(
		session,
		CombatEffectPresentationPlanBuilder.new(),
		CombatEffectPresentationScheduler.new(bridge)
	)
	session.start()
	session.advance(0.0)
	_expect(session.driver.is_waiting_for_presentation(), "关闭前 Driver 正在等待 Effect 表现")
	coordinator.shutdown()
	_expect(not session.driver.is_waiting_for_presentation(), "Coordinator 关闭会安全释放全部 Batch 屏障")
	_expect(coordinator.get_pending_batch_ids().is_empty(), "关闭后不保留待确认 Batch")


func _finish_batch_presentations(
	batch_id: String,
	presentation_results: Dictionary,
	bridge: RecordingCombatPresentationBridge,
	coordinator: CombatPresentationCoordinator
) -> void:
	var result: CombatEffectBatchResult = presentation_results.get(batch_id)
	if result == null:
		_expect(false, "缺少 Batch %s 的表现结果" % batch_id)
		return
	var effect_prefixes: Array[String] = []
	for event in result.events:
		if event.event_type == CombatEventTypes.EFFECT_APPLIED:
			effect_prefixes.append("%s:" % event.effect_id)
	var guard := 0
	while coordinator.get_pending_batch_ids().has(batch_id) and guard < 64:
		guard += 1
		var completed_one := false
		for clip_id_value in bridge.handles.keys():
			var clip_id := str(clip_id_value)
			if not _starts_with_any(clip_id, effect_prefixes):
				continue
			var handle: CombatAnimationHandle = bridge.handles[clip_id]
			if handle != null and not handle.is_finished():
				handle.complete()
				completed_one = true
				break
		if not completed_one:
			await process_frame
	_expect(not coordinator.get_pending_batch_ids().has(batch_id), "Batch %s 的 Effect 表现应可全部完成" % batch_id)


func _assert_monster_damage_facts(
	result: CombatEffectBatchResult,
	plans: Array[CombatEffectPresentationPlan]
) -> void:
	var shield_event: CombatStateEvent = null
	var points_event: CombatStateEvent = null
	for event in result.events:
		if event.event_type == CombatEventTypes.SHIELD_CHANGED:
			shield_event = event
		elif event.event_type == CombatEventTypes.CARD_POINTS_CHANGED:
			points_event = event
	_expect(shield_event != null, "怪物攻击提交护盾变化事实")
	_expect(points_event != null, "怪物攻击提交卡牌点数变化事实")
	if shield_event != null:
		_expect(shield_event.payload.get("before") == 3, "怪物攻击读取两批次之间增加后的最新护盾")
		_expect(shield_event.payload.get("after") == 0, "伤害优先扣除正式护盾状态")
	if points_event != null:
		_expect(points_event.payload.get("before") == 6, "点数事实读取怪物攻击前最新点数")
		_expect(points_event.payload.get("after") == 3, "剩余反击伤害写入卡牌点数事实")
	var shield_clip := _find_clip(plans, CombatPresentationClipTypes.CARD_SHIELD_CHANGE)
	var points_clip := _find_clip(plans, CombatPresentationClipTypes.CARD_POINTS_CHANGE)
	_expect(shield_clip != null and shield_event != null and shield_clip.payload == shield_event.payload, "护盾动画只复制已提交事实 payload")
	_expect(points_clip != null and points_event != null and points_clip.payload == points_event.payload, "点数动画只复制已提交事实 payload")


func _assert_chain_payload_matches_committed_fact(
	result: CombatEffectBatchResult,
	builder: CombatEffectPresentationPlanBuilder
) -> void:
	var split_event: CombatStateEvent = null
	for event in result.events:
		if event.event_type == CombatEventTypes.CHAIN_SPLIT:
			split_event = event
			break
	_expect(split_event != null, "撤退操作提交 CHAIN_SPLIT 事实")
	if split_event == null:
		return
	var plans := builder.build_effect_plans(result, 1.0, 1.0)
	var split_clip := _find_clip(plans, CombatPresentationClipTypes.CHAIN_SPLIT)
	var reflow_clip := _find_clip(plans, CombatPresentationClipTypes.CHAIN_REFLOW)
	_expect(split_clip != null, "拆链 Effect 生成 CHAIN_SPLIT Clip")
	_expect(reflow_clip != null, "拆链 Effect 生成 CHAIN_REFLOW Clip")
	if split_clip != null:
		_expect(split_clip.payload.get("active_card_ids") == split_event.payload.get("active_card_ids"), "拆链动画使用事实中的 active_card_ids")
		_expect(split_clip.payload.get("detached_card_ids") == split_event.payload.get("detached_card_ids"), "拆链动画使用事实中的 detached_card_ids")
	if reflow_clip != null:
		_expect(reflow_clip.payload.get("active_card_ids") == split_event.payload.get("active_card_ids"), "重排动画使用事实中的 active_card_ids")
		_expect(reflow_clip.payload.get("detached_card_ids") == split_event.payload.get("detached_card_ids"), "重排动画使用事实中的 detached_card_ids")


func _plans_have_type(
	plans: Array[CombatEffectPresentationPlan],
	clip_type: StringName
) -> bool:
	return _find_clip(plans, clip_type) != null


func _find_clip(
	plans: Array[CombatEffectPresentationPlan],
	clip_type: StringName
) -> CombatPresentationClip:
	for plan in plans:
		for clip in plan.clips:
			if clip.clip_type == clip_type:
				return clip
	return null


func _starts_with_any(value: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if value.begins_with(prefix):
			return true
	return false


func _initial_state(monster_hp: int, card_points: int, card_shield: int, gold: int) -> Dictionary:
	return CombatStateSchema.create_initial_state(
		{"entity_id": "player", "hp": 10, "gold": gold},
		{"entity_id": "monster", "hp": monster_hp, "shield": 0},
		{"card_a": {"points": card_points, "shield": card_shield}},
		["card_a"]
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
