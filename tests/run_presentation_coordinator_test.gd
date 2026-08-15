extends SceneTree

const PresentationPath := "res://scripts/game/run/run_presentation_coordinator.gd"


class RecordingGameInfo:
	extends GameInfo
	var last_hp := -1
	var last_max_hp := -1
	var last_gold := -1
	var vitality_updates := 0
	var gold_updates := 0

	func set_vitality(current_hp: int, max_hp: int) -> void:
		last_hp = current_hp
		last_max_hp = max_hp
		vitality_updates += 1

	func set_gold(current_gold: int) -> void:
		last_gold = current_gold
		gold_updates += 1


class RecordingDragLayer:
	extends DraggerLayer


var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_unconfigured_bind_is_rejected()
	_test_duplicate_bind_is_rejected()
	_test_player_signals_update_game_info()
	_test_retraction_event_does_not_update_gold_display()
	_test_flow_completion_does_not_pull_player_state()
	_test_modal_lock_request_reaches_drag_layer()
	_test_failed_flow_cannot_unlock_input()
	_test_flow_terminal_signals_keep_input_locked()
	_test_finished_flow_cannot_unlock_input()
	quit(1 if _failure_count > 0 else 0)


func _test_unconfigured_bind_is_rejected() -> void:
	var presentation = _new_presentation()
	_expect(presentation != null, "RunPresentationCoordinator script exists")
	if presentation == null:
		return
	var fixture := _make_fixture()
	_expect(
		not presentation.bind(fixture.flow, fixture.modal),
		"bind rejects an unconfigured presentation coordinator"
	)
	_cleanup_fixture(fixture)


func _test_duplicate_bind_is_rejected() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	_expect(
		presentation.configure(
			fixture.game_info,
			fixture.drag_layer,
			fixture.player,
			fixture.stats
		),
		"configure accepts all required presentation dependencies"
	)
	_expect(presentation.bind(fixture.flow, fixture.modal), "first bind succeeds")
	_expect(
		not presentation.bind(fixture.flow, fixture.modal),
		"duplicate bind is rejected"
	)
	_cleanup_fixture(fixture)


func _test_player_signals_update_game_info() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	fixture.player.gold = 73
	fixture.stats.hp = 18
	fixture.stats.max_hp = 31
	_expect(_bind(presentation, fixture), "player-signal fixture binds")
	_expect(
		fixture.game_info.last_hp == 18 and fixture.game_info.last_max_hp == 31,
		"configuration immediately synchronizes player vitality"
	)
	_expect(fixture.game_info.last_gold == 73, "configuration immediately synchronizes player gold")

	fixture.player.add_gold(18)
	fixture.stats.set_vitality(11, 31)
	_expect(fixture.game_info.last_gold == 91, "gold signal updates GameInfo")
	_expect(fixture.game_info.last_hp == 11, "vitality signal updates GameInfo")
	_cleanup_fixture(fixture)


func _test_retraction_event_does_not_update_gold_display() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	fixture.player.gold = 10
	fixture.retraction.configure(fixture.player)
	_expect(_configure(presentation, fixture), "retraction fixture configures")
	_expect(fixture.game_info.last_gold == 10, "retraction fixture starts with current gold")
	fixture.retraction.retraction_cost_paid.emit(2, 1, 8)
	_expect(
		fixture.game_info.last_gold == 10,
		"business payment events do not write GameInfo directly"
	)
	fixture.player.spend_gold(2)
	_expect(fixture.game_info.last_gold == 8, "player gold signal updates the display")
	_cleanup_fixture(fixture)


