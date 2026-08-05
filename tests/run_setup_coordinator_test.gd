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
	await _test_initialize_creates_isolated_runtime_state()
	await _test_initialize_exposes_runtime_card_and_interaction_services()
	quit(1 if _failure_count > 0 else 0)


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
