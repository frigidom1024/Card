class_name CombatService2
extends RefCounted

## Resolves one encounter as a sequence of point clashes.
##
## The chain resolves from its head (the final placed card) back toward the
## root. Each eligible card repeatedly compares its remaining points with the
## echo's current HP: it first spends points against the echo, then armor
## absorbs the echo's pre-clash HP before any remaining retaliation consumes
## card points. A card stays in the clash while it retains points, so armor has
## immediate combat value by preserving further attacks. Normal echo actions
## and player HP are intentionally outside this baseline loop; specialised
## outcome effects remain available through CombatResult.


func resolve_encounter(
	player_stats: CombatStats, card_chain: Array[CardInstance], monster: MobInstance
) -> CombatResult:
	var player_copy := player_stats.duplicate_runtime() if player_stats != null else null
	var monster_copy := monster.duplicate_for_encounter() if monster != null else null
	var context := CombatContext.new(player_copy, monster_copy, card_chain)

	if context.cards.is_empty() or not _is_root_card(context.cards[0]):
		push_error("CombatService requires the first card in a chain to be a root card")
		return _build_result(context, CombatResult.Outcome.RETREAT)
	if context.monster == null or context.monster.stats == null:
		push_error("CombatService requires an encounter monster with combat stats")
		return _build_result(context, CombatResult.Outcome.RETREAT)

	for card_index in range(context.cards.size() - 1, -1, -1):
		var card := context.cards[card_index]
		if card == null or card.card_data == null or card.is_depleted():
			continue

		# A card is counted once even if armor lets it clash repeatedly.
		context.resolved_cards.append(card)
		while not card.is_depleted() and not _is_monster_defeated(context):
			if _resolve_card_clash(context, card):
				context.remaining_cards.erase(card)
				return _build_result(context, CombatResult.Outcome.VICTORY)
		context.remaining_cards.erase(card)

	return _build_result(context, CombatResult.Outcome.RETREAT)


## Resolves one simultaneous card-versus-echo comparison.
## Returns true only when this clash defeats the echo.
func _resolve_card_clash(context: CombatContext, card: CardInstance) -> bool:
	var player_before := _copy_player_stats(context)
	var monster_before := _copy_monster_stats(context)
	var points_before := card.current_points if card != null else 0
	var armor_before := card.current_armor if card != null else 0
	var source_name := _card_name(card)
	var applied_effects: Array[CombatEffect] = []
	var card_was_used := card != null and card.card_data != null and points_before > 0

	if card_was_used:
		# The echo's pre-clash HP is its power for this comparison. Its own armor
		# still absorbs incoming card points through CombatStats.take_damage().
		var echo_power := context.monster.stats.hp
		context.monster.take_damage(points_before)
		applied_effects.append(
			CombatEffect.new(
				CombatEffect.Type.DAMAGE,
				CombatEffect.Target.MONSTER,
				points_before,
				_source_type_for(card),
				source_name
			)
		)
		card.take_point_damage(echo_power)

	_append_step(
		context,
		CombatStep.Kind.ROOT_CARD if _is_root_card(card) else CombatStep.Kind.PLAYER_CARD,
		source_name,
		applied_effects,
		player_before,
		monster_before,
		points_before,
		card.current_points if card != null else 0,
		armor_before,
		card.current_armor if card != null else 0
	)
	if card_was_used and card.is_depleted() and card not in context.depleted_cards:
		context.depleted_cards.append(card)
	return _is_monster_defeated(context)


func _append_step(
	context: CombatContext,
	kind: CombatStep.Kind,
	source_name: String,
	effects: Array[CombatEffect],
	player_before: CombatStats,
	monster_before: CombatStats,
	card_points_before: int,
	card_points_after: int,
	card_armor_before: int,
	card_armor_after: int
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
			_copy_monster_stats(context),
			card_points_before,
			card_points_after,
			card_armor_before,
			card_armor_after
		)
	)


func _build_result(context: CombatContext, outcome: CombatResult.Outcome) -> CombatResult:
	return CombatResult.new(
		outcome,
		context.player_stats if context != null else null,
		context.monster.stats if context != null and context.monster != null else null,
		context.steps if context != null else [],
		context.resolved_cards.size() if context != null else 0,
		[],
		context.monster.action_index if context != null and context.monster != null else 0,
		context.depleted_cards if context != null else []
	)


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


func _source_type_for(card: CardInstance) -> CombatEffect.SourceType:
	return CombatEffect.SourceType.ROOT_CARD if _is_root_card(card) else CombatEffect.SourceType.PLAYER_CARD


func _card_name(card: CardInstance) -> String:
	return card.card_data.card_name if card != null and card.card_data != null else ""