extends SceneTree

const CardRetractionCostServiceScript := preload("res://scripts/game/run/card_retraction_cost_service.gd")
const ChainRetractionTransactionScript := preload("res://scripts/game/chain_retraction_transaction.gd")
const PlayerDataScript := preload("res://scripts/player/player_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_one_returned_card_costs_two_gold()
	_test_insufficient_gold_does_not_charge_or_publish()
	_test_source_and_followers_are_all_charged()
	quit(1 if _failure_count > 0 else 0)


func _test_one_returned_card_costs_two_gold() -> void:
	var player := PlayerDataScript.new()
	player.gold = 10
	var published_gold: Array[int] = []
	player.gold_changed.connect(func(value: int) -> void:
		published_gold.append(value)
	)
	var transaction := ChainRetractionTransactionScript.new(null, [], 1)
	var service := CardRetractionCostServiceScript.new()
	service.configure(player)
	_expect(service.get_returned_card_count(transaction) == 1, "source card counts as one returned card")
	_expect(service.get_cost(transaction) == 2, "one returned card costs two gold")
	service.resolve_confirmed_chain_retraction(transaction)
	_expect(player.gold == 8, "one returned card deducts two gold")
	_expect(published_gold == [8], "retraction cost publishes the new gold balance")


func _test_insufficient_gold_does_not_charge_or_publish() -> void:
	var player := PlayerDataScript.new()
	player.gold = 1
	var published_gold: Array[int] = []
	var payment_events: Array[Vector3i] = []
	player.gold_changed.connect(func(value: int) -> void:
		published_gold.append(value)
	)
	var transaction := ChainRetractionTransactionScript.new(null, [], 1)
	var service := CardRetractionCostServiceScript.new()
	service.configure(player)
	service.retraction_cost_paid.connect(func(cost: int, returned_count: int, remaining_gold: int) -> void:
		payment_events.append(Vector3i(cost, returned_count, remaining_gold))
	)
	service.resolve_confirmed_chain_retraction(transaction)
	_expect(player.gold == 1, "insufficient gold leaves the balance unchanged")
	_expect(published_gold.is_empty(), "insufficient gold publishes no balance change")
	_expect(payment_events.is_empty(), "insufficient gold publishes no payment event")


func _test_source_and_followers_are_all_charged() -> void:
	var player := PlayerDataScript.new()
	player.gold = 10
	var first_follower := Card.new()
	var second_follower := Card.new()
	var followers: Array[Card] = [first_follower, second_follower]
	var transaction := ChainRetractionTransactionScript.new(null, followers, 3)
	var service := CardRetractionCostServiceScript.new()
	service.configure(player)
	service.resolve_confirmed_chain_retraction(transaction)
	_expect(player.gold == 4, "source and two followers cost six gold")
	first_follower.free()
	second_follower.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
