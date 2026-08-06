class_name RunContext
extends RefCounted

## Stable references to the mutable runtime graph for one game run.
##
## The fields are intentionally exposed for read access by current GDScript
## callers. RunSetupCoordinator is the owner that configures this object once.

var player_data: PlayerData
var player_stats: CombatStats
var card_service: RunCardService
var combat_flow: EncounterCombatFlowCoordinator
var event_interaction_controller: EventInteractionController
var random: RunRandomService


func configure(
	player_data_value: PlayerData,
	player_stats_value: CombatStats,
	card_service_value: RunCardService,
	combat_flow_value: EncounterCombatFlowCoordinator,
	event_interaction_controller_value: EventInteractionController,
	random_value: RunRandomService
) -> bool:
	if (
		player_data_value == null
		or player_stats_value == null
		or card_service_value == null
		or combat_flow_value == null
		or event_interaction_controller_value == null
		or random_value == null
	):
		return false
	player_data = player_data_value
	player_stats = player_stats_value
	card_service = card_service_value
	combat_flow = combat_flow_value
	event_interaction_controller = event_interaction_controller_value
	random = random_value
	return true


func is_valid() -> bool:
	return (
		player_data != null
		and player_stats != null
		and card_service != null
		and combat_flow != null
		and event_interaction_controller != null
		and random != null
	)
