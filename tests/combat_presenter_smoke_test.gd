extends SceneTree

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_card_presenter_uses_committed_values_and_completes_actions()
	await _test_monster_presenter_uses_committed_values_and_completes_actions()
	await _test_chain_presenter_consumes_committed_chain_facts()
	await _test_hud_presenter_uses_committed_values()
	await _test_presenter_exit_completes_active_handle()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _test_card_presenter_uses_committed_values_and_completes_actions() -> void:
	var card := CombatCardPresenter.new()
	var visual_root := Node2D.new()
	var points_label := Label.new()
	var shield_label := Label.new()
	root.add_child(card)
	if not _expect_properties(
		card,
		[&"visual_root", &"points_label", &"shield_label"],
		"卡牌 Presenter"
	):
		card.queue_free()
		await process_frame
		return
	card.add_child(visual_root)
	card.add_child(points_label)
	card.add_child(shield_label)
	card.visual_root = visual_root
	card.points_label = points_label
	card.shield_label = shield_label

	var points_clip := _clip(
		CombatPresentationClipTypes.CARD_POINTS_CHANGE,
		{"before": 5, "after": 2, "delta": -99}
	)
	await _expect_handle_finishes(card.animate_points_change(points_clip, 0.01), "卡牌点数动画")
	_expect(points_label.text == "2", "卡牌点数必须显示正式事实 after，不能根据 delta 重算")

	var shield_clip := _clip(
		CombatPresentationClipTypes.CARD_SHIELD_CHANGE,
		{"before": 3, "after": 8, "delta": 999}
	)
	await _expect_handle_finishes(card.animate_shield_change(shield_clip, 0.01), "卡牌护盾动画")
	_expect(shield_label.text == "8", "卡牌护盾必须显示正式事实 after")

	await _expect_handle_finishes(
		card.play_trigger(_clip(CombatPresentationClipTypes.CARD_TRIGGER), 0.01),
		"卡牌触发动画"
	)
	await _expect_handle_finishes(
		card.play_attack(_clip(CombatPresentationClipTypes.CARD_ATTACK), 0.01),
		"卡牌攻击动画"
	)
	await _expect_handle_finishes(
		card.play_hit(_clip(CombatPresentationClipTypes.CARD_HIT), 0.01),
		"卡牌受击动画"
	)
	await _expect_handle_finishes(
		card.play_death(_clip(CombatPresentationClipTypes.CARD_DEATH), 0.01),
		"卡牌死亡动画"
	)

	card.queue_free()
	await process_frame


func _test_monster_presenter_uses_committed_values_and_completes_actions() -> void:
	var monster := CombatMonsterPresenter.new()
	var visual_root := Node2D.new()
	var health_label := Label.new()
	var shield_label := Label.new()
	root.add_child(monster)
	if not _expect_properties(
		monster,
		[&"visual_root", &"health_label", &"shield_label"],
		"怪物 Presenter"
	):
		monster.queue_free()
		await process_frame
		return
	monster.add_child(visual_root)
	monster.add_child(health_label)
	monster.add_child(shield_label)
	monster.visual_root = visual_root
	monster.health_label = health_label
	monster.shield_label = shield_label

	var health_clip := _clip(
		CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE,
		{"before": 12, "after": 7, "delta": -100}
	)
	await _expect_handle_finishes(monster.animate_health_change(health_clip, 0.01), "怪物生命动画")
	_expect(health_label.text == "7", "怪物生命必须显示正式事实 after")

	var shield_clip := _clip(
		CombatPresentationClipTypes.MONSTER_SHIELD_CHANGE,
		{"before": 4, "after": 1, "delta": 500}
	)
	await _expect_handle_finishes(monster.animate_shield_change(shield_clip, 0.01), "怪物护盾动画")
	_expect(shield_label.text == "1", "怪物护盾必须显示正式事实 after")

	await _expect_handle_finishes(
		monster.play_attack(_clip(CombatPresentationClipTypes.MONSTER_ATTACK), 0.01),
		"怪物攻击动画"
	)
	await _expect_handle_finishes(
		monster.play_hit(_clip(CombatPresentationClipTypes.MONSTER_HIT), 0.01),
		"怪物受击动画"
	)
	await _expect_handle_finishes(
		monster.play_death(_clip(CombatPresentationClipTypes.MONSTER_DEATH), 0.01),
		"怪物死亡动画"
	)

	monster.queue_free()
	await process_frame


