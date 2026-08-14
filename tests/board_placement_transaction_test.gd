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

	var placement_events: Array[Dictionary] = []
	var detach_events: Array[Dictionary] = []
	_expect(board.has_signal("card_placed"), "BoardZone exposes direct card placement facts")
	_expect(board.has_signal("chain_detached"), "BoardZone exposes direct chain detach facts")
	if board.has_signal("card_placed"):
		board.connect(&"card_placed", func(
			card: Card,
			occupied_cells: Array[Vector2i],
			affected_cards: Array[Card],
			guide_resolved: bool
		) -> void:
			placement_events.append({
				"card": card,
				"occupied_cells": occupied_cells,
				"affected_cards": affected_cards,
				"guide_resolved": guide_resolved,
			})
		)
	if board.has_signal("chain_detached"):
		board.connect(&"chain_detached", func(
			removed_card: Card,
			followers_to_return: Array[Card],
			original_chain_size: int
		) -> void:
			detach_events.append({
				"removed_card": removed_card,
				"followers_to_return": followers_to_return,
				"original_chain_size": original_chain_size,
			})
		)

	var root_card := _make_card(CardData.CardType.ROOT, "Root")
	root.add_child(root_card)
	await process_frame
	_move_card_to_anchor(board, root_card, Vector2i(3, 5))
	_expect(board.add_card(root_card), "ROOT commits through BoardZone")
	_expect(placement_events.size() == 1, "successful placement publishes one direct fact")
	if placement_events.size() == 1:
		var placement := placement_events[0]
		_expect(placement.card == root_card, "placement fact keeps the source Card")
		_expect(
			placement.occupied_cells == [Vector2i(3, 5), Vector2i(3, 4)],
			"placement fact reports occupied cells"
		)
		_expect(placement.affected_cards == [root_card], "placement fact reports affected cards")
		_expect(not placement.guide_resolved, "ROOT placement is not a GUIDE resolution")

	var middle := _make_card(CardData.CardType.NORMAL, "Middle")
	root.add_child(middle)
	await process_frame
	_move_card_to_anchor(board, middle, Vector2i(3, 3))
	_expect(board.add_card(middle), "middle card extends the chain")

	var tail := _make_card(CardData.CardType.NORMAL, "Tail")
	root.add_child(tail)
	await process_frame
	_move_card_to_anchor(board, tail, Vector2i(3, 1))
	_expect(board.add_card(tail), "tail card extends the chain")

	board.start_drag(middle)
	_expect(board.drag_end_source(middle, true), "removing the middle card commits the detach")
	_expect(detach_events.size() == 1, "chain removal publishes one direct detach fact")
	if detach_events.size() == 1:
		var detached := detach_events[0]
		_expect(detached.removed_card == middle, "detach fact identifies the removed card")
		_expect(detached.followers_to_return == [tail], "detach fact preserves follower order")
		_expect(detached.original_chain_size == 3, "detach fact reports the original chain size")

	board.free()
	quit(1 if _failures > 0 else 0)


func _make_card(card_type: CardData.CardType, card_name: String) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var instance := CardInstance.new(data)
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(board: BoardZone, card: Card, anchor: Vector2i) -> void:
	var background := board.back_ground
	var local_center := Vector2(
		(float(anchor.x) + 0.5) * background.cell_size,
		(float(anchor.y) + 1.0) * background.cell_size
	)
	card.global_position = background.to_global(local_center) - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
