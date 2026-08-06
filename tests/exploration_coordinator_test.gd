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
const NextCardPointBonusRuleScript := preload(
	"res://scripts/combatv2/card/rules/next_card_point_bonus_rule.gd"
)

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_initial_events_are_visible_after_initialization()
	_test_root_and_normal_placements_generate_but_guide_does_not()
	_test_chain_extension_runs_all_card_rules_against_the_added_card()
	_test_boss_contact_uses_the_same_event_request_path_as_monster()
	_test_defeated_boss_is_removed_from_event_grid()
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


func _test_chain_extension_runs_all_card_rules_against_the_added_card() -> void:
	var board := _make_board()
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(
		coordinator.configure(_make_event_lib(), board, _make_config()),
		"coordinator configures card-chain rules"
	)
	var source := _make_card(board, CardData.CardType.NORMAL)
	var rule := NextCardPointBonusRuleScript.new()
	rule.bonus_points = 2
	source.card_instance.card_data.effect_rules.append(rule)
	var added := _make_card(board, CardData.CardType.NORMAL)
	added.card_instance.card_data.max_points = 1
	added.card_instance.reset_points()
	board.cards.append_array([source, added])

	coordinator.resolve_placement(_make_result(added))

	_expect(
		added.card_instance.current_points == 3,
		"chain extension resolves every in-chain CardRule against its newly added card"
	)
	_expect(
		source.card_instance.get_rule_trigger_count(0) == 1,
		"successful placement rule use is owned by its source card instance"
	)
	board.queue_free()


func _test_boss_contact_uses_the_same_event_request_path_as_monster() -> void:
	var board := _make_board()
	var event_lib := _make_event_lib()
	var config := _make_config()
	var coordinator := ExplorationCoordinatorScript.new()
	_expect(coordinator.configure(event_lib, board, config), "coordinator configures ordinary event interaction")
	var requested: Array[EventInstance] = []
	coordinator.event_interaction_requested.connect(func(instance: EventInstance) -> void:
		requested.append(instance)
	)
	var source_card := _make_card(board, CardData.CardType.NORMAL)
	var monster := _attach_event(board, event_lib.entries[0].event_data.create_instance(), Vector2i(0, 0))
	var boss := _attach_event(board, event_lib.entries[1].event_data.create_instance(), Vector2i(5, 4))
	coordinator.resolve_placement(_make_result(source_card, BoardPlacementResult.Kind.CHAIN_EXTENDED, monster.event_instance))
	coordinator.resolve_placement(_make_result(source_card, BoardPlacementResult.Kind.CHAIN_EXTENDED, boss.event_instance))
	_expect(requested == [monster.event_instance, boss.event_instance], "monster and Boss contact use the same ordinary event request signal")
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
