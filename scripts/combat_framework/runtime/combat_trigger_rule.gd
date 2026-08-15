class_name CombatTriggerRule
extends RefCounted

var observed_event_type: StringName = &""
var priority: int = 0
var registration_sequence: int = -1


func matches(event: CombatStateEvent, _snapshot: CombatStateSnapshot) -> bool:
	return observed_event_type == &"" or event.event_type == observed_event_type


func create_batch(
	_event: CombatStateEvent,
	_snapshot: CombatStateSnapshot
) -> CombatEffectBatch:
	return null
