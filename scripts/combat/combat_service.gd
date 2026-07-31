class_name CombatService
extends RefCounted

const MobActionResolverScript = preload("res://scripts/combat/mob_action_resolver.gd")


func resolve_encounter(
	player_stats: CombatStats, card_chain: Array[CardInstance], monster: MobInstance
) -> CombatResult:
	var player_copy := player_stats.duplicate_runtime() if player_stats != null else null
	var monster_copy := monster.duplicate_for_encounter() if monster != null else null
	var cards_copy: Array[CardInstance] = []
	for card in card_chain:
		cards_copy.append(card)
	var state := CombatState.new(player_copy, monster_copy, cards_copy)

	if state.cards.is_empty() or not _is_root_card(state.cards[0]):
		push_error("CombatService requires the first card in a chain to be a root card")
		return _build_result(state, CombatResult.Outcome.RETREAT, _retreat_penalties())

	var root: CardInstance = state.cards[0]
	if resolve_player_card(state, root, 0, CombatEffect.SourceType.ROOT_CARD):
		return _build_result(state, CombatResult.Outcome.VICTORY)
	if _is_player_defeated(state):
		return _build_result(state, CombatResult.Outcome.DEFEAT)

	_register_root_chain_rules(state, root)
	var tracker := ChainRuleTracker.new()
	tracker.start(state.active_chain_rules)

	for index in range(1, state.cards.size()):
		var card: CardInstance = state.cards[index]
		if tracker.begin_card(card):
			if resolve_monster_action(state):
				return _build_result(state, CombatResult.Outcome.DEFEAT)
			if _is_monster_defeated(state):
				return _build_result(state, CombatResult.Outcome.VICTORY)

		if resolve_player_card(state, card, index, CombatEffect.SourceType.PLAYER_CARD):
			return _build_result(state, CombatResult.Outcome.VICTORY)
		if _is_player_defeated(state):
			return _build_result(state, CombatResult.Outcome.DEFEAT)

		if tracker.finish_card(card):
			if resolve_monster_action(state):
				return _build_result(state, CombatResult.Outcome.DEFEAT)
			if _is_monster_defeated(state):
				return _build_result(state, CombatResult.Outcome.VICTORY)

	if tracker.flush_pending():
		if resolve_monster_action(state):
			return _build_result(state, CombatResult.Outcome.DEFEAT)
		if _is_monster_defeated(state):
			return _build_result(state, CombatResult.Outcome.VICTORY)

	if _is_player_defeated(state):
		return _build_result(state, CombatResult.Outcome.DEFEAT)
	if _is_monster_defeated(state):
		return _build_result(state, CombatResult.Outcome.VICTORY)
	return _build_result(state, CombatResult.Outcome.RETREAT, _retreat_penalties())


func apply_effect(state: CombatState, effect: CombatEffect) -> int:
	if state == null or effect == null:
		return 0
	var target_stats := _target_stats(state, effect.target)
	if target_stats == null:
		return 0
	match effect.type:
		CombatEffect.Type.DAMAGE:
			return target_stats.take_damage(effect.value)
		CombatEffect.Type.ADD_DEFENSE:
			var defense_before := target_stats.defense
			target_stats.add_defense(effect.value)
			return target_stats.defense - defense_before
		CombatEffect.Type.HEAL:
			return target_stats.heal(effect.value)
	return 0


func resolve_player_card(
	state: CombatState, card: CardInstance, index: int, source_type: CombatEffect.SourceType
) -> bool:
	var player_before := _copy_player_stats(state)
	var monster_before := _copy_monster_stats(state)
	var source_name := _card_name(card)
	var applied_effects: Array[CombatEffect] = []

	if card != null and card.card_data != null:
		var context := CardResolutionContext.new(state, card, index)
		var draft := CardResolutionDraft.from_card(card.card_data)
		for rule in card.card_data.effect_rules:
			if rule != null:
				rule.apply(context, draft)
		for effect in draft.to_effects(source_type, source_name):
			apply_effect(state, effect)
			applied_effects.append(effect)
			if _is_monster_defeated(state) or _is_player_defeated(state):
				break

	var kind := (
		CombatStep.Kind.ROOT_CARD
		if source_type == CombatEffect.SourceType.ROOT_CARD
		else CombatStep.Kind.PLAYER_CARD
	)
	_append_step(state, kind, source_name, applied_effects, player_before, monster_before)
	state.resolved_cards.append(card)
	state.remaining_cards.erase(card)
	return _is_monster_defeated(state)


