extends SceneTree

const BOARD_ZONE_SCENE := preload("res://scenes/zone/board_zone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const TOLERANCE := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board)
	await process_frame

	_expect(board != null, "BoardZone scene instantiates with the Card protocol")
	_expect(board.has_signal("placement_applied"), "BoardZone publishes structured placement operations")
	_expect(board.has_signal("chain_segment_detached"), "BoardZone publishes structured chain retractions")

	var placements: Array[BoardCardPlacement] = []
	var retractions: Array[BoardCardRetraction] = []
	if board.has_signal("placement_applied"):
		board.placement_applied.connect(func(operation: BoardCardPlacement) -> void:
			placements.append(operation)
		)
	if board.has_signal("chain_segment_detached"):
		board.chain_segment_detached.connect(func(operation: BoardCardRetraction) -> void:
			retractions.append(operation)
		)

	var unbound_card := CARD_SCENE.instantiate() as Card
	root.add_child(unbound_card)
	await process_frame
	_move_card_to_anchor(board, unbound_card, Vector2i(4, 4), 0)
	unbound_card.bind_card_inst(null)
	_expect(not board.add_card(unbound_card), "BoardZone rejects a Card without a bound CardInstance")
	unbound_card.free()

	var root_card := _make_card(CardData.CardType.ROOT, 0, "Root")
	root.add_child(root_card)
	await process_frame
	_move_card_to_anchor(board, root_card, Vector2i(4, 4), 0)
	_expect(board.add_card(root_card), "ROOT enters an empty BoardZone")
	_expect(board.owns_card(root_card), "BoardZone owns a stably committed ROOT")
	_expect(root_card.get_card_inst().cur_zone == CardInstance.ZONE.BOARD, "stable ROOT state is BOARD")
	_expect(root_card.get_card_inst().battlefield_pos == Vector2i(4, 4), "stable ROOT stores its anchor")
	_expect(root_card.get_card_inst().direction == 0, "stable ROOT stores its direction")
	_expect(placements.size() == 1, "ROOT emits one placement operation")
	if placements.size() == 1:
		_expect(placements[0].kind == BoardCardPlacement.Kind.CHAIN_EXTENDED, "ROOT placement is CHAIN_EXTENDED")
		_expect(placements[0].card == root_card, "placement keeps the exact Card")
		_expect(placements[0].card_inst == root_card.get_card_inst(), "placement keeps the exact CardInstance")

	board.start_drag(root_card)
	_expect(not board.owns_card(root_card), "a dragging board card temporarily loses stable ownership")
	root_card.get_card_inst().direction = 2
	root_card.global_position += Vector2(100.0, 80.0)
	_expect(board.drag_end_source(root_card, false), "cancelled drag restores the source snapshot")
	_expect(board.owns_card(root_card), "cancelled drag restores stable ownership")
	_expect(root_card.get_card_inst().battlefield_pos == Vector2i(4, 4), "cancelled drag restores battlefield_pos")
	_expect(root_card.get_card_inst().direction == 0, "cancelled drag restores direction")

	var normal_first_board := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(normal_first_board)
	await process_frame
	var normal_first := _make_card(CardData.CardType.NORMAL, 0, "NoRoot")
	root.add_child(normal_first)
	await process_frame
	_move_card_to_anchor(normal_first_board, normal_first, Vector2i(4, 4), 0)
	_expect(not normal_first_board.add_card(normal_first), "NORMAL cannot be the first board card")
	normal_first.free()
	normal_first_board.free()

	var middle := _make_card(CardData.CardType.NORMAL, 0, "Middle")
	root.add_child(middle)
	await process_frame
	_move_card_to_anchor(board, middle, Vector2i(4, 2), 0)
	_expect(board.add_card(middle), "connected NORMAL extends the chain")

	var tail := _make_card(CardData.CardType.NORMAL, 0, "Tail")
	root.add_child(tail)
	await process_frame
	_move_card_to_anchor(board, tail, Vector2i(4, 0), 0)
	_expect(board.add_card(tail), "second connected NORMAL extends the chain")
	_expect(board.get_cards() == [root_card, middle, tail], "stable cards preserve chain order")
	_expect(board.get_combat_card_chain() == [root_card.get_card_inst(), middle.get_card_inst(), tail.get_card_inst()], "combat chain preserves exact instances")

	var tail_saved_position := tail.global_position
	board.start_drag(tail)
	_expect(not board.owns_card(tail), "dragging tail is removed from stable members")
	_move_card_to_anchor(board, tail, Vector2i(3, 1), 1)
	board.update_drag(tail)
	_expect(board.can_trans_to_target(tail), "tail can move within BoardZone while staying connected")
	_expect(board.drag_end_target(tail, true), "same-zone target commits the moved tail")
	_expect(board.drag_end_source(tail, true), "same-zone source finalizes without deleting the target membership")
	_expect(board.owns_card(tail), "same-zone move keeps stable ownership")
	_expect(tail.global_position.distance_to(tail_saved_position) > TOLERANCE, "same-zone move changes the tail position")
	_expect(retractions.is_empty(), "same-zone tail movement does not emit a chain retraction")

	var saved_middle_position := middle.global_position
	var saved_middle_target := middle.target_position
	var saved_middle_anchor := middle.get_card_inst().battlefield_pos
	var saved_middle_direction := middle.get_card_inst().direction
	board.start_drag(middle)
	middle.get_card_inst().direction = 2
	middle.global_position += Vector2(180.0, 120.0)
	middle.target_position = middle.position
	board.update_drag(middle)
	_expect(not board.can_trans_to_target(middle), "a middle chain card cannot be placed back as a target")
	_expect(board.drag_end_source(middle, false), "middle-card cancellation restores the source")
	_expect(middle.global_position.distance_to(saved_middle_position) <= TOLERANCE, "cancel restores middle position")
	_expect(middle.target_position.distance_to(saved_middle_target) <= TOLERANCE, "cancel restores middle target")
	_expect(middle.get_card_inst().battlefield_pos == saved_middle_anchor, "cancel restores middle anchor")
	_expect(middle.get_card_inst().direction == saved_middle_direction, "cancel restores middle direction")
	_expect(board.get_cards() == [root_card, middle, tail], "cancel restores the original chain")

	board.start_drag(middle)
	_expect(board.drag_end_source(middle, true), "external target success commits middle-card removal")
	_expect(board.get_cards() == [root_card], "removing a middle card detaches all followers")
	_expect(retractions.size() == 1, "middle-card removal emits exactly one retraction")
	if retractions.size() == 1:
		_expect(retractions[0].removed_card == middle, "retraction identifies the directly removed card")
		_expect(retractions[0].followers_to_return == [tail], "followers preserve original chain order")
		_expect(retractions[0].original_chain_size == 3, "retraction records the original chain size")
	_expect(middle.get_card_inst().battlefield_pos == Vector2i(-1, -1), "removed card clears board coordinates")
	_expect(tail.get_card_inst().battlefield_pos == Vector2i(-1, -1), "detached follower clears board coordinates")

	var drag_layer := DraggerLayer.new()
	var replacement_layer := DraggerLayer.new()
	root.add_child(drag_layer)
	root.add_child(replacement_layer)
	board.set_drag_layer(drag_layer)
	_expect(drag_layer.get_registered_zones().has(board), "BoardZone registers with the current DraggerLayer")
	_expect(root_card.drag_layer == drag_layer, "BoardZone binds stable cards to the current DraggerLayer")
	board.set_drag_layer(replacement_layer)
	_expect(not drag_layer.get_registered_zones().has(board), "BoardZone unregisters from the previous DraggerLayer")
	_expect(replacement_layer.get_registered_zones().has(board), "BoardZone registers with the replacement DraggerLayer")
	_expect(root_card.drag_layer == replacement_layer, "BoardZone rebinds stable cards")
	board.set_drag_layer(null)
	_expect(not replacement_layer.get_registered_zones().has(board), "clearing the DraggerLayer unregisters BoardZone")
	_expect(root_card.drag_layer == null, "clearing the DraggerLayer unbinds stable cards")

	board.free()
	drag_layer.free()
	replacement_layer.free()
	quit(1 if _failures > 0 else 0)


func _make_card(card_type: CardData.CardType, direction: int, card_name: String) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var instance := CardInstance.new(data)
	instance.direction = direction
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(board: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board.back_ground
	var cell_size := background.cell_size
	var local_center: Vector2
	if posmod(direction, 4) % 2 == 0:
		local_center = Vector2((float(anchor.x) + 0.5) * cell_size, (float(anchor.y) + 1.0) * cell_size)
	else:
		local_center = Vector2((float(anchor.x) + 1.0) * cell_size, (float(anchor.y) + 0.5) * cell_size)
	var center := background.to_global(local_center)
	card.global_position = center - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
