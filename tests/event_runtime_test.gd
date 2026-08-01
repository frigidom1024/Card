extends SceneTree

const PlayerDataScript = preload("res://scripts/player/player_data.gd")
const EventDataScript = preload("res://scripts/game/event/event_data.gd")
const EventInstanceScript = preload("res://scripts/game/event/event_zone.gd")
const EventShopContentScript = preload("res://scripts/game/event/event_shop_content.gd")
const EventTreasureContentScript = preload("res://scripts/game/event/event_treasure_content.gd")
const ShopItemDataScript = preload("res://scripts/game/event/shop_item_data.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure_reward_option.gd")
const EventResolutionResultScript = preload("res://scripts/game/event/event_resolution_result.gd")
const EventRewardResolverScript = preload("res://scripts/game/event/event_reward_resolver.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")

var _failure_count := 0
var resolver := EventRewardResolverScript.new()


func _init() -> void:
	_test_player_starts_with_persistent_gold()
	_test_shop_purchase_changes_only_successful_state()
	_test_shop_failure_does_not_mutate_state()
	_test_treasure_options_are_cached_and_include_gold()
	_test_full_hand_rejects_card_but_allows_gold()
	call_deferred("_finish_tests")


func _test_player_starts_with_persistent_gold() -> void:
	var player := PlayerDataScript.new()
	_expect(player.gold == 30, "player starts with 30 gold")


func _test_shop_purchase_changes_only_successful_state() -> void:
	var player := PlayerDataScript.new()
	player.gold = 10
	var instance := _make_shop_instance([_offer("Twig Blade", 6)])
	var result := resolver.purchase_shop_item(instance, 0, player, true)
	_expect(result.success, "shop purchase succeeds")
	_expect(player.gold == 4, "deducts exact price")
	_expect(result.granted_card.card_name == "Twig Blade", "returns purchased card")
	_expect(instance.shop_sold_flags == [true], "marks item sold")
	_expect(not instance.is_resolved, "shop stays unresolved")


func _test_shop_failure_does_not_mutate_state() -> void:
	var player := PlayerDataScript.new()
	player.gold = 5
	var instance := _make_shop_instance([_offer("Twig Blade", 6)])
	var result := resolver.purchase_shop_item(instance, 0, player, true)
	_expect(not result.success, "insufficient gold rejects purchase")
	_expect(
		result.failure == EventResolutionResultScript.Failure.INSUFFICIENT_GOLD,
		"returns typed failure"
	)
	_expect(player.gold == 5 and instance.shop_sold_flags == [false], "failure keeps all state")


func _test_treasure_options_are_cached_and_include_gold() -> void:
	var instance := _make_treasure_instance([_card("A"), _card("B"), _card("C")], Vector2i(9, 9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var first := resolver.ensure_treasure_options(instance, rng)
	var second := resolver.ensure_treasure_options(instance, rng)
	_expect(first.size() == 3, "two cards plus gold")
	_expect(
		first[2].kind == TreasureRewardOptionScript.Kind.GOLD and first[2].gold_amount == 9,
		"cached gold option"
	)
	_expect(second == first, "same instance never rerolls")


func _test_full_hand_rejects_card_but_allows_gold() -> void:
	var player := PlayerDataScript.new()
	player.gold = 30
	var instance := _make_treasure_instance([_card("A"), _card("B")], Vector2i(7, 7))
	resolver.ensure_treasure_options(instance, RandomNumberGenerator.new())
	var card_result := resolver.claim_treasure_reward(instance, 0, player, false, RandomNumberGenerator.new())
	_expect(not card_result.success and not instance.is_resolved, "full hand keeps treasure open")
	var gold_result := resolver.claim_treasure_reward(instance, 2, player, false, RandomNumberGenerator.new())
	_expect(
		gold_result.success and player.gold == 37 and instance.is_resolved,
		"gold resolves treasure"
	)
	_expect(gold_result.granted_card == null, "gold never creates a card instance")


func _make_shop_instance(items: Array) -> EventInstance:
	var content := EventShopContentScript.new()
	content.items.assign(items)
	return _make_instance(EventDataScript.EventType.SHOP, content)


func _make_treasure_instance(cards: Array, gold_range: Vector2i) -> EventInstance:
	var content := EventTreasureContentScript.new()
	content.card_rewards.assign(cards)
	content.gold_range = gold_range
	return _make_instance(EventDataScript.EventType.TREASURE, content)


func _make_instance(event_type: EventData.EventType, content: Resource) -> EventInstance:
	var template := EventDataScript.new()
	template.event_type = event_type
	template.content = content
	var instance := EventInstanceScript.new()
	instance.template = template
	return instance


func _offer(card_name: String, price: int) -> ShopItemData:
	var offer := ShopItemDataScript.new()
	offer.card_data = _card(card_name)
	offer.price = price
	return offer


func _card(card_name: String) -> CardData:
	var card := CardDataScript.new()
	card.card_name = card_name
	return card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)


func _finish_tests() -> void:
	quit(0 if _failure_count == 0 else 1)
