extends SceneTree

const RunFlowCoordinatorPath := "res://scripts/game/run/run_flow_coordinator.gd"

const STATE_UNINITIALIZED := 0
const STATE_EXPLORING := 1
const STATE_INTERACTING := 2
const STATE_FAILED := 3
const STATE_FINISHED := 4


class RecordingModal:
	extends EventModalCoordinator
	var begun_instances: Array[EventInstance] = []
	var completed_settlements := 0
	var begun_chains: Array = []

	func begin(
		instance: EventInstance, _player_stats: CombatStats, _chain: Array[CardInstance]
	) -> void:
		begun_instances.append(instance)
		begun_chains.append(_chain.duplicate())

	func complete_combat_settlement() -> void:
		completed_settlements += 1


class RecordingResolution:
	extends EncounterResolutionCoordinator
	var apply_result := true
	var applied_instances: Array[EventInstance] = []
	var apply_count := 0
	var emit_failure_on_defeat := false
	var resolve_victory := false

	func apply(instance: EventInstance, result: CombatResult) -> bool:
		apply_count += 1
		if not apply_result:
			return false
		applied_instances.append(instance)
		if resolve_victory and result.outcome == CombatResult.Outcome.VICTORY:
			instance.resolve()
		if emit_failure_on_defeat and result.outcome == CombatResult.Outcome.DEFEAT:
			exploration_failed.emit(result)
		return true


class RecordingExploration:
	extends ExplorationCoordinator
	var faith_echo_requests := 0
	var dismissed_events: Array[EventInstance] = []

	func request_faith_echo() -> bool:
		faith_echo_requests += 1
		return true

	func dismiss_resolved_event(instance: EventInstance) -> bool:
		dismissed_events.append(instance)
		return true


class RecordingFaithEchoEndpoint:
	extends RefCounted
	var request_count := 0

	func request() -> bool:
		request_count += 1
		return true


class RecordingCardService:
	extends RunCardService
	var returned_cards: Array[Card] = []
	var return_allow_overflow: Array[bool] = []

	func return_existing_to_hand(card: Card, allow_overflow := false) -> bool:
		returned_cards.append(card)
		return_allow_overflow.append(allow_overflow)
		return true


var _failure_count := 0
var _fixture_boards: Array[Board] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_unconfigured_flow_cannot_start()
	_test_start_enters_exploring()
	_test_placement_contact_enters_interacting_and_begins_modal()
	_test_failed_settlement_keeps_interaction_and_modal_pending()
	_test_retreat_can_retry_same_encounter()
	_test_resolution_failure_enters_failed_once()
	_test_failed_boss_settlement_keeps_interaction_pending()
	_test_boss_victory_enters_finished()
	_test_resolved_non_boss_event_uses_cleanup_port()
	_test_faith_echo_is_forwarded_without_owning_guide_return()
	_test_explicit_faith_echo_port_overrides_pipeline_internals()
	_cleanup_fixtures()
	await process_frame
	quit(1 if _failure_count > 0 else 0)


func _test_unconfigured_flow_cannot_start() -> void:
	var flow_script = ResourceLoader.load(RunFlowCoordinatorPath)
	_expect(flow_script != null, "run-flow coordinator script exists for unconfigured start")
	if flow_script == null:
		return
	var flow = flow_script.new()
	_expect(not flow.start(), "unconfigured flow rejects start")
	_expect(flow.get_state() == STATE_UNINITIALIZED, "unconfigured flow remains uninitialized")


func _test_start_enters_exploring() -> void:
	var fixture := _make_fixture()
	var flow = fixture.flow
	_expect(flow != null, "run-flow coordinator script exists")
	if flow == null:
		return
	_expect(flow.get_state() == STATE_UNINITIALIZED, "new flow starts uninitialized")
	_expect(flow.start(), "flow starts exactly once")
	_expect(flow.get_state() == STATE_EXPLORING, "start enters exploration")
	_expect(flow.accepts_placement(), "exploring flow accepts placements")
	_expect(not flow.start(), "started flow rejects a second start")


