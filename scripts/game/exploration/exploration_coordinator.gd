class_name ExplorationCoordinator
extends RefCounted

const ExplorationEventServiceScript := preload("res://scripts/game/exploration/exploration_event_service.gd")
const BossPressureServiceScript := preload("res://scripts/game/exploration/boss_pressure_service.gd")

## Applies exploration-side effects after PlacementPipelineCoordinator commits a placement.
## PlacementPipelineCoordinator owns the event-interaction request emitted to RunFlowCoordinator.
signal event_spawned(event_node: BoardEvent)
signal boss_registered(event_node: BoardEvent)

var _event_service := ExplorationEventServiceScript.new()
var _boss_pressure_service := BossPressureServiceScript.new()
var _progression: RunProgressionService
var _board: Board


func configure(
	event_lib: EventLib,
	board: Board,
	config: ExplorationConfig,
	progression: RunProgressionService = null
) -> bool:
	if event_lib == null or board == null or config == null:
		return false
	var validation_error := config.validate(event_lib)
	if not validation_error.is_empty():
		push_error("Invalid ExplorationConfig: %s" % validation_error)
		return false
	if not _event_service.configure(event_lib, board, config.spawn_config, null, progression):
		return false
	_progression = progression
	_board = board
	_boss_pressure_service.configure(
		config.boss_pursuit_enabled,
		config.cards_to_boss_surround,
		config.cards_to_boss_intercept
	)
	if not _event_service.event_spawned.is_connected(_on_event_spawned):
		_event_service.event_spawned.connect(_on_event_spawned)
	return true


## Creates the initially visible event set after outer game systems have connected.
func initialize_events() -> int:
	return _event_service.spawn_initial_events()


func resolve_placement(result: BoardPlacementResult) -> void:
	if result == null or _board == null:
		return
	var boss_before_placement := _boss_pressure_service.get_registered_boss()
	if _progression != null:
		_progression.record_player_action(result)
	_event_service.try_spawn_after_placement(result)
	if boss_before_placement != null and result.overlapped_event != boss_before_placement.event_instance:
		_boss_pressure_service.record_placement(_board, result)


## Legacy hook retained for compatibility while faith consequences are disabled.
func request_faith_echo() -> bool:
	return _event_service.request_faith_echo()


## Removes an event only after its reward/combat lifecycle has resolved it.
## Bosses retain their existing pressure cleanup before their board event is removed.
func dismiss_resolved_event(instance: EventInstance) -> bool:
	if instance == null or _board == null:
		return false
	if not instance.is_resolved:
		return false
	if instance.get_event_type() == EventData.EventType.BOSS:
		return dismiss_defeated_boss(instance)
	var event_node := _find_event_node(instance)
	return event_node != null and _board.remove_event(event_node)


func dismiss_defeated_boss(instance: EventInstance) -> bool:
	if instance == null or instance.get_event_type() != EventData.EventType.BOSS or _board == null:
		return false
	var event_node := _find_event_node(instance)
	if event_node == null:
		return false
	_boss_pressure_service.clear_boss()
	return _board.remove_event(event_node)


func get_exploration_placement_count() -> int:
	return _event_service.get_exploration_placement_count()


func get_boss_phase() -> int:
	return _boss_pressure_service.get_phase()


func get_boss_event() -> BoardEvent:
	return _boss_pressure_service.get_registered_boss()


func _on_event_spawned(event_node: BoardEvent) -> void:
	if event_node == null or event_node.event_instance == null:
		return
	if event_node.event_instance.get_event_type() == EventData.EventType.BOSS:
		_boss_pressure_service.register_boss(event_node)
		boss_registered.emit(event_node)
	event_spawned.emit(event_node)


func _find_event_node(instance: EventInstance) -> BoardEvent:
	for event_node in _board.events:
		if event_node != null and event_node.event_instance == instance:
			return event_node
	return null
