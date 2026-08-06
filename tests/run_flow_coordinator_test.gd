extends SceneTree

const RunFlowCoordinatorPath := "res://scripts/game/run/run_flow_coordinator.gd"

const STATE_UNINITIALIZED := 0
const STATE_EXPLORING := 1
const STATE_INTERACTING := 2
const STATE_FAILED := 3
const STATE_FINISHED := 4


class RecordingModal extends EventModalCoordinator:
	var begun_instances: Array[EventInstance] = []
	var completed_settlements := 0

	func begin(instance: EventInstance, _player_stats: CombatStats, _chain: Array[CardInstance]) -> void:
		begun_instances.append(instance)

	func complete_combat_settlement() -> void:
		completed_settlements += 1


class RecordingResolution extends EncounterResolutionCoordinator:
	var apply_result := true
	var applied_instances: Array[EventInstance] = []
	var emit_failure_on_defeat := false

	func apply(instance: EventInstance, result: CombatResult) -> bool:
		if not apply_result:
			return false
		applied_instances.append(instance)
		if emit_failure_on_defeat and result.outcome == CombatResult.Outcome.DEFEAT:
			exploration_failed.emit(result)
		return true


class RecordingExploration extends ExplorationCoordinator:
	var faith_echo_requests := 0

	func request_faith_echo() -> bool:
		faith_echo_requests += 1
		return true


class RecordingCardService extends RunCardService:
	var returned_cards: Array[CardEntity] = []
	var return_allow_overflow: Array[bool] = []

	func return_existing_to_hand(card: CardEntity, allow_overflow := false) -> bool:
		returned_cards.append(card)
		return_allow_overflow.append(allow_overflow)
		return true


var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_start_enters_exploring()
	_test_placement_contact_enters_interacting_and_begins_modal()
	_test_failed_settlement_keeps_interaction_and_modal_pending()
	_test_resolution_failure_enters_failed_once()
	_test_boss_victory_enters_finished()
	_test_faith_echo_and_guide_return_delegate_to_runtime_services()
	quit(1 if _failure_count > 0 else 0)


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

	_expect(flow.handle_combat_settlement_request(instance, defeat), "flow accepts applied defeat settlement")
	_expect(flow.get_state() == STATE_FAILED, "resolution failure enters failed state")
	_expect(failures == [defeat], "flow forwards resolution failure exactly once")
	_expect(
		fixture.modal.completed_settlements == 1,
		"applied defeat completes the modal before locking the failed run"
	)


func _test_boss_victory_enters_finished() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var finish_signals: Array[bool] = []
	flow.run_finished.connect(func() -> void: finish_signals.append(true))
	var boss := _event(EventData.EventType.BOSS)
	fixture.pipeline.event_interaction_requested.emit(boss)

	_expect(
		flow.handle_combat_settlement_request(boss, _result(CombatResult.Outcome.VICTORY)),
		"flow applies boss victory"
	)
	_expect(flow.get_state() == STATE_FINISHED, "boss victory finishes the run")
	_expect(finish_signals == [true], "flow emits one run-finished signal")
	_expect(not flow.accepts_placement(), "finished flow rejects placements")


func _test_faith_echo_and_guide_return_delegate_to_runtime_services() -> void:
	var fixture := _make_started_fixture()
	var flow = fixture.flow
	if flow == null:
		return
	var faith_values: Array[int] = []
	flow.faith_changed.connect(func(value: int) -> void: faith_values.append(value))
	fixture.faith.faith_changed.emit(2)
	fixture.faith.echo_spawn_requested.emit()

	var returned_card := CardEntity.new()
	fixture.board.card_return_requested.emit(returned_card)

	_expect(faith_values == [2], "flow forwards FaithService changes")
	_expect(
		fixture.exploration.faith_echo_requests == 1,
		"flow delegates faith echo spawning to exploration"
	)
	_expect(
		fixture.card_service.returned_cards == [returned_card],
		"flow delegates board guide return to the run card service"
	)
	_expect(
		fixture.card_service.return_allow_overflow == [true],
		"guide return permits the required hand overflow"
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


func _event(event_type: EventData.EventType) -> EventInstance:
	var data := EventData.new()
	data.event_id = "flow-test-%s" % EventData.EventType.keys()[event_type].to_lower()
	data.event_type = event_type
	return data.create_instance()


func _result(outcome: CombatResult.Outcome) -> CombatResult:
	var player_after := CombatStats.new()
	var monster_after := CombatStats.new()
	return CombatResult.new(outcome, player_after, monster_after, [], 0, [])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)