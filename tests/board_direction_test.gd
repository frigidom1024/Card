extends SceneTree

const BOARD_ZONE_SCENE := preload("res://scenes/zone/board_zone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board)
	await process_frame

	var root_card := _make_card(CardData.CardType.ROOT, 3)
	root.add_child(root_card)
	await process_frame
	_move_card_to_anchor(board, root_card, Vector2i(4, 3), 3)
	_expect(board.add_card(root_card), "a left-facing ROOT can be placed")
	_expect(board.get_placement_cell(root_card) == Vector2i(3, 3), "direction 3 exposes the left connection cell")

	var candidate := _make_card(CardData.CardType.NORMAL, 0)
	root.add_child(candidate)
	await process_frame
	_move_card_to_anchor(board, candidate, Vector2i(3, 2), 0)
	_expect(board.can_place_card(candidate), "a candidate covering the left connection cell can extend the chain")
	_expect(board.add_card(candidate), "the left-connected candidate commits")
	_expect(candidate.get_card_inst().direction == 0, "committed direction remains in CardInstance")

	board.free()
	quit(1 if _failures > 0 else 0)


func _make_card(card_type: CardData.CardType, direction: int) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	var instance := CardInstance.new(data)
	instance.direction = direction
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(board: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board.back_ground
	var cell_size := background.cell_size
	var local_center := Vector2((float(anchor.x) + 0.5) * cell_size, (float(anchor.y) + 1.0) * cell_size)
	if posmod(direction, 4) % 2 == 1:
		local_center = Vector2((float(anchor.x) + 1.0) * cell_size, (float(anchor.y) + 0.5) * cell_size)
	card.global_position = background.to_global(local_center) - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