func _test_placement_contact_enters_interacting_and_begins_modal() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var instance := _event(EventData.EventType.MONSTER)
	fixture.pipeline.event_interaction_requested.emit(instance)

	_expect(flow.get_state() == STATE_INTERACTING, "placement contact enters interaction")
	_expect(fixture.modal.begun_instances == [instance], "flow begins the contacted event modal")
	_expect(not flow.accepts_placement(), "interacting flow rejects additional placements")


func _test_failed_settlement_keeps_interaction_and_modal_pending() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var instance := _event(EventData.EventType.MONSTER)
	fixture.pipeline.event_interaction_requested.emit(instance)
	fixture.resolution.apply_result = false

	_expect(
		not flow.handle_combat_settlement_request(instance, _result(CombatResult.Outcome.VICTORY)),
		"flow rejects an unapplied combat settlement"
	)
	_expect(flow.get_state() == STATE_INTERACTING, "failed settlement keeps the interaction active")
	_expect(
		fixture.modal.completed_settlements == 0,
		"failed settlement does not complete the pending modal lifecycle"
	)
	fixture.resolution.apply_result = true
	_expect(
		flow.handle_combat_settlement_request(instance, _result(CombatResult.Outcome.VICTORY)),
		"a failed settlement can be confirmed again after the resolver recovers"
	)
	_expect(flow.get_state() == STATE_EXPLORING, "recovered settlement returns to exploration")


func _test_retreat_can_retry_same_encounter() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var instance := _event(EventData.EventType.MONSTER)
	var retreat := _result(CombatResult.Outcome.RETREAT)
	fixture.pipeline.event_interaction_requested.emit(instance)

	_expect(
		flow.handle_combat_settlement_request(instance, retreat),
		"first retreat settlement is accepted"
	)
	_expect(flow.get_state() == STATE_EXPLORING, "retreat returns the flow to exploration")
	_expect(fixture.modal.completed_settlements == 1, "first retreat completes the modal lifecycle")

	fixture.pipeline.event_interaction_requested.emit(instance)
	_expect(flow.get_state() == STATE_INTERACTING, "same encounter can be challenged again after retreat")
	_expect(
		flow.handle_combat_settlement_request(instance, retreat),
		"second retreat settlement is accepted"
	)
	_expect(fixture.modal.completed_settlements == 2, "second retreat completes the modal lifecycle")


func _test_resolution_failure_enters_failed_once() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var failures: Array[CombatResult] = []
	flow.exploration_failed.connect(func(result: CombatResult) -> void: failures.append(result))
	var instance := _event(EventData.EventType.MONSTER)
	fixture.pipeline.event_interaction_requested.emit(instance)
	fixture.resolution.emit_failure_on_defeat = true
	var defeat := _result(CombatResult.Outcome.DEFEAT)

	_expect(
		flow.handle_combat_settlement_request(instance, defeat),
		"flow accepts applied defeat settlement"
	)
	_expect(flow.get_state() == STATE_FAILED, "resolution failure enters failed state")
	_expect(failures == [defeat], "flow forwards resolution failure exactly once")
	_expect(
		fixture.modal.completed_settlements == 1,
		"applied defeat completes the modal before locking the failed run"
	)
	var placement_resolutions := 0
	fixture.pipeline.placement_resolved.connect(
		func(_result: BoardPlacementResult, _rules: int) -> void: placement_resolutions += 1
	)
	fixture.pipeline.resolve_placement(_placement_result())
	_expect(placement_resolutions == 0, "FAILED flow rejects new placement pipeline work")


func _test_failed_boss_settlement_keeps_interaction_pending() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var boss := _event(EventData.EventType.BOSS)
	var resolved_signals := 0
	var finish_signals := 0
	flow.combat_resolved.connect(func(_instance, _result) -> void: resolved_signals += 1)
	flow.run_finished.connect(func() -> void: finish_signals += 1)
	fixture.pipeline.event_interaction_requested.emit(boss)
	fixture.resolution.apply_result = false

	_expect(
		not flow.handle_combat_settlement_request(boss, _result(CombatResult.Outcome.VICTORY)),
		"failed Boss dismissal rejects the settlement at Flow boundary"
	)
	_expect(flow.get_state() == STATE_INTERACTING, "failed Boss dismissal keeps Flow interacting")
	_expect(fixture.modal.completed_settlements == 0, "failed Boss dismissal keeps Modal pending")
	_expect(resolved_signals == 0, "failed Boss dismissal emits no combat-resolved signal")
	_expect(finish_signals == 0, "failed Boss dismissal emits no run-finished signal")