func _test_flow_completion_does_not_pull_player_state() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	fixture.player.gold = 10
	_expect(_bind(presentation, fixture), "flow-completion fixture binds")
	var initial_gold_updates: int = fixture.game_info.gold_updates
	var initial_vitality_updates: int = fixture.game_info.vitality_updates
	fixture.player.gold = 99
	fixture.stats.hp = 1
	fixture.modal.non_combat_interaction_finished.emit(null)
	fixture.flow.combat_resolved.emit(null, null)
	_expect(fixture.game_info.last_gold == 10, "flow completion does not pull gold")
	_expect(fixture.game_info.last_hp == 20, "flow completion does not pull vitality")
	_expect(
		fixture.game_info.gold_updates == initial_gold_updates
		and fixture.game_info.vitality_updates == initial_vitality_updates,
		"flow completion publishes no redundant HUD updates"
	)
	_cleanup_fixture(fixture)


func _test_modal_lock_request_reaches_drag_layer() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	_expect(_bind(presentation, fixture), "lock fixture binds")
	fixture.modal.interaction_lock_changed.emit(true)
	_expect(presentation.is_input_locked(), "modal lock request locks input")
	fixture.modal.interaction_lock_changed.emit(false)
	_expect(
		not presentation.is_input_locked(),
		"modal unlock request unlocks input before terminal state"
	)
	_cleanup_fixture(fixture)


func _test_failed_flow_cannot_unlock_input() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	_expect(_bind(presentation, fixture), "failed-flow fixture binds")
	presentation.apply_flow_state(RunFlowCoordinator.State.FAILED)
	presentation.apply_lock_request(false)
	_expect(presentation.is_input_locked(), "FAILED flow state permanently keeps input locked")
	_cleanup_fixture(fixture)


func _test_flow_terminal_signals_keep_input_locked() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	_expect(_bind(presentation, fixture), "terminal-signal fixture binds")
	fixture.flow.exploration_failed.emit(null)
	presentation.apply_lock_request(false)
	_expect(presentation.is_input_locked(), "flow failure signal applies a permanent lock")

	var finished_presentation = _new_presentation()
	var finished_fixture := _make_fixture()
	_expect(_bind(finished_presentation, finished_fixture), "run-finished fixture binds")
	finished_fixture.flow.run_finished.emit()
	finished_presentation.apply_lock_request(false)
	_expect(finished_presentation.is_input_locked(), "run-finished signal keeps input locked")
	_cleanup_fixture(fixture)
	_cleanup_fixture(finished_fixture)


func _test_finished_flow_cannot_unlock_input() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	_expect(_bind(presentation, fixture), "finished-flow fixture binds")
	presentation.apply_flow_state(RunFlowCoordinator.State.FINISHED)
	presentation.apply_lock_request(false)
	_expect(presentation.is_input_locked(), "FINISHED flow state keeps input locked")
	_cleanup_fixture(fixture)


func _cleanup_fixture(fixture: Dictionary) -> void:
	for key in ["game_info", "drag_layer"]:
		var node = fixture.get(key)
		if node != null and is_instance_valid(node):
			node.free()


func _new_presentation():
	if not ResourceLoader.exists(PresentationPath):
		return null
	var script := load(PresentationPath) as GDScript
	return script.new() if script != null else null


func _configure(presentation, fixture: Dictionary) -> bool:
	if presentation == null:
		return false
	return presentation.configure(
		fixture.game_info,
		fixture.drag_layer,
		fixture.player,
		fixture.stats
	)


func _bind(presentation, fixture: Dictionary) -> bool:
	return (
		_configure(presentation, fixture)
		and presentation.bind(fixture.flow, fixture.modal)
	)


func _make_fixture() -> Dictionary:
	var game_info := RecordingGameInfo.new()
	var drag_layer := RecordingDragLayer.new()
	var player := PlayerData.new()
	var stats := CombatStats.new()
	stats.max_hp = 25
	stats.hp = 20
	var faith := FaithService.new()
	faith.configure(player)
	var flow := RunFlowCoordinator.new()
	var modal := EventModalCoordinator.new()
	var retraction := CardRetractionCostService.new()
	return {
		"game_info": game_info,
		"drag_layer": drag_layer,
		"player": player,
		"stats": stats,
		"faith": faith,
		"flow": flow,
		"modal": modal,
		"retraction": retraction,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)

