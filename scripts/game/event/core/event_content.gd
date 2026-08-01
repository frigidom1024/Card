class_name EventContent
extends Resource

const EventRuntimeStateScript = preload("res://scripts/game/event/core/event_runtime_state.gd")


func create_runtime_state() -> EventRuntimeStateScript:
	return EventRuntimeStateScript.new()
