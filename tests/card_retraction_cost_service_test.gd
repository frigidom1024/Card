extends SceneTree

const CardRetractionCostServiceScript := preload("res://scripts/game/run/card_retraction_cost_service.gd")
const ChainRetractionTransactionScript := preload("res://scripts/game/chain_retraction_transaction.gd")
const PlayerDataScript := preload("res://scripts/player/player_data.gd")

var _failure_count := 0

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    _test_one_returned_card_costs_two_gold()
    _test_source_and_followers_are_all_charged()
    quit(1 if _failure_count > 0 else 0)

func _test_one_returned_card_costs_two_gold() -> void:
    var player := PlayerDataScript.new()
    player.gold = 10
    var transaction := ChainRetractionTransactionScript.new(null, [], 1)
    var service := CardRetractionCostServiceScript.new()
    service.configure(player)
    _expect(service.get_returned_card_count(transaction) == 1, "source card counts as one returned card")
    _expect(service.get_cost(transaction) == 2, "one returned card costs two gold")
    service.resolve_confirmed_chain_retraction(transaction)
    _expect(player.gold == 8, "one returned card deducts two gold")

func _test_source_and_followers_are_all_charged() -> void:
    var player := PlayerDataScript.new()
    player.gold = 10
    var followers: Array[CardEntity] = []
    followers.resize(2)
    var transaction := ChainRetractionTransactionScript.new(null, followers, 3)
    var service := CardRetractionCostServiceScript.new()
    service.configure(player)
    service.resolve_confirmed_chain_retraction(transaction)
    _expect(player.gold == 4, "source and two followers cost six gold")

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
