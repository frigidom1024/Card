class_name ExplorationEventService
extends RefCounted

## Creates level events only from cells made visible by the current exploration transaction.
signal event_spawned(event_node: BoardEvent)#exploration_coordinator

var _event_lib: EventLib
var _board: Board
var _placement_service := EventPlacementService.new()
var _rng := RandomNumberGenerator.new()
var _scheduled_templates: Array[EventData] = []
var _scheduled_thresholds: Array[int] = []
var _next_scheduled_index := 0
var _revealed_count := 0
var _boss_reveal_threshold := 24
var _boss_spawned := false


func configure(event_lib: EventLib, board: Board, config: ExplorationConfig) -> void:
	_event_lib = event_lib
	_board = board
	_next_scheduled_index = 0
	_revealed_count = 0
	_boss_spawned = false
	_scheduled_templates.clear()
	_scheduled_thresholds.clear()
	if config != null:
		_boss_reveal_threshold = maxi(1, config.boss_reveal_threshold)
		_scheduled_thresholds.assign(config.scheduled_event_reveal_thresholds)
	if _event_lib == null:
		return
	for entry in _event_lib.entries:
		if entry == null or entry.event_data == null:
			continue
		if entry.event_data.event_type != EventData.EventType.BOSS:
			_scheduled_templates.append(entry.event_data)
	while _scheduled_thresholds.size() < _scheduled_templates.size():
		var next_threshold := 4
		if not _scheduled_thresholds.is_empty():
			next_threshold = _scheduled_thresholds.back() + 4
		_scheduled_thresholds.append(next_threshold)
	_rng.randomize()


func on_cells_revealed(new_cells: Array[Vector2i]) -> void:
	if _event_lib == null or _board == null or new_cells.is_empty():
		return
	_revealed_count += new_cells.size()
	_spawn_scheduled_events(new_cells)
	_spawn_boss_if_due(new_cells)


func get_revealed_count() -> int:
	return _revealed_count


func request_faith_echo() -> bool:
	if _event_lib == null or _board == null:
		return false
	var templates := _event_lib.get_templates_of_type(EventData.EventType.MONSTER)
	if templates.is_empty():
		push_warning("Faith consequence could not find a normal monster event template")
		return false
	var template := templates[_rng.randi_range(0, templates.size() - 1)]
	var instance := template.create_instance()
	if not _placement_service.place_event_instance(instance, _event_lib, _board, _rng):
		return false
	event_spawned.emit(_find_event_node(instance))
	return true


func is_boss_spawned() -> bool:
	return _boss_spawned


func _spawn_scheduled_events(new_cells: Array[Vector2i]) -> void:
	while _next_scheduled_index < _scheduled_templates.size():
		if _revealed_count < _scheduled_thresholds[_next_scheduled_index]:
			return
		var instance := _scheduled_templates[_next_scheduled_index].create_instance()
		if not _placement_service.place_event_instance_in_cells(instance, _event_lib, _board, new_cells, _rng):
			return
		_next_scheduled_index += 1
		event_spawned.emit(_find_event_node(instance))


func _spawn_boss_if_due(new_cells: Array[Vector2i]) -> void:
	if _boss_spawned or _revealed_count < _boss_reveal_threshold:
		return
	var boss_templates := _event_lib.get_templates_of_type(EventData.EventType.BOSS)
	if boss_templates.is_empty():
		return
	var instance := boss_templates[0].create_instance()
	if not _placement_service.place_event_instance_in_cells(instance, _event_lib, _board, new_cells, _rng):
		return
	_boss_spawned = true
	event_spawned.emit(_find_event_node(instance))


func _find_event_node(instance: EventInstance) -> BoardEvent:
	for event_node in _board.events:
		if event_node != null and event_node.event_instance == instance:
			return event_node
	return null
