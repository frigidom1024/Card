extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")
const EventScene := preload("res://scenes/game/event.tscn")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const EventEntryScript := preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript := preload("res://scripts/game/event/core/event_lib.gd")
const ExplorationConfigScript := preload("res://scripts/game/exploration/exploration_config.gd")
const ExplorationCoordinatorScript := preload("res://scripts/game/exploration/exploration_coordinator.gd")
const BossPressureServiceScript := preload("res://scripts/game/exploration/boss_pressure_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_chain_extension_reveals_then_spawns_then_requests_event()
	_test_guide_reveals_new_cells_without_advancing_boss_pressure()
	_test_disabled_boss_pursuit_keeps_revealed_boss_stationary()
	_test_contacted_boss_does_not_move_before_interaction()
	_test_newly_revealed_boss_does_not_consume_its_first_pressure_count()
	_test_defeated_intercepting_boss_is_removed_from_event_grid()
	_test_boss_contact_uses_the_same_event_request_path_as_monster()
	quit(1 if _failure_count > 0 else 0)


func _test_chain_extension_reveals_then_spawns_then_requests_event() -> void:
	var board := _make_board()
	var coordinator := ExplorationCoordinatorScript.new()
	var config := _make_config([1], 99)
	_expect(coordinator.configure(_make_event_lib([EventData.EventType.MONSTER]), board, config), "coordinator accepts valid exploration dependencies")

	var source_card := _make_card(board, CardData.CardType.NORMAL)
	var contacted := _make_event_template("contact_echo", EventData.EventType.MONSTER).create_instance()
	contacted.origin = Vector2i(1, 1)
	_expect(_attach_event(board, contacted), "contact event attaches before the placement is resolved")

	var signal_order: Array[String] = []
	coordinator.fog_revealed.connect(func(_cells: Array[Vector2i]) -> void:
		signal_order.append("fog_revealed")
	)
	coordinator.event_spawned.connect(func(_event_node: BoardEvent) -> void:
		signal_order.append("event_spawned")
	)
	coordinator.event_interaction_requested.connect(func(instance: EventInstance) -> void:
		signal_order.append("event_interaction_requested")
		_expect(instance == contacted, "the interaction request retains the originally contacted event")
	)

	var result := _make_result(source_card, [Vector2i(1, 1), Vector2i(4, 4)], contacted)
	coordinator.resolve_placement(result)

	_expect(signal_order == ["fog_revealed", "event_spawned", "event_interaction_requested"], "exploration resolves in reveal, spawn, then ordinary event request order")
	board.queue_free()


func _test_guide_reveals_new_cells_without_advancing_boss_pressure() -> void:
	var board := _make_board()
	var root_card := _place_root(board)
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(_make_event_lib([EventData.EventType.BOSS]), board, _make_config([], 1, true, 1, 1)), "guide pressure setup configures coordinator")
	coordinator.resolve_placement(_make_result(root_card, board.get_card_cells(root_card.global_position, root_card.rotation_degrees)))
	_expect(coordinator.get_boss_phase() == BossPressureServiceScript.Phase.ACTIVE, "first reveal registers an active Boss")
	var revealed_before := coordinator.get_revealed_count()

	var guide := _make_card(board, CardData.CardType.GUIDE)
	coordinator.resolve_placement(_make_result(guide, [Vector2i(6, 4)], null, BoardPlacementResult.Kind.GUIDE_RESOLVED))

	_expect(coordinator.get_revealed_count() > revealed_before, "guide resolution still reveals new fog")
	_expect(coordinator.get_boss_phase() == BossPressureServiceScript.Phase.ACTIVE, "guide resolution does not advance Boss pressure")
	board.queue_free()


