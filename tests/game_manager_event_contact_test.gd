extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const MarrowRatEvent = preload("res://data/levels/ribwood/events/ribwood_marrow_rat_event.tres")
const BrokenBannerShopEvent = preload("res://data/levels/ribwood/events/ribwood_broken_banner_shop_event.tres")
const MarrowLampTreasureEvent = preload("res://data/levels/ribwood/events/ribwood_marrow_lamp_treasure_event.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	await _assert_real_event_contact_opens_its_modal(
		MarrowRatEvent, EventData.EventType.MONSTER, "combat"
	)
	await _assert_real_event_contact_opens_its_modal(
		BrokenBannerShopEvent, EventData.EventType.SHOP, "shop"
	)
	await _assert_real_event_contact_opens_its_modal(
		MarrowLampTreasureEvent, EventData.EventType.TREASURE, "treasure"
	)
	await _assert_closing_shop_restores_event_contact_flow()
	await _assert_guide_contact_opens_combat_modal()
	await _assert_monster_contact_for_all_directions()
	quit(0 if _failure_count == 0 else 1)


func _assert_real_event_contact_opens_its_modal(
	event_data: EventData, event_type: EventData.EventType, modal_name: String
) -> void:
	var manager := await _make_manager()
	var board: Board = manager.board
	var event_node := _attach_event(board, event_data, Vector2i(3, 0))
	_expect(event_node != null, "%s fixture attaches the Ribwood event" % modal_name)
	_expect(_place_root(board), "%s fixture places the root card" % modal_name)

	var card := _make_hand_card(manager, 3)
	manager.drag_layer.on_card_drag_start(card)
	card.global_position = _horizontal_global_center(board, Vector2i(2, 0))
	card.rotation_degrees = 90.0
	manager.drag_layer.on_card_drag_end(card)

	_expect(card in board.cards, "%s contact commits the dragged card" % modal_name)
	_expect(
		manager.get_run_flow().get_state() == RunFlowCoordinator.State.INTERACTING,
		"%s contact enters interaction state" % modal_name
	)
	match event_type:
		EventData.EventType.MONSTER, EventData.EventType.BOSS:
			_expect(manager.combat_event_view.visible, "%s contact opens combat UI" % modal_name)
		EventData.EventType.SHOP:
			_expect(manager.shop_event_view.visible, "%s contact opens shop UI" % modal_name)
		EventData.EventType.TREASURE:
			_expect(manager.treasure_event_view.visible, "%s contact opens treasure UI" % modal_name)
	manager.free()
	await process_frame

func _assert_closing_shop_restores_event_contact_flow() -> void:
	var manager := await _make_manager()
	var board: Board = manager.board
	var shop_event := _attach_event(board, BrokenBannerShopEvent, Vector2i(3, 0))
	_expect(shop_event != null, "shop-close fixture attaches the Ribwood shop event")
	var monster_event := _attach_event(board, MarrowRatEvent, Vector2i(5, 0))
	_expect(monster_event != null, "shop-close fixture attaches the following monster event")
	_expect(_place_root(board), "shop-close fixture places the root card")

	var shop_card := _make_hand_card(manager, 3)
	_expect(
		_drop_card(manager, shop_card, _horizontal_global_center(board, Vector2i(2, 0))),
		"shop-close fixture reaches the shop event"
	)
	_expect(manager.shop_event_view.visible, "shop-close fixture opens shop UI")
	_expect(
		manager.get_run_flow().get_state() == RunFlowCoordinator.State.INTERACTING,
		"shop-close fixture enters interaction state"
	)

	manager.shop_event_view.close_requested.emit()
	await process_frame
	_expect(not manager.shop_event_view.visible, "closing the shop hides its UI")
	_expect(
		manager.get_run_flow().get_state() == RunFlowCoordinator.State.EXPLORING,
		"closing the shop restores exploration state"
	)

	var monster_card := _make_hand_card(manager, 3)
	_expect(
		_drop_card(manager, monster_card, _horizontal_global_center(board, Vector2i(4, 0))),
		"shop-close fixture reaches the following monster event"
	)
	_expect(
		manager.get_run_flow().get_state() == RunFlowCoordinator.State.INTERACTING,
		"event contact after closing shop re-enters interaction state"
	)
	_expect(manager.combat_event_view.visible, "event contact after closing shop opens combat UI")
	manager.free()
	await process_frame


func _assert_monster_contact_for_all_directions() -> void:
	for direction in range(4):
		await _assert_monster_contact_for_direction(direction)