func _test_boss_victory_enters_finished() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var finish_signals: Array[bool] = []
	var signal_order: Array[String] = []
	var signal_states: Array[bool] = []
	var reentry_state := {"attempts": 0, "result": true}
	var on_run_finished := func() -> void:
		signal_order.append("run_finished")
		signal_states.append(flow.get_state() == STATE_FINISHED)
		finish_signals.append(true)
	var on_combat_resolved := (
		func(resolved_instance: EventInstance, resolved_result: CombatResult) -> void:
			signal_order.append("combat_resolved")
			signal_states.append(
				flow.get_state() == STATE_FINISHED and fixture.modal.completed_settlements == 1
			)
			if reentry_state.attempts > 0:
				return
			reentry_state.attempts += 1
			reentry_state.result = flow.handle_combat_settlement_request(
				resolved_instance, resolved_result
			)
	)
	flow.run_finished.connect(on_run_finished)
	flow.combat_resolved.connect(on_combat_resolved)
	var boss := _event(EventData.EventType.BOSS)
	fixture.pipeline.event_interaction_requested.emit(boss)

	_expect(
		flow.handle_combat_settlement_request(boss, _result(CombatResult.Outcome.VICTORY)),
		"flow applies boss victory"
	)
	_expect(flow.get_state() == STATE_FINISHED, "boss victory finishes the run")
	_expect(
		not reentry_state.result, "combat-resolved listeners cannot reenter terminal settlement"
	)
	_expect(finish_signals == [true], "flow emits one run-finished signal")
	_expect(
		signal_order == ["combat_resolved", "run_finished"],
		"flow emits settlement signals in strict order"
	)
	_expect(
		signal_states == [true, true],
		"settlement listeners observe terminal state and completed modal"
	)
	_expect(
		fixture.resolution.apply_count == 1, "duplicate Boss settlement invokes resolution once"
	)
	_expect(
		not flow.handle_combat_settlement_request(boss, _result(CombatResult.Outcome.VICTORY)),
		"flow rejects a duplicate non-empty Boss settlement"
	)
	_expect(
		fixture.resolution.apply_count == 1, "duplicate Boss settlement does not reapply rewards"
	)
	_expect(finish_signals == [true], "duplicate Boss settlement does not re-emit run-finished")
	_expect(not flow.accepts_placement(), "finished flow rejects placements")
	var placement_resolutions := 0
	fixture.pipeline.placement_resolved.connect(
		func(_result: BoardPlacementResult, _rules: int) -> void: placement_resolutions += 1
	)
	fixture.pipeline.resolve_placement(_placement_result())
	_expect(placement_resolutions == 0, "FINISHED flow rejects new placement pipeline work")
	flow.run_finished.disconnect(on_run_finished)
	flow.combat_resolved.disconnect(on_combat_resolved)


func _test_resolved_non_boss_event_uses_cleanup_port() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var echo := _event(EventData.EventType.MONSTER)
	fixture.resolution.resolve_victory = true
	fixture.pipeline.event_interaction_requested.emit(echo)
	_expect(
		flow.handle_combat_settlement_request(echo, _result(CombatResult.Outcome.VICTORY)),
		"resolved residual echo settlement is accepted"
	)
	_expect(
		fixture.exploration.dismissed_events == [echo],
		"resolved residual echo is dismissed through Flow's explicit cleanup port"
	)


