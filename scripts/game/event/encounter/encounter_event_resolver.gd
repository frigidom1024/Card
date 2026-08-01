class_name EncounterEventResolver
extends RefCounted

const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")


func begin(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var event_type := instance.get_event_type()
	if event_type != EventDataScript.EventType.MONSTER and event_type != EventDataScript.EventType.BOSS:
		return null
	if instance.is_resolved:
		return null
	var content := instance.get_content() as EncounterEventContent
	if content == null:
		return null
	var mob := content.mob
	if mob == null or mob.base_stats == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	if state == null:
		return null
	if state.mob_instance != null:
		return state.mob_instance
	state.mob_instance = mob.create_instance()
	state.has_started = true
	return state.mob_instance
