class_name EventRewardResolver
extends RefCounted

const EventTreasureContentScript = preload("res://scripts/game/event/event_treasure_content.gd")
const EventResolutionResultScript = preload("res://scripts/game/event/core/event_resolution_result.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure_reward_option.gd")


func claim_treasure_reward(
	instance, option_index: int, player, hand_has_capacity: bool, rng: RandomNumberGenerator
) -> EventResolutionResultScript:
	if instance == null or player == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)

	var content = instance.get_content() as EventTreasureContentScript
	if content == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)
	if instance.is_resolved:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.ALREADY_RESOLVED)

	if instance.treasure_options.is_empty():
		var card_option_count := mini(2, content.unique_card_count())
		if option_index < 0 or option_index > card_option_count:
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_INDEX)
		if option_index < card_option_count and not hand_has_capacity:
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.HAND_FULL)
	else:
		if option_index < 0 or option_index >= instance.treasure_options.size():
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_INDEX)
		if (
			instance.treasure_options[option_index].kind == TreasureRewardOptionScript.Kind.CARD
			and not hand_has_capacity
		):
			return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.HAND_FULL)

	var options = ensure_treasure_options(instance, rng)
	var option = options[option_index]
	var result := EventResolutionResultScript.new()
	result.success = true
	if option.kind == TreasureRewardOptionScript.Kind.GOLD:
		player.gold += option.gold_amount
		result.gold_delta = option.gold_amount
	else:
		result.granted_card = option.card_data

	instance.selected_treasure_option = option_index
	instance.resolve()
	return result


func ensure_treasure_options(instance, rng: RandomNumberGenerator) -> Array[TreasureRewardOptionScript]:
	if instance == null:
		return []
	if not instance.treasure_options.is_empty():
		return instance.treasure_options

	var content = instance.get_content() as EventTreasureContentScript
	if content == null:
		return []

	for card in content.draw_unique_choices(2, rng):
		instance.treasure_options.append(TreasureRewardOptionScript.card(card))
	instance.treasure_options.append(
		TreasureRewardOptionScript.gold(rng.randi_range(content.gold_range.x, content.gold_range.y))
	)
	return instance.treasure_options
