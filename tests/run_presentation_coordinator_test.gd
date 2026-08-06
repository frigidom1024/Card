extends SceneTree

const PresentationPath := "res://scripts/game/run/run_presentation_coordinator.gd"


class RecordingHandTray:
	extends HandTray
	var last_count := -1
	var last_max_count := -1

	func set_hand_count(current_count: int, max_count: int) -> void:
		last_count = current_count
		last_max_count = max_count


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
	extends DragLayer
	var lock_requests: Array[bool] = []

	func set_interaction_locked(locked: bool) -> void:
		lock_requests.append(locked)
		interaction_locked = locked


var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_unconfigured_bind_is_rejected()
	_test_duplicate_bind_is_rejected()
	_test_hand_count_updates_tray()
	_test_player_state_sync_updates_crest()
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
		not presentation.bind(fixture.flow, fixture.modal, fixture.market),
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
			fixture.hand,
			fixture.hand_tray,
			fixture.crest,
			fixture.drag_layer,
			fixture.player,
			fixture.stats,
			fixture.faith
		),
		"configure accepts all required presentation dependencies"
	)
	_expect(presentation.bind(fixture.flow, fixture.modal, fixture.market), "first bind succeeds")
	_expect(
		not presentation.bind(fixture.flow, fixture.modal, fixture.market),
		"duplicate bind is rejected"
	)
	_cleanup_fixture(fixture)


func _test_hand_count_updates_tray() -> void:
	var presentation = _new_presentation()
	if presentation == null:
		return
	var fixture := _make_fixture()
	fixture.hand.cards.resize(4)
	fixture.hand.max_hand_size = 9
	_expect(_configure(presentation, fixture), "hand-count fixture configures")
	presentation.sync_all()
	_expect(fixture.hand_tray.last_count == 4, "sync_all synchronizes the current hand count")
	_expect(fixture.hand_tray.last_max_count == 9, "sync_all synchronizes the hand capacity")
	fixture.hand.cards.resize(6)
	fixture.hand.hand_count_changed.emit(6, 9)
	_expect(fixture.hand_tray.last_count == 6, "hand-count changes reach HandTray")
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
	fixture.market.player_state_changed.emit()
	_expect(fixture.crest.last_faith == 2, "faith changes synchronize the crest")
	_expect(fixture.crest.last_gold == 91, "market player-state changes synchronize gold")
	_expect(fixture.crest.last_hp == 11, "player-state changes synchronize vitality")
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
	for key in ["hand", "hand_tray", "crest", "drag_layer"]:
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
		fixture.hand,
		fixture.hand_tray,
		fixture.crest,
		fixture.drag_layer,
		fixture.player,
		fixture.stats,
		fixture.faith
	)


func _bind(presentation, fixture: Dictionary) -> bool:
	return (
		_configure(presentation, fixture)
		and presentation.bind(fixture.flow, fixture.modal, fixture.market)
	)


func _make_fixture() -> Dictionary:
	var hand := HandArea.new()
	var hand_tray := RecordingHandTray.new()
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
	var market := PersistentMarketCoordinator.new()
	return {
		"hand": hand,
		"hand_tray": hand_tray,
		"crest": crest,
		"drag_layer": drag_layer,
		"player": player,
		"stats": stats,
		"faith": faith,
		"flow": flow,
		"modal": modal,
		"market": market,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
