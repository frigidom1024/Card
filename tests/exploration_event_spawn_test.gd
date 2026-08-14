extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const CardScene := preload("res://scenes/card/card.tscn")
const EventScene := preload("res://scenes/game/event.tscn")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const EventEntryScript := preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript := preload("res://scripts/game/event/core/event_lib.gd")
const EventSpawnCandidateScript := preload(
	"res://scripts/game/exploration/event_spawn_candidate.gd"
)
const ExplorationEventServiceScript := preload(
	"res://scripts/game/exploration/exploration_event_service.gd"
)
const ExplorationSpawnConfigScript := preload(
	"res://scripts/game/exploration/exploration_spawn_config.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_initial_spawn_uses_configured_count()
	await _test_placement_uses_weighted_count_and_skips_guide()
	await _test_dynamic_events_obey_unresolved_cap_and_space()
	await _test_boss_threshold_uses_exploration_placements_and_retries_pending_spawn()
	quit(1 if _failure_count > 0 else 0)


func _test_initial_spawn_uses_configured_count() -> void:
	var board := _make_board()
	var lib := _make_event_lib()
	var config := _make_spawn_config()
	config.initial_event_count_min = 2
	config.initial_event_count_max = 2
	config.initial_event_pool.append(_candidate(_normal_template(lib)))
	var service := ExplorationEventServiceScript.new()

	_expect(service.configure(lib, board, config, _seeded_rng()), "service configures for initial events")
	_expect(service.spawn_initial_events() == 2, "initial spawn uses configured count")
	var events := board.event_zone.get_events()
	_expect(events.size() == 2, "initial events are attached to BoardEventZone")
	for event_node: BoardEvent in events:
		_expect(
			not board.event_zone.can_attach_event(event_node.event_instance),
			"attached event origin is occupied"
		)
		_expect(event_node.event_instance.origin.x >= 0, "attached event has a board origin")
	await _free_board(board)


func _test_placement_uses_weighted_count_and_skips_guide() -> void:
	var board := _make_board()
	var lib := _make_event_lib()
	var config := _make_spawn_config()
	config.placement_spawn_count_weights = {0: 0, 1: 0, 2: 1}
	config.placement_event_pool.append(_candidate(_normal_template(lib)))
	var service := ExplorationEventServiceScript.new()
	_expect(service.configure(lib, board, config, _seeded_rng()), "service configures for dynamic events")

	var normal_card := _make_card(board, CardData.CardType.NORMAL)
	_expect(
		service.try_spawn_after_placement(_make_result(normal_card)) == 2,
		"placement can spawn two events"
	)
	_expect(board.event_zone.get_events().size() == 2, "two dynamic events are attached")
	_expect(
		service.get_exploration_placement_count() == 1,
		"ordinary placement increments exploration count"
	)

	var guide_card := _make_card(board, CardData.CardType.GUIDE)
	_expect(
		service.try_spawn_after_placement(_make_result(guide_card)) == 0,
		"guide placement does not generate events"
	)
	_expect(
		service.get_exploration_placement_count() == 1,
		"guide placement does not increment exploration count"
	)
	await _free_board(board)


func _test_dynamic_events_obey_unresolved_cap_and_space() -> void:
	var board := _make_board()
	var lib := _make_event_lib()
	var config := _make_spawn_config()
	config.max_unresolved_events = 1
	config.placement_spawn_count_weights = {0: 0, 1: 0, 2: 1}
	config.placement_event_pool.append(_candidate(_normal_template(lib)))
	var service := ExplorationEventServiceScript.new()
	_expect(service.configure(lib, board, config, _seeded_rng()), "service configures for event cap")
	var normal_card := _make_card(board, CardData.CardType.NORMAL)
	_expect(
		service.try_spawn_after_placement(_make_result(normal_card)) == 1,
		"dynamic events stop at unresolved cap"
	)
	_expect(board.event_zone.get_events().size() == 1, "event cap limits attached events")

	var filled_board := _make_board(1, 1)
	var filled_config := _make_spawn_config()
	filled_config.placement_spawn_count_weights = {0: 0, 1: 1, 2: 0}
	filled_config.placement_event_pool.append(_candidate(_normal_template(lib)))
	var filled_service := ExplorationEventServiceScript.new()
	_expect(
		filled_service.configure(lib, filled_board, filled_config, _seeded_rng()),
		"filled board service configures"
	)
	var occupied := _normal_template(lib).create_instance()
	occupied.origin = Vector2i.ZERO
	_expect(_attach_event(filled_board, occupied), "filled board contains an existing event")
	var filled_card := _make_card(filled_board, CardData.CardType.NORMAL)
	_expect(
		filled_service.try_spawn_after_placement(_make_result(filled_card)) == 0,
		"no legal space returns zero spawned events"
	)
	_expect(
		filled_board.event_zone.get_events().size() == 1,
		"failed placement leaves no unattached board event"
	)
	await _free_board(board)
	await _free_board(filled_board)


func _test_boss_threshold_uses_exploration_placements_and_retries_pending_spawn() -> void:
	var board := _make_board(1, 1)
	var lib := _make_event_lib()
	var config := _make_spawn_config()
	config.boss_spawn_after_placements = 2
	config.placement_spawn_count_weights = {0: 1, 1: 0, 2: 0}
	var service := ExplorationEventServiceScript.new()
	_expect(service.configure(lib, board, config, _seeded_rng()), "boss threshold service configures")

	var occupied := _normal_template(lib).create_instance()
	occupied.origin = Vector2i.ZERO
	_expect(_attach_event(board, occupied), "small board starts occupied")
	var root_card := _make_card(board, CardData.CardType.ROOT)
	_expect(
		service.try_spawn_after_placement(_make_result(root_card)) == 0,
		"first root placement does not reach Boss threshold"
	)
	_expect(not service.is_boss_spawned(), "Boss has not spawned before threshold")
	var normal_card := _make_card(board, CardData.CardType.NORMAL)
	_expect(
		service.try_spawn_after_placement(_make_result(normal_card)) == 0,
		"second normal placement attempts Boss spawn"
	)
	_expect(service.get_pending_boss(), "Boss becomes pending when no legal origin exists")
	_expect(not service.is_boss_spawned(), "pending Boss is not marked spawned")

	var attached_events := board.event_zone.get_events()
	_expect(board.remove_event(attached_events[0]), "occupied event is removed to free Boss space")
	var guide_card := _make_card(board, CardData.CardType.GUIDE)
	_expect(
		service.try_spawn_after_placement(_make_result(guide_card)) == 0,
		"guide does not retry pending Boss spawn"
	)
	_expect(service.get_pending_boss(), "guide leaves pending Boss unchanged")
	var retry_card := _make_card(board, CardData.CardType.NORMAL)
	_expect(
		service.try_spawn_after_placement(_make_result(retry_card)) == 0,
		"normal placement retries pending Boss spawn"
	)
	_expect(service.is_boss_spawned(), "Boss spawns after a later ordinary placement frees space")
	_expect(not service.get_pending_boss(), "Boss pending state clears after successful spawn")
	await _free_board(board)


func _make_board(width: int = 4, height: int = 4) -> Board:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	board.board_zone.back_ground.grid_width = width
	board.board_zone.back_ground.grid_height = height
	board.board_zone.sync_layout()
	return board


func _make_event_lib() -> EventLib:
	var lib := EventLibScript.new()
	lib.event_scene = EventScene
	var normal_entry := EventEntryScript.new()
	normal_entry.event_data = _make_template("normal_echo", EventData.EventType.MONSTER)
	var boss_entry := EventEntryScript.new()
	boss_entry.event_data = _make_template("boss_echo", EventData.EventType.BOSS)
	lib.entries = [normal_entry, boss_entry]
	return lib


func _make_template(event_id: String, event_type: EventData.EventType) -> EventData:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.event_type = event_type
	template.size = Vector2i.ONE
	return template


func _normal_template(lib: EventLib) -> EventData:
	return lib.entries[0].event_data


func _candidate(template: EventData, allow_duplicate: bool = true) -> EventSpawnCandidate:
	var candidate := EventSpawnCandidateScript.new()
	candidate.event_data = template
	candidate.allow_duplicate = allow_duplicate
	candidate.weight = 1
	return candidate


func _make_spawn_config() -> ExplorationSpawnConfig:
	var config := ExplorationSpawnConfigScript.new()
	config.initial_event_count_min = 0
	config.initial_event_count_max = 0
	config.placement_spawn_count_weights = {0: 1, 1: 0, 2: 0}
	config.max_unresolved_events = 8
	config.boss_spawn_after_placements = 99
	return config


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	return rng


func _make_result(source: Card) -> BoardPlacementResult:
	return BoardPlacementResult.new(
		BoardPlacementResult.Kind.CHAIN_EXTENDED,
		source,
		source,
		[source],
		[],
		null
	)


func _make_card(board: Board, card_type: CardData.CardType) -> Card:
	var card := CardScene.instantiate() as Card
	board.add_child(card)
	var data := CardData.new()
	data.card_type = card_type
	card.bind_card_inst(CardInstance.new(data))
	card.refresh_display()
	return card


func _attach_event(board: Board, instance: EventInstance) -> bool:
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, int(board.event_zone.cell_size))
	return board.attach_event(event_node)


func _free_board(board: Board) -> void:
	if board != null and is_instance_valid(board):
		board.queue_free()
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
