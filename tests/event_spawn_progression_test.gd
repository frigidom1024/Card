extends SceneTree

const EventSpawnCandidateScript := preload("res://scripts/game/exploration/event_spawn_candidate.gd")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")

var _failure_count := 0

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    _test_locked_candidate_has_no_effective_weight()
    _test_unlocked_candidate_gains_weight_over_time()
    quit(1 if _failure_count > 0 else 0)

func _test_locked_candidate_has_no_effective_weight() -> void:
    var candidate := EventSpawnCandidateScript.new()
    candidate.event_data = EventDataScript.new()
    candidate.weight = 20
    candidate.unlock_action_count = 4
    _expect(candidate.get_effective_weight(3) == 0, "locked event candidate has no effective weight")

func _test_unlocked_candidate_gains_weight_over_time() -> void:
    var candidate := EventSpawnCandidateScript.new()
    candidate.event_data = EventDataScript.new()
    candidate.weight = 5
    candidate.unlock_action_count = 4
    candidate.weight_per_action = 3
    _expect(candidate.get_effective_weight(4) == 5, "candidate starts at base weight when unlocked")
    _expect(candidate.get_effective_weight(6) == 11, "candidate weight grows with later actions")

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
