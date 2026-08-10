class_name CombatService2
extends RefCounted

## Resolves a point-clash encounter from the chain head back to its root.
##
## Cards and echoes never mutate combat state here through their rules. They
## only edit CombatEffectDraft; CombatEffectResolver applies the finished list
## in order, which makes each CombatStep a complete replay/log payload.

var _effect_resolver := CombatEffectResolver.new()


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

	_resolve_combat_start_effects(context)
	var outcome := CombatResult.Outcome.RETREAT
	if _resolve_pre_head_trigger(context):
		outcome = CombatResult.Outcome.VICTORY
	else:
		for card_index in range(context.cards.size() - 1, -1, -1):
			var card := context.cards[card_index]
			if _should_skip_card(context, card):
				continue
			if _resolve_card_until_depleted_or_victory(context, card):
				outcome = CombatResult.Outcome.VICTORY
				break

	_resolve_combat_end_effects(context)
	_register_depleted_cards(context)
	return _build_result(context, outcome)


## Applies card lifecycle rules before the first point clash. Each effect gets
## its own replay step so logs and future animations can show the bonus.
func _resolve_combat_start_effects(context: CombatContext) -> void:
	if context == null:
		return
	for card in context.cards:
		if card == null or card.card_data == null:
			continue
		var player_before := _copy_player_stats(context)
		var monster_before := _copy_monster_stats(context)
		var points_before := card.current_points
		var armor_before := card.current_armor
		var draft := CombatEffectDraft.new(context, card)
		draft.phase = "combat_start"
		_run_card_hooks(card, "on_combat_started", draft)
		if draft.effects.is_empty():
			continue
		var resolved_effects := _effect_resolver.resolve(draft)
		_append_step(
			context,
			CombatStep.Kind.COMBAT_START,
			_card_name(card),
			resolved_effects,
			player_before,
			monster_before,
			points_before,
			card.current_points,
			armor_before,
			card.current_armor
		)


## Removes only the still-present part of combat-only point grants. This means
## a card keeps exactly the persistent points it would have had without the
## temporary bonus, while every state change remains a CombatEffect.
func _resolve_combat_end_effects(context: CombatContext) -> void:
	if context == null or context.temporary_card_points.is_empty():
		return
	var cards: Array[CardInstance] = []
	for card in context.temporary_card_points.keys():
		if card is CardInstance:
			cards.append(card)
	for card in cards:
		var temporary_points := context.get_temporary_card_points(card)
		if temporary_points <= 0:
			context.clear_temporary_card_points(card)
			continue
		var player_before := _copy_player_stats(context)
		var monster_before := _copy_monster_stats(context)
		var points_before := card.current_points
		var armor_before := card.current_armor
		var draft := CombatEffectDraft.new(context, card)
		draft.phase = "combat_end"
		draft.add_card_points(
			-temporary_points,
			card,
			CombatEffect.SourceType.SYSTEM,
			"战斗结算",
			{"temporary_cleanup": true, "duration": "combat"},
			["combat_end", "temporary_card_points"]
		)
		var resolved_effects := _effect_resolver.resolve(draft)
		context.clear_temporary_card_points(card)
		_append_step(
			context,
			CombatStep.Kind.COMBAT_END,
			_card_name(card),
			resolved_effects,
			player_before,
			monster_before,
			points_before,
			card.current_points,
			armor_before,
			card.current_armor
		)


