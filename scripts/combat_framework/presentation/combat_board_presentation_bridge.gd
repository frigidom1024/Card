class_name CombatBoardPresentationBridge
extends Node

var _cards: Dictionary = {}
var _monsters: Dictionary = {}
var _chain_presenter: CombatChainPresenter = null
var _hud_presenter: CombatHudPresenter = null


func register_card(card_id: String, presenter: CombatCardPresenter) -> void:
	if card_id.is_empty() or presenter == null:
		push_warning("注册卡牌 Presenter 时必须提供稳定 ID 和节点")
		return
	_cards[card_id] = presenter


func unregister_card(card_id: String, presenter: CombatCardPresenter = null) -> void:
	if not _cards.has(card_id):
		return
	if presenter != null and _cards.get(card_id) != presenter:
		return
	_cards.erase(card_id)


func register_monster(monster_id: String, presenter: CombatMonsterPresenter) -> void:
	if monster_id.is_empty() or presenter == null:
		push_warning("注册怪物 Presenter 时必须提供稳定 ID 和节点")
		return
	_monsters[monster_id] = presenter


func unregister_monster(
	monster_id: String,
	presenter: CombatMonsterPresenter = null
) -> void:
	if not _monsters.has(monster_id):
		return
	if presenter != null and _monsters.get(monster_id) != presenter:
		return
	_monsters.erase(monster_id)


func set_chain_presenter(presenter: CombatChainPresenter) -> void:
	_chain_presenter = presenter


func set_hud_presenter(presenter: CombatHudPresenter) -> void:
	_hud_presenter = presenter


func clear() -> void:
	_cards.clear()
	_monsters.clear()
	_chain_presenter = null
	_hud_presenter = null


func execute_clip(clip: CombatPresentationClip, duration: float) -> CombatAnimationHandle:
	if clip == null:
		return _missing(null)
	match clip.clip_type:
		CombatPresentationClipTypes.CARD_TRIGGER:
			var source_card := _card(clip.source_entity_id)
			return source_card.play_trigger(clip, duration) if source_card != null else _missing(clip)
		CombatPresentationClipTypes.CARD_ATTACK:
			var attacking_card := _card(clip.source_entity_id)
			return attacking_card.play_attack(clip, duration) if attacking_card != null else _missing(clip)
		CombatPresentationClipTypes.CARD_HIT:
			var hit_card := _target_card(clip)
			return hit_card.play_hit(clip, duration) if hit_card != null else _missing(clip)
		CombatPresentationClipTypes.CARD_POINTS_CHANGE:
			var points_card := _target_card(clip)
			return points_card.animate_points_change(clip, duration) if points_card != null else _missing(clip)
		CombatPresentationClipTypes.CARD_SHIELD_CHANGE:
			var shield_card := _target_card(clip)
			return shield_card.animate_shield_change(clip, duration) if shield_card != null else _missing(clip)
		CombatPresentationClipTypes.CARD_DEATH:
			var dead_card := _target_card(clip)
			return dead_card.play_death(clip, duration) if dead_card != null else _missing(clip)
		CombatPresentationClipTypes.MONSTER_ATTACK:
			var attacking_monster := _monster(clip.source_entity_id)
			return attacking_monster.play_attack(clip, duration) if attacking_monster != null else _missing(clip)
		CombatPresentationClipTypes.MONSTER_HIT:
			var hit_monster := _target_monster(clip)
			return hit_monster.play_hit(clip, duration) if hit_monster != null else _missing(clip)
		CombatPresentationClipTypes.MONSTER_HEALTH_CHANGE:
			var health_monster := _target_monster(clip)
			return health_monster.animate_health_change(clip, duration) if health_monster != null else _missing(clip)
		CombatPresentationClipTypes.MONSTER_SHIELD_CHANGE:
			var shield_monster := _target_monster(clip)
			return shield_monster.animate_shield_change(clip, duration) if shield_monster != null else _missing(clip)
		CombatPresentationClipTypes.MONSTER_DEATH:
			var dead_monster := _target_monster(clip)
			return dead_monster.play_death(clip, duration) if dead_monster != null else _missing(clip)
		CombatPresentationClipTypes.CHAIN_SPLIT:
			var chain := _chain()
			return chain.play_chain_split(clip, duration) if chain != null else _missing(clip)
		CombatPresentationClipTypes.CHAIN_REFLOW:
			var reflow_chain := _chain()
			return reflow_chain.play_chain_reflow(clip, duration) if reflow_chain != null else _missing(clip)
		CombatPresentationClipTypes.GOLD_CHANGE:
			var gold_hud := _hud()
			return gold_hud.animate_gold_change(clip, duration) if gold_hud != null else _missing(clip)
		CombatPresentationClipTypes.PLAYER_HEALTH_CHANGE:
			var health_hud := _hud()
			return health_hud.animate_player_health_change(clip, duration) if health_hud != null else _missing(clip)
		_:
			return _missing(clip)


func _card(card_id: String) -> CombatCardPresenter:
	var presenter: CombatCardPresenter = _cards.get(card_id)
	if not _is_live_presenter(presenter):
		_cards.erase(card_id)
		return null
	return presenter


func _monster(monster_id: String) -> CombatMonsterPresenter:
	var presenter: CombatMonsterPresenter = _monsters.get(monster_id)
	if not _is_live_presenter(presenter):
		_monsters.erase(monster_id)
		return null
	return presenter


func _target_card(clip: CombatPresentationClip) -> CombatCardPresenter:
	return _card(_first_target_id(clip))


func _target_monster(clip: CombatPresentationClip) -> CombatMonsterPresenter:
	return _monster(_first_target_id(clip))


func _chain() -> CombatChainPresenter:
	if not _is_live_presenter(_chain_presenter):
		_chain_presenter = null
	return _chain_presenter


func _hud() -> CombatHudPresenter:
	if not _is_live_presenter(_hud_presenter):
		_hud_presenter = null
	return _hud_presenter


func _first_target_id(clip: CombatPresentationClip) -> String:
	return clip.target_entity_ids[0] if not clip.target_entity_ids.is_empty() else ""


func _is_live_presenter(presenter: Node) -> bool:
	return presenter != null and is_instance_valid(presenter) and presenter.is_inside_tree()


func _missing(clip: CombatPresentationClip) -> CombatAnimationHandle:
	var clip_id := clip.clip_id if clip != null else "<null>"
	push_warning("跳过无法路由的战斗表现 Clip：%s" % clip_id)
	return _completed_handle()


func _completed_handle() -> CombatAnimationHandle:
	var handle := CombatAnimationHandle.new()
	handle.call_deferred("complete")
	return handle
