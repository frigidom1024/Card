extends SceneTree

const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const EventEntryScript := preload("res://scripts/game/event/core/event_entry.gd")
const EventLibScript := preload("res://scripts/game/event/core/event_lib.gd")
const EventSpawnCandidateScript := preload("res://scripts/game/exploration/event_spawn_candidate.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_default_candidate_is_invalid()
	_test_positive_weight_and_template_are_valid()
	_test_candidate_rejects_template_outside_current_event_lib()
	quit(1 if _failure_count > 0 else 0)


func _test_default_candidate_is_invalid() -> void:
	var candidate := EventSpawnCandidateScript.new()
	_expect(candidate.validate(null) != "", "empty candidate fails validation")


func _test_positive_weight_and_template_are_valid() -> void:
	var event_lib := _make_event_lib_with_template("ribwood_rat")
	var candidate := EventSpawnCandidateScript.new()
	candidate.event_data = event_lib.entries[0].event_data
	candidate.weight = 10
	_expect(candidate.validate(event_lib).is_empty(), "candidate with a template in the current EventLib is valid")


func _test_candidate_rejects_template_outside_current_event_lib() -> void:
	var event_lib := _make_event_lib_with_template("ribwood_rat")
	var outside_template := _make_event_template("other_level_event")
	var candidate := EventSpawnCandidateScript.new()
	candidate.event_data = outside_template
	candidate.weight = 1
	_expect(candidate.validate(event_lib) != "", "candidate rejects a template outside the current EventLib")


func _make_event_lib_with_template(event_id: String) -> EventLib:
	var event_lib := EventLibScript.new()
	var entry := EventEntryScript.new()
	entry.event_data = _make_event_template(event_id)
	event_lib.entries = [entry]
	return event_lib


func _make_event_template(event_id: String) -> EventData:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.event_type = EventData.EventType.MONSTER
	return template


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
