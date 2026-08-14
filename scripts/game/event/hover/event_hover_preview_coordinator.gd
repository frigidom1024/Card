class_name EventHoverPreviewCoordinator
extends RefCounted

const GAP := 10.0
const VIEWPORT_MARGIN := 12.0
const EventHoverPreviewFormatterScript = preload(
	"res://scripts/game/event/hover/event_hover_preview_formatter.gd"
)

var _board: Board
var _preview
var _viewport: Viewport
var _formatter
var _active_event: BoardEvent


func _init(formatter = null) -> void:
	_formatter = formatter if formatter != null else EventHoverPreviewFormatterScript.new()


## 连接已有和后续动态生成的事件；不接入事件触发或结算路径。
func configure(board: Board, preview, viewport: Viewport) -> bool:
	_disconnect_board()
	_board = board
	_preview = preview
	_viewport = viewport
	_active_event = null
	if (
		_board == null
		or _board.event_zone == null
		or _preview == null
		or _viewport == null
	):
		return false
	if not _board.event_attached.is_connected(_on_event_attached):
		_board.event_attached.connect(_on_event_attached)
	if not _board.event_removed.is_connected(_on_event_removed):
		_board.event_removed.connect(_on_event_removed)
	for event_node: BoardEvent in _board.event_zone.get_events():
		_bind_event(event_node)
	_preview.dismiss()
	return true


func show_for(event_node: BoardEvent) -> void:
	if event_node == null or not is_instance_valid(event_node) or event_node.event_instance == null:
		hide()
		return
	var model = _formatter.build(event_node.event_instance)
	if model == null or not model.visible:
		hide()
		return
	_active_event = event_node
	_preview.present(model)
	_position_preview(event_node)


func hide() -> void:
	_active_event = null
	if _preview != null and is_instance_valid(_preview):
		_preview.dismiss()


func calculate_position(event_rect: Rect2, panel_size: Vector2, viewport_size: Vector2) -> Vector2:
	var right_position := event_rect.position + Vector2(event_rect.size.x + GAP, -4.0)
	var left_position := Vector2(event_rect.position.x - GAP - panel_size.x, right_position.y)
	var position := right_position
	if right_position.x + panel_size.x > viewport_size.x - VIEWPORT_MARGIN:
		position = left_position
	position.x = clampf(
		position.x,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, viewport_size.x - VIEWPORT_MARGIN - panel_size.x)
	)
	position.y = clampf(
		position.y,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, viewport_size.y - VIEWPORT_MARGIN - panel_size.y)
	)
	return position


func _on_event_attached(event_node: BoardEvent) -> void:
	_bind_event(event_node)


func _on_event_removed(event_node: BoardEvent) -> void:
	_unbind_event(event_node)
	if _active_event == event_node:
		hide()


func _bind_event(event_node: BoardEvent) -> void:
	if event_node == null or not is_instance_valid(event_node):
		return
	if not event_node.hover_started.is_connected(_on_event_hover_started):
		event_node.hover_started.connect(_on_event_hover_started)
	if not event_node.hover_ended.is_connected(_on_event_hover_ended):
		event_node.hover_ended.connect(_on_event_hover_ended)


func _unbind_event(event_node: BoardEvent) -> void:
	if event_node == null or not is_instance_valid(event_node):
		return
	if event_node.hover_started.is_connected(_on_event_hover_started):
		event_node.hover_started.disconnect(_on_event_hover_started)
	if event_node.hover_ended.is_connected(_on_event_hover_ended):
		event_node.hover_ended.disconnect(_on_event_hover_ended)


func _on_event_hover_started(event_node: BoardEvent) -> void:
	show_for(event_node)


func _on_event_hover_ended(event_node: BoardEvent) -> void:
	if _active_event == event_node:
		hide()


func _position_preview(event_node: BoardEvent) -> void:
	if _preview == null or not is_instance_valid(_preview) or _viewport == null:
		return
	_preview.reset_size()
	var panel_size: Vector2 = _preview.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = _preview.get_combined_minimum_size()
	_preview.position = calculate_position(
		event_node.get_global_rect(), panel_size, _viewport.get_visible_rect().size
	)


func _disconnect_board() -> void:
	if _board == null or not is_instance_valid(_board):
		return
	if _board.event_attached.is_connected(_on_event_attached):
		_board.event_attached.disconnect(_on_event_attached)
	if _board.event_removed.is_connected(_on_event_removed):
		_board.event_removed.disconnect(_on_event_removed)
	var event_zone: BoardEventZone = _board.event_zone
	if event_zone != null:
		for event_node: BoardEvent in event_zone.get_events():
			_unbind_event(event_node)
