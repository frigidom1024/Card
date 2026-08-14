extends SceneTree

const EVENT_ZONE_SCENE := preload("res://scenes/zone/board_event_zone.tscn")
const BOARD_ZONE_SCENE := preload("res://scenes/zone/board_zone.tscn")
const EVENT_SCENE := preload("res://scenes/game/event.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board_zone)
	await process_frame
	var event_zone := EVENT_ZONE_SCENE.instantiate() as BoardEventZone
	root.add_child(event_zone)
	event_zone.grid_source = board_zone.back_ground
	event_zone.card_zone = board_zone
	await process_frame

	_expect(event_zone.width == board_zone.back_ground.grid_width, "event zone shares grid width")
	_expect(event_zone.height == board_zone.back_ground.grid_height, "event zone shares grid height")
	_expect(is_equal_approx(event_zone.cell_size, board_zone.back_ground.cell_size), "event zone shares cell size")
	_expect(
		event_zone.get_event_cells(Vector2i(2, 1), Vector2i(2, 2)) == [
			Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 1), Vector2i(3, 2)
		],
		"event footprint follows row-major grid order"
	)
	_expect(event_zone.get_event_buffer_cells(Vector2i(2, 1), Vector2i(2, 2)).size() > 4, "event buffer includes surrounding cells")
	_expect(event_zone.get_event_cells(Vector2i(-1, 0), Vector2i(2, 2)).is_empty(), "out-of-bounds footprint is rejected")

	var invalid_instance := _make_instance(Vector2i(-1, -1), Vector2i.ONE)
	var invalid_node := _make_event(invalid_instance)
	var invalid_parent := invalid_node.get_parent()
	_expect(not event_zone.attach_event(invalid_node), "invalid event attach fails")
	_expect(event_zone.get_events().is_empty(), "failed attach does not index invalid event")
	_expect(invalid_instance.origin == Vector2i(-1, -1), "failed attach preserves invalid origin")
	_expect(invalid_node.get_parent() == invalid_parent, "failed attach preserves event parent")

	var instance := _make_instance(Vector2i(1, 1), Vector2i.ONE)
	var node := _make_event(instance)
	_expect(event_zone.attach_event(node), "valid event attaches")
	_expect(event_zone.get_events() == [node], "attach indexes event once")
	_expect(node.get_parent() == event_zone, "attach reparents event into zone")
	_expect(event_zone.get_overlapping_unresolved_event([Vector2i(1, 1)]) == instance, "unresolved overlap is returned")
	instance.is_resolved = true
	_expect(event_zone.get_overlapping_unresolved_event([Vector2i(1, 1)]) == null, "resolved overlap is ignored")

	var original_origin := instance.origin
	_expect(not event_zone.move_event(node, Vector2i(-1, 1)), "invalid move fails")
	_expect(instance.origin == original_origin, "failed move preserves origin")
	_expect(event_zone.move_event(node, Vector2i(3, 2)), "valid move succeeds")
	_expect(instance.origin == Vector2i(3, 2), "move updates instance origin")
	_expect(event_zone.get_overlapping_unresolved_event([Vector2i(1, 1)]) == null, "old cells are released")

	_expect(event_zone.remove_event(node), "event removes")
	_expect(event_zone.get_events().is_empty(), "remove clears event membership")
	_expect(not event_zone.remove_event(node), "duplicate remove fails")

	# 附加失败的节点从未进入场景树，需要由测试显式释放。
	invalid_node.free()
	# BoardEventZone 持有 BoardZone 的网格引用，先释放依赖方再释放数据源。
	event_zone.free()
	board_zone.free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _make_instance(origin: Vector2i, event_size: Vector2i) -> EventInstance:
	var data := EventData.new()
	data.event_id = "board_event_zone_test"
	data.event_type = EventData.EventType.TREASURE
	data.size = event_size
	var instance := data.create_instance()
	instance.origin = origin
	return instance


func _make_event(instance: EventInstance) -> BoardEvent:
	var node := EVENT_SCENE.instantiate() as BoardEvent
	node.setup(instance, 92)
	return node


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
