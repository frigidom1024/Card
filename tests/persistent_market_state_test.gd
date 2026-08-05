extends SceneTree

const PersistentMarketStateScript = preload("res://scripts/game/market/persistent_market_state.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_state_fills_three_non_root_offers_without_duplicates()
	_test_replace_offer_preserves_other_slots()
	quit(1 if _failure_count > 0 else 0)


func _test_state_fills_three_non_root_offers_without_duplicates() -> void:
	var library := _library_with_cards([_card("Root", CardData.CardType.ROOT), _card("A"), _card("B"), _card("C"), _card("D")])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var state: Object = PersistentMarketStateScript.new()
	state.call("initialize", library, rng)
	var offers: Array = state.get("offers")
	_expect(offers.size() == 3, "market fills three slots")
	_expect(offers.all(func(card): return card.card_type != CardData.CardType.ROOT), "market excludes root cards")
	_expect(_unique_count(offers) == 3, "market avoids duplicates when pool is large enough")


func _test_replace_offer_preserves_other_slots() -> void:
	var library := _library_with_cards([_card("A"), _card("B"), _card("C"), _card("D")])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var state: Object = PersistentMarketStateScript.new()
	state.call("initialize", library, rng)
	var before_left = state.call("get_offer", 0)
	var before_right = state.call("get_offer", 2)
	state.call("replace_offer", 1)
	_expect(state.call("get_offer", 0) == before_left, "replacement preserves left slot")
	_expect(state.call("get_offer", 2) == before_right, "replacement preserves right slot")


func _library_with_cards(cards: Array[CardData]) -> CardLibrary:
	var library := CardLibrary.new()
	library.cards = cards
	return library


func _card(card_name: String, card_type: CardData.CardType = CardData.CardType.NORMAL) -> CardData:
	var card := CardData.new()
	card.card_name = card_name
	card.card_type = card_type
	return card


func _unique_count(cards: Array) -> int:
	var unique_cards: Array = []
	for card in cards:
		if card not in unique_cards:
			unique_cards.append(card)
	return unique_cards.size()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)