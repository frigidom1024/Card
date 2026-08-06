class_name RunSetupCoordinator
extends RefCounted

## Builds the mutable state required by one game run.
##
## This coordinator owns no scene policy beyond assigning starter cards to the
## supplied hand. GameManager remains responsible for composing its FaithService
## after retrieving the isolated runtime PlayerData.
signal initialization_failed(reason: String)

const RunCardServiceScript := preload("res://scripts/game/run/run_card_service.gd")
const EventInteractionControllerScript := preload("res://scripts/game/event/event_interaction_controller.gd")
const RunContextScript := preload("res://scripts/game/run/run_context.gd")
const RunRandomServiceScript := preload("res://scripts/game/run/run_random_service.gd")

var _source_player: PlayerData
var _starting_deck: StartingDeckData
var _card_manager: Node2D
var _hand_area: HandArea
var _drag_layer: Node2D

var _runtime_player: PlayerData
var _player_stats: CombatStats
var _card_service: RunCardService
var _encounter_combat_flow: EncounterCombatFlowCoordinator
var _event_interaction_controller: EventInteractionController
var _context: RunContext
var _failure_reason := ""


func configure(
	source_player: PlayerData,
	deck: StartingDeckData,
	card_manager: Node2D,
	hand_area: HandArea,
	drag_layer: Node2D
) -> bool:
	if source_player == null or deck == null or card_manager == null or hand_area == null or drag_layer == null:
		return false
	_source_player = source_player
	_starting_deck = deck
	_card_manager = card_manager
	_hand_area = hand_area
	_drag_layer = drag_layer
	return true


func initialize() -> bool:
	_clear_runtime_state()
	_failure_reason = ""
	if _source_player == null or _source_player.base_stats == null:
		return _fail("Run setup is missing PlayerData.base_stats")
	if _starting_deck == null or not _starting_deck.validate().is_empty():
		return _fail("Run setup is missing a valid StartingDeckData")
	if _card_manager == null or _hand_area == null or _drag_layer == null:
		return _fail("Run setup is missing card runtime dependencies")

	var runtime_player := _source_player.duplicate(true) as PlayerData
	if runtime_player == null or runtime_player.base_stats == null:
		return _fail("Run setup could not duplicate PlayerData")
	runtime_player.faith = PlayerData.INITIAL_FAITH

	var player_stats := CombatStats.from_data(runtime_player.base_stats)
	if player_stats == null:
		return _fail("Run setup could not create runtime combat stats")

	var card_service: RunCardService = RunCardServiceScript.new()
	if not card_service.configure(_card_manager, _hand_area, _drag_layer):
		return _fail("Run setup could not configure runtime card service", card_service)
	if not card_service.initialize_starting_deck(_starting_deck):
		return _fail("Run setup could not create configured starter cards", card_service)

	var root_card := _starting_deck.get_root_card()
	var combat_flow := EncounterCombatFlowCoordinator.new(_create_combat_service_for_root(root_card))
	var event_interaction_controller: EventInteractionController = EventInteractionControllerScript.new()
	event_interaction_controller.configure(combat_flow)

	var random: RunRandomService = RunRandomServiceScript.new()
	var context: RunContext = RunContextScript.new()
	if not context.configure(
		runtime_player,
		player_stats,
		card_service,
		combat_flow,
		event_interaction_controller,
		random
	):
		return _fail("Run setup could not configure RunContext", card_service)

	_runtime_player = runtime_player
	_player_stats = player_stats
	_card_service = card_service
	_encounter_combat_flow = combat_flow
	_event_interaction_controller = event_interaction_controller
	_context = context
	return true


func get_context() -> RunContext:
	return _context


func get_player_data() -> PlayerData:
	return _runtime_player


func get_player_stats() -> CombatStats:
	return _player_stats


func get_card_service() -> RunCardService:
	return _card_service


func get_encounter_combat_flow() -> EncounterCombatFlowCoordinator:
	return _encounter_combat_flow


func get_event_interaction_controller() -> EventInteractionController:
	return _event_interaction_controller


func get_failure_reason() -> String:
	return _failure_reason


## Extension point for future root-specific combat services.
func _create_combat_service_for_root(_root_card: CardData) -> CombatService2:
	return CombatService2.new()


func _clear_runtime_state() -> void:
	if _card_service != null:
		_card_service.clear()
	_runtime_player = null
	_player_stats = null
	_card_service = null
	_encounter_combat_flow = null
	_event_interaction_controller = null
	_context = null


func _fail(reason: String, partial_card_service: RunCardService = null) -> bool:
	if partial_card_service != null:
		partial_card_service.clear()
	_clear_runtime_state()
	_failure_reason = reason
	initialization_failed.emit(reason)
	return false
