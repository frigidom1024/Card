extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const BasePlayerData = preload("res://data/player/player_data.tres")
const StartingDeckDataScript = preload("res://scripts/run/starting_deck_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_valid_preset_initializes_isolated_run_state()
	_test_invalid_preset_is_rejected_before_scene_entry()
	quit(1 if _failure_count > 0 else 0)


func _test_valid_preset_initializes_isolated_run_state() -> void:
	var manager = GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "valid preset is accepted before GameManager enters the tree")
	root.add_child(manager)
	await process_frame

	_expect(
		manager.cards_inst.size() == RevivalDeck.starter_cards.size(),
		"run creates exactly every configured starter card"
	)
	_expect(_count_roots(manager.cards_inst) == 1, "run creates exactly one root card")
	for index in range(RevivalDeck.starter_cards.size()):
		_expect(
			manager.cards_inst[index].card_data == RevivalDeck.starter_cards[index],
			"run preserves configured starter order at index %d" % index
		)

	_expect(manager.player_data != BasePlayerData, "run owns a copied PlayerData resource")
	_expect(
		manager.player_data.base_stats != BasePlayerData.base_stats,
		"run owns a copied nested CombatStatsData resource"
	)
	manager.player_data.gold = 1
	_expect(BasePlayerData.gold == 30, "run gold changes do not mutate the static PlayerData resource")
	_expect(manager._encounter_combat_flow != null, "run creates an encounter combat flow")
	_expect(
		manager.board.card_return_requested.is_connected(manager._on_board_card_return_requested),
		"GameManager listens for Board guide-card return requests"
	)
	var returned_guide := _make_guide_card()
	manager.add_child(returned_guide)
	manager._on_board_card_return_requested(returned_guide)
	_expect(returned_guide in manager.hand_area.cards, "GameManager returns guide cards through HandArea")

	manager.hand_area.max_hand_size = manager.hand_area.cards.size()
	var returned_when_full := _make_guide_card()
	manager.add_child(returned_when_full)
	manager._on_board_card_return_requested(returned_when_full)
	_expect(returned_when_full in manager.hand_area.cards, "GameManager never loses a guide card when the hand is full")
	_expect(
		manager.hand_area.max_hand_size >= manager.hand_area.cards.size(),
		"GameManager temporarily expands hand capacity for an already-owned guide card"
	)

	manager.free()
	await process_frame


func _test_invalid_preset_is_rejected_before_scene_entry() -> void:
	var invalid_preset = StartingDeckDataScript.new()
	var manager = GameManagerScene.instantiate()
	_expect(not manager.configure_run(invalid_preset), "invalid preset is rejected before GameManager enters the tree")
	manager.free()


func _make_guide_card() -> CardEntity:
	var entity := preload("res://scenes/card_view/card_entity.tscn").instantiate() as CardEntity
	var data := CardData.new()
	data.card_type = CardData.CardType.GUIDE
	data.card_name = "Guide"
	entity.bind_instance(CardInstance.new(data))
	return entity


func _count_roots(cards: Array) -> int:
	var count := 0
	for card in cards:
		if card != null and card.card_data != null and card.card_data.card_type == CardData.CardType.ROOT:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
