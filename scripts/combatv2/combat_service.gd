class_name CombatService2
extends RefCounted


var action_queue:Array[CombatAction]
const MobActionResolverScript = preload("res://scripts/combatv2/mob_action_resolver.gd")

var player_index:int = 0
var monster_index:int = 0

# gdlint: disable=max-returns
func resolve_encounter(
	player_stats: CombatStats, card_chain: Array[CardInstance], monster: MobInstance
) -> CombatResult:
	player_index = 0
	monster_index = 0
	action_queue.clear()
	var player_copy := player_stats.duplicate_runtime() if player_stats != null else null
	var monster_copy := monster.duplicate_for_encounter() if monster != null else null
	var cards_copy: Array[CardInstance] = []
	for card in card_chain:
		cards_copy.append(card)
	var context := CombatContext.new(player_copy, monster_copy, cards_copy)

	if context.cards.is_empty() or not _is_root_card(context.cards[0]):
		push_error("CombatService requires the first card in a chain to be a root card")
		return _build_result(context, CombatResult.Outcome.RETREAT)

	var root: CardInstance = context.cards[0]
	if resolve_player_card(context, root, 0, CombatEffect.SourceType.ROOT_CARD):
		return _build_result(context, CombatResult.Outcome.VICTORY)
	if _is_player_defeated(context):
		return _build_result(context, CombatResult.Outcome.DEFEAT)
	player_index+=1

	while player_index < context.cards.size():
		action_queue.append(CombatAction.new(CombatAction.TYPE.PLAYER, player_index))
		while not action_queue.is_empty():
			var result := _process_action(context)
			if result != null:
				return result
		
		action_queue.append(CombatAction.new(CombatAction.TYPE.MONSTER, monster_index))
		while not action_queue.is_empty():
			var result := _process_action(context)
			if result != null:
				return result
	
	if _is_player_defeated(context):
		return _build_result(context, CombatResult.Outcome.DEFEAT)
	if _is_monster_defeated(context):
		return _build_result(context, CombatResult.Outcome.VICTORY)
	return _build_result(context, CombatResult.Outcome.RETREAT)


# gdlint: enable=max-returns
func apply_effect(context: CombatContext, effect: CombatEffect) -> int:
	if context == null or effect == null:
		return 0
	var target_stats := _target_stats(context, effect.target)
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
	context: CombatContext, card: CardInstance, index: int, source_type: CombatEffect.SourceType
) -> bool:
	var player_before := _copy_player_stats(context)
	var monster_before := _copy_monster_stats(context)
	var source_name := _card_name(card)
	var applied_effects: Array[CombatEffect] = []

	if card != null and card.card_data != null:
		var resolution_context := CardResolutionContext.new(context, card, index)
		var draft := CardResolutionDraft.from_card(card.card_data)
		for rule in card.card_data.effect_rules:
			if rule != null:
				rule.execute(resolution_context, draft)
		for effect in draft.to_effects(source_type, source_name):
			apply_effect(context, effect)
			applied_effects.append(effect)
			if _is_monster_defeated(context) or _is_player_defeated(context):
				break

	var kind := (
		CombatStep.Kind.ROOT_CARD
		if source_type == CombatEffect.SourceType.ROOT_CARD
		else CombatStep.Kind.PLAYER_CARD
	)
	_append_step(context, kind, source_name, applied_effects, player_before, monster_before)
	context.resolved_cards.append(card)
	context.remaining_cards.erase(card)
	return _is_monster_defeated(context)


func resolve_monster_action(context: CombatContext) -> bool:
	var player_before := _copy_player_stats(context)
	var monster_before := _copy_monster_stats(context)
	var source_name := _monster_name(context)
	var applied_effects: Array[CombatEffect] = []
	var action: MobAction = (
		context.monster.next_action() if context != null and context.monster != null else null
	)
	if action != null:
		for effect in MobActionResolverScript.to_effects(
			action, source_name, context.monster.enhancement_stacks
		):
			apply_effect(context, effect)
			applied_effects.append(effect)
			if _is_player_defeated(context) or _is_monster_defeated(context):
				break
	_append_step(
		context,
		CombatStep.Kind.MONSTER_ACTION,
		source_name,
		applied_effects,
		player_before,
		monster_before
	)
	return _is_player_defeated(context)




func _process_action(context: CombatContext) -> CombatResult:
	var action: CombatAction = action_queue.front()
	action_queue.pop_front()
	if action.type == CombatAction.TYPE.PLAYER:
		var card := context.cards[player_index]
		if resolve_player_card(context, card, player_index, CombatEffect.SourceType.PLAYER_CARD):
			return _build_result(context, CombatResult.Outcome.VICTORY)
		player_index += 1
	if action.type == CombatAction.TYPE.MONSTER:
		resolve_monster_action(context)
		if _is_player_defeated(context):
			return _build_result(context, CombatResult.Outcome.DEFEAT)
		monster_index += 1
	return null


func _append_step(
	context: CombatContext,
	kind: CombatStep.Kind,
	source_name: String,
	effects: Array[CombatEffect],
	player_before: CombatStats,
	monster_before: CombatStats
) -> void:
	if context == null:
		return
	context.steps.append(
		CombatStep.new(
			kind,
			source_name,
			effects,
			player_before,
			_copy_player_stats(context),
			monster_before,
			_copy_monster_stats(context)
		)
	)


func _build_result(
	context: CombatContext, outcome: CombatResult.Outcome, penalties: Array[CombatPenalty] = []
) -> CombatResult:
	return CombatResult.new(
		outcome,
		context.player_stats if context != null else null,
		context.monster.stats if context != null and context.monster != null else null,
		context.steps if context != null else [],
		context.resolved_cards.size() if context != null else 0,
		penalties,
		context.monster.action_index if context != null and context.monster != null else 0
	)


func _target_stats(context: CombatContext, target: CombatEffect.Target) -> CombatStats:
	if target == CombatEffect.Target.PLAYER:
		return context.player_stats
	if target == CombatEffect.Target.MONSTER and context.monster != null:
		return context.monster.stats
	return null


func _copy_player_stats(context: CombatContext) -> CombatStats:
	return (
		context.player_stats.duplicate_runtime()
		if context != null and context.player_stats != null
		else null
	)


func _copy_monster_stats(context: CombatContext) -> CombatStats:
	return (
		context.monster.stats.duplicate_runtime()
		if context != null and context.monster != null and context.monster.stats != null
		else null
	)


func _is_player_defeated(context: CombatContext) -> bool:
	return context == null or context.player_stats == null or not context.player_stats.is_alive()


func _is_monster_defeated(context: CombatContext) -> bool:
	return (
		context == null
		or context.monster == null
		or context.monster.stats == null
		or not context.monster.is_alive()
	)


func _is_root_card(card: CardInstance) -> bool:
	return (
		card != null
		and card.card_data != null
		and card.card_data.card_type == CardData.CardType.ROOT
	)


func _card_name(card: CardInstance) -> String:
	return card.card_data.card_name if card != null and card.card_data != null else ""


func _monster_name(context: CombatContext) -> String:
	return (
		context.monster.data.mob_name
		if context != null and context.monster != null and context.monster.data != null
		else ""
	)
