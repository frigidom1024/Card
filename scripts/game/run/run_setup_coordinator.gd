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
	_failure_reason = ""
	if _source_player == null or _source_player.base_stats == null:
		return _fail("Run setup is missing PlayerData.base_stats")
	if _starting_deck == null or not _starting_deck.validate().is_empty():
		return _fail("Run setup is missing a valid StartingDeckData")
	if _card_manager == null or _hand_area == null or _drag_layer == null:
		return _fail("Run setup is missing card runtime dependencies")

	_runtime_player = _source_player.duplicate(true) as PlayerData
	if _runtime_player == null or _runtime_player.base_stats == null:
		return _fail("Run setup could not duplicate PlayerData")
	_runtime_player.faith = PlayerData.INITIAL_FAITH

	_player_stats = CombatStats.from_data(_runtime_player.base_stats)
	if _player_stats == null:
		return _fail("Run setup could not create runtime combat stats")

	_card_service = RunCardServiceScript.new()
	if not _card_service.configure(_card_manager, _hand_area, _drag_layer):
		return _fail("Run setup could not configure runtime card service")
	if not _card_service.initialize_starting_deck(_starting_deck):
		_card_service.clear()
		return _fail("Run setup could not create configured starter cards")

	var root_card := _starting_deck.get_root_card()
	_encounter_combat_flow = EncounterCombatFlowCoordinator.new(_create_combat_service_for_root(root_card))
	_event_interaction_controller = EventInteractionControllerScript.new()
	_event_interaction_controller.configure(_encounter_combat_flow)
	return true


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


func _fail(reason: String) -> bool:
	_failure_reason = reason
	initialization_failed.emit(reason)
	return false
