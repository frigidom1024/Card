class_name EventSpawnCandidate
extends Resource

## One weighted template candidate inside a level-specific exploration spawn pool.
@export var event_data: EventData
@export_range(1, 999, 1) var weight := 1
@export var allow_duplicate := true


func validate(event_lib: EventLib = null) -> String:
	if event_data == null:
		return "Event spawn candidate is missing event_data"
	if weight <= 0:
		return "Event spawn candidate weight must be positive"
	if event_lib != null and event_data not in event_lib.get_all_templates():
		return "Event spawn candidate must belong to the current EventLib"
	return ""