func _assert_monster_contact_for_direction(direction: int) -> void:
	var manager := await _make_manager()
	var board: Board = manager.board
	var root_cells: Array[Vector2i]
	var card_cells: Array[Vector2i]
	var event_origin: Vector2i
	match direction:
		0:
			root_cells = [Vector2i(3, 2), Vector2i(3, 3)]
			card_cells = [Vector2i(3, 0), Vector2i(3, 1)]
			event_origin = Vector2i(3, 0)
		1:
			root_cells = [Vector2i(2, 3), Vector2i(3, 3)]
			card_cells = [Vector2i(4, 3), Vector2i(5, 3)]
			event_origin = Vector2i(5, 3)
		2:
			root_cells = [Vector2i(3, 3), Vector2i(3, 4)]
			card_cells = [Vector2i(3, 5), Vector2i(3, 6)]
			event_origin = Vector2i(3, 6)
		3:
			root_cells = [Vector2i(3, 3), Vector2i(4, 3)]
			card_cells = [Vector2i(1, 3), Vector2i(2, 3)]
			event_origin = Vector2i(1, 3)

	var event_node := _attach_event(board, MarrowRatEvent, event_origin)
	_expect(event_node != null, "direction %d fixture attaches the Ribwood monster event" % direction)
	_expect(_place_root(board, root_cells, direction), "direction %d fixture places the root card" % direction)

	var card := _make_hand_card(manager, 3)
	_expect(
		_drop_card(manager, card, _card_center(board, card_cells), direction),
		"direction %d contact commits the dragged card" % direction
	)
	_expect(
		manager.get_run_flow().get_state() == RunFlowCoordinator.State.INTERACTING,
		"direction %d contact enters interaction state" % direction
	)
	_expect(manager.combat_event_view.visible, "direction %d contact opens combat UI" % direction)
	manager.free()
	await process_frame


func _assert_guide_contact_opens_combat_modal() -> void:
	var manager := await _make_manager()
	var board: Board = manager.board
	var event_node := _attach_event(board, MarrowRatEvent, Vector2i(5, 0))
	_expect(event_node != null, "guide fixture attaches the Ribwood monster event")
	_expect(_place_root(board), "guide fixture places the root card")
	var normal := _make_hand_card(manager, 3)
	_expect(_drop_card(manager, normal, _horizontal_global_center(board, Vector2i(2, 0))), "guide fixture extends the chain")

	var guide := _make_hand_card(manager, 0, CardData.CardType.GUIDE)
	_expect(_drop_card(manager, guide, _horizontal_global_center(board, Vector2i(4, 0))), "guide card placement commits")
	_expect(
		manager.get_run_flow().get_state() == RunFlowCoordinator.State.INTERACTING,
		"guide-driven contact enters interaction state"
	)
	_expect(manager.combat_event_view.visible, "guide-driven contact opens combat UI")
	_expect(guide in manager.hand_area.cards, "guide card returns to hand after resolving its movement")
	manager.free()
	await process_frame


func _drop_card(
	manager: Node, card: CardEntity, global_position: Vector2, direction: int = 1
) -> bool:
	manager.drag_layer.on_card_drag_start(card)
	card.global_position = global_position
	card.rotation_degrees = direction * 90.0
	manager.drag_layer.on_card_drag_end(card)
	return card in manager.board.cards or card in manager.hand_area.cards

func _make_manager() -> Node:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "contact fixture configures the game manager")
	root.add_child(manager)
	await process_frame
	for event_node in manager.board.events.duplicate():
		manager.board.remove_event(event_node)
	return manager


func _attach_event(board: Board, event_data: EventData, origin: Vector2i) -> BoardEvent:
	var instance := event_data.create_instance()
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, board.cell_size)
	if not board.attach_event(event_node):
		event_node.free()
		return null
	return event_node


func _place_root(
	board: Board,
	cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)],
	direction: int = 1
) -> bool:
	var root_data := CardData.new()
	root_data.card_type = CardData.CardType.ROOT
	var root := CardEntityScene.instantiate() as CardEntity
	root.bind_instance(CardInstance.new(root_data))
	root.global_position = _card_center(board, cells)
	root.rotation_degrees = direction * 90.0
	get_root().add_child(root)
	return board.add_card(root)


func _make_hand_card(manager: Node, damage: int, card_type := CardData.CardType.NORMAL) -> CardEntity:
	var data := CardData.new()
	data.card_type = card_type
	data.damage = damage
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(CardInstance.new(data))
	card.drag_layer = manager.drag_layer
	manager.hand_area.add_card(card, false)
	return card


func _horizontal_global_center(board: Board, left_cell: Vector2i) -> Vector2:
	var right_cell := left_cell + Vector2i.RIGHT
	return _card_center(board, [left_cell, right_cell])


func _card_center(board: Board, cells: Array[Vector2i]) -> Vector2:
	var center := Vector2.ZERO
	for cell in cells:
		center += board.grid_to_world_center(cell)
	return center / cells.size()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
