class_name EncounterEventContent
extends EventContent

const EncounterRuntimeStateScript = preload("res://scripts/game/event/encounter/encounter_runtime_state.gd")

@export var mob: MobData = null
@export_range(1, 99, 1) var count := 1


func create_runtime_state() -> EncounterRuntimeStateScript:
	return EncounterRuntimeStateScript.new()