func _test_disabled_boss_pursuit_keeps_revealed_boss_stationary() -> void:
	var board := _make_board()
	var root_card := _place_root(board)
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(_make_event_lib([EventData.EventType.BOSS]), board, _make_config([], 1, false, 1, 1)), "disabled pursuit configures coordinator")
	coordinator.resolve_placement(_make_result(root_card, board.get_card_cells(root_card.global_position, root_card.rotation_degrees)))
	var boss := coordinator.get_boss_event()
	_expect(boss != null, "the Boss is revealed even while pursuit is disabled")
	if boss != null:
		var original_origin := boss.event_instance.origin
		var normal := _make_card(board, CardData.CardType.NORMAL)
		coordinator.resolve_placement(_make_result(normal, [Vector2i(6, 4)]))
		_expect(coordinator.get_boss_phase() == BossPressureServiceScript.Phase.ACTIVE, "disabled pursuit keeps the revealed Boss active")
		_expect(boss.event_instance.origin == original_origin, "disabled pursuit leaves the ordinary Boss event stationary")
	board.queue_free()


func _test_contacted_boss_does_not_move_before_interaction() -> void:
	var board := _make_board()
	var root_card := _place_root(board)
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(_make_event_lib([EventData.EventType.BOSS]), board, _make_config([], 1, true, 1, 1)), "contact setup configures coordinator")
	coordinator.resolve_placement(_make_result(root_card, board.get_card_cells(root_card.global_position, root_card.rotation_degrees)))
	var boss := coordinator.get_boss_event()
	_expect(boss != null, "contact setup reveals Boss")
	if boss == null:
		board.queue_free()
		return

	var normal := _make_card(board, CardData.CardType.NORMAL)
	coordinator.resolve_placement(_make_result(normal, [Vector2i(6, 4)]))
	_expect(coordinator.get_boss_phase() == BossPressureServiceScript.Phase.SURROUNDING, "ordinary extension advances Boss into surrounding phase")
	var contacted_origin := boss.event_instance.origin
	var requests: Array[EventInstance] = []
	coordinator.event_interaction_requested.connect(func(instance: EventInstance) -> void:
		requests.append(instance)
	)
	coordinator.resolve_placement(_make_result(normal, [Vector2i(7, 5)], boss.event_instance))

	_expect(boss.event_instance.origin == contacted_origin, "contacted Boss is not moved before its ordinary interaction request")
	_expect(requests == [boss.event_instance], "contacted Boss uses the coordinator event request")
	board.queue_free()


func _test_newly_revealed_boss_does_not_consume_its_first_pressure_count() -> void:
	var board := _make_board()
	var root_card := _place_root(board)
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(_make_event_lib([EventData.EventType.BOSS]), board, _make_config([], 1, true, 1, 1)), "new Boss pressure setup configures coordinator")
	coordinator.resolve_placement(_make_result(root_card, board.get_card_cells(root_card.global_position, root_card.rotation_degrees)))

	_expect(coordinator.get_boss_phase() == BossPressureServiceScript.Phase.ACTIVE, "a newly revealed Boss starts active with zero pressure progress")
	var normal := _make_card(board, CardData.CardType.NORMAL)
	coordinator.resolve_placement(_make_result(normal, [Vector2i(6, 4)]))
	_expect(coordinator.get_boss_phase() == BossPressureServiceScript.Phase.SURROUNDING, "only the following ordinary extension advances the newly revealed Boss")
	board.queue_free()


func _test_defeated_intercepting_boss_is_removed_from_event_grid() -> void:
	var board := _make_board()
	var root_card := _place_root(board)
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(_make_event_lib([EventData.EventType.BOSS]), board, _make_config([], 1, true, 1, 1)), "dismissal setup configures coordinator")
	coordinator.resolve_placement(_make_result(root_card, board.get_card_cells(root_card.global_position, root_card.rotation_degrees)))
	var boss := coordinator.get_boss_event()
	_expect(boss != null, "dismissal setup reveals Boss")
	if boss == null:
		board.queue_free()
		return
	var intercept_cell := board.get_placement_cell(root_card)
	_expect(board.move_event(boss, intercept_cell), "ordinary Boss event can occupy the chain forward cell")
	_expect(coordinator.dismiss_defeated_boss(boss.event_instance), "coordinator dismisses a defeated Boss through Board event removal")
	_expect(boss not in board.events, "dismissed Boss no longer belongs to the Board event collection")
	_expect(board.get_overlapping_unresolved_event([intercept_cell]) == null, "dismissal releases the Boss event cell")
	var candidate := _make_card(board, CardData.CardType.NORMAL)
	candidate.position = board.grid_to_world_center(intercept_cell)
	candidate.rotation_degrees = 90.0
	_expect(board.can_place_card(board.get_card_cells(candidate.global_position, candidate.rotation_degrees), candidate), "released intercept cell remains a legal chain placement")
	board.queue_free()


