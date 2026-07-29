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
		var candidates := _get_valid_origins(instance, board)
		if candidates.is_empty():
			push_warning("No board space remains for event: %s" % instance.template.event_id)
			continue
		instance.origin = candidates[random.randi_range(0, candidates.size() - 1)]
		var event_node := event_lib.create_event_scene(instance, board.cell_size)
		if event_node and board.attach_event(event_node):
			placed.append(instance)
	return placed


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
