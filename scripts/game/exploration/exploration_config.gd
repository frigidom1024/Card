class_name ExplorationConfig
extends Resource

const ExplorationSpawnConfigScript := preload("res://scripts/game/exploration/exploration_spawn_config.gd")
const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")

## Per-level exploration pacing. Keep this data next to the level EventLib.
@export var spawn_config: ExplorationSpawnConfig
@export var progression_config: RunProgressionConfig
@export var boss_pursuit_enabled := true
@export_range(1, 99, 1) var cards_to_boss_surround := 2
@export_range(1, 99, 1) var cards_to_boss_intercept := 2


func validate(event_lib: EventLib = null) -> String:
	if spawn_config == null:
		return "Exploration spawn config is required"
	var spawn_error := spawn_config.validate(event_lib)
	if not spawn_error.is_empty():
		return "Invalid exploration spawn config: %s" % spawn_error
	if progression_config != null and not progression_config.validate().is_empty():
		return "Invalid progression config: %s" % progression_config.validate()
	if cards_to_boss_surround <= 0 or cards_to_boss_intercept <= 0:
		return "Boss pressure thresholds must be positive"
	return ""
