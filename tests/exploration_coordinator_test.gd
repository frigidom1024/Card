extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")
const EventScene := preload("res://scenes/game/event.tscn")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const EventEntryScript := preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript := preload("res://scripts/game/event/core/event_lib.gd")
const EventSpawnCandidateScript := preload("res://scripts/game/exploration/event_spawn_candidate.gd")
const ExplorationConfigScript := preload("res://scripts/game/exploration/exploration_config.gd")
const ExplorationCoordinatorScript := preload("res://scripts/game/exploration/exploration_coordinator.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_initial_events_are_visible_after_initialization()
	_test_root_and_normal_placements_generate_but_guide_does_not()
	_test_defeated_boss_is_removed_from_event_grid()
	_test_only_resolved_non_boss_events_are_removed()
	quit(1 if _failure_count > 0 else 0)


func _test_initial_events_are_visible_after_initialization() -> void:
	var board := _make_board()
	var event_lib := _make_event_lib()
	var config := _make_config()
	config.spawn_config.initial_event_count_min = 2
	config.spawn_config.initial_event_count_max = 2
	config.spawn_config.initial_event_pool.append(_candidate(event_lib.entries[0].event_data))
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(event_lib, board, config), "coordinator accepts placement spawn configuration")
	_expect(coordinator.initialize_events() == 2, "coordinator initializes configured events")
	_expect(board.events.size() == 2, "initial events are visible immediately")
	board.queue_free()


func _test_root_and_normal_placements_generate_but_guide_does_not() -> void:
	var board := _make_board()
	var event_lib := _make_event_lib()
	var config := _make_config()
	config.spawn_config.placement_spawn_count_weights = {0: 0, 1: 1, 2: 0}
	config.spawn_config.placement_event_pool.append(_candidate(event_lib.entries[0].event_data))
	config.spawn_config.boss_spawn_after_placements = 99
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(event_lib, board, config), "coordinator configures placement pacing")
	var root_card := _make_card(board, CardData.CardType.ROOT)
	coordinator.resolve_placement(_make_result(root_card))
	_expect(board.events.size() == 1, "ROOT placement spawns one ordinary event")
	_expect(coordinator.get_exploration_placement_count() == 1, "ROOT increments exploration placement count")

	var guide := _make_card(board, CardData.CardType.GUIDE)
	coordinator.resolve_placement(_make_result(guide, BoardPlacementResult.Kind.GUIDE_RESOLVED))
	_expect(board.events.size() == 1, "GUIDE placement does not spawn an ordinary event")
	_expect(coordinator.get_exploration_placement_count() == 1, "GUIDE placement does not increment exploration placement count")
	board.queue_free()




func _test_defeated_boss_is_removed_from_event_grid() -> void:
	var board := _make_board()
	var event_lib := _make_event_lib()
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(event_lib, board, _make_config()), "coordinator configures Boss removal")
	var boss := _attach_event(board, event_lib.entries[1].event_data.create_instance(), Vector2i(2, 2))
	_expect(coordinator.dismiss_defeated_boss(boss.event_instance), "defeated Boss is removed by coordinator")
	_expect(board.events.is_empty(), "removed Boss no longer occupies the event grid")
	board.queue_free()


func _test_only_resolved_non_boss_events_are_removed() -> void:
	var board := _make_board()
	var event_lib := _make_event_lib()
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(event_lib, board, _make_config()), "coordinator configures resolved event cleanup")
	var echo := _attach_event(board, event_lib.entries[0].event_data.create_instance(), Vector2i(2, 2))
	_expect(
		not coordinator.dismiss_resolved_event(echo.event_instance),
		"unresolved residual echo remains on the board"
	)
	echo.event_instance.resolve()
	_expect(
		coordinator.dismiss_resolved_event(echo.event_instance),
		"resolved residual echo is removed through the generic cleanup port"
	)
	_expect(board.events.is_empty(), "removed residual echo frees its event cells")
	board.queue_free()


func _make_board(width: int = 8, height: int = 6) -> Board:
	var board := BoardScene.instantiate() as Board
	board.width = width
	board.height = height
	root.add_child(board)
	return board


func _make_config() -> ExplorationConfig:
	var config := ExplorationConfigScript.new()
	config.spawn_config = ExplorationSpawnConfig.new()
	config.spawn_config.initial_event_count_min = 0
	config.spawn_config.initial_event_count_max = 0
	config.spawn_config.placement_spawn_count_weights = {0: 1, 1: 0, 2: 0}
	config.spawn_config.boss_spawn_after_placements = 99
	config.spawn_config.max_unresolved_events = 8
	config.boss_pursuit_enabled = true
	config.cards_to_boss_surround = 2
	config.cards_to_boss_intercept = 2
	return config


func _make_event_lib() -> EventLib:
	var event_lib := EventLibScript.new()
	event_lib.event_scene = EventScene
	var monster_entry := EventEntryScript.new()
	monster_entry.event_data = _make_template("monster_echo", EventData.EventType.MONSTER)
	var boss_entry := EventEntryScript.new()
	boss_entry.event_data = _make_template("boss_echo", EventData.EventType.BOSS)
	event_lib.entries = [monster_entry, boss_entry]
	return event_lib


func _make_template(event_id: String, event_type: EventData.EventType) -> EventData:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.event_type = event_type
	template.size = Vector2i.ONE
	return template


func _candidate(template: EventData) -> EventSpawnCandidate:
	var candidate := EventSpawnCandidateScript.new()
	candidate.event_data = template
	candidate.weight = 1
	return candidate


func _make_result(
	source_card: CardEntity,
	kind: BoardPlacementResult.Kind = BoardPlacementResult.Kind.CHAIN_EXTENDED,
	overlapped_event: EventInstance = null
) -> BoardPlacementResult:
	return BoardPlacementResult.new(kind, source_card, source_card, [source_card], [], overlapped_event)


func _make_card(board: Board, card_type: CardData.CardType) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	board.add_child(card)
	var data := CardData.new()
	data.card_type = card_type
	card.bind_instance(CardInstance.new(data))
	return card


func _attach_event(board: Board, instance: EventInstance, origin: Vector2i) -> BoardEvent:
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, board.cell_size)
	_expect(board.attach_event(event_node), "test event attaches to board")
	return event_node


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
