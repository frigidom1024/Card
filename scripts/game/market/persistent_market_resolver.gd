class_name PersistentMarketResolver
extends RefCounted


const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

enum Failure { NONE, INVALID_OFFER, HAND_FULL, INSUFFICIENT_GOLD, INVALID_CARD }


class TransactionResult extends RefCounted:
	var success := false
	var failure := Failure.NONE
	var card_data: CardData
	var gold_delta := 0


var _pricing: Object


func _init(pricing: Object = null) -> void:
	_pricing = pricing if pricing != null else MarketPricingServiceScript.new()


func purchase(state, slot_index: int, player: PlayerData, hand_has_capacity: bool, context) -> TransactionResult:
	if state == null or player == null:
		return _failure(Failure.INVALID_OFFER)
	var card_data = state.call("get_offer", slot_index)
	if card_data == null:
		return _failure(Failure.INVALID_OFFER)
	if not hand_has_capacity:
		return _failure(Failure.HAND_FULL)
	var price: int = int(_pricing.call("get_purchase_price", card_data, context))
	if not player.spend_gold(price):
		return _failure(Failure.INSUFFICIENT_GOLD)
	state.call("replace_offer", slot_index)
	return _success(card_data, -price)


func reclaim(card_data: CardData, player: PlayerData, context) -> TransactionResult:
	if card_data == null or player == null:
		return _failure(Failure.INVALID_CARD)
	var payout: int = int(_pricing.call("get_reclaim_price", card_data, context))
	player.add_gold(payout)
	return _success(card_data, payout)


func refresh(state, player: PlayerData, context) -> TransactionResult:
	if state == null or player == null:
		return _failure(Failure.INVALID_OFFER)
	var cost: int = int(_pricing.call("get_refresh_cost", context))
	if not player.spend_gold(cost):
		return _failure(Failure.INSUFFICIENT_GOLD)
	state.call("refresh_offers")
	return _success(null, -cost)


func _success(card_data: CardData, gold_delta: int) -> TransactionResult:
	var result := TransactionResult.new()
	result.success = true
	result.card_data = card_data
	result.gold_delta = gold_delta
	return result


func _failure(failure: Failure) -> TransactionResult:
	var result := TransactionResult.new()
	result.failure = failure
	return result
