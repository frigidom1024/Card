extends SceneTree

const RunSetupCoordinatorPath := "res://scripts/game/run/run_setup_coordinator.gd"
const CardManagerScript = preload("res://scripts/game/card_manager.gd")
const HandScene = preload("res://scenes/game/hand.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const BasePlayerData = preload("res://data/player/player_data.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_initialize_failure_clears_partial_runtime_state()
	await _test_initialize_creates_isolated_runtime_state()
	await _test_initialize_exposes_runtime_card_and_interaction_services()
	await _test_initialize_exposes_progression_service()
	quit(1 if _failure_count > 0 else 0)


func _test_initialize_failure_clears_partial_runtime_state() -> void:
	var fixture := _create_fixture()
	_expect(RevivalDeck.starter_cards.size() > 1, "failure fixture requires multiple starter cards")
	fixture.hand_area.max_hand_size = 1
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture, null)
		return

	_expect(
		coordinator.configure(
			fixture.source_player,
			RevivalDeck,
			fixture.card_manager,
			fixture.hand_area,
			fixture.drag_layer
		),
		"run setup accepts dependencies before a failure test"
	)
	_expect(not coordinator.initialize(), "run setup rejects a deck that cannot fully enter the hand")
	await process_frame
	_expect(fixture.hand_area.cards.is_empty(), "failed run setup cleans up the first created starter card")
	_expect(coordinator.get_context() == null, "failed run setup does not expose a context")
	_expect(coordinator.get_player_data() == null, "failed run setup clears runtime player data")
	_expect(coordinator.get_player_stats() == null, "failed run setup clears runtime combat stats")
	_expect(coordinator.get_card_service() == null, "failed run setup clears the card service")
	_expect(
		coordinator.get_encounter_combat_flow() == null,
		"failed run setup clears the encounter combat flow"
	)
	_expect(
		coordinator.get_event_interaction_controller() == null,
		"failed run setup clears the event interaction controller"
	)

	await _free_fixture(fixture, coordinator)

func _test_initialize_creates_isolated_runtime_state() -> void:
	var fixture := _create_fixture()
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture, null)
		return

	_expect(
		coordinator.configure(
			fixture.source_player,
			RevivalDeck,
			fixture.card_manager,
			fixture.hand_area,
			fixture.drag_layer
		),
		"run setup accepts valid runtime dependencies"
	)
	_expect(coordinator.initialize(), "run setup initializes a valid starting deck")

	var runtime_player: PlayerData = coordinator.get_player_data()
	_expect(runtime_player != null, "run setup exposes a runtime player")
	_expect(runtime_player != fixture.source_player, "run setup duplicates the static player resource")
	_expect(runtime_player.base_stats != fixture.source_player.base_stats, "run setup duplicates nested player stats")
	_expect(runtime_player.faith == PlayerData.INITIAL_FAITH, "run setup resets faith for a new run")
	_expect(fixture.source_player.faith == 0, "run setup does not mutate source player faith")
	_expect(coordinator.get_player_stats() != null, "run setup creates combat runtime stats")
	_expect(
		coordinator.get_player_stats().max_hp == runtime_player.base_stats.max_hp,
		"runtime combat stats use copied player base stats"
	)

	await _free_fixture(fixture, coordinator)


func _test_initialize_exposes_runtime_card_and_interaction_services() -> void:
	var fixture := _create_fixture()
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture, null)
		return

	_expect(
		coordinator.configure(
			fixture.source_player,
			RevivalDeck,
			fixture.card_manager,
			fixture.hand_area,
			fixture.drag_layer
		),
		"run setup accepts dependencies before service creation"
	)
	_expect(coordinator.initialize(), "run setup creates services for a valid deck")

	var card_service: RunCardService = coordinator.get_card_service()
	_expect(card_service != null, "run setup exposes the run card service")
	if card_service != null:
		_expect(
			card_service.get_instances().size() == RevivalDeck.starter_cards.size(),
			"run setup creates every starter card instance"
		)
		_expect(
			card_service.get_entities().size() == RevivalDeck.starter_cards.size(),
			"run setup creates every starter card entity"
		)
		_expect(
			card_service.get_entities().all(func(card: CardEntity) -> bool: return card in fixture.hand_area.cards),
			"run setup places every starter card in hand"
		)
	_expect(coordinator.get_encounter_combat_flow() != null, "run setup creates combat flow")
	_expect(coordinator.get_event_interaction_controller() != null, "run setup creates event interaction lifecycle")

	var context = coordinator.get_context()
	_expect(context != null, "run setup exposes a configured run context")
	if context != null:
		_expect(context.is_valid(), "run setup context is valid after initialization")
		_expect(context.player_data == coordinator.get_player_data(), "context shares runtime player with legacy getter")
		_expect(context.player_stats == coordinator.get_player_stats(), "context shares runtime stats with legacy getter")
		_expect(context.card_service == coordinator.get_card_service(), "context shares card service with legacy getter")
		_expect(context.combat_flow == coordinator.get_encounter_combat_flow(), "context shares combat flow with legacy getter")
		_expect(
			context.event_interaction_controller == coordinator.get_event_interaction_controller(),
			"context shares interaction controller with legacy getter"
		)

	await _free_fixture(fixture, coordinator)



func _test_initialize_exposes_progression_service() -> void:
	var fixture := _create_fixture()
	var coordinator = _create_coordinator()
	if coordinator == null:
		await _free_fixture(fixture, null)
		return
	_expect(
		coordinator.configure(
			fixture.source_player,
			RevivalDeck,
			fixture.card_manager,
			fixture.hand_area,
			fixture.drag_layer
		),
		"run setup accepts dependencies for progression wiring"
	)
	_expect(coordinator.initialize(), "run setup initializes progression wiring")
	var context = coordinator.get_context()
	_expect(context != null and context.progression != null, "run context exposes the run progression service")
	_expect(context != null and context.progression.get_action_count() == 0, "run progression starts at zero actions")
	await _free_fixture(fixture, coordinator)

func _create_coordinator():
	var coordinator_script = ResourceLoader.load(RunSetupCoordinatorPath)
	_expect(
		coordinator_script != null,
		"run setup coordinator script exists so GameManager can delegate run initialization"
	)
	return coordinator_script.new() if coordinator_script != null else null


func _create_fixture() -> Dictionary:
	var source_player := BasePlayerData.duplicate(true) as PlayerData
	source_player.faith = 0
	var card_manager := CardManagerScript.new()
	card_manager.card_scene = CardEntityScene
	var hand_area := HandScene.instantiate() as HandArea
	root.add_child(hand_area)
	var drag_layer := Node2D.new()
	root.add_child(drag_layer)
	return {
		"source_player": source_player,
		"card_manager": card_manager,
		"hand_area": hand_area,
		"drag_layer": drag_layer,
	}


func _free_fixture(fixture: Dictionary, coordinator) -> void:
	if coordinator != null:
		var card_service: RunCardService = coordinator.get_card_service()
		if card_service != null:
			card_service.clear()
	var hand_area: HandArea = fixture.hand_area
	var drag_layer: Node2D = fixture.drag_layer
	if is_instance_valid(hand_area):
		hand_area.queue_free()
	if is_instance_valid(drag_layer):
		drag_layer.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
