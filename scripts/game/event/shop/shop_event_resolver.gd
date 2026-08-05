class_name ShopEventResolver
extends RefCounted


const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")


var _pricing: Object


func _init(pricing: Object = null) -> void:
	_pricing = pricing if pricing != null else MarketPricingServiceScript.new()


func purchase_item(
	instance: EventInstance,
	item_index: int,
	player: PlayerData,
	hand_has_capacity: bool,
	context = null
) -> EventResolutionResult:
	if instance == null or player == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)
	if instance.get_event_type() != EventData.EventType.SHOP:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)

	var content = instance.get_content() as ShopEventContent
	var state = instance.runtime_state as ShopRuntimeState
	if content == null or state == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)
	if item_index < 0 or item_index >= content.items.size():
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_INDEX)
	if instance.is_resolved:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.ALREADY_RESOLVED)
	if _is_item_sold(state, item_index):
		return EventResolutionResult.rejected(EventResolutionResult.Failure.SOLD_OUT)
	if not hand_has_capacity:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.HAND_FULL)

	var item = content.items[item_index]
	if item == null or item.card_data == null:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INVALID_EVENT)
	var price := int(_pricing.call("get_purchase_price", item.card_data, context))
	if player.gold < price:
		return EventResolutionResult.rejected(EventResolutionResult.Failure.INSUFFICIENT_GOLD)

	_ensure_sold_flags(state, content.items.size())
	player.gold -= price
	state.sold_flags[item_index] = true

	var result := EventResolutionResult.new()
	result.success = true
	result.granted_card = item.card_data
	return result


func _is_item_sold(state: ShopRuntimeState, item_index: int) -> bool:
	return item_index < state.sold_flags.size() and state.sold_flags[item_index]


func _ensure_sold_flags(state: ShopRuntimeState, item_count: int) -> void:
	if state.sold_flags.size() == item_count:
		return

	var flags: Array[bool] = []
	flags.resize(item_count)
	for index in mini(state.sold_flags.size(), item_count):
		flags[index] = state.sold_flags[index]
	state.sold_flags = flags