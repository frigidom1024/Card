extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0
var _returned_card: CardEntity = null


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_expect(CardData.CardType.GUIDE != CardData.CardType.NORMAL, "GUIDE must be a distinct CardType")
	var guide := _make_card(CardData.CardType.GUIDE)
	_expect(guide.card_instance.card_data.card_type == CardData.CardType.GUIDE, "guide card keeps GUIDE type")
	guide.queue_free()

	_test_guide_card_shifts_chain_and_returns()
	quit(1 if _failure_count > 0 else 0)


func _test_guide_card_shifts_chain_and_returns() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	board.card_return_requested.connect(_on_card_return_requested)

	var root_card := _make_card(CardData.CardType.ROOT)
	root_card.position = Vector2(156, 260)
	root_card.card_instance.direction = 0
	root_card.rotation_degrees = 0.0
	_expect(board.add_card(root_card), "root card can be placed")

	var second_card := _make_card(CardData.CardType.NORMAL)
	second_card.position = board.grid_to_world_center(Vector2i(1, 1))
	second_card.card_instance.direction = 1
	second_card.rotation_degrees = 90.0
	_expect(board.add_card(second_card), "second card can be placed after root")

	var root_position := root_card.global_position
	var second_position := second_card.global_position
	var second_rotation := second_card.rotation_degrees

	var guide := _make_card(CardData.CardType.GUIDE)
	guide.position = board.grid_to_world_center(Vector2i(3, 1))
	guide.card_instance.direction = 1
	guide.rotation_degrees = 90.0
	_expect(board.add_card(guide), "guide card can be placed after the chain")

	_expect(_returned_card == guide, "board requests the guide card be returned")
	_expect(board.cards.size() == 2, "guide card is not added to the board chain")
	_expect(board.cards[0] == root_card and board.cards[1] == second_card, "board chain order stays unchanged")
	_expect(root_card.global_position.is_equal_approx(second_position), "card 1 moves to card 2's old position")
	_expect(second_card.global_position.is_equal_approx(guide.global_position), "card 2 moves to guide card's old position")
	_expect(is_equal_approx(root_card.rotation_degrees, second_rotation), "card 1 inherits card 2's rotation")
	_expect(is_equal_approx(second_card.rotation_degrees, guide.rotation_degrees), "card 2 inherits guide card's rotation")
	_expect(root_card.card_instance.direction == 1, "card 1 inherits card 2's direction")
	_expect(second_card.card_instance.direction == 1, "card 2 inherits guide card's direction")
	_expect(guide.get_parent() == board, "guide card remains available for the return handler")
	_expect(not board._grid_owner.values().has(guide), "guide card does not own board cells")
	_expect(board._grid_owner[Vector2i(1, 1)] == root_card, "board grid is rebuilt for card 1")
	_expect(board._grid_owner[Vector2i(3, 1)] == second_card, "board grid is rebuilt for card 2")
	_expect(root_position != root_card.global_position, "card 1 actually moved")

	board.queue_free()
	guide.queue_free()


func _make_card(card_type: CardData.CardType) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = "Test Card"
	card.bind_instance(CardInstance.new(data))
	root.add_child(card)
	return card


func _on_card_return_requested(card: CardEntity) -> void:
	_returned_card = card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