func _test_boss_contact_uses_the_same_event_request_path_as_monster() -> void:
	var board := _make_board()
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(_make_event_lib([]), board, _make_config([], 99)), "shared interaction-path setup configures coordinator")
	var monster := _make_event_template("ordinary_echo", EventData.EventType.MONSTER).create_instance()
	monster.origin = Vector2i(1, 1)
	var boss := _make_event_template("ordinary_boss", EventData.EventType.BOSS).create_instance()
	boss.origin = Vector2i(5, 4)
	_expect(_attach_event(board, monster), "ordinary echo attaches")
	_expect(_attach_event(board, boss), "ordinary Boss attaches through the same Board API")
	var source_card := _make_card(board, CardData.CardType.NORMAL)
	var requested: Array[EventInstance] = []
	coordinator.event_interaction_requested.connect(func(instance: EventInstance) -> void:
		requested.append(instance)
	)

	coordinator.resolve_placement(_make_result(source_card, [Vector2i(1, 1)], monster))
	coordinator.resolve_placement(_make_result(source_card, [Vector2i(5, 4)], boss))

	_expect(requested == [monster, boss], "monster and Boss contact both use the single ordinary event request signal")
	board.queue_free()


func _make_board() -> Board:
	var board := BoardScene.instantiate() as Board
	board.width = 8
	board.height = 6
	root.add_child(board)
	return board


func _place_root(board: Board) -> CardEntity:
	var root_card := _make_card(board, CardData.CardType.ROOT)
	root_card.position = Vector2(280, 280)
	root_card.rotation_degrees = 0.0
	_expect(board.add_card(root_card), "root card establishes a real Board chain")
	return root_card


func _make_result(source: CardEntity, cells: Array[Vector2i], overlap: EventInstance = null, kind: BoardPlacementResult.Kind = BoardPlacementResult.Kind.CHAIN_EXTENDED) -> BoardPlacementResult:
	return BoardPlacementResult.new(
		kind,
		source,
		source,
		[source],
		cells,
		overlap
	)


func _make_config(
	thresholds: Array[int],
	boss_threshold: int,
	pursuit_enabled: bool = true,
	surround_threshold: int = 2,
	intercept_threshold: int = 2
) -> ExplorationConfig:
	var config := ExplorationConfigScript.new()
	config.scheduled_event_reveal_thresholds = thresholds
	config.boss_reveal_threshold = boss_threshold
	config.boss_pursuit_enabled = pursuit_enabled
	config.cards_to_boss_surround = surround_threshold
	config.cards_to_boss_intercept = intercept_threshold
	return config


func _make_event_lib(event_types: Array[int]) -> EventLib:
	var event_lib := EventLibScript.new()
	event_lib.event_scene = EventScene
	for index in event_types.size():
		var entry := EventEntryScript.new()
		entry.event_data = _make_event_template("test_event_%d" % index, event_types[index])
		entry.min_count = 1
		entry.max_count = 1
		event_lib.entries.append(entry)
	return event_lib


func _make_event_template(event_id: String, event_type: EventData.EventType) -> EventData:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.event_type = event_type
	template.size = Vector2i.ONE
	return template


func _attach_event(board: Board, instance: EventInstance) -> bool:
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, board.cell_size)
	return board.attach_event(event_node)


func _make_card(board: Board, card_type: CardData.CardType) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	board.add_child(card)
	var data := CardData.new()
	data.card_type = card_type
	card.bind_instance(CardInstance.new(data))
	return card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