func _test_faith_echo_is_forwarded_without_owning_guide_return() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var faith_values: Array[int] = []
	flow.faith_changed.connect(func(value: int) -> void: faith_values.append(value))
	fixture.faith.faith_changed.emit(2)
	fixture.faith.echo_spawn_requested.emit()

	var returned_card := Card.new()
	fixture.board.card_return_requested.emit(returned_card)

	_expect(faith_values == [2], "flow forwards FaithService changes")
	_expect(
		fixture.exploration.faith_echo_requests == 1,
		"flow delegates faith echo spawning to exploration"
	)
	_expect(
		fixture.card_service.returned_cards.is_empty(),
		"RunFlow leaves Board card-return ownership to the page composition"
	)
	_expect(
		fixture.card_service.return_allow_overflow.is_empty(),
		"RunFlow does not choose hand overflow policy for page-level returns"
	)
	returned_card.free()


func _test_explicit_faith_echo_port_overrides_pipeline_internals() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var endpoint := RecordingFaithEchoEndpoint.new()
	_expect(flow.has_method("set_faith_echo_request"), "flow exposes an explicit faith-echo port")
	if not flow.has_method("set_faith_echo_request"):
		return
	_expect(
		flow.call("set_faith_echo_request", Callable(endpoint, "request")),
		"flow accepts the configured faith-echo port"
	)
	fixture.faith.echo_spawn_requested.emit()
	_expect(endpoint.request_count == 1, "flow invokes the configured faith-echo port")
	_expect(
		fixture.exploration.faith_echo_requests == 0,
		"flow does not reflect into PlacementPipelineCoordinator internals for faith echo"
	)


func _make_started_fixture() -> Dictionary:
	var fixture := _make_fixture()
	if fixture.flow != null:
		_expect(fixture.flow.start(), "fixture flow starts")
	return fixture


func _make_fixture() -> Dictionary:
	var flow_script = ResourceLoader.load(RunFlowCoordinatorPath)
	if flow_script == null:
		_expect(false, "run-flow coordinator script exists")
		return {"flow": null}

	var board := Board.new()
	var board_zone := BoardZone.new()
	board.add_child(board_zone)
	board.board_zone = board_zone
	_fixture_boards.append(board)
	var player := PlayerData.new()
	var player_stats := CombatStats.new()
	var card_service := RecordingCardService.new()
	var controller := EventInteractionController.new()
	var context := RunContext.new()
	_expect(
		context.configure(
			player,
			player_stats,
			card_service,
			EncounterCombatFlowCoordinator.new(),
			controller,
			RunRandomService.new()
		),
		"fixture configures run context"
	)

	var exploration := RecordingExploration.new()
	var pipeline := PlacementPipelineCoordinator.new()
	_expect(
		pipeline.configure(board, CardChainCoordinator.new(), exploration),
		"fixture configures placement pipeline"
	)
	var modal := RecordingModal.new()
	var resolution := RecordingResolution.new()
	var faith := FaithService.new()
	faith.configure(player)
	var flow = flow_script.new()
	_expect(
		flow.configure(context, pipeline, modal, resolution, faith, board),
		"flow configures all run dependencies"
	)
	if flow.has_method("set_faith_echo_request"):
		_expect(
			flow.call("set_faith_echo_request", Callable(exploration, "request_faith_echo")),
			"fixture configures the explicit faith-echo port"
		)
	_expect(
		flow.set_resolved_event_dismissal_request(Callable(exploration, "dismiss_resolved_event")),
		"fixture configures the explicit resolved-event cleanup port"
	)
	return {
		"board": board,
		"card_service": card_service,
		"exploration": exploration,
		"faith": faith,
		"flow": flow,
		"modal": modal,
		"pipeline": pipeline,
		"resolution": resolution,
	}


func _cleanup_fixtures() -> void:
	for board: Board in _fixture_boards:
		if is_instance_valid(board):
			board.free()
	_fixture_boards.clear()


func _event(event_type: EventData.EventType) -> EventInstance:
	var data := EventData.new()
	data.event_id = "flow-test-%s" % EventData.EventType.keys()[event_type].to_lower()
	data.event_type = event_type
	return data.create_instance()


func _placement_result() -> BoardPlacementResult:
	return BoardPlacementResult.new(BoardPlacementResult.Kind.CHAIN_EXTENDED, null, null, [], [])


func _result(outcome: CombatResult.Outcome) -> CombatResult:
	var player_after := CombatStats.new()
	var monster_after := CombatStats.new()
	return CombatResult.new(outcome, player_after, monster_after, [], 0, [])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
