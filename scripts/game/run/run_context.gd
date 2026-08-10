class_name RunContext
extends RefCounted

## Stable references to the mutable runtime graph for one game run.
##
## The backing fields are private by convention. Getter-only properties keep
## the existing context.player_data-style read syntax without allowing callers
## to replace the configured runtime graph.

var _player_data: PlayerData
var _player_stats: CombatStats
var _card_service: RunCardService
var _combat_flow: EncounterCombatFlowCoordinator
var _event_interaction_controller: EventInteractionController
var _random: RunRandomService
var _progression: RunProgressionService

var player_data: PlayerData:
	get:
		return _player_data

var player_stats: CombatStats:
	get:
		return _player_stats

var card_service: RunCardService:
	get:
		return _card_service

var combat_flow: EncounterCombatFlowCoordinator:
	get:
		return _combat_flow

var event_interaction_controller: EventInteractionController:
	get:
		return _event_interaction_controller

var random: RunRandomService:
	get:
		return _random

var progression: RunProgressionService:
	get:
		return _progression


func configure(
	player_data_value: PlayerData,
	player_stats_value: CombatStats,
	card_service_value: RunCardService,
	combat_flow_value: EncounterCombatFlowCoordinator,
	event_interaction_controller_value: EventInteractionController,
	random_value: RunRandomService,
	progression_value: RunProgressionService = null
) -> bool:
	if is_valid():
		return false
	if (
		player_data_value == null
		or player_stats_value == null
		or card_service_value == null
		or combat_flow_value == null
		or event_interaction_controller_value == null
		or random_value == null
	):
		return false
	_player_data = player_data_value
	_player_stats = player_stats_value
	_card_service = card_service_value
	_combat_flow = combat_flow_value
	_event_interaction_controller = event_interaction_controller_value
	_random = random_value
	_progression = progression_value
	return true


func is_valid() -> bool:
	return (
		_player_data != null
		and _player_stats != null
		and _card_service != null
		and _combat_flow != null
		and _event_interaction_controller != null
		and _random != null
	)
