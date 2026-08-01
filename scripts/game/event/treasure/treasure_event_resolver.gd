class_name TreasureEventResolver
extends RefCounted

const TreasureEventContentScript = preload("res://scripts/game/event/treasure/treasure_event_content.gd")
const TreasureRuntimeStateScript = preload("res://scripts/game/event/treasure/treasure_runtime_state.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure/treasure_reward_option.gd")
const EventResolutionResultScript = preload("res://scripts/game/event/core/event_resolution_result.gd")


func ensure_options(
	instance: EventInstance, rng: RandomNumberGenerator
) -> Array[TreasureRewardOptionScript]:
	if instance == null:
		return []

	var content := instance.get_content() as TreasureEventContentScript
	var state := instance.runtime_state as TreasureRuntimeStateScript
	if content == null or state == null:
		return []
	if not state.options.is_empty():
		return state.options

	for card in content.draw_unique_choices(2, rng):
		state.options.append(TreasureRewardOptionScript.card(card))
	state.options.append(
		TreasureRewardOptionScript.gold(rng.randi_range(content.gold_range.x, content.gold_range.y))
	)
	return state.options


func claim_reward(
	instance: EventInstance,
	option_index: int,
	player: PlayerData,
	hand_has_capacity: bool,
	rng: RandomNumberGenerator
) -> EventResolutionResultScript:
	if instance == null or player == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)

	var content := instance.get_content() as TreasureEventContentScript
	var state := instance.runtime_state as TreasureRuntimeStateScript
	if content == null or state == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)
	if instance.is_resolved:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.ALREADY_RESOLVED)

	if state.options.is_empty():
		var card_option_count := mini(2, content.unique_card_count())
		if option_index < 0 or option_index > card_option_count:
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_INDEX)
		if option_index < card_option_count and not hand_has_capacity:
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.HAND_FULL)
	else:
		if option_index < 0 or option_index >= state.options.size():
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_INDEX)
		if (
			state.options[option_index].kind == TreasureRewardOptionScript.Kind.CARD
			and not hand_has_capacity
		):
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.HAND_FULL)

	var options := ensure_options(instance, rng)
	var option := options[option_index]
	var result := EventResolutionResultScript.new()
	result.success = true
	if option.kind == TreasureRewardOptionScript.Kind.GOLD:
		player.gold += option.gold_amount
		result.gold_delta = option.gold_amount
	else:
		result.granted_card = option.card_data

	state.selected_option_index = option_index
	instance.resolve()
	return result
