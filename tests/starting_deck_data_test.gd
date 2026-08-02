extends SceneTree

const StartingDeckDataScript = preload("res://scripts/run/starting_deck_data.gd")
const CardManagerScript = preload("res://scripts/game/card_manager.gd")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_revival_preset_is_valid_and_has_exactly_one_root()
	_test_factory_creates_fresh_instances_in_configured_order()
	_test_invalid_presets_report_actionable_errors()
	quit(1 if _failure_count > 0 else 0)


func _test_revival_preset_is_valid_and_has_exactly_one_root() -> void:
	_expect(RevivalDeck.validate().is_empty(), "revival preset validates successfully")
	var root := RevivalDeck.get_root_card()
	_expect(root != null, "revival preset resolves a root card")
	_expect(root != null and root.card_type == CardData.CardType.ROOT, "resolved card is a ROOT")
	_expect(
		RevivalDeck.get_remaining_starter_cards().size() == RevivalDeck.starter_cards.size() - 1,
		"remaining starters exclude exactly the displayed root"
	)


func _test_factory_creates_fresh_instances_in_configured_order() -> void:
	var manager := CardManagerScript.new()
	var first_run := manager.create_starting_instances(RevivalDeck)
	var second_run := manager.create_starting_instances(RevivalDeck)

	_expect(first_run.size() == RevivalDeck.starter_cards.size(), "factory creates every configured starter")
	_expect(second_run.size() == RevivalDeck.starter_cards.size(), "second run creates every configured starter")
	for index in range(RevivalDeck.starter_cards.size()):
		_expect(
			first_run[index].card_data == RevivalDeck.starter_cards[index],
			"first run preserves configured card order at index %d" % index
		)
		_expect(
			second_run[index].card_data == RevivalDeck.starter_cards[index],
			"second run preserves configured card order at index %d" % index
		)
		_expect(
			first_run[index] != second_run[index],
			"each run creates a distinct CardInstance at index %d" % index
		)


func _test_invalid_presets_report_actionable_errors() -> void:
	var root := RevivalDeck.get_root_card()
	var non_root := RevivalDeck.get_remaining_starter_cards()[0]

	var no_root := StartingDeckDataScript.new()
	no_root.deck_id = "no-root"
	no_root.display_name = "No Root"
	no_root.starter_cards = [non_root]
	_expect(
		"starter_cards must contain exactly one ROOT card" in no_root.validate(),
		"preset without a root reports the root-count error"
	)

	var two_roots := StartingDeckDataScript.new()
	two_roots.deck_id = "two-roots"
	two_roots.display_name = "Two Roots"
	two_roots.starter_cards = [root, root]
	_expect(
		"starter_cards must contain exactly one ROOT card" in two_roots.validate(),
		"preset with two roots reports the root-count error"
	)

	var null_card := StartingDeckDataScript.new()
	null_card.deck_id = "null-card"
	null_card.display_name = "Null Card"
	null_card.starter_cards = [root, null]
	_expect("starter_cards contains null" in null_card.validate(), "preset with null reports the null-card error")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
