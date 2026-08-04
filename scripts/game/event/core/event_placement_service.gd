class_name EventPlacementService
extends RefCounted


func place_initial_events(
	event_lib: EventLib,
	board: Board,
	rng: RandomNumberGenerator = null
) -> Array[EventInstance]:
	var placed: Array[EventInstance] = []
	if event_lib == null or board == null:
		return placed
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	for instance in event_lib.generate_event_datas():
		if place_event_instance(instance, event_lib, board, random):
			placed.append(instance)
		elif instance != null and instance.template != null:
			push_warning("No board space remains for event: %s" % instance.template.event_id)
	return placed


## Attaches a supplied runtime event at one randomly chosen valid map origin.
func place_event_instance(
	instance: EventInstance,
	event_lib: EventLib,
	board: Board,
	rng: RandomNumberGenerator = null
) -> bool:
	if instance == null or instance.template == null or event_lib == null or board == null:
		return false
	var candidates := _get_valid_origins(instance, board)
	if candidates.is_empty():
		return false
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	instance.origin = candidates[random.randi_range(0, candidates.size() - 1)]
	var event_node := event_lib.create_event_scene(instance, board.cell_size)
	if event_node != null and board.attach_event(event_node):
		return true
	if event_node != null:
		event_node.queue_free()
	instance.origin = Vector2i(-1, -1)
	return false


func _get_valid_origins(instance: EventInstance, board: Board) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if instance == null or instance.template == null:
		return candidates
	var event_size := instance.get_size()
	for x in maxi(0, board.width - event_size.x + 1):
		for y in maxi(0, board.height - event_size.y + 1):
			var origin := Vector2i(x, y)
			instance.origin = origin
			if board.can_attach_event(instance):
				candidates.append(origin)
	instance.origin = Vector2i(-1, -1)
	return candidates
