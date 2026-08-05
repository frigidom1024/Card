class_name EventInteractionController
extends RefCounted

## Owns the event-interaction lifecycle. Views and board changes remain external adapters.
signal interaction_started(instance: EventInstance)
signal interaction_finished(instance: EventInstance)
signal combat_result_ready(instance: EventInstance, result: CombatResult)

var _active_event: EventInstance
var _pending_combat_instance: EventInstance
var _pending_combat_result: CombatResult
var _combat_flow: EncounterCombatFlowCoordinator


func configure(combat_flow: EncounterCombatFlowCoordinator) -> void:
	_combat_flow = combat_flow
	_active_event = null
	_pending_combat_instance = null
	_pending_combat_result = null


func begin(instance: EventInstance, player_stats: CombatStats, chain: Array[CardInstance]) -> void:
	if instance == null or instance.is_resolved or _active_event != null:
		return
	_active_event = instance
	interaction_started.emit(instance)
	if instance.get_event_type() != EventData.EventType.MONSTER and instance.get_event_type() != EventData.EventType.BOSS:
		return
	if _combat_flow == null:
		return
	var monster := _combat_flow.begin(instance)
	if monster == null:
		_finish_active_interaction()
		return
	var result := _combat_flow.resolve(player_stats, chain, monster)
	if result == null:
		_finish_active_interaction()
		return
	_pending_combat_instance = instance
	_pending_combat_result = result
	combat_result_ready.emit(instance, result)


func close_shop() -> void:
	if _active_event == null or _active_event.get_event_type() != EventData.EventType.SHOP:
		return
	_finish_active_interaction()


func claim_treasure(_option_index: int) -> void:
	# Reward resolution is owned by the treasure adapter. This method reserves the lifecycle API.
	pass


func confirm_combat_settlement() -> void:
	if _pending_combat_instance == null or _pending_combat_result == null:
		return
	_pending_combat_instance = null
	_pending_combat_result = null
	_finish_active_interaction()


func get_active_event() -> EventInstance:
	return _active_event


func get_pending_combat_instance() -> EventInstance:
	return _pending_combat_instance


func get_pending_combat_result() -> CombatResult:
	return _pending_combat_result


func _finish_active_interaction() -> void:
	if _active_event == null:
		return
	var finished := _active_event
	_active_event = null
	interaction_finished.emit(finished)
