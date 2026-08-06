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
signal faith_changed(current_faith: int)

var _context: RunContext
var _pipeline: PlacementPipelineCoordinator
var _modal: EventModalCoordinator
var _resolution: EncounterResolutionCoordinator
var _faith: FaithService
var _board: Board
var _state := State.UNINITIALIZED


func configure(
	context: RunContext,
	pipeline: PlacementPipelineCoordinator,
	modal: EventModalCoordinator,
	resolution: EncounterResolutionCoordinator,
	faith: FaithService,
	board: Board
) -> bool:
	if context == null or pipeline == null or modal == null or resolution == null or faith == null or board == null:
		return false
	if not context.is_valid():
		return false
	_disconnect_signals()
	_context = context
	_pipeline = pipeline
	_modal = modal
	_resolution = resolution
	_faith = faith
	_board = board
	_state = State.UNINITIALIZED
	_connect_signals()
	return true


func start() -> bool:
	if _state != State.UNINITIALIZED:
		return false
	_state = State.EXPLORING
	return true


func get_state() -> State:
	return _state


func accepts_placement() -> bool:
	return _state == State.EXPLORING


func handle_combat_settlement_request(instance: EventInstance, result: CombatResult) -> bool:
	if _state != State.INTERACTING or instance == null or result == null:
		return false
	if not _resolution.apply(instance, result):
		return false

	_modal.complete_combat_settlement()
	combat_resolved.emit(instance, result)

	if _state == State.FAILED:
		# EncounterResolutionCoordinator emits failure synchronously during apply().
		# Completing the controller releases its normal lock, so retain it terminally.
		_modal.lock_interaction()
		return true
	if result.outcome == CombatResult.Outcome.DEFEAT:
		_enter_failed(result)
		return true
	if instance.get_event_type() == EventData.EventType.BOSS and result.outcome == CombatResult.Outcome.VICTORY:
		_state = State.FINISHED
		run_finished.emit()
		return true
	_state = State.EXPLORING
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
	if not _modal.combat_started.is_connected(_forward_combat_started):
		_modal.combat_started.connect(_forward_combat_started)
	if not _resolution.exploration_failed.is_connected(_on_resolution_exploration_failed):
		_resolution.exploration_failed.connect(_on_resolution_exploration_failed)
	if not _faith.faith_changed.is_connected(_forward_faith_changed):
		_faith.faith_changed.connect(_forward_faith_changed)
	if not _faith.echo_spawn_requested.is_connected(_on_faith_echo_spawn_requested):
		_faith.echo_spawn_requested.connect(_on_faith_echo_spawn_requested)
	if not _board.card_return_requested.is_connected(handle_card_return_requested):
		_board.card_return_requested.connect(handle_card_return_requested)


func _disconnect_signals() -> void:
	if _pipeline != null and _pipeline.event_interaction_requested.is_connected(_on_event_interaction_requested):
		_pipeline.event_interaction_requested.disconnect(_on_event_interaction_requested)
	if _modal != null and _modal.combat_settlement_confirmed.is_connected(handle_combat_settlement_request):
		_modal.combat_settlement_confirmed.disconnect(handle_combat_settlement_request)
	if _modal != null and _modal.combat_started.is_connected(_forward_combat_started):
		_modal.combat_started.disconnect(_forward_combat_started)
	if _resolution != null and _resolution.exploration_failed.is_connected(_on_resolution_exploration_failed):
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
	_state = State.INTERACTING
	_modal.begin(instance, _context.player_stats, _board.get_combat_card_chain())


func _on_resolution_exploration_failed(result: CombatResult) -> void:
	if result == null:
		return
	_enter_failed(result)


func _enter_failed(result: CombatResult) -> void:
	if _state == State.FAILED or _state == State.FINISHED:
		return
	_state = State.FAILED
	_modal.lock_interaction()
	exploration_failed.emit(result)


func _forward_combat_started(instance: EventInstance, monster: MobInstance) -> void:
	combat_started.emit(instance, monster)


func _forward_faith_changed(current_faith: int) -> void:
	faith_changed.emit(current_faith)


func _on_faith_echo_spawn_requested() -> void:
	var exploration := _get_current_exploration()
	if exploration != null:
		exploration.request_faith_echo()


func _get_current_exploration() -> ExplorationCoordinator:
	if _pipeline == null:
		return null
	# Compatibility bridge until Task 4 supplies the narrow explicit port.
	return _pipeline.get("_exploration") as ExplorationCoordinator