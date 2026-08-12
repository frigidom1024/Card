class_name CombatEffectDraft
extends RefCounted

## Mutable effect list for one card-versus-echo clash.
##
## This is deliberately not a second effect model: it only carries the same
## CombatEffect instances while rules inspect and alter the pending list.
var combat_context: CombatContext
var current_card: CardInstance
var card_chain: Array[CardInstance] = []
var effects: Array[CombatEffect] = []
var phase: String = "attack"


func _init(context: CombatContext = null, card: CardInstance = null) -> void:
	combat_context = context
	current_card = card
	if context != null:
		card_chain = context.cards.duplicate()


func add_effect(effect: CombatEffect) -> CombatEffect:
	if effect == null:
		return null
	if effect.sequence < 0:
		effect.sequence = effects.size()
	if effect.phase.is_empty():
		effect.phase = phase
	if effect.target == CombatEffect.Target.CARD and effect.target_card != null and effect.target_name.is_empty():
		effect.target_name = _card_name(effect.target_card)
	elif effect.target_name.is_empty():
		effect.target_name = _target_name(effect.target)
	effects.append(effect)
	return effect


func _card_name(card: CardInstance) -> String:
	return card.card_data.card_name if card != null and card.card_data != null else "卡牌"


func _target_name(target: CombatEffect.Target) -> String:
	match target:
		CombatEffect.Target.PLAYER:
			return "玩家"
		CombatEffect.Target.MONSTER:
			return combat_context.monster.data.mob_name if combat_context != null and combat_context.monster != null and combat_context.monster.data != null else "残响"
		CombatEffect.Target.CARD:
			return "卡牌"
	return "目标"


func add_damage(
	target: CombatEffect.Target,
	value: int,
	source_type: CombatEffect.SourceType,
	source_name: String,
	target_card: CardInstance = null,
	parameters: Dictionary = {},
	tags: Array = []
) -> CombatEffect:
	return add_effect(
		CombatEffect.new(
			CombatEffect.Type.DAMAGE,
			target,
			value,
			source_type,
			source_name,
			target_card,
			parameters,
			tags
		)
	)


func add_card_points(
	value: int,
	target_card: CardInstance = null,
	source_type: int = -1,
	source_name: String = "",
	parameters: Dictionary = {},
	tags: Array = []
) -> CombatEffect:
	var resolved_card: CardInstance = target_card if target_card != null else current_card
	var resolved_source_type: CombatEffect.SourceType = (
		get_current_source_type() if source_type < 0 else source_type
	)
	var resolved_source_name := source_name if not source_name.is_empty() else get_current_source_name()
	return add_effect(CombatEffect.new(
		CombatEffect.Type.MODIFY_CARD_POINTS,
		CombatEffect.Target.CARD,
		value,
		resolved_source_type,
		resolved_source_name,
		resolved_card,
		parameters,
		tags
	))


func find_effects(type: CombatEffect.Type = -1, target: CombatEffect.Target = -1) -> Array[CombatEffect]:
	var found: Array[CombatEffect] = []
	for effect in effects:
		if effect == null:
			continue
		if type >= 0 and effect.type != type:
			continue
		if target >= 0 and effect.target != target:
			continue
		found.append(effect)
	return found


func get_card_damage_effect() -> CombatEffect:
	for effect in effects:
		if effect != null and effect.type == CombatEffect.Type.DAMAGE and effect.target == CombatEffect.Target.CARD:
			if effect.target_card == current_card:
				return effect
	return null


func get_monster_damage_effect() -> CombatEffect:
	for effect in effects:
		if effect != null and effect.type == CombatEffect.Type.DAMAGE and effect.target == CombatEffect.Target.MONSTER:
			return effect
	return null


func is_current_card_first() -> bool:
	return card_chain.find(current_card) == 0


func is_current_card_last() -> bool:
	return not card_chain.is_empty() and card_chain.find(current_card) == card_chain.size() - 1


func get_previous_resolved_card() -> CardInstance:
	if combat_context == null:
		return null
	for index in range(combat_context.resolved_cards.size() - 1, -1, -1):
		var card := combat_context.resolved_cards[index]
		if card != null and card != current_card:
			return card
	return null


func get_current_source_type() -> CombatEffect.SourceType:
	if current_card != null and current_card.card_data != null and current_card.card_data.card_type == CardData.CardType.ROOT:
		return CombatEffect.SourceType.ROOT_CARD
	return CombatEffect.SourceType.PLAYER_CARD


func get_current_source_name() -> String:
	return current_card.card_data.card_name if current_card != null and current_card.card_data != null else "卡牌"


func add_player_defense(value: int, tags: Array = []) -> CombatEffect:
	return add_effect(CombatEffect.new(
		CombatEffect.Type.ADD_DEFENSE,
		CombatEffect.Target.PLAYER,
		value,
		get_current_source_type(),
		get_current_source_name(),
		null,
		{},
		tags
	))


func add_player_heal(value: int, tags: Array = []) -> CombatEffect:
	return add_effect(CombatEffect.new(
		CombatEffect.Type.HEAL,
		CombatEffect.Target.PLAYER,
		value,
		get_current_source_type(),
		get_current_source_name(),
		null,
		{},
		tags
	))


func get_cards_behind_current(count: int = -1) -> Array[CardInstance]:
	var cards: Array[CardInstance] = []
	if current_card == null:
		return cards
	var index := card_chain.find(current_card)
	if index < 0:
		return cards
	var start := index - 1
	while start >= 0 and (count < 0 or cards.size() < count):
		var card := card_chain[start]
		if card != null:
			cards.append(card)
		start -= 1
	return cards


func get_cards_ahead_of_current(count: int = -1) -> Array[CardInstance]:
	var cards: Array[CardInstance] = []
	if current_card == null:
		return cards
	var index := card_chain.find(current_card)
	if index < 0:
		return cards
	var next_index := index + 1
	while next_index < card_chain.size() and (count < 0 or cards.size() < count):
		var card := card_chain[next_index]
		if card != null:
			cards.append(card)
		next_index += 1
	return cards
