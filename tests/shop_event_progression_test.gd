extends SceneTree

const ShopEvent := preload("res://data/levels/ribwood/events/ribwood_broken_banner_shop_event.tres")
const ShopEventResolverScript := preload("res://scripts/game/event/shop/shop_event_resolver.gd")
const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")
const RunProgressionServiceScript := preload("res://scripts/game/run/run_progression_service.gd")
const PlayerDataScript := preload("res://scripts/player/player_data.gd")
const EventResolutionResultScript := preload("res://scripts/game/event/core/event_resolution_result.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_event_shop_hides_locked_rarity_from_purchase()
	_test_event_shop_allows_card_after_rarity_unlock()
	quit(1 if _failure_count > 0 else 0)


func _test_event_shop_hides_locked_rarity_from_purchase() -> void:
	var progression := RunProgressionServiceScript.new()
	progression.configure(RunProgressionConfigScript.new())
	var resolver := ShopEventResolverScript.new(null, progression)
	var player := PlayerDataScript.new()
	player.gold = 100
	var result := resolver.purchase_item(ShopEvent.create_instance(), 1, player, true)
	_expect(not result.success, "event shop rejects a rare card before its action threshold")
	_expect(result.failure == EventResolutionResultScript.Failure.CARD_LOCKED, "locked event-shop card reports a dedicated failure")


func _test_event_shop_allows_card_after_rarity_unlock() -> void:
	var progression := RunProgressionServiceScript.new()
	progression.configure(RunProgressionConfigScript.new())
	progression.set_action_count(4)
	var resolver := ShopEventResolverScript.new(null, progression)
	var player := PlayerDataScript.new()
	player.gold = 100
	var result := resolver.purchase_item(ShopEvent.create_instance(), 1, player, true)
	_expect(result.success, "event shop allows a rare card after its action threshold")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
