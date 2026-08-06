class_name ExplorationEventService
extends RefCounted

## Owns all level-configured event spawning. Events are still ordinary BoardEvent instances
## and keep using BoardPlacementResult.overlapped_event for their interaction path.
signal event_spawned(event_node: BoardEvent)

var _event_lib: EventLib
var _board: Board
var _spawn_config: ExplorationSpawnConfig
var _placement_service := EventPlacementService.new()
var _rng := RandomNumberGenerator.new()
var _exploration_placement_count := 0
var _boss_spawned := false
var _boss_pending := false


func configure(
	event_lib: EventLib,
	board: Board,
	spawn_config: ExplorationSpawnConfig,
	rng: RandomNumberGenerator = null
) -> bool:
	_event_lib = event_lib
	_board = board
	_spawn_config = spawn_config
	_exploration_placement_count = 0
	_boss_spawned = false
	_boss_pending = false
	if rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	else:
		_rng = rng
	if _event_lib == null or _board == null or _spawn_config == null:
		return false
	return _spawn_config.validate(_event_lib).is_empty()


func spawn_initial_events() -> int:
	if not _is_configured():
		return 0
	var requested_count := _rng.randi_range(
		_spawn_config.initial_event_count_min,
		_spawn_config.initial_event_count_max
	)
	return _spawn_from_pool(requested_count, _spawn_config.initial_event_pool)


## Called only after Board has committed a successful placement transaction.
## GUIDE cards intentionally do not advance normal exploration pacing.
func try_spawn_after_placement(result: BoardPlacementResult) -> int:
	if not _is_configured() or result == null or _is_guide_result(result):
		return 0
	_exploration_placement_count += 1
	var spawned_count := _spawn_from_pool(
		_spawn_config.get_spawn_count(_rng),
		_spawn_config.placement_event_pool
	)
	_try_spawn_due_boss()
	return spawned_count


## Faith consequences remain independent from pacing caps and normal spawn pools.
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


func get_exploration_placement_count() -> int:
	return _exploration_placement_count


func get_pending_boss() -> bool:
	return _boss_pending


func _try_spawn_due_boss() -> void:
	if _boss_spawned or _exploration_placement_count < _spawn_config.boss_spawn_after_placements:
		return
	var boss_templates := _event_lib.get_templates_of_type(EventData.EventType.BOSS)
	if boss_templates.is_empty():
		return
	var instance := boss_templates[0].create_instance()
	if not _placement_service.place_event_instance(instance, _event_lib, _board, _rng):
		_boss_pending = true
		return
	_boss_spawned = true
	_boss_pending = false
	event_spawned.emit(_find_event_node(instance))


func _spawn_from_pool(count: int, pool: Array[EventSpawnCandidate]) -> int:
	if count <= 0 or pool.is_empty():
		return 0
	var available_slots := maxi(0, _spawn_config.max_unresolved_events - _count_unresolved_events())
	var remaining := mini(count, available_slots)
	var spawned_count := 0
	var used_templates := _get_unresolved_templates()
	while remaining > 0:
		var candidate := _choose_candidate(pool, used_templates)
		if candidate == null:
			break
		if not _create_and_place(candidate):
			break
		spawned_count += 1
		remaining -= 1
		if not candidate.allow_duplicate and candidate.event_data not in used_templates:
			used_templates.append(candidate.event_data)
	return spawned_count


func _choose_candidate(
	pool: Array[EventSpawnCandidate],
	used_templates: Array[EventData] = []
) -> EventSpawnCandidate:
	var eligible: Array[EventSpawnCandidate] = []
	var total_weight := 0
	for candidate in pool:
		if candidate == null or candidate.event_data == null:
			continue
		if not candidate.allow_duplicate and candidate.event_data in used_templates:
			continue
		eligible.append(candidate)
		total_weight += candidate.weight
	if eligible.is_empty() or total_weight <= 0:
		return null
	var roll := _rng.randi_range(1, total_weight)
	var cumulative := 0
	for candidate in eligible:
		cumulative += candidate.weight
		if roll <= cumulative:
			return candidate
	return eligible.back()


func _create_and_place(candidate: EventSpawnCandidate) -> bool:
	if candidate == null or candidate.event_data == null:
		return false
	var instance := candidate.event_data.create_instance()
	if not _placement_service.place_event_instance(instance, _event_lib, _board, _rng):
		return false
	event_spawned.emit(_find_event_node(instance))
	return true


func _count_unresolved_events() -> int:
	var count := 0
	for event_node in _board.events:
		if event_node != null and event_node.event_instance != null and not event_node.event_instance.is_resolved:
			count += 1
	return count


func _get_unresolved_templates() -> Array[EventData]:
	var templates: Array[EventData] = []
	for event_node in _board.events:
		if event_node == null or event_node.event_instance == null:
			continue
		var instance := event_node.event_instance
		if not instance.is_resolved and instance.template != null and instance.template not in templates:
			templates.append(instance.template)
	return templates


func _is_guide_result(result: BoardPlacementResult) -> bool:
	if result.kind == BoardPlacementResult.Kind.GUIDE_RESOLVED:
		return true
	var source_card := result.source_card
	return source_card != null \
		and source_card.card_instance != null \
		and source_card.card_instance.card_data != null \
		and source_card.card_instance.card_data.card_type == CardData.CardType.GUIDE


func _is_configured() -> bool:
	return _event_lib != null and _board != null and _spawn_config != null


func _find_event_node(instance: EventInstance) -> BoardEvent:
	for event_node in _board.events:
		if event_node != null and event_node.event_instance == instance:
			return event_node
	return null
