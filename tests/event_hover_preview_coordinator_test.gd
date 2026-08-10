extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const EventHoverPreviewScene = preload("res://scenes/game/event_hover_preview.tscn")
const EventHoverPreviewCoordinatorScript = preload(
	"res://scripts/game/event/hover/event_hover_preview_coordinator.gd"
)
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const MonsterEventContentScript = preload("res://scripts/game/event/encounter/monster_event_content.gd")
const MobDataScript = preload("res://scripts/game/event/encounter/mob_data.gd")
const CombatStatsDataScript = preload("res://scripts/combatv2/combat_stats_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_preview_position_prefers_right_then_flips_and_clamps()
	await _test_coordinator_tracks_hovered_dynamic_events()
	quit(1 if _failure_count > 0 else 0)


func _test_preview_position_prefers_right_then_flips_and_clamps() -> void:
	var coordinator = EventHoverPreviewCoordinatorScript.new()
	var panel_size := Vector2(292.0, 180.0)
	var viewport_size := Vector2(1280.0, 720.0)

	var right_position := coordinator.calculate_position(
		Rect2(Vector2(240.0, 200.0), Vector2(80.0, 80.0)), panel_size, viewport_size
	)
	_expect(right_position.x > 320.0, "preview prefers the event's right side when space is available")

	var left_position := coordinator.calculate_position(
		Rect2(Vector2(1180.0, 200.0), Vector2(80.0, 80.0)), panel_size, viewport_size
	)
	_expect(left_position.x + panel_size.x < 1180.0, "preview flips left when right side lacks space")

	var top_position := coordinator.calculate_position(
		Rect2(Vector2(240.0, -40.0), Vector2(80.0, 80.0)), panel_size, viewport_size
	)
	_expect(top_position.y >= EventHoverPreviewCoordinatorScript.VIEWPORT_MARGIN, "preview remains inside top viewport edge")

	var bottom_position := coordinator.calculate_position(
		Rect2(Vector2(240.0, 680.0), Vector2(80.0, 80.0)), panel_size, viewport_size
	)
	_expect(
		bottom_position.y + panel_size.y <= viewport_size.y - EventHoverPreviewCoordinatorScript.VIEWPORT_MARGIN,
		"preview remains inside bottom viewport edge"
	)


func _test_coordinator_tracks_hovered_dynamic_events() -> void:
	var board := BoardScene.instantiate() as Board
	var preview = EventHoverPreviewScene.instantiate()
	root.add_child(board)
	root.add_child(preview)
	await process_frame

	var coordinator = EventHoverPreviewCoordinatorScript.new()
	_expect(coordinator.configure(board, preview, root), "coordinator accepts board, preview, and viewport")
	var first_event := _make_event(Vector2i(1, 1), "啮髓鼠群")
	var second_event := _make_event(Vector2i(4, 1), "腐肋巨狼")
	_expect(board.attach_event(first_event), "first dynamic event attaches")
	_expect(board.attach_event(second_event), "second dynamic event attaches")

	first_event.mouse_entered.emit()
	await process_frame
	_expect(preview.visible, "hovering an attached event presents the shared preview")
	_expect(_title_of(preview) == "啮髓鼠群", "preview uses first hovered event data")

	second_event.mouse_entered.emit()
	await process_frame
	_expect(_title_of(preview) == "腐肋巨狼", "new hover replaces the single shared preview")
	first_event.mouse_exited.emit()
	_expect(preview.visible, "leaving an older event does not hide newer active preview")
	second_event.mouse_exited.emit()
	_expect(not preview.visible, "leaving active event hides preview immediately")

	first_event.mouse_entered.emit()
	await process_frame
	_expect(preview.visible, "event can be previewed again")
	_expect(board.remove_event(first_event), "active event can be removed")
	_expect(not preview.visible, "removing active event dismisses its preview")

	board.queue_free()
	preview.queue_free()
	await process_frame


func _make_event(origin: Vector2i, name: String) -> BoardEvent:
	var stats := CombatStatsDataScript.new()
	stats.max_hp = 6
	var mob := MobDataScript.new()
	mob.mob_name = name
	mob.base_stats = stats
	var content := MonsterEventContentScript.new()
	content.mob = mob
	var data := EventDataScript.new()
	data.event_id = name
	data.event_type = EventData.EventType.MONSTER
	data.content = content
	var instance := data.create_instance()
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, 80)
	return event_node


func _title_of(preview) -> String:
	var title := preview.get_node_or_null("MarginContainer/Content/Header/TitleLabel") as Label
	return title.text if title != null else ""


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
