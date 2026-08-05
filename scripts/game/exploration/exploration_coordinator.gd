class_name ExplorationCoordinator
extends RefCounted

const FogServiceScript := preload("res://scripts/game/exploration/fog_service.gd")
const ExplorationEventServiceScript := preload("res://scripts/game/exploration/exploration_event_service.gd")
const BossPressureServiceScript := preload("res://scripts/game/exploration/boss_pressure_service.gd")

## Coordinates a completed board transaction. Board remains responsible only for spatial state.
signal fog_revealed(cells: Array[Vector2i])
signal event_spawned(event_node: BoardEvent)
signal event_interaction_requested(instance: EventInstance)
signal boss_registered(event_node: BoardEvent)

var _fog_service := FogServiceScript.new()
var _event_service := ExplorationEventServiceScript.new()
var _boss_pressure_service := BossPressureServiceScript.new()
var _board: Board


func configure(event_lib: EventLib, board: Board, config: ExplorationConfig) -> bool:
	if event_lib == null or board == null or config == null:
		return false
	var validation_error := config.validate()
	if not validation_error.is_empty():
		push_error("Invalid ExplorationConfig: %s" % validation_error)
		return false
	_board = board
	_fog_service.configure(board.width, board.height)
	_event_service.configure(event_lib, board, config)
	_boss_pressure_service.configure(
		config.boss_pursuit_enabled,
		config.cards_to_boss_surround,
		config.cards_to_boss_intercept
	)
	if not _fog_service.cells_revealed.is_connected(_on_cells_revealed):
		_fog_service.cells_revealed.connect(_on_cells_revealed)
	if not _event_service.event_spawned.is_connected(_on_event_spawned):
		_event_service.event_spawned.connect(_on_event_spawned)
	return true


func resolve_placement(result: BoardPlacementResult) -> void:
	if result == null or _board == null:
		return
	var boss_before_reveal := _boss_pressure_service.get_registered_boss()
	var newly_revealed := _fog_service.reveal_for_placement(_board, result)
	_event_service.on_cells_revealed(newly_revealed)
	if boss_before_reveal != null and result.overlapped_event != boss_before_reveal.event_instance:
		_boss_pressure_service.record_placement(_board, result)
	if result.overlapped_event != null and not result.overlapped_event.is_resolved:
		event_interaction_requested.emit(result.overlapped_event)


func dismiss_defeated_boss(instance: EventInstance) -> bool:
	if instance == null or instance.get_event_type() != EventData.EventType.BOSS or _board == null:
		return false
	var event_node := _find_event_node(instance)
	if event_node == null:
		return false
	_boss_pressure_service.clear_boss()
	return _board.remove_event(event_node)


func get_revealed_count() -> int:
	return _fog_service.get_revealed_count()


func get_boss_phase() -> int:
	return _boss_pressure_service.get_phase()


func get_boss_event() -> BoardEvent:
	return _boss_pressure_service.get_registered_boss()


func _on_cells_revealed(cells: Array[Vector2i]) -> void:
	fog_revealed.emit(cells)


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