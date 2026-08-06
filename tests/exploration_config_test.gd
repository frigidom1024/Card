extends SceneTree

const RibwoodExplorationConfig := preload("res://data/levels/ribwood/exploration_config.tres")
const RibwoodSpawnConfig := preload("res://data/levels/ribwood/exploration_spawn_config.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_ribwood_references_level_spawn_profile()
	_test_ribwood_profile_uses_expected_pacing()
	quit(1 if _failure_count > 0 else 0)


func _test_ribwood_references_level_spawn_profile() -> void:
	_expect(RibwoodExplorationConfig != null, "Ribwood exploration config resource loads")
	_expect(RibwoodSpawnConfig != null, "Ribwood spawn config resource loads")
	if RibwoodExplorationConfig != null:
		_expect(
			RibwoodExplorationConfig.spawn_config == RibwoodSpawnConfig,
			"Ribwood exploration config references its dedicated spawn profile"
		)
		_expect(RibwoodExplorationConfig.boss_pursuit_enabled, "Ribwood explicitly enables configurable Boss pursuit")
		_expect(RibwoodExplorationConfig.cards_to_boss_surround == 2, "Ribwood surrounds after two extensions")
		_expect(RibwoodExplorationConfig.cards_to_boss_intercept == 2, "Ribwood intercepts after two more extensions")


func _test_ribwood_profile_uses_expected_pacing() -> void:
	if RibwoodSpawnConfig == null:
		return
	_expect(RibwoodSpawnConfig.initial_event_count_min == 3, "Ribwood starts with at least three visible events")
	_expect(RibwoodSpawnConfig.initial_event_count_max == 5, "Ribwood starts with at most five visible events")
	_expect(RibwoodSpawnConfig.placement_spawn_count_weights == {0: 60, 1: 30, 2: 10}, "Ribwood uses the configured 0/1/2 placement weights")
	_expect(RibwoodSpawnConfig.max_unresolved_events == 8, "Ribwood caps unresolved ordinary pacing events at eight")
	_expect(RibwoodSpawnConfig.boss_spawn_after_placements == 8, "Ribwood schedules the Boss after eight exploration placements")
	_expect(RibwoodSpawnConfig.validate().is_empty(), "Ribwood spawn profile validates without an EventLib lookup")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
