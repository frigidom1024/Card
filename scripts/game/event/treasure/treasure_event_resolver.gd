class_name TreasureEventResolver
extends RefCounted



func ensure_options(
	instance: EventInstance, rng: RandomNumberGenerator
) -> Array[TreasureRewardOption]:
	if instance == null:
		return []
	if instance.get_event_type() != EventData.EventType.TREASURE:
		return []

	var content := instance.get_content() as TreasureEventContent
	var state := instance.runtime_state as TreasureRuntimeState
	if content == null or state == null:
		return []
	if instance.is_resolved or rng == null:
		return []
	if not state.options.is_empty():
		return state.options

	for card in content.draw_unique_choices(2, rng):
		state.options.append(TreasureRewardOption.card(card))
	state.options.append(
		TreasureRewardOption.gold(rng.randi_range(content.gold_range.x, content.gold_range.y))
	)
	return state.options


func claim_reward(
	instance: EventInstance,
	option_index: int,
	player: PlayerData,
	hand_has_capacity: bool,
	rng: RandomNumberGenerator
) -> EventResolutionResult:
	if instance == null or player == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)
	if instance.get_event_type() != EventData.EventType.TREASURE:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)

	var content := instance.get_content() as TreasureEventContent
	var state := instance.runtime_state as TreasureRuntimeState
	if content == null or state == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)
	if instance.is_resolved:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.ALREADY_RESOLVED)
	if rng == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)

	if state.options.is_empty():
		var card_option_count := mini(2, content.unique_card_count())
		if option_index < 0 or option_index > card_option_count:
			return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_INDEX)
		if option_index < card_option_count and not hand_has_capacity:
			return EventResolutionResult.rejected(EventResolutionResult.Failure.HAND_FULL)
	else:
		if option_index < 0 or option_index >= state.options.size():
			return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_INDEX)
		if (
			state.options[option_index].kind == TreasureRewardOption.Kind.CARD
			and not hand_has_capacity
		):
			return EventResolutionResult.rejected(EventResolutionResult.Failure.HAND_FULL)

	var options := ensure_options(instance, rng)
	var option := options[option_index]
	var result := EventResolutionResult.new()
	result.success = true
	if option.kind == TreasureRewardOption.Kind.GOLD:
		player.add_gold(option.gold_amount)
		result.gold_delta = option.gold_amount
	else:
		result.granted_card = option.card_data

	state.selected_option_index = option_index
	instance.resolve()
	return result
