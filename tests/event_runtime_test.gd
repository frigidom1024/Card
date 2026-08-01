extends SceneTree

const PlayerDataScript = preload("res://scripts/player/player_data.gd")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const EventInstanceScript = preload("res://scripts/game/event/core/event_instance.gd")
const EventRuntimeStateScript = preload("res://scripts/game/event/core/event_runtime_state.gd")
const ShopEventContentScript = preload("res://scripts/game/event/shop/shop_event_content.gd")
const ShopItemDataScript = preload("res://scripts/game/event/shop/shop_item_data.gd")
const ShopRuntimeStateScript = preload("res://scripts/game/event/shop/shop_runtime_state.gd")
const ShopEventResolverScript = preload("res://scripts/game/event/shop/shop_event_resolver.gd")
const EventTreasureContentScript = preload("res://scripts/game/event/event_treasure_content.gd")
const TreasureRewardOptionScript = preload("res://scripts/game/event/treasure_reward_option.gd")
const EventResolutionResultScript = preload("res://scripts/game/event/core/event_resolution_result.gd")
const EventRewardResolverScript = preload("res://scripts/game/event/event_reward_resolver.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const EventEntryScript = preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript = preload("res://scripts/game/event/core/event_lib.gd")
const EventPlacementServiceScript = preload("res://scripts/game/event/core/event_placement_service.gd")

var _failure_count := 0
var treasure_resolver := EventRewardResolverScript.new()
var shop_resolver := ShopEventResolverScript.new()


func _init() -> void:
	_test_player_starts_with_persistent_gold()
	_test_event_instance_creates_base_runtime_state_for_missing_content()
	_test_event_data_uses_content_runtime_state_factory()
	_test_resolve_marks_event_revealed_and_resolved()
	_test_shop_purchase_changes_only_successful_state()
	_test_shop_failures_do_not_mutate_runtime_state()
	_test_shop_rejects_mismatched_runtime_state()
	_test_shop_validation_order_preserves_state()
	_test_treasure_options_are_cached_and_include_gold()
	_test_treasure_always_offers_two_cards_and_gold_when_available()
	_test_treasure_failures_do_not_mutate_runtime_state()
	_test_full_hand_rejects_card_but_allows_gold()
	_test_seeded_event_placement_reserves_footprints_and_boundaries()
	call_deferred("_finish_tests")


func _test_player_starts_with_persistent_gold() -> void:
	var player := PlayerDataScript.new()
	_expect(player.gold == 30, "player starts with 30 gold")


func _test_event_instance_creates_base_runtime_state_for_missing_content() -> void:
	var template := EventDataScript.new()
	var instance := template.create_instance()
	_expect(instance.runtime_state != null, "event instance always owns runtime state")
	_expect(not instance.is_revealed and not instance.is_resolved, "new event begins unresolved")


func _test_event_data_uses_content_runtime_state_factory() -> void:
	var content := ShopEventContentScript.new()
	var template := EventDataScript.new()
	template.content = content
	var instance := template.create_instance()
	_expect(
		instance.runtime_state is ShopRuntimeStateScript,
		"event data uses the content runtime-state factory"
	)


func _test_resolve_marks_event_revealed_and_resolved() -> void:
	var instance := EventInstanceScript.new()
	instance.resolve()
	_expect(instance.is_revealed, "resolve reveals the event")
	_expect(instance.is_resolved, "resolve marks the event resolved")


func _test_shop_purchase_changes_only_successful_state() -> void:
	var player := PlayerDataScript.new()
	player.gold = 10
	var instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var result = shop_resolver.purchase_item(instance, 0, player, true)
	_expect(result.success, "shop purchase succeeds")
	_expect(player.gold == 4, "deducts exact price")
	_expect(result.granted_card.card_name == "Twig Blade", "returns purchased card")
	var state := instance.runtime_state as ShopRuntimeStateScript
	_expect(state != null, "shop instance creates shop runtime state")
	if state != null:
		_expect(state.sold_flags == [true], "marks item sold in shop runtime state")
	_expect(not instance.is_resolved, "shop stays unresolved")


func _test_shop_failures_do_not_mutate_runtime_state() -> void:
	var insufficient_gold_player := PlayerDataScript.new()
	insufficient_gold_player.gold = 5
	var insufficient_gold_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var insufficient_gold_before := _snapshot_runtime_state(insufficient_gold_player, insufficient_gold_instance)
	var insufficient_gold_result = shop_resolver.purchase_item(
		insufficient_gold_instance, 0, insufficient_gold_player, true
	)
	_expect_failure_preserves_runtime_state(
		insufficient_gold_result,
		EventResolutionResultScript.Failure.INSUFFICIENT_GOLD,
		insufficient_gold_before,
		insufficient_gold_player,
		insufficient_gold_instance,
		"shop insufficient-gold failure"
	)

	var full_hand_player := PlayerDataScript.new()
	full_hand_player.gold = 10
	var full_hand_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var full_hand_before := _snapshot_runtime_state(full_hand_player, full_hand_instance)
	var full_hand_result = shop_resolver.purchase_item(full_hand_instance, 0, full_hand_player, false)
	_expect_failure_preserves_runtime_state(
		full_hand_result,
		EventResolutionResultScript.Failure.HAND_FULL,
		full_hand_before,
		full_hand_player,
		full_hand_instance,
		"shop full-hand failure"
	)

	var invalid_index_player := PlayerDataScript.new()
	invalid_index_player.gold = 10
	var invalid_index_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var invalid_index_before := _snapshot_runtime_state(invalid_index_player, invalid_index_instance)
	var invalid_index_result = shop_resolver.purchase_item(invalid_index_instance, 1, invalid_index_player, true)
	_expect_failure_preserves_runtime_state(
		invalid_index_result,
		EventResolutionResultScript.Failure.INVALID_INDEX,
		invalid_index_before,
		invalid_index_player,
		invalid_index_instance,
		"shop invalid-index failure"
	)

	var sold_out_player := PlayerDataScript.new()
	sold_out_player.gold = 10
	var sold_out_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var sold_out_state := sold_out_instance.runtime_state as ShopRuntimeStateScript
	if sold_out_state != null:
		sold_out_state.sold_flags.append(true)
	var sold_out_before := _snapshot_runtime_state(sold_out_player, sold_out_instance)
	var sold_out_result = shop_resolver.purchase_item(sold_out_instance, 0, sold_out_player, true)
	_expect_failure_preserves_runtime_state(
		sold_out_result,
		EventResolutionResultScript.Failure.SOLD_OUT,
		sold_out_before,
		sold_out_player,
		sold_out_instance,
		"shop sold-out failure"
	)

	var resolved_player := PlayerDataScript.new()
	resolved_player.gold = 10
	var resolved_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	resolved_instance.resolve()
	var resolved_before := _snapshot_runtime_state(resolved_player, resolved_instance)
	var resolved_result = shop_resolver.purchase_item(resolved_instance, 0, resolved_player, true)
	_expect_failure_preserves_runtime_state(
		resolved_result,
		EventResolutionResultScript.Failure.ALREADY_RESOLVED,
		resolved_before,
		resolved_player,
		resolved_instance,
		"shop resolved-event failure"
	)


func _test_shop_rejects_mismatched_runtime_state() -> void:
	var player := PlayerDataScript.new()
	player.gold = 10
	var instance = _make_shop_instance([_offer("Twig Blade", 6)])
	instance.runtime_state = EventRuntimeStateScript.new()
	var result = shop_resolver.purchase_item(instance, 0, player, true)
	_expect(
		result.failure == EventResolutionResultScript.Failure.INVALID_EVENT,
		"shop rejects wrong runtime state"
	)
	_expect(
		player.gold == 10 and not instance.is_revealed and not instance.is_resolved,
		"wrong shop state does not mutate event"
	)


func _test_shop_validation_order_preserves_state() -> void:
	var invalid_index_player := PlayerDataScript.new()
	invalid_index_player.gold = 10
	var invalid_index_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	invalid_index_instance.resolve()
	var invalid_index_before := _snapshot_runtime_state(invalid_index_player, invalid_index_instance)
	var invalid_index_result = shop_resolver.purchase_item(invalid_index_instance, 1, invalid_index_player, true)
	_expect_failure_preserves_runtime_state(
		invalid_index_result,
		EventResolutionResultScript.Failure.INVALID_INDEX,
		invalid_index_before,
		invalid_index_player,
		invalid_index_instance,
		"shop validates index before resolved state"
	)

	var resolved_player := PlayerDataScript.new()
	resolved_player.gold = 10
	var resolved_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var resolved_state := resolved_instance.runtime_state as ShopRuntimeStateScript
	if resolved_state != null:
		resolved_state.sold_flags.append(true)
	resolved_instance.resolve()
	var resolved_before := _snapshot_runtime_state(resolved_player, resolved_instance)
	var resolved_result = shop_resolver.purchase_item(resolved_instance, 0, resolved_player, false)
	_expect_failure_preserves_runtime_state(
		resolved_result,
		EventResolutionResultScript.Failure.ALREADY_RESOLVED,
		resolved_before,
		resolved_player,
		resolved_instance,
		"shop validates resolved state before sold and hand capacity"
	)

	var sold_player := PlayerDataScript.new()
	sold_player.gold = 10
	var sold_instance = _make_shop_instance([_offer("Twig Blade", 6)])
	var sold_state := sold_instance.runtime_state as ShopRuntimeStateScript
	if sold_state != null:
		sold_state.sold_flags.append(true)
	var sold_before := _snapshot_runtime_state(sold_player, sold_instance)
	var sold_result = shop_resolver.purchase_item(sold_instance, 0, sold_player, false)
	_expect_failure_preserves_runtime_state(
		sold_result,
		EventResolutionResultScript.Failure.SOLD_OUT,
		sold_before,
		sold_player,
		sold_instance,
		"shop validates sold state before hand capacity"
	)

	var full_hand_player := PlayerDataScript.new()
	full_hand_player.gold = 0
	var full_hand_instance = _make_shop_instance([null])
	var full_hand_before := _snapshot_runtime_state(full_hand_player, full_hand_instance)
	var full_hand_result = shop_resolver.purchase_item(full_hand_instance, 0, full_hand_player, false)
	_expect_failure_preserves_runtime_state(
		full_hand_result,
		EventResolutionResultScript.Failure.HAND_FULL,
		full_hand_before,
		full_hand_player,
		full_hand_instance,
		"shop validates hand capacity before item and gold"
	)

	var null_item_player := PlayerDataScript.new()
	null_item_player.gold = 0
	var null_item_instance = _make_shop_instance([null])
	var null_item_before := _snapshot_runtime_state(null_item_player, null_item_instance)
	var null_item_result = shop_resolver.purchase_item(null_item_instance, 0, null_item_player, true)
	_expect_failure_preserves_runtime_state(
		null_item_result,
		EventResolutionResultScript.Failure.INVALID_EVENT,
		null_item_before,
		null_item_player,
		null_item_instance,
		"shop validates item before gold"
	)


func _test_treasure_options_are_cached_and_include_gold() -> void:
	var instance = _make_treasure_instance([_card("A"), _card("B"), _card("C")], Vector2i(9, 9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var first = treasure_resolver.ensure_treasure_options(instance, rng)
	var second = treasure_resolver.ensure_treasure_options(instance, rng)
	_expect(first.size() == 3, "two cards plus gold")
	_expect(
		first[2].kind == TreasureRewardOptionScript.Kind.GOLD and first[2].gold_amount == 9,
		"cached gold option"
	)
	_expect(second == first, "same instance never rerolls")


func _test_treasure_always_offers_two_cards_and_gold_when_available() -> void:
	for configured_choices in [0, 1, 3]:
		var instance = _make_treasure_instance(
			[_card("A"), _card("B"), _card("C")], Vector2i(9, 9), configured_choices
		)
		var options = treasure_resolver.ensure_treasure_options(instance, RandomNumberGenerator.new())
		_expect(options.size() == 3, "choices=%d still creates two cards and gold" % configured_choices)
		if options.size() < 3:
			continue
		_expect(
			options[0].kind == TreasureRewardOptionScript.Kind.CARD
				and options[1].kind == TreasureRewardOptionScript.Kind.CARD,
			"choices=%d starts with two card options" % configured_choices
		)
		_expect(options[0].card_data != options[1].card_data, "choices=%d cards are unique" % configured_choices)
		_expect(
			options[2].kind == TreasureRewardOptionScript.Kind.GOLD,
			"choices=%d ends with a gold option" % configured_choices
		)


func _test_treasure_failures_do_not_mutate_runtime_state() -> void:
	var full_hand_player := PlayerDataScript.new()
	full_hand_player.gold = 30
	var full_hand_instance = _make_treasure_instance([_card("A"), _card("B")], Vector2i(7, 7))
	treasure_resolver.ensure_treasure_options(full_hand_instance, RandomNumberGenerator.new())
	var full_hand_before := _snapshot_runtime_state(full_hand_player, full_hand_instance)
	var full_hand_result = treasure_resolver.claim_treasure_reward(
		full_hand_instance, 0, full_hand_player, false, RandomNumberGenerator.new()
	)
	_expect_failure_preserves_runtime_state(
		full_hand_result,
		EventResolutionResultScript.Failure.HAND_FULL,
		full_hand_before,
		full_hand_player,
		full_hand_instance,
		"treasure full-hand card failure"
	)

	var invalid_index_player := PlayerDataScript.new()
	invalid_index_player.gold = 30
	var invalid_index_instance = _make_treasure_instance([_card("A"), _card("B")], Vector2i(7, 7))
	var invalid_index_before := _snapshot_runtime_state(invalid_index_player, invalid_index_instance)
	var invalid_index_result = treasure_resolver.claim_treasure_reward(
		invalid_index_instance, 3, invalid_index_player, true, RandomNumberGenerator.new()
	)
	_expect_failure_preserves_runtime_state(
		invalid_index_result,
		EventResolutionResultScript.Failure.INVALID_INDEX,
		invalid_index_before,
		invalid_index_player,
		invalid_index_instance,
		"treasure invalid-index failure"
	)

	var resolved_player := PlayerDataScript.new()
	resolved_player.gold = 30
	var resolved_instance = _make_treasure_instance([_card("A"), _card("B")], Vector2i(7, 7))
	treasure_resolver.ensure_treasure_options(resolved_instance, RandomNumberGenerator.new())
	resolved_instance.resolve()
	var resolved_before := _snapshot_runtime_state(resolved_player, resolved_instance)
	var resolved_result = treasure_resolver.claim_treasure_reward(
		resolved_instance, 0, resolved_player, true, RandomNumberGenerator.new()
	)
	_expect_failure_preserves_runtime_state(
		resolved_result,
		EventResolutionResultScript.Failure.ALREADY_RESOLVED,
		resolved_before,
		resolved_player,
		resolved_instance,
		"treasure resolved-event failure"
	)


func _test_full_hand_rejects_card_but_allows_gold() -> void:
	var player := PlayerDataScript.new()
	player.gold = 30
	var instance = _make_treasure_instance([_card("A"), _card("B")], Vector2i(7, 7))
	treasure_resolver.ensure_treasure_options(instance, RandomNumberGenerator.new())
	var card_result = treasure_resolver.claim_treasure_reward(instance, 0, player, false, RandomNumberGenerator.new())
	_expect(not card_result.success and not instance.is_resolved, "full hand keeps treasure open")
	var gold_result = treasure_resolver.claim_treasure_reward(instance, 2, player, false, RandomNumberGenerator.new())
	_expect(
		gold_result.success and player.gold == 37 and instance.is_resolved,
		"gold resolves treasure"
	)
	_expect(gold_result.granted_card == null, "gold never creates a card instance")


func _expect_failure_preserves_runtime_state(
	result, expected_failure, before: Dictionary, player, instance, label: String
) -> void:
	_expect(not result.success, "%s rejects the claim" % label)
	_expect(result.failure == expected_failure, "%s returns the typed failure" % label)
	_expect(
		before == _snapshot_runtime_state(player, instance), "%s preserves runtime state" % label
	)


func _snapshot_runtime_state(player, instance) -> Dictionary:
	var sold_flags: Array[bool] = []
	var shop_state := instance.runtime_state as ShopRuntimeStateScript
	if shop_state != null:
		sold_flags = shop_state.sold_flags.duplicate()
	return {
		"gold": player.gold,
		"sold_flags": sold_flags,
		"selected_treasure_option": instance.selected_treasure_option,
		"is_revealed": instance.is_revealed,
		"is_resolved": instance.is_resolved,
		"treasure_options": instance.treasure_options.duplicate(),
	}


func _make_shop_instance(items: Array):
	var content = ShopEventContentScript.new()
	content.items.assign(items)
	return _make_instance(EventDataScript.EventType.SHOP, content)


func _make_treasure_instance(cards: Array, gold_range: Vector2i, choices: int = 2):
	var content = EventTreasureContentScript.new()
	content.card_rewards.assign(cards)
	content.gold_range = gold_range
	content.choices = choices
	return _make_instance(EventDataScript.EventType.TREASURE, content)


func _make_instance(event_type: int, content: Resource):
	var template = EventDataScript.new()
	template.event_type = event_type
	template.content = content
	return template.create_instance()


func _offer(card_name: String, price: int):
	var offer = ShopItemDataScript.new()
	offer.card_data = _card(card_name)
	offer.price = price
	return offer


func _card(card_name: String):
	var card = CardDataScript.new()
	card.card_name = card_name
	return card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)


func _finish_tests() -> void:
	quit(0 if _failure_count == 0 else 1)

func _test_seeded_event_placement_reserves_footprints_and_boundaries() -> void:
	for seed in range(8):
		var board := BoardScene.instantiate() as Board
		board.width = 4
		board.height = 1
		root.add_child(board)

		var template := EventDataScript.new()
		template.event_id = "seeded_%d" % seed
		template.size = Vector2i.ONE
		var entry := EventEntryScript.new()
		entry.event_data = template
		entry.min_count = 2
		entry.max_count = 2
		var event_lib := EventLibScript.new()
		event_lib.entries = [entry]
		event_lib.event_scene = EventScene
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var placed := EventPlacementServiceScript.new().place_initial_events(event_lib, board, rng)
		_expect(placed.size() == 2, "seed %d places both events" % seed)
		if placed.size() == 2:
			var horizontal_gap := absi(placed[0].origin.x - placed[1].origin.x)
			_expect(
				horizontal_gap > 1,
				"seed %d later event avoids the footprint and mandatory empty boundary" % seed
			)
		board.queue_free()
