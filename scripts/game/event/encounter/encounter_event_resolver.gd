class_name EncounterEventResolver
extends RefCounted


func begin(instance: EventInstance) -> MobInstance:
	if instance == null:
		return null
	var content := instance.get_content() as EncounterEventContent
	if content == null or content.mob == null:
		return null
	var state := instance.runtime_state as EncounterRuntimeState
	if state == null:
		return null
	if state.mob_instance != null:
		return state.mob_instance
	state.mob_instance = content.mob.create_instance()
	state.has_started = true
	return state.mob_instance
