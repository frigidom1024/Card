extends SceneTree

const CONFIG_PATH := "res://data/levels/ribwood/exploration_config.tres"

var _failure_count := 0


func _init() -> void:
	var config := load(CONFIG_PATH) as ExplorationConfig
	_expect(config != null, "Ribwood exploration config resource loads")
	if config != null:
		_expect(
			config.scheduled_event_reveal_thresholds == [4, 8, 14, 20, 22],
			"Ribwood preserves its scheduled event thresholds"
		)
		_expect(config.boss_reveal_threshold == 24, "Ribwood reveals its Boss after 24 cells")
		_expect(
			config.get("boss_pursuit_enabled") == true,
			"Ribwood explicitly enables configurable Boss pursuit"
		)
		_expect(
			config.get("cards_to_boss_surround") == 2,
			"Ribwood moves the Boss to surrounding after two chain extensions"
		)
		_expect(
			config.get("cards_to_boss_intercept") == 2,
			"Ribwood moves the Boss to interception after two more chain extensions"
		)
		_expect(
			config.get("cards_to_boss_block") == null,
			"Ribwood no longer exposes the obsolete blocking threshold"
		)
		_expect(config.validate().is_empty(), "Ribwood exploration config validates")
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)