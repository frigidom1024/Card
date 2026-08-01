class_name ShopEventResolver
extends RefCounted

const ShopEventContentScript = preload("res://scripts/game/event/shop/shop_event_content.gd")
const ShopRuntimeStateScript = preload("res://scripts/game/event/shop/shop_runtime_state.gd")
const EventResolutionResultScript = preload("res://scripts/game/event/core/event_resolution_result.gd")


func purchase_item(
	instance: EventInstance, item_index: int, player: PlayerData, hand_has_capacity: bool
) -> EventResolutionResultScript:
	if instance == null or player == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)

	var content = instance.get_content() as ShopEventContentScript
	var state = instance.runtime_state as ShopRuntimeStateScript
	if content == null or state == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)
	if item_index < 0 or item_index >= content.items.size():
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_INDEX)
	if instance.is_resolved:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.ALREADY_RESOLVED)
	if _is_item_sold(state, item_index):
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.SOLD_OUT)
	if not hand_has_capacity:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.HAND_FULL)

	var item = content.items[item_index]
	if item == null:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INVALID_EVENT)
	if player.gold < item.price:
		return EventResolutionResultScript.rejected(EventResolutionResultScript.Failure.INSUFFICIENT_GOLD)

	_ensure_sold_flags(state, content.items.size())
	player.gold -= item.price
	state.sold_flags[item_index] = true

	var result := EventResolutionResultScript.new()
	result.success = true
	result.granted_card = item.card_data
	return result


func _is_item_sold(state: ShopRuntimeStateScript, item_index: int) -> bool:
	return item_index < state.sold_flags.size() and state.sold_flags[item_index]


func _ensure_sold_flags(state: ShopRuntimeStateScript, item_count: int) -> void:
	if state.sold_flags.size() == item_count:
		return

	var flags: Array[bool] = []
	flags.resize(item_count)
	for index in mini(state.sold_flags.size(), item_count):
		flags[index] = state.sold_flags[index]
	state.sold_flags = flags