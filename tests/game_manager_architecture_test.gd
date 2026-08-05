extends SceneTree

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_manager.gd")
	_expect(not source.is_empty(), "GameManager source is available for structural regression checks")
	_expect(source.contains("func _configure_exploration() -> void:"), "GameManager names exploration setup as coordinator composition")
	_expect(not source.contains("func init_events"), "GameManager does not claim responsibility for direct event initialization")
	_expect(source.contains("var _exploration_coordinator: ExplorationCoordinator"), "GameManager holds exploration through the coordinator facade type")
	_expect(source.contains("ExplorationCoordinatorScript.new()"), "GameManager constructs only the exploration coordinator facade")
	_expect(not source.contains("FogService.new()"), "GameManager does not directly construct FogService")
	_expect(not source.contains("ExplorationEventService.new()"), "GameManager does not directly construct ExplorationEventService")
	_expect(not source.contains("BossPressureService.new()"), "GameManager does not directly construct BossPressureService")
	_expect(source.contains("RunSetupCoordinatorScript.new()"), "GameManager composes run initialization through RunSetupCoordinator")
	_expect(source.contains("var _run_setup"), "GameManager retains the run setup coordinator as a composition dependency")
	_expect(not source.contains("RunCardServiceScript.new()"), "GameManager does not construct runtime card ownership directly")
	_expect(not source.contains("EventInteractionControllerScript.new()"), "GameManager does not construct event interaction lifecycle directly")
	_expect(not source.contains("CombatStats.from_data(player_data.base_stats)"), "GameManager does not build run combat stats directly")
	_expect(source.contains("EncounterResolutionCoordinatorScript.new()"), "GameManager composes confirmed encounter settlement through EncounterResolutionCoordinator")
	_expect(not source.contains("func _apply_combat_result"), "GameManager does not apply combat results directly")
	_expect(not source.contains("func _strengthen_encounter_monster"), "GameManager does not own retreat monster strengthening")
	var threshold_array := RegEx.new()
	threshold_array.compile("(?m)^\\s*(?:var|const)\\s+\\w*(?:threshold|schedule)\\w*.*=\\s*\\[")
	_expect(threshold_array.search(source) == null, "GameManager does not own event threshold arrays")
	quit(1 if _failure_count > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
