extends SceneTree

const Cards = [
	preload("res://data/levels/ribwood/cards/ribwood_guardian_root.tres"),
	preload("res://data/levels/ribwood/cards/ribwood_rib_blade.tres"),
	preload("res://data/levels/ribwood/cards/ribwood_old_tinder.tres"),
	preload("res://data/levels/ribwood/cards/ribwood_folded_rib_shield.tres"),
	preload("res://data/levels/ribwood/cards/ribwood_warm_marrow_flask.tres"),
]
const StartingDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_starter_card_contract()
	_test_starter_deck_uses_ribwood_cards()
	quit(1 if _failure_count > 0 else 0)


func _test_starter_card_contract() -> void:
	_expect(Cards[0].card_type == CardData.CardType.ROOT, "guardian root is ROOT")
	_expect(Cards[0].defense == 2, "guardian root grants 2 defense")
	_expect(Cards[1].damage == 2 and Cards[1].tags.has(CardData.CardTag.WEAPON), "rib blade is a 2 damage weapon")
	_expect(Cards[2].damage == 1 and Cards[2].effect_rules.size() == 1, "old tinder has one combo rule")
	_expect(Cards[3].defense == 2 and Cards[3].effect_rules.size() == 1, "folded shield has one tail rule")
	_expect(Cards[4].heal == 2 and Cards[4].tags.has(CardData.CardTag.HEAL), "warm flask heals 2")


func _test_starter_deck_uses_ribwood_cards() -> void:
	_expect(StartingDeck.validate().is_empty(), "Ribwood starting deck validates")
	_expect(StartingDeck.starter_cards.size() == 5, "Ribwood starting deck has five cards")
	for card in StartingDeck.starter_cards:
		_expect(card.resource_path.begins_with("res://data/levels/ribwood/cards/"), "starting card is scoped to Ribwood")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
