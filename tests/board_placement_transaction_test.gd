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
	var operations: Array[BoardCardPlacement] = []
	if board.has_signal("placement_applied"):
		board.placement_applied.connect(func(operation: BoardCardPlacement) -> void:
			operations.append(operation)
		)

	var card := _make_root_card()
	root.add_child(card)
	await process_frame
	_move_card_to_anchor(board, card, Vector2i(3, 3))
	_expect(board.add_card(card), "ROOT commits through BoardZone")
	_expect(operations.size() == 1, "successful placement publishes exactly one operation")
	if operations.size() == 1:
		_expect(operations[0].card == card, "operation keeps the source Card")
		_expect(operations[0].card_inst == card.get_card_inst(), "operation keeps the exact CardInstance")
		_expect(operations[0].occupied_cells == [Vector2i(3, 3), Vector2i(3, 4)], "operation records occupied cells")
		_expect(operations[0].affected_cards == [card], "normal placement reports only the placed card")

	board.free()
	quit(1 if _failures > 0 else 0)


func _make_root_card() -> Card:
	var data := CardData.new()
	data.card_type = CardData.CardType.ROOT
	var instance := CardInstance.new(data)
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(board: BoardZone, card: Card, anchor: Vector2i) -> void:
	var background := board.back_ground
	var local_center := Vector2((float(anchor.x) + 0.5) * background.cell_size, (float(anchor.y) + 1.0) * background.cell_size)
	card.global_position = background.to_global(local_center) - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
