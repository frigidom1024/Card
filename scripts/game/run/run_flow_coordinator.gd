class_name RunFlowCoordinator
extends RefCounted

## Owns the cross-domain lifecycle for one game run.
##
## EncounterResolutionCoordinator remains on its current exploration-coupled
## interface in this task. The faith-echo bridge is intentionally isolated so
## Task 4 can replace it with an explicit narrow port without changing Flow's
## signal wiring or state transitions.

enum State { UNINITIALIZED, EXPLORING, INTERACTING, FAILED, FINISHED }

signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_resolved(instance: EventInstance, result: CombatResult)
signal exploration_failed(result: CombatResult)
signal run_finished
signal state_changed(state: State)
signal faith_changed(current_faith: int)

var _context: RunContext
var _pipeline: PlacementPipelineCoordinator
var _modal: EventModalCoordinator
var _resolution: EncounterResolutionCoordinator
var _faith: FaithService
var _board: Board
var _faith_echo_request: Callable
var _state := State.UNINITIALIZED
var _configured := false
var _settlement_in_progress := false
var _settled_instances: Array[EventInstance] = []
var _finished_event: EventInstance


func configure(
	context: RunContext,
	pipeline: PlacementPipelineCoordinator,
	modal: EventModalCoordinator,
	resolution: EncounterResolutionCoordinator,
	faith: FaithService = null,
	board: Board = null
) -> bool:
	if (
		context == null
		or pipeline == null
		or modal == null
		or resolution == null
		or board == null
	):
		return false
	if not context.is_valid():
		return false
	_disconnect_signals()
	_configured = false
	_settlement_in_progress = false
	_finished_event = null
	_settled_instances.clear()
	_context = context
	_pipeline = pipeline
	_modal = modal
	_resolution = resolution
	_faith = faith
	_board = board
	_faith_echo_request = Callable()
	_state = State.UNINITIALIZED
	if not _pipeline.set_placement_guard(Callable(self, "accepts_placement")):
		_context = null
		_pipeline = null
		_modal = null
		_resolution = null
		_faith = null
		_board = null
		return false
	_connect_signals()
	_configured = true
	return true


func set_faith_echo_request(request: Callable) -> bool:
	if not request.is_valid():
		return false
	_faith_echo_request = request
	return true


func start() -> bool:
	if not _configured or _state != State.UNINITIALIZED:
		return false
	_set_state(State.EXPLORING)
	return true


func get_state() -> State:
	return _state


func accepts_placement() -> bool:
	return _configured and _state == State.EXPLORING


func resolve_placement(result: BoardPlacementResult) -> bool:
	if not accepts_placement() or result == null:
		return false
	_pipeline.resolve_placement(result)
	return true


func handle_combat_settlement_request(instance: EventInstance, result: CombatResult) -> bool:
	if (
		not _configured
		or _state != State.INTERACTING
		or _settlement_in_progress
		or instance == null
		or result == null
		or instance in _settled_instances
	):
		return false
	_settlement_in_progress = true
	if not _resolution.apply(instance, result):
		_settlement_in_progress = false
		return false
	_settled_instances.append(instance)

	var is_boss_victory := (
		instance.get_event_type() == EventData.EventType.BOSS
		and result.outcome == CombatResult.Outcome.VICTORY
	)
	if _state == State.FAILED or result.outcome == CombatResult.Outcome.DEFEAT:
		if _state != State.FAILED:
			_enter_failed(result)
	else:
		_set_state(State.FINISHED if is_boss_victory else State.EXPLORING)
		if is_boss_victory:
			_finished_event = instance

	# State is terminal/exploring before this synchronous controller signal so
	# presentation unlock requests cannot race the lifecycle transition.
	_modal.complete_combat_settlement()
	if _state == State.FAILED:
		# Completing the controller releases its normal lock, so retain it terminally.
		_modal.lock_interaction()
	combat_resolved.emit(instance, result)
	if is_boss_victory and _finished_event == instance:
		run_finished.emit()
	_settlement_in_progress = false
	return true


func handle_card_return_requested(card: CardEntity) -> bool:
	if _context == null or _context.card_service == null or card == null:
		return false
	return _context.card_service.return_existing_to_hand(card, true)


