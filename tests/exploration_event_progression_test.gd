extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const ExplorationEventServiceScript := preload("res://scripts/game/exploration/exploration_event_service.gd")
const ExplorationSpawnConfigScript := preload("res://scripts/game/exploration/exploration_spawn_config.gd")
const EventSpawnCandidateScript := preload("res://scripts/game/exploration/event_spawn_candidate.gd")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const EventEntryScript := preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript := preload("res://scripts/game/event/core/event_lib.gd")
const RunProgressionConfigScript := preload("res://scripts/game/run/run_progression_config.gd")
const RunProgressionServiceScript := preload("res://scripts/game/run/run_progression_service.gd")

var _failure_count := 0

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    _test_event_choice_excludes_locked_high_tier_candidate()
    quit(1 if _failure_count > 0 else 0)

func _test_event_choice_excludes_locked_high_tier_candidate() -> void:
    var low := _make_event("low")
    var high := _make_event("high")
    var event_lib := EventLibScript.new()
    var low_entry := EventEntryScript.new()
    low_entry.event_data = low
    var high_entry := EventEntryScript.new()
    high_entry.event_data = high
    event_lib.entries = [low_entry, high_entry]
    var low_candidate := EventSpawnCandidateScript.new()
    low_candidate.event_data = low
    low_candidate.weight = 1
    var high_candidate := EventSpawnCandidateScript.new()
    high_candidate.event_data = high
    high_candidate.weight = 100
    high_candidate.unlock_action_count = 1
    var config := ExplorationSpawnConfigScript.new()
    config.initial_event_count_min = 0
    config.initial_event_count_max = 0
    config.placement_event_pool = [low_candidate, high_candidate]
    var progression := RunProgressionServiceScript.new()
    _expect(progression.configure(RunProgressionConfigScript.new()), "progression configures for event selection")
    var board := BoardScene.instantiate() as Board
    root.add_child(board)
    var service := ExplorationEventServiceScript.new()
    _expect(service.configure(event_lib, board, config, RandomNumberGenerator.new(), progression), "event service accepts progression")
    var chosen = service._choose_candidate(config.placement_event_pool)
    _expect(chosen == low_candidate, "locked high-tier residual is excluded before its action threshold")
    board.queue_free()

func _make_event(event_id: String) -> EventData:
    var event_data := EventDataScript.new()
    event_data.event_id = event_id
    event_data.event_type = EventData.EventType.MONSTER
    return event_data

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
