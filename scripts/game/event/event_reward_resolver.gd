class_name EventRewardResolver
extends RefCounted


func purchase_shop_item(
	instance: EventInstance, item_index: int, player: PlayerData, hand_has_capacity: bool
) -> EventResolutionResult:
	if instance == null or player == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)

	var content := instance.get_content() as EventShopContent
	if content == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)

	if instance.shop_sold_flags.is_empty() and not content.items.is_empty():
		instance.shop_sold_flags.resize(content.items.size())
		instance.shop_sold_flags.fill(false)

	if item_index < 0 or item_index >= content.items.size():
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_INDEX)
	if instance.is_resolved:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.ALREADY_RESOLVED)
	if instance.shop_sold_flags[item_index]:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.SOLD_OUT)
	if not hand_has_capacity:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.HAND_FULL)

	var item := content.items[item_index]
	if player.gold < item.price:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INSUFFICIENT_GOLD)

	player.gold -= item.price
	instance.shop_sold_flags[item_index] = true

	var result := EventResolutionResult.new()
	result.success = true
	result.granted_card = item.card_data
	return result


func claim_treasure_reward(
	instance: EventInstance,
	option_index: int,
	player: PlayerData,
	hand_has_capacity: bool,
	rng: RandomNumberGenerator
) -> EventResolutionResult:
	if instance == null or player == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)

	var content := instance.get_content() as EventTreasureContent
	if content == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)
	if instance.is_resolved:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.ALREADY_RESOLVED)

	var options := ensure_treasure_options(instance, rng)
	if option_index < 0 or option_index >= options.size():
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_INDEX)

	var option := options[option_index]
	if option.kind == TreasureRewardOption.Kind.CARD and not hand_has_capacity:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.HAND_FULL)

	var result := EventResolutionResult.new()
	result.success = true
	if option.kind == TreasureRewardOption.Kind.GOLD:
		player.gold += option.gold_amount
		result.gold_delta = option.gold_amount
	else:
		result.granted_card = option.card_data

	instance.selected_treasure_option = option_index
	instance.resolve()
	return result


func ensure_treasure_options(
	instance: EventInstance, rng: RandomNumberGenerator
) -> Array[TreasureRewardOption]:
	if instance == null:
		return []
	if not instance.treasure_options.is_empty():
		return instance.treasure_options

	var content := instance.get_content() as EventTreasureContent
	if content == null:
		return []

	var card_count := mini(content.choices, 2)
	for card in content.draw_unique_choices(card_count, rng):
		instance.treasure_options.append(TreasureRewardOption.card(card))
	instance.treasure_options.append(
		TreasureRewardOption.gold(rng.randi_range(content.gold_range.x, content.gold_range.y))
	)
	return instance.treasure_options