func _connect_signals() -> void:
	if not _pipeline.event_interaction_requested.is_connected(_on_event_interaction_requested):
		_pipeline.event_interaction_requested.connect(_on_event_interaction_requested)
	if not _modal.combat_settlement_confirmed.is_connected(handle_combat_settlement_request):
		_modal.combat_settlement_confirmed.connect(handle_combat_settlement_request)
	if not _modal.non_combat_interaction_finished.is_connected(_on_non_combat_interaction_finished):
		_modal.non_combat_interaction_finished.connect(_on_non_combat_interaction_finished)
	if not _modal.combat_started.is_connected(_forward_combat_started):
		_modal.combat_started.connect(_forward_combat_started)
	if not _resolution.exploration_failed.is_connected(_on_resolution_exploration_failed):
		_resolution.exploration_failed.connect(_on_resolution_exploration_failed)
	if _faith != null and not _faith.faith_changed.is_connected(_forward_faith_changed):
		_faith.faith_changed.connect(_forward_faith_changed)
	if _faith != null and not _faith.echo_spawn_requested.is_connected(_on_faith_echo_spawn_requested):
		_faith.echo_spawn_requested.connect(_on_faith_echo_spawn_requested)
	if not _board.card_return_requested.is_connected(handle_card_return_requested):
		_board.card_return_requested.connect(handle_card_return_requested)


func _disconnect_signals() -> void:
	if (
		_pipeline != null
		and _pipeline.event_interaction_requested.is_connected(_on_event_interaction_requested)
	):
		_pipeline.event_interaction_requested.disconnect(_on_event_interaction_requested)
	if (
		_modal != null
		and _modal.combat_settlement_confirmed.is_connected(handle_combat_settlement_request)
	):
		_modal.combat_settlement_confirmed.disconnect(handle_combat_settlement_request)
	if (
		_modal != null
		and _modal.non_combat_interaction_finished.is_connected(_on_non_combat_interaction_finished)
	):
		_modal.non_combat_interaction_finished.disconnect(_on_non_combat_interaction_finished)
	if _modal != null and _modal.combat_started.is_connected(_forward_combat_started):
		_modal.combat_started.disconnect(_forward_combat_started)
	if (
		_resolution != null
		and _resolution.exploration_failed.is_connected(_on_resolution_exploration_failed)
	):
		_resolution.exploration_failed.disconnect(_on_resolution_exploration_failed)
	if _faith != null and _faith.faith_changed.is_connected(_forward_faith_changed):
		_faith.faith_changed.disconnect(_forward_faith_changed)
	if _faith != null and _faith.echo_spawn_requested.is_connected(_on_faith_echo_spawn_requested):
		_faith.echo_spawn_requested.disconnect(_on_faith_echo_spawn_requested)
	if _board != null and _board.card_return_requested.is_connected(handle_card_return_requested):
		_board.card_return_requested.disconnect(handle_card_return_requested)


func _on_event_interaction_requested(instance: EventInstance) -> void:
	if not accepts_placement() or instance == null or instance.is_resolved:
		return
	_set_state(State.INTERACTING)
	_modal.begin(instance, _context.player_stats, _board.get_combat_card_chain())


## Shop and treasure dialogs finish synchronously without combat settlement.
func _on_non_combat_interaction_finished(_instance: EventInstance) -> void:
	if not _configured or _state != State.INTERACTING:
		return
	_set_state(State.EXPLORING)


func _on_resolution_exploration_failed(result: CombatResult) -> void:
	if result == null:
		return
	_enter_failed(result)


func _enter_failed(result: CombatResult) -> void:
	if _state == State.FAILED or _state == State.FINISHED:
		return
	_set_state(State.FAILED)
	_modal.lock_interaction()
	exploration_failed.emit(result)


func _set_state(next_state: State) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(_state)


func _forward_combat_started(instance: EventInstance, monster: MobInstance) -> void:
	combat_started.emit(instance, monster)


func _forward_faith_changed(current_faith: int) -> void:
	faith_changed.emit(current_faith)


func _on_faith_echo_spawn_requested() -> void:
	if _faith_echo_request.is_valid():
		_faith_echo_request.call()
