class_name EventRewardResolver
extends RefCounted

const EventShopContentScript = preload("res://scripts/game/event/event_shop_content.gd")
const EventTreasureContentScript = preload("res://scripts/game/event/event_treasure_content.gd")
const EventResolutionResultScript = preload("res://scripts/game/event/core/event_resolution_result.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure_reward_option.gd")


func purchase_shop_item(instance, item_index: int, player, hand_has_capacity: bool) -> EventResolutionResultScript:
	if instance == null or player == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)

	var content = instance.get_content() as EventShopContentScript
	if content == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)
	if item_index < 0 or item_index >= content.items.size():
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_INDEX)
	if instance.is_resolved:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.ALREADY_RESOLVED)
	if _is_shop_item_sold(instance, item_index):
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.SOLD_OUT)
	if not hand_has_capacity:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.HAND_FULL)

	var item = content.items[item_index]
	if player.gold < item.price:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INSUFFICIENT_GOLD)

	_ensure_shop_sold_flags(instance, content.items.size())
	player.gold -= item.price
	instance.shop_sold_flags[item_index] = true

	var result := EventResolutionResultScript.new()
	result.success = true
	result.granted_card = item.card_data
	return result


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


func _is_shop_item_sold(instance, item_index: int) -> bool:
	return item_index < instance.shop_sold_flags.size() and instance.shop_sold_flags[item_index]


func _ensure_shop_sold_flags(instance, item_count: int) -> void:
	if instance.shop_sold_flags.size() == item_count:
		return

	var flags: Array[bool] = []
	flags.resize(item_count)
	flags.fill(false)
	for index in mini(instance.shop_sold_flags.size(), item_count):
		flags[index] = instance.shop_sold_flags[index]
	instance.shop_sold_flags = flags