extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const BasePlayerData = preload("res://data/player/player_data.tres")
const StartingDeckDataScript = preload("res://scripts/run/starting_deck_data.gd")
const CardScene = preload("res://scenes/card/card.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_valid_preset_initializes_isolated_run_state()
	_test_invalid_preset_is_rejected_before_scene_entry()
	quit(1 if _failure_count > 0 else 0)


func _test_valid_preset_initializes_isolated_run_state() -> void:
	var manager = GameManagerScene.instantiate()
	_expect(
		manager.configure_run(RevivalDeck),
		"valid preset is accepted before GameManager enters the tree"
	)
	_expect(
		not manager.configure_run(RevivalDeck),
		"GameManager rejects a second run configuration before scene entry"
	)
	root.add_child(manager)
	await process_frame

	_expect(
		manager.cards_inst.size() == RevivalDeck.starter_cards.size(),
		"run creates exactly every configured starter card"
	)

	var run_card_service = manager.get("_run_card_service")
	_expect(
		run_card_service != null, "GameManager composes a dedicated runtime card ownership service"
	)
	if run_card_service != null:
		_expect(
			run_card_service.get_instances() == manager.cards_inst,
			"GameManager exposes the card instances owned by its runtime card service"
		)
		_expect(
			run_card_service.get_entities() == manager.card_entities,
			"GameManager exposes the card entities owned by its runtime card service"
		)
	_expect(_count_roots(manager.cards_inst) == 1, "run creates exactly one root card")
	for index in range(RevivalDeck.starter_cards.size()):
		_expect(
			manager.cards_inst[index].card_data == RevivalDeck.starter_cards[index],
			"run preserves configured starter order at index %d" % index
		)

	_expect(manager.player_data != BasePlayerData, "run owns a copied PlayerData resource")
	_expect(
		manager.player_data.base_stats != BasePlayerData.base_stats,
		"run owns a copied nested CombatStatsData resource"
	)
	manager.player_data.gold = 1
	_expect(
		BasePlayerData.gold == 30, "run gold changes do not mutate the static PlayerData resource"
	)
	var run_setup = manager.get("_run_setup")
	_expect(run_setup != null, "GameManager composes the run-setup coordinator")
	if run_setup != null:
		_expect(
			run_setup.get_encounter_combat_flow() != null,
			"run setup creates the encounter combat flow used by event interaction"
		)
	_expect(manager.has_method("get_run_context"), "GameManager exposes the composed RunContext")
	_expect(
		manager.has_method("get_run_flow"), "GameManager exposes the composed RunFlowCoordinator"
	)
	var context: RunContext = (
		manager.get_run_context() if manager.has_method("get_run_context") else null
	)
	var flow: RunFlowCoordinator = (
		manager.get_run_flow() if manager.has_method("get_run_flow") else null
	)
	_expect(context != null, "GameManager obtains the runtime graph from RunSetupCoordinator")
	_expect(flow != null, "GameManager configures a run-flow coordinator")
	if context != null:
		_expect(
			context.player_data == manager.player_data, "GameManager reuses RunContext PlayerData"
		)
		_expect(
			context.player_stats == manager.player_stats,
			"GameManager reuses RunContext CombatStats"
		)
		_expect(
			context.card_service == run_card_service, "GameManager reuses RunContext card service"
		)
	if flow != null:
		_expect(
			flow.get_state() == RunFlowCoordinator.State.EXPLORING,
			"configured run flow enters EXPLORING exactly once"
		)
	var placement_connections: Array = manager.board.placement_committed.get_connections()
	_expect(
		placement_connections.size() == 1, "Board placement has exactly one production subscriber"
	)
	if placement_connections.size() == 1:
		var placement_subscriber: Object = placement_connections[0].callable.get_object()
		_expect(
			placement_subscriber is PlacementPipelineCoordinator,
			"PlacementPipelineCoordinator is the sole Board placement subscriber"
		)
		_expect(
			not placement_subscriber is CardChainCoordinator,
			"CardChainCoordinator does not subscribe to Board placements directly"
		)
	var return_connections: Array = manager.board.card_return_requested.get_connections()
	_expect(
		return_connections.size() == 1,
		"Board card return has exactly one page-level subscriber"
	)
	if return_connections.size() == 1:
		_expect(
			return_connections[0].callable == Callable(manager, "_on_board_card_return_requested"),
			"GameManager is the sole Board card-return subscriber"
		)
	var exploration_coordinator = manager.get("_exploration_coordinator")
	_expect(
		exploration_coordinator != null, "GameManager creates a dedicated exploration coordinator"
	)
	var interaction_controller = manager.get("_event_interaction_controller")
	_expect(
		interaction_controller != null,
		"GameManager creates an event interaction lifecycle controller"
	)
	_expect(
		not manager.board.has_signal("event_interaction_requested"),
		"Board no longer exposes a direct event-interaction signal"
	)
	_expect(
		not manager.board.event_zone.get_events().is_empty(),
		"run setup immediately pre-spawns the configured level events"
	)
	var returned_guide := _make_guide_card()
	var returned_instance := returned_guide.get_card_inst()
	manager.add_child(returned_guide)
	manager._on_board_card_return_requested(returned_guide)
	_expect(
		manager.hand_zone.owns_card(returned_guide),
		"GameManager returns guide cards through HandZone"
	)
	_expect(
		returned_guide.get_card_inst() == returned_instance,
		"returning a guide preserves its exact CardInstance"
	)

	manager.free()
	await process_frame


func _test_invalid_preset_is_rejected_before_scene_entry() -> void:
	var invalid_preset = StartingDeckDataScript.new()
	var manager = GameManagerScene.instantiate()
	_expect(
		not manager.configure_run(invalid_preset),
		"invalid preset is rejected before GameManager enters the tree"
	)
	manager.free()


func _make_guide_card() -> Card:
	var card := CardScene.instantiate() as Card
	var data := CardData.new()
	data.card_type = CardData.CardType.GUIDE
	data.card_name = "Guide"
	card.bind_card_inst(CardInstance.new(data))
	return card


func _count_roots(cards: Array) -> int:
	var count := 0
	for card in cards:
		if (
			card != null
			and card.card_data != null
			and card.card_data.card_type == CardData.CardType.ROOT
		):
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