func resolve_monster_action(state: CombatState) -> bool:
	var player_before := _copy_player_stats(state)
	var monster_before := _copy_monster_stats(state)
	var source_name := _monster_name(state)
	var applied_effects: Array[CombatEffect] = []
	var action: MobAction = state.monster.next_action() if state != null and state.monster != null else null
	if action != null:
		for effect in MobActionResolverScript.to_effects(action, source_name):
			apply_effect(state, effect)
			applied_effects.append(effect)
			if _is_player_defeated(state) or _is_monster_defeated(state):
				break
	_append_step(
		state,
		CombatStep.Kind.MONSTER_ACTION,
		source_name,
		applied_effects,
		player_before,
		monster_before
	)
	return _is_player_defeated(state)


func _register_root_chain_rules(state: CombatState, root: CardInstance) -> void:
	if state == null or root == null or root.card_data == null:
		return
	var context := CardResolutionContext.new(state, root, 0)
	for provider in root.card_data.root_rule_providers:
		if provider == null:
			continue
		for rule in provider.build_rules(context):
			if rule != null:
				state.active_chain_rules.append(rule)


func _append_step(
	state: CombatState,
	kind: CombatStep.Kind,
	source_name: String,
	effects: Array[CombatEffect],
	player_before: CombatStats,
	monster_before: CombatStats
) -> void:
	if state == null:
		return
	state.steps.append(
		CombatStep.new(
			kind,
			source_name,
			effects,
			player_before,
			_copy_player_stats(state),
			monster_before,
			_copy_monster_stats(state)
		)
	)


func _build_result(
	state: CombatState, outcome: CombatResult.Outcome, penalties: Array[CombatPenalty] = []
) -> CombatResult:
	return CombatResult.new(
		outcome,
		state.player_stats if state != null else null,
		state.monster.stats if state != null and state.monster != null else null,
		state.steps if state != null else [],
		state.resolved_cards.size() if state != null else 0,
		penalties
	)


func _retreat_penalties() -> Array[CombatPenalty]:
	return [
		CombatPenalty.new(
			CombatPenalty.Type.REMOVE_CARD, 1, CombatPenalty.Target.TAIL_OF_CARD_CHAIN
		)
	]


func _target_stats(state: CombatState, target: CombatEffect.Target) -> CombatStats:
	if target == CombatEffect.Target.PLAYER:
		return state.player_stats
	if target == CombatEffect.Target.MONSTER and state.monster != null:
		return state.monster.stats
	return null


func _copy_player_stats(state: CombatState) -> CombatStats:
	return state.player_stats.duplicate_runtime() if state != null and state.player_stats != null else null


func _copy_monster_stats(state: CombatState) -> CombatStats:
	return (
		state.monster.stats.duplicate_runtime()
		if state != null and state.monster != null and state.monster.stats != null
		else null
	)


func _is_player_defeated(state: CombatState) -> bool:
	return state == null or state.player_stats == null or not state.player_stats.is_alive()


func _is_monster_defeated(state: CombatState) -> bool:
	return state == null or state.monster == null or state.monster.stats == null or not state.monster.is_alive()


func _is_root_card(card: CardInstance) -> bool:
	return card != null and card.card_data != null and card.card_data.card_type == CardData.CardType.ROOT


func _card_name(card: CardInstance) -> String:
	return card.card_data.card_name if card != null and card.card_data != null else ""


func _monster_name(state: CombatState) -> String:
	return state.monster.data.mob_name if state != null and state.monster != null and state.monster.data != null else ""