extends SceneTree

const SHOP_SCENE := preload("res://scenes/zone/shop.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var library := _make_library()
	var player := PlayerData.new()
	player.gold = 30
	var card_service := RunCardService.new()
	var pricing := MarketPricingService.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 24680

	var shop = SHOP_SCENE.instantiate()
	root.add_child(shop)
	await process_frame

	var required_methods := [
		"configure",
		"set_drag_layer",
		"refresh_shop",
		"refresh_display",
		"get_offer",
		"get_offers",
		"get_offer_data",
		"get_offer_slot_for_card",
	]
	for method_name in required_methods:
		_expect(shop.has_method(method_name), "Shop exposes %s" % method_name)

	if not shop.has_method("configure"):
		shop.free()
		quit(1)
		return

	_expect(
		not bool(shop.call("configure", null, player, card_service, pricing, rng)),
		"Shop rejects a null CardLibrary"
	)
	_expect(
		not bool(shop.call("configure", library, null, card_service, pricing, rng)),
		"Shop rejects a null PlayerData"
	)
	_expect(
		bool(shop.call("configure", library, player, card_service, pricing, rng)),
		"Shop accepts complete required dependencies"
	)
	await process_frame

	var zone := shop.get_node_or_null("MarginContainer/VBoxContainer/ShopZone") as ShopZone
	var refresh_button := shop.get_node_or_null(
		"MarginContainer/VBoxContainer/HBoxContainer/RefreshButton"
	) as Button
	var cost_label := shop.get_node_or_null(
		"MarginContainer/VBoxContainer/HBoxContainer/CostCoin"
	) as Label
	_expect(zone != null, "Shop uses the ShopZone scene at the expected path")
	_expect(refresh_button != null and cost_label != null, "Shop uses the renamed RefreshButton and CostCoin nodes")
	if zone == null:
		shop.free()
		quit(1)
		return

	_assert_stock(shop, zone, 3)
	_expect(cost_label.text == "1", "CostCoin displays the current refresh price")
	_expect(not refresh_button.disabled, "refresh is enabled when the player can afford it")

	var first_layer := DraggerLayer.new()
	var second_layer := DraggerLayer.new()
	root.add_child(first_layer)
	root.add_child(second_layer)
	shop.call("set_drag_layer", first_layer)
	_expect(zone in first_layer.get_registered_zones(), "Shop registers ShopZone in the provided DraggerLayer")
	for card in zone.get_cards():
		_expect(card.drag_layer == first_layer, "Shop binds every product Card to the provided DraggerLayer")

	shop.call("set_drag_layer", second_layer)
	_expect(zone not in first_layer.get_registered_zones(), "switching DraggerLayer unregisters the old ShopZone")
	_expect(zone in second_layer.get_registered_zones(), "switching DraggerLayer registers the new ShopZone")
	for card in zone.get_cards():
		_expect(card.drag_layer == second_layer, "switching DraggerLayer rebinds every current product Card")

	var offers_before_refresh: Array = shop.call("get_offers")
	var cards_before_refresh := zone.get_products()
	var gold_before_refresh := player.gold
	_expect(bool(shop.call("refresh_shop")), "refresh succeeds when configured and affordable")
	await process_frame
	_expect(player.gold == gold_before_refresh - 1, "successful refresh deducts the pricing service refresh cost")
	_assert_stock(shop, zone, 3)
	for slot_index in range(zone.max_products):
		_expect(shop.call("get_offer", slot_index) != offers_before_refresh[slot_index], "refresh replaces CardInstance in slot %d" % slot_index)
		_expect(zone.get_product(slot_index) != cards_before_refresh[slot_index], "refresh replaces Card view in slot %d" % slot_index)
		_expect(zone.get_product(slot_index).drag_layer == second_layer, "refreshed Card remains bound to the active DraggerLayer")

	var dragged_card := zone.get_product(0)
	var offers_before_drag_block: Array = shop.call("get_offers")
	var gold_before_drag_block := player.gold
	zone.start_drag(dragged_card)
	_expect(not bool(shop.call("refresh_shop")), "refresh is blocked while a product drag is active")
	_expect(player.gold == gold_before_drag_block, "blocked refresh does not deduct gold")
	_assert_same_offer_identities(shop.call("get_offers"), offers_before_drag_block, "blocked refresh preserves offers")
	zone.drag_end_source(dragged_card, false)

	player.gold = 0
	shop.call("refresh_display")
	var offers_before_insufficient: Array = shop.call("get_offers")
	_expect(refresh_button.disabled, "refresh button disables when the player cannot afford the refresh")
	_expect(not bool(shop.call("refresh_shop")), "refresh fails when gold is insufficient")
	_expect(player.gold == 0, "failed refresh does not mutate gold")
	_assert_same_offer_identities(shop.call("get_offers"), offers_before_insufficient, "failed refresh preserves offers")
	player.gold = 30
	shop.call("refresh_display")

	var purchase_slot := 1
	var purchased_card := zone.get_product(purchase_slot)
	var purchased_inst: CardInstance = shop.call("get_offer", purchase_slot)
	var purchase_price := pricing.get_purchase_price(purchased_inst.card_data, _make_price_context(player))
	var purchase_gold_before := player.gold
	var other_slot := 0
	var other_offer: CardInstance = shop.call("get_offer", other_slot)
	var other_card := zone.get_product(other_slot)
	_expect(zone.can_trans_from_source(purchased_card), "Shop purchase validator accepts the exact affordable product")
	_expect(int(shop.call("get_offer_slot_for_card", purchased_card)) == purchase_slot, "Shop maps a product Card to its offer slot")
	_expect(shop.call("get_offer_data", purchase_slot) == purchased_inst.card_data, "Shop exposes CardData for an offer slot")

	zone.start_drag(purchased_card)
	var hand_zone := HandZone.new()
	hand_zone.size = Vector2(500.0, 200.0)
	root.add_child(hand_zone)
	_expect(hand_zone.add_card(purchased_card), "test target commits the purchased Card before source completion")
	_expect(zone.drag_end_source(purchased_card, true), "ShopZone emits the committed purchase")
	await process_frame

	_expect(player.gold == purchase_gold_before - purchase_price, "successful purchase deducts the product price")
	_expect(purchased_inst in card_service.get_instances(), "purchase registers the exact displayed CardInstance")
	_expect(purchased_card in card_service.get_card_views(), "purchase registers the exact displayed Card view")
	_expect(purchased_card.get_parent() == hand_zone and hand_zone.owns_card(purchased_card) and purchased_inst.cur_zone == CardInstance.ZONE.HAND, "purchase preserves target ownership of the displayed Card")
	_expect(shop.call("get_offer", other_slot) == other_offer, "single-slot restock preserves other offer instances")
	_expect(zone.get_product(other_slot) == other_card, "single-slot restock preserves other Card views")
	var replacement_inst: CardInstance = shop.call("get_offer", purchase_slot)
	var replacement_card := zone.get_product(purchase_slot)
	_expect(replacement_inst != null and replacement_inst != purchased_inst, "purchase creates a replacement CardInstance only for the vacated slot")
	_expect(replacement_card != null and replacement_card != purchased_card, "purchase creates a replacement Card view only for the vacated slot")
	_expect(replacement_card.get_card_inst() == replacement_inst, "replacement Card binds the exact replacement CardInstance")
	_expect(replacement_card.drag_layer == second_layer, "replacement Card binds the active DraggerLayer")
	_expect(int(shop.call("get_offer_slot_for_card", purchased_card)) == -1, "purchased Card is no longer a shop offer")

	shop.call("set_drag_layer", null)
	_expect(zone not in second_layer.get_registered_zones(), "clearing DraggerLayer unregisters ShopZone")
	for card in zone.get_cards():
		_expect(card.drag_layer == null, "clearing DraggerLayer clears product Card bindings")

	shop.free()
	hand_zone.free()
	first_layer.free()
	second_layer.free()
	quit(1 if _failures > 0 else 0)


func _make_library() -> CardLibrary:
	var library := CardLibrary.new()
	var cards: Array[CardData] = []
	for index in range(4):
		var data := CardData.new()
		data.card_id = index + 1
		data.card_name = "Product %d" % (index + 1)
		data.card_type = CardData.CardType.NORMAL
		data.rarity = CardData.Rarity.COMMON
		cards.append(data)
	var root_card := CardData.new()
	root_card.card_id = 99
	root_card.card_name = "Root"
	root_card.card_type = CardData.CardType.ROOT
	cards.append(root_card)
	library.cards = cards
	return library


func _make_price_context(player: PlayerData) -> MarketPriceContext:
	var context := MarketPriceContext.new()
	context.player = player
	return context


func _assert_stock(shop, zone: ShopZone, expected_count: int) -> void:
	var offers: Array = shop.call("get_offers")
	var products := zone.get_products()
	_expect(offers.size() == expected_count, "Shop exposes %d logical offer slots" % expected_count)
	_expect(products.size() == expected_count, "ShopZone exposes %d logical product slots" % expected_count)
	var seen_data: Array[CardData] = []
	for slot_index in range(mini(offers.size(), products.size())):
		var offer := offers[slot_index] as CardInstance
		var card := products[slot_index] as Card
		_expect(offer != null, "offer slot %d contains a CardInstance" % slot_index)
		_expect(card != null, "product slot %d contains a Card view" % slot_index)
		if offer == null or card == null:
			continue
		_expect(card.get_card_inst() == offer, "product slot %d binds the exact offer CardInstance" % slot_index)
		_expect(offer.card_data != null and offer.card_data.card_type != CardData.CardType.ROOT, "offer slot %d excludes ROOT cards" % slot_index)
		_expect(offer.card_data not in seen_data, "initial/full refresh avoids duplicate CardData when enough candidates exist")
		seen_data.append(offer.card_data)


func _assert_same_offer_identities(actual: Array, expected: Array, message: String) -> void:
	_expect(actual.size() == expected.size(), "%s: slot count is unchanged" % message)
	for index in range(mini(actual.size(), expected.size())):
		_expect(actual[index] == expected[index], "%s: slot %d identity is unchanged" % [message, index])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
