extends SceneTree

const PresentationPath := "res://scripts/game/run/run_presentation_coordinator.gd"


class RecordingCrest:
	extends PilgrimCrestHud
	var last_hp := -1
	var last_max_hp := -1
	var last_faith := -1
	var last_gold := -1

	func set_vitality(current_hp: int, max_hp: int) -> void:
		last_hp = current_hp
		last_max_hp = max_hp

	func set_faith(current_faith: int) -> void:
		last_faith = current_faith

	func set_gold(current_gold: int) -> void:
		last_gold = current_gold


class RecordingDragLayer:
	extends DraggerLayer


var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_unconfigured_bind_is_rejected()
	_test_duplicate_bind_is_rejected()
	_test_player_state_sync_updates_crest()
	_test_retraction_cost_updates_gold_display()
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
			fixture.crest,
			fixture.drag_layer,
			fixture.player,
			fixture.stats,
			fixture.faith
		),
		"configure accepts all required presentation dependencies"
	)
	_expect(presentation.bind(fixture.flow, fixture.modal), "first bind succeeds")
	_expect(
		not presentation.bind(fixture.flow, fixture.modal),
		"duplicate bind is rejected"
	)
	_cleanup_fixture(fixture)


func _test_player_state_sync_updates_crest() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	fixture.player.gold = 73
	fixture.player.faith = 5
	fixture.stats.hp = 18
	fixture.stats.max_hp = 31
	_expect(_bind(presentation, fixture), "player-state fixture binds")
	presentation.sync_all()
	_expect(
		fixture.crest.last_hp == 18 and fixture.crest.last_max_hp == 31,
		"sync_all synchronizes player vitality"
	)
	_expect(fixture.crest.last_gold == 73, "sync_all synchronizes player gold")
	_expect(fixture.crest.last_faith == 5, "sync_all synchronizes player faith")

	fixture.player.gold = 91
	fixture.player.faith = 2
	fixture.stats.hp = 11
	fixture.faith.faith_changed.emit(2)
	presentation.sync_all()
	_expect(fixture.crest.last_faith == 2, "faith changes synchronize the crest")
	_expect(fixture.crest.last_gold == 91, "explicit presentation sync updates gold")
	_expect(fixture.crest.last_hp == 11, "explicit presentation sync updates vitality")
	_cleanup_fixture(fixture)


func _test_retraction_cost_updates_gold_display() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	fixture.player.gold = 10
	fixture.retraction.configure(fixture.player)
	_expect(
		presentation.configure(
			fixture.crest,
			fixture.drag_layer,
			fixture.player,
			fixture.stats,
			fixture.faith,
			fixture.retraction
		),
		"retraction-cost fixture configures"
	)
	presentation.sync_all()
	_expect(fixture.crest.last_gold == 10, "retraction fixture starts with current gold")
	fixture.retraction.retraction_cost_paid.emit(2, 1, 8)
	_expect(fixture.crest.last_gold == 8, "retraction cost updates the gold display immediately")
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
	for key in ["crest", "drag_layer"]:
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
		fixture.crest,
		fixture.drag_layer,
		fixture.player,
		fixture.stats,
		fixture.faith,
		fixture.retraction
	)


func _bind(presentation, fixture: Dictionary) -> bool:
	return (
		_configure(presentation, fixture)
		and presentation.bind(fixture.flow, fixture.modal)
	)


func _make_fixture() -> Dictionary:
	var crest := RecordingCrest.new()
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
		"crest": crest,
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

