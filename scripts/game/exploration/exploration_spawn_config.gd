class_name ExplorationSpawnConfig
extends Resource

## Per-level pacing for immediately visible and placement-driven encounters.
@export_range(0, 20, 1) var initial_event_count_min := 3
@export_range(0, 20, 1) var initial_event_count_max := 5
@export var initial_event_pool: Array[EventSpawnCandidate] = []

## Keys are spawn counts (0, 1, or 2); values are their relative weights.
@export var placement_spawn_count_weights: Dictionary = {
	0: 60,
	1: 30,
	2: 10,
}
@export var placement_event_pool: Array[EventSpawnCandidate] = []

@export_range(1, 30, 1) var max_unresolved_events := 8
@export_range(1, 99, 1) var boss_spawn_after_placements := 8


func validate(event_lib: EventLib = null) -> String:
	if initial_event_count_min < 0 or initial_event_count_max < initial_event_count_min:
		return "Initial event count range is invalid"
	var count_weight_error := _validate_spawn_count_weights()
	if not count_weight_error.is_empty():
		return count_weight_error
	if max_unresolved_events <= 0:
		return "Maximum unresolved event count must be positive"
	if boss_spawn_after_placements <= 0:
		return "Boss spawn placement threshold must be positive"
	if initial_event_count_max > 0 and initial_event_pool.is_empty():
		return "Initial event pool is required when initial events can spawn"
	var initial_pool_error := _validate_pool(initial_event_pool, event_lib, false)
	if not initial_pool_error.is_empty():
		return initial_pool_error
	if _can_spawn_dynamic_events() and placement_event_pool.is_empty():
		return "Placement event pool is required when dynamic events can spawn"
	return _validate_pool(placement_event_pool, event_lib, true)


func get_spawn_count(rng: RandomNumberGenerator = null) -> int:
	var random := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	var total_weight := 0
	for count in [0, 1, 2]:
		total_weight += int(placement_spawn_count_weights.get(count, 0))
	if total_weight <= 0:
		return 0
	var roll := random.randi_range(1, total_weight)
	var cumulative := 0
	for count in [0, 1, 2]:
		cumulative += int(placement_spawn_count_weights.get(count, 0))
		if roll <= cumulative:
			return count
	return 0


func _validate_spawn_count_weights() -> String:
	var total_weight := 0
	for count_key in placement_spawn_count_weights:
		if not (count_key is int) or count_key < 0 or count_key > 2:
			return "Placement spawn count weights only support 0, 1, and 2"
		var weight_value = placement_spawn_count_weights[count_key]
		if not (weight_value is int) or weight_value < 0:
			return "Placement spawn count weights must be non-negative integers"
		total_weight += int(weight_value)
	if total_weight <= 0:
		return "Placement spawn count weights must have a positive total"
	return ""


func _validate_pool(
	pool: Array[EventSpawnCandidate],
	event_lib: EventLib,
	forbid_boss: bool
) -> String:
	for candidate in pool:
		if candidate == null:
			return "Event spawn pool cannot contain null candidates"
		var candidate_error := candidate.validate(event_lib)
		if not candidate_error.is_empty():
			return candidate_error
		if forbid_boss and candidate.event_data.event_type == EventData.EventType.BOSS:
			return "Boss events cannot enter the ordinary placement event pool"
	return ""


func _can_spawn_dynamic_events() -> bool:
	return int(placement_spawn_count_weights.get(1, 0)) > 0 \
		or int(placement_spawn_count_weights.get(2, 0)) > 0