## Gives the card immediately behind the head a one-time battle-opening window.
## Positional rules create their own one-way effects here; unlike an ordinary
## point clash, this path does not add the monster retaliation effect.
func _resolve_pre_head_trigger(context: CombatContext) -> bool:
	if context == null or context.cards.size() < 2:
		return false
	var card_index := context.cards.size() - 2
	var card := context.cards[card_index]
	if _should_skip_card(context, card):
		return false

	var resolution_context := CardResolutionContext.new(context, card, card_index)
	var eligible_rule_indices: Array[int] = []
	for rule_index in range(card.card_data.effect_rules.size()):
		var rule := card.card_data.effect_rules[rule_index]
		if rule != null and rule.should_trigger_before_head(resolution_context):
			eligible_rule_indices.append(rule_index)
	if eligible_rule_indices.is_empty():
		return false

	var player_before := _copy_player_stats(context)
	var monster_before := _copy_monster_stats(context)
	var points_before := card.current_points
	var armor_before := card.current_armor
	var draft := CombatEffectDraft.new(context, card)
	draft.phase = "pre_combat"
	for rule_index in eligible_rule_indices:
		var rule: CardRule = card.card_data.effect_rules[rule_index]
		if not card.can_trigger_rule(rule_index, rule.effective_count):
			continue
		if rule.on_pre_combat(draft):
			card.record_rule_trigger(rule_index)
	if draft.effects.is_empty():
		return false

	# A pre-combat strike is an extra action, not a replacement for this card's
	# ordinary chain clash. Keep it in the pending chain so it can still fight if
	# the cards ahead of it are defeated.
	if card not in context.resolved_cards:
		context.resolved_cards.append(card)
	var resolved_effects := _effect_resolver.resolve(draft)
	if card.is_depleted():
		_run_card_depletion_hooks(context, card, draft, resolved_effects)
		_register_depleted_cards(context)
	_append_step(
		context,
		CombatStep.Kind.PRE_COMBAT_CARD,
		_card_name(card),
		resolved_effects,
		player_before,
		monster_before,
		points_before,
		card.current_points,
		armor_before,
		card.current_armor
	)
	return _is_monster_defeated(context)

func _should_skip_card(context: CombatContext, card: CardInstance) -> bool:
	return (
		card == null
		or card.card_data == null
		or card.is_depleted()
		or card in context.pre_resolved_cards
	)


## A card remains active while it still has points. This preserves the existing
## armor loop: armor can protect points, allowing the same card to attack again.
func _resolve_card_until_depleted_or_victory(context: CombatContext, card: CardInstance) -> bool:
	if context == null or card == null or card.card_data == null or card.is_depleted():
		return false
	if card not in context.resolved_cards:
		context.resolved_cards.append(card)
	while not card.is_depleted() and not _is_monster_defeated(context):
		if _resolve_card_clash(context, card):
			context.remaining_cards.erase(card)
			return true
	context.remaining_cards.erase(card)
	return false


## Builds the base simultaneous clash and lets both sides modify its one shared
## CombatEffect list before the resolver mutates any runtime state.
func _resolve_card_clash(context: CombatContext, card: CardInstance) -> bool:
	var player_before := _copy_player_stats(context)
	var monster_before := _copy_monster_stats(context)
	var points_before := card.current_points if card != null else 0
	var armor_before := card.current_armor if card != null else 0
	var source_name := _card_name(card)
	var draft := CombatEffectDraft.new(context, card)
	var card_was_used := card != null and card.card_data != null and points_before > 0

	if card_was_used:
		# Echo power is captured before any card damage. Its current HP therefore
		# remains the clean, readable comparison value for this clash.
		var echo_power := context.monster.stats.hp
		draft.add_damage(
			CombatEffect.Target.MONSTER,
			points_before,
			_source_type_for(card),
			source_name,
			null,
			{},
			["point_clash", "card_attack"]
		)
		draft.add_damage(
			CombatEffect.Target.CARD,
			echo_power,
			CombatEffect.SourceType.MONSTER_ACTION,
			_monster_name(context.monster),
			card,
			{},
			["point_clash", "echo_retaliation"]
		)
		draft.phase = "attack"
		_run_card_hooks(card, "on_attack", draft)
		_run_mob_hooks(context.monster, "on_attack", draft)
		draft.phase = "before_resolve"
		_run_card_hooks(card, "on_before_resolve", draft)
		_run_mob_hooks(context.monster, "on_before_resolve", draft)

	var resolved_effects := _effect_resolver.resolve(draft)
	if card_was_used and card.is_depleted():
		_run_card_depletion_hooks(context, card, draft, resolved_effects)
		_register_depleted_cards(context)

	_append_step(
		context,
		CombatStep.Kind.ROOT_CARD if _is_root_card(card) else CombatStep.Kind.PLAYER_CARD,
		source_name,
		resolved_effects,
		player_before,
		monster_before,
		points_before,
		card.current_points if card != null else 0,
		armor_before,
		card.current_armor if card != null else 0
	)
	return _is_monster_defeated(context)


