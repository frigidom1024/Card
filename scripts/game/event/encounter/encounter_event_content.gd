class_name EncounterEventContent
extends EventContent


@export var mob: MobData = null
@export_range(1, 99, 1) var count := 1


func create_runtime_state() -> EncounterRuntimeState:
	return EncounterRuntimeState.new()