func _test_chain_presenter_consumes_committed_chain_facts() -> void:
	var chain := CombatChainPresenter.new()
	var reflowed_ids: Array[String] = []
	root.add_child(chain)
	if not chain.has_signal("reflow_requested"):
		_expect(false, "牌链 Presenter 必须提供 reflow_requested 信号")
		chain.queue_free()
		await process_frame
		return
	chain.reflow_requested.connect(
		func(active_card_ids: Array[String]) -> void:
			reflowed_ids.assign(active_card_ids)
	)

	var facts := {
		"active_card_ids": ["root", "middle"],
		"detached_card_ids": ["head"],
		"target_card_id": "head",
	}
	await _expect_handle_finishes(
		chain.play_chain_split(_clip(CombatPresentationClipTypes.CHAIN_SPLIT, facts), 0.01),
		"牌链拆分动画"
	)
	await _expect_handle_finishes(
		chain.play_chain_reflow(_clip(CombatPresentationClipTypes.CHAIN_REFLOW, facts), 0.01),
		"牌链重排动画"
	)
	_expect(reflowed_ids == ["root", "middle"], "牌链重排只能消费正式事实 active_card_ids")

	chain.queue_free()
	await process_frame


func _test_hud_presenter_uses_committed_values() -> void:
	var hud := CombatHudPresenter.new()
	var gold_label := Label.new()
	var health_label := Label.new()
	root.add_child(hud)
	if not _expect_properties(hud, [&"gold_label", &"player_health_label"], "HUD Presenter"):
		hud.queue_free()
		await process_frame
		return
	hud.add_child(gold_label)
	hud.add_child(health_label)
	hud.gold_label = gold_label
	hud.player_health_label = health_label

	var gold_clip := _clip(
		CombatPresentationClipTypes.GOLD_CHANGE,
		{"before": 10, "after": 6, "delta": -999}
	)
	await _expect_handle_finishes(hud.animate_gold_change(gold_clip, 0.01), "金币动画")
	_expect(gold_label.text == "6", "金币必须显示正式事实 after")

	var health_clip := _clip(
		CombatPresentationClipTypes.PLAYER_HEALTH_CHANGE,
		{"before": 9, "after": 3, "delta": 999}
	)
	await _expect_handle_finishes(hud.animate_player_health_change(health_clip, 0.01), "玩家生命动画")
	_expect(health_label.text == "3", "玩家生命必须显示正式事实 after")

	hud.queue_free()
	await process_frame


func _test_presenter_exit_completes_active_handle() -> void:
	var card := CombatCardPresenter.new()
	var visual_root := Node2D.new()
	root.add_child(card)
	if not _expect_properties(card, [&"visual_root"], "卡牌 Presenter"):
		card.queue_free()
		await process_frame
		return
	card.add_child(visual_root)
	card.visual_root = visual_root
	var handle := card.play_attack(_clip(CombatPresentationClipTypes.CARD_ATTACK), 10.0)
	_expect(not handle.is_finished(), "长动画句柄在 Presenter 存活时应保持活动")
	card.queue_free()
	await process_frame
	await process_frame
	_expect(handle.is_finished(), "Presenter 离开场景树时必须安全完成活动句柄")


func _expect_handle_finishes(handle: CombatAnimationHandle, context: String) -> void:
	_expect(handle != null, "%s必须返回 CombatAnimationHandle" % context)
	if handle == null:
		return
	var deadline := Time.get_ticks_msec() + 2000
	while not handle.is_finished() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(handle.is_finished(), "%s必须最终完成" % context)


func _clip(clip_type: StringName, payload: Dictionary = {}) -> CombatPresentationClip:
	var clip := CombatPresentationClip.new()
	clip.clip_id = str(clip_type)
	clip.clip_type = clip_type
	clip.payload = payload.duplicate(true)
	return clip


func _expect_properties(
	object: Object,
	property_names: Array[StringName],
	context: String
) -> bool:
	var available: Dictionary = {}
	for property_info in object.get_property_list():
		available[StringName(property_info.get("name", ""))] = true
	var found_all := true
	for property_name in property_names:
		if available.has(property_name):
			continue
		found_all = false
		_expect(false, "%s 缺少属性 %s" % [context, property_name])
	return found_all


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
