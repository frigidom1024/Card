class_name EventSpawnCandidate
extends Resource

## One weighted template candidate inside a level-specific exploration spawn pool.
## `unlock_action_count` gates advanced residuals until enough ordinary cards
## have been placed; `weight_per_action` makes them progressively more common.
@export var event_data: EventData
@export_range(1, 999, 1) var weight := 1
@export_range(0, 999, 1) var unlock_action_count := 0
@export_range(0, 999, 1) var weight_per_action := 0
@export var allow_duplicate := true


func get_effective_weight(action_count: int) -> int:
    if action_count < unlock_action_count:
        return 0
    return weight + maxi(0, action_count - unlock_action_count) * weight_per_action


func validate(event_lib: EventLib = null) -> String:
    if event_data == null:
        return "Event spawn candidate is missing event_data"
    if weight <= 0:
        return "Event spawn candidate weight must be positive"
    if unlock_action_count < 0:
        return "Event spawn candidate unlock action count must be non-negative"
    if weight_per_action < 0:
        return "Event spawn candidate weight per action must be non-negative"
    if event_lib != null and event_data not in event_lib.get_all_templates():
        return "Event spawn candidate must belong to the current EventLib"
    return ""
