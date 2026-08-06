extends SceneTree

const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const EventEntryScript := preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript := preload("res://scripts/game/event/core/event_lib.gd")
const EventSpawnCandidateScript := preload("res://scripts/game/exploration/event_spawn_candidate.gd")
const ExplorationSpawnConfigScript := preload("res://scripts/game/exploration/exploration_spawn_config.gd")
const RibwoodSpawnConfig := preload("res://data/levels/ribwood/exploration_spawn_config.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_initial_range_rejects_min_above_max()
	_test_spawn_count_weights_reject_unsupported_count_and_empty_weight()
	_test_valid_profile_accepts_seeded_weighted_count()
	_test_dynamic_pool_rejects_boss_template()
	_test_ribwood_pool_excludes_boss_template()
	quit(1 if _failure_count > 0 else 0)


func _test_initial_range_rejects_min_above_max() -> void:
	var config = _make_valid_config()
	config.initial_event_count_min = 4
	config.initial_event_count_max = 2
	_expect(config.validate(_make_event_lib()) != "", "initial min above max is rejected")


func _test_spawn_count_weights_reject_unsupported_count_and_empty_weight() -> void:
	var config = _make_valid_config()
	config.placement_spawn_count_weights = {3: 1}
	_expect(config.validate(_make_event_lib()) != "", "unsupported dynamic spawn count is rejected")
	config.placement_spawn_count_weights = {0: 0, 1: 0, 2: 0}
	_expect(config.validate(_make_event_lib()) != "", "zero dynamic spawn weight is rejected")


func _test_valid_profile_accepts_seeded_weighted_count() -> void:
	var event_lib := _make_event_lib()
	var config = _make_valid_config()
	config.initial_event_pool.append(_make_candidate(event_lib.entries[0].event_data))
	config.placement_event_pool.append(_make_candidate(event_lib.entries[0].event_data))
	_expect(config.validate(event_lib).is_empty(), "valid spawn profile validates")
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 12345
	second_rng.seed = 12345
	_expect(
		config.get_spawn_count(first_rng) == config.get_spawn_count(second_rng),
		"weighted spawn count is reproducible with the same seed"
	)


func _test_dynamic_pool_rejects_boss_template() -> void:
	var event_lib := _make_event_lib()
	var config = _make_valid_config()
	config.initial_event_pool.append(_make_candidate(event_lib.entries[0].event_data))
	config.placement_event_pool.append(_make_candidate(event_lib.entries[1].event_data))
	_expect(config.validate(event_lib) != "", "Boss cannot enter the ordinary dynamic pool")


func _make_valid_config() -> ExplorationSpawnConfig:
	var config := ExplorationSpawnConfigScript.new()
	config.initial_event_count_min = 1
	config.initial_event_count_max = 2
	config.placement_spawn_count_weights = {0: 60, 1: 30, 2: 10}
	config.max_unresolved_events = 8
	config.boss_spawn_after_placements = 4
	return config


func _make_event_lib() -> EventLib:
	var event_lib := EventLibScript.new()
	var monster_entry := EventEntryScript.new()
	monster_entry.event_data = _make_template("normal_echo", EventData.EventType.MONSTER)
	var boss_entry := EventEntryScript.new()
	boss_entry.event_data = _make_template("boss_echo", EventData.EventType.BOSS)
	event_lib.entries = [monster_entry, boss_entry]
	return event_lib


func _make_template(event_id: String, event_type: EventData.EventType) -> EventData:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.event_type = event_type
	return template


func _make_candidate(template: EventData) -> EventSpawnCandidate:
	var candidate := EventSpawnCandidateScript.new()
	candidate.event_data = template
	candidate.weight = 1
	return candidate


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)



func _test_ribwood_pool_excludes_boss_template() -> void:
	_expect(RibwoodSpawnConfig != null, "Ribwood spawn config loads")
	if RibwoodSpawnConfig == null:
		return
	for candidate in RibwoodSpawnConfig.initial_event_pool:
		_expect(candidate.event_data.event_type != EventData.EventType.BOSS, "Ribwood initial pool excludes Boss")
	for candidate in RibwoodSpawnConfig.placement_event_pool:
		_expect(candidate.event_data.event_type != EventData.EventType.BOSS, "Ribwood dynamic pool excludes Boss")