func _run_card_hooks(card: CardInstance, hook_name: String, draft: CombatEffectDraft) -> void:
	if card == null or card.card_data == null:
		return
	var rules := card.card_data.effect_rules
	for rule_index in range(rules.size()):
		var rule := rules[rule_index]
		if rule == null or not card.can_trigger_rule(rule_index, rule.effective_count):
			continue
		var changed := bool(rule.call(hook_name, draft))
		if changed:
			card.record_rule_trigger(rule_index)


func _run_mob_hooks(monster: MobInstance, hook_name: String, draft: CombatEffectDraft) -> void:
	if monster == null:
		return
	var effects := monster.get_effects()
	for effect_index in range(effects.size()):
		var effect: Resource = effects[effect_index]
		if effect == null or not effect.has_method(hook_name):
			continue
		var configured_value: Variant = effect.get("effective_count")
		var configured_count := -1 if configured_value == null else int(configured_value)
		if not monster.can_trigger_effect(effect_index, configured_count):
			continue
		var changed := bool(effect.call(hook_name, draft))
		if changed:
			monster.record_effect_trigger(effect_index)


func _run_card_depletion_hooks(
	context: CombatContext,
	card: CardInstance,
	draft: CombatEffectDraft,
	resolved_effects: Array[CombatEffect]
) -> void:
	var resolved_count := draft.effects.size()
	draft.phase = "card_depleted"
	var rules := card.card_data.effect_rules
	for rule_index in range(rules.size()):
		var rule := rules[rule_index]
		if rule == null or not card.can_trigger_rule(rule_index, rule.effective_count):
			continue
		if rule.on_card_depleted(draft, card):
			card.record_rule_trigger(rule_index)
	var mob_effects := context.monster.get_effects()
	for effect_index in range(mob_effects.size()):
		var effect: Resource = mob_effects[effect_index]
		if effect == null or not effect.has_method("on_card_depleted"):
			continue
		var configured_value: Variant = effect.get("effective_count")
		var configured_count := -1 if configured_value == null else int(configured_value)
		if not context.monster.can_trigger_effect(effect_index, configured_count):
			continue
		if bool(effect.on_card_depleted(draft, card)):
			context.monster.record_effect_trigger(effect_index)
	if draft.effects.size() <= resolved_count:
		return
	var added_effects: Array[CombatEffect] = []
	for index in range(resolved_count, draft.effects.size()):
		added_effects.append(draft.effects[index])
	resolved_effects.append_array(_effect_resolver.resolve_effects(added_effects, context, card))


func _register_depleted_cards(context: CombatContext) -> void:
	if context == null:
		return
	for card in context.cards:
		if card != null and card.is_depleted() and card not in context.depleted_cards:
			context.depleted_cards.append(card)


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
	return context.player_stats.duplicate_runtime() if context != null and context.player_stats != null else null


func _copy_monster_stats(context: CombatContext) -> CombatStats:
	return context.monster.stats.duplicate_runtime() if context != null and context.monster != null and context.monster.stats != null else null


func _is_monster_defeated(context: CombatContext) -> bool:
	return context == null or context.monster == null or context.monster.stats == null or not context.monster.is_alive()


func _is_root_card(card: CardInstance) -> bool:
	return card != null and card.card_data != null and card.card_data.card_type == CardData.CardType.ROOT


func _source_type_for(card: CardInstance) -> CombatEffect.SourceType:
	return CombatEffect.SourceType.ROOT_CARD if _is_root_card(card) else CombatEffect.SourceType.PLAYER_CARD


func _card_name(card: CardInstance) -> String:
	return card.card_data.card_name if card != null and card.card_data != null else ""


func _monster_name(monster: MobInstance) -> String:
	return monster.data.mob_name if monster != null and monster.data != null else "残响"
