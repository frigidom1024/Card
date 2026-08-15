extends SceneTree

class FakeCardPresenter:
	extends CombatCardPresenter
	var calls: Array[StringName] = []

	func play_trigger(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"card_trigger")

	func play_attack(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"card_attack")

	func play_hit(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"card_hit")

	func animate_points_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"card_points_change")

	func animate_shield_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"card_shield_change")

	func play_death(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"card_death")

	func _record(call_name: StringName) -> CombatAnimationHandle:
		calls.append(call_name)
		return CombatAnimationHandle.new()


class FakeMonsterPresenter:
	extends CombatMonsterPresenter
	var calls: Array[StringName] = []

	func play_attack(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"monster_attack")

	func play_hit(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"monster_hit")

	func animate_health_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"monster_health_change")

	func animate_shield_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"monster_shield_change")

	func play_death(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"monster_death")

	func _record(call_name: StringName) -> CombatAnimationHandle:
		calls.append(call_name)
		return CombatAnimationHandle.new()


class FakeChainPresenter:
	extends CombatChainPresenter
	var calls: Array[StringName] = []

	func play_chain_split(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"chain_split")

	func play_chain_reflow(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"chain_reflow")

	func _record(call_name: StringName) -> CombatAnimationHandle:
		calls.append(call_name)
		return CombatAnimationHandle.new()


class FakeHudPresenter:
	extends CombatHudPresenter
	var calls: Array[StringName] = []

	func animate_gold_change(_clip: CombatPresentationClip, _duration: float) -> CombatAnimationHandle:
		return _record(&"gold_change")

	func animate_player_health_change(
		_clip: CombatPresentationClip,
		_duration: float
	) -> CombatAnimationHandle:
		return _record(&"player_health_change")

	func _record(call_name: StringName) -> CombatAnimationHandle:
		calls.append(call_name)
		return CombatAnimationHandle.new()


var _failures := 0
var _bridge: CombatBoardPresentationBridge
var _card: FakeCardPresenter
var _monster: FakeMonsterPresenter
var _chain: FakeChainPresenter
var _hud: FakeHudPresenter


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_setup_bridge()
	_test_routes_card_effect_clips_by_stable_id()
	_test_routes_monster_effect_clips_by_stable_id()
	_test_routes_chain_and_hud_clips()
	await _test_missing_or_unregistered_presenter_completes_safely()
	_teardown_bridge()
	quit(1 if _failures > 0 else 0)


func _setup_bridge() -> void:
	_bridge = CombatBoardPresentationBridge.new()
	_card = FakeCardPresenter.new()
	_monster = FakeMonsterPresenter.new()
	_chain = FakeChainPresenter.new()
	_hud = FakeHudPresenter.new()
	root.add_child(_bridge)
	root.add_child(_card)
	root.add_child(_monster)
	root.add_child(_chain)
	root.add_child(_hud)
	_bridge.register_card("card_a", _card)
	_bridge.register_monster("monster_a", _monster)
	_bridge.set_chain_presenter(_chain)
	_bridge.set_hud_presenter(_hud)


func _test_routes_card_effect_clips_by_stable_id() -> void:
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.CARD_TRIGGER, "card_a"), 0.2)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.CARD_ATTACK, "card_a", ["monster_a"]),
		0.2
	)
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.CARD_HIT, "monster_a", ["card_a"]), 0.2)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.CARD_POINTS_CHANGE, "monster_a", ["card_a"]),
		0.2
	)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.CARD_SHIELD_CHANGE, "player", ["card_a"]),
		0.2
	)
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.CARD_DEATH, "card_a", ["card_a"]), 0.2)
	_expect(
		_card.calls == [
			&"card_trigger",
			&"card_attack",
			&"card_hit",
			&"card_points_change",
			&"card_shield_change",
			&"card_death",
		],
		"卡牌 Clip 必须按 source/target 稳定 ID 路由到卡牌 Presenter"
	)


func _test_routes_monster_effect_clips_by_stable_id() -> void:
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.MONSTER_ATTACK, "monster_a", ["card_a"]),
		0.2
	)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.MONSTER_HIT, "card_a", ["monster_a"]),
		0.2
	)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE, "card_a", ["monster_a"]),
		0.2
	)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.MONSTER_SHIELD_CHANGE, "card_a", ["monster_a"]),
		0.2
	)
	_bridge.execute_clip(
		_clip(CombatPresentationClipTypes.MONSTER_DEATH, "monster_a", ["monster_a"]),
		0.2
	)
	_expect(
		_monster.calls == [
			&"monster_attack",
			&"monster_hit",
			&"monster_health_change",
			&"monster_shield_change",
			&"monster_death",
		],
		"怪物 Clip 必须按 source/target 稳定 ID 路由到怪物 Presenter"
	)


func _test_routes_chain_and_hud_clips() -> void:
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.CHAIN_SPLIT), 0.2)
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.CHAIN_REFLOW), 0.2)
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.GOLD_CHANGE), 0.2)
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.PLAYER_HEALTH_CHANGE), 0.2)
	_expect(_chain.calls == [&"chain_split", &"chain_reflow"], "牌链 Clip 路由到牌链 Presenter")
	_expect(_hud.calls == [&"gold_change", &"player_health_change"], "数值 HUD Clip 路由到 HUD Presenter")


func _test_missing_or_unregistered_presenter_completes_safely() -> void:
	var replacement := FakeCardPresenter.new()
	root.add_child(replacement)
	_bridge.register_card("card_a", replacement)
	_bridge.unregister_card("card_a", _card)
	_bridge.execute_clip(_clip(CombatPresentationClipTypes.CARD_TRIGGER, "card_a"), 0.1)
	_expect(replacement.calls == [&"card_trigger"], "旧 Presenter 注销不能误删新注册实例")

	_bridge.unregister_card("card_a", replacement)
	var missing_handle := _bridge.execute_clip(
		_clip(CombatPresentationClipTypes.CARD_TRIGGER, "card_a"),
		0.1
	)
	_expect(missing_handle != null, "Presenter 缺失时返回安全句柄")
	await process_frame
	_expect(missing_handle.is_finished(), "Presenter 缺失时句柄下一帧完成")

	replacement.queue_free()
	await process_frame


func _teardown_bridge() -> void:
	_bridge.clear()
	_bridge.queue_free()
	_card.queue_free()
	_monster.queue_free()
	_chain.queue_free()
	_hud.queue_free()


func _clip(
	clip_type: StringName,
	source_entity_id: String = "",
	target_entity_ids: Array[String] = []
) -> CombatPresentationClip:
	var clip := CombatPresentationClip.new()
	clip.clip_id = str(clip_type)
	clip.clip_type = clip_type
	clip.source_entity_id = source_entity_id
	clip.target_entity_ids.assign(target_entity_ids)
	return clip


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
