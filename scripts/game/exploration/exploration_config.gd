class_name ExplorationConfig
extends Resource

## Per-level exploration pacing. Keep this data next to the level EventLib.
@export var scheduled_event_reveal_thresholds: Array[int] = [4, 8, 14, 20, 22]
@export_range(1, 999, 1) var boss_reveal_threshold := 24
@export var boss_pursuit_enabled := true
@export_range(1, 99, 1) var cards_to_boss_surround := 2
@export_range(1, 99, 1) var cards_to_boss_intercept := 2


func validate() -> String:
	if boss_reveal_threshold <= 0:
		return "Boss reveal threshold must be positive"
	if cards_to_boss_surround <= 0 or cards_to_boss_intercept <= 0:
		return "Boss pressure thresholds must be positive"
	var previous := 0
	for threshold in scheduled_event_reveal_thresholds:
		if threshold <= previous:
			return "Event reveal thresholds must be strictly increasing"
		previous = threshold
	return ""
