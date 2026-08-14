## 牌桌事件区域组件
##
## 负责管理牌桌事件节点的稳定成员关系与事件空间索引。
## 包括：
## - 共享牌桌网格的宽度、高度和格子尺寸
## - 事件占用格与外围缓冲格的合法性检查
## - 事件节点的添加、移动、删除和视觉位置同步
## - 根据卡牌占用格查询未解决事件
##
## 不负责：
## - 事件模板选择、随机生成和探索进度
## - 事件触发时机、结算流程或弹窗显示
## - 卡牌拖拽、牌链规则或卡牌业务结果
## - 事件费用、奖励和其它跨系统业务
##
## 使用方式：
## 由 Board 注入共享的 BoardZoneBG 和可选的 BoardZone，
## 通过 attach_event()、move_event()、remove_event() 管理 BoardEvent，
## 通过 get_overlapping_unresolved_event() 查询卡牌放置覆盖的事件。
##
## 依赖：
## BoardZoneBG：提供唯一的牌桌网格几何来源。
## BoardZone：可选地提供卡牌占用查询，避免事件覆盖现有牌链。
## BoardEvent / EventInstance：提供事件视图与运行时事件状态。

class_name BoardEventZone
extends Control

@export var grid_source: BoardZoneBG
@export var card_zone: BoardZone

var width: int:
	get:
		return grid_source.grid_width if _has_grid_source() else 0

var height: int:
	get:
		return grid_source.grid_height if _has_grid_source() else 0

var cell_size: float:
	get:
		return grid_source.cell_size if _has_grid_source() else 0.0

var _events: Array[BoardEvent] = []
var _event_grid_owner: Dictionary[Vector2i, BoardEvent] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func get_events() -> Array[BoardEvent]:
	_prune_events()
	return _events.duplicate()


func get_event_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]:
	if event_size.x <= 0 or event_size.y <= 0 or not _is_origin_size_in_bounds(origin, event_size):
		return []
	var cells: Array[Vector2i] = []
	for x in range(event_size.x):
		for y in range(event_size.y):
			cells.append(origin + Vector2i(x, y))
	return cells


func get_event_buffer_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]:
	var footprint := get_event_cells(origin, event_size)
	if footprint.is_empty():
		return []
	var result: Array[Vector2i] = []
	for x in range(origin.x - 1, origin.x + event_size.x + 1):
		for y in range(origin.y - 1, origin.y + event_size.y + 1):
			var cell := Vector2i(x, y)
			if _is_cell_in_bounds(cell):
				result.append(cell)
	return result


func can_attach_event(instance: EventInstance) -> bool:
	if not _is_valid_event_instance(instance):
		return false
	var cells := get_event_cells(instance.origin, instance.get_size())
	if cells.is_empty():
		return false
	if _has_card_conflict(cells):
		return false
	for cell in cells:
		if _event_grid_owner.has(cell):
			return false
	for buffer_cell in get_event_buffer_cells(instance.origin, instance.get_size()):
		var buffered_event := _event_grid_owner.get(buffer_cell) as BoardEvent
		if buffered_event != null:
			return false
	return true


func attach_event(event_node: BoardEvent) -> bool:
	if not _is_valid_event_node(event_node) or _events.has(event_node):
		return false
	var instance := event_node.event_instance
	if not can_attach_event(instance):
		return false
	var cells := get_event_cells(instance.origin, instance.get_size())
	if cells.is_empty():
		return false

	# 所有校验完成后才改变父节点、视觉位置和索引，失败不会留下半写入状态。
	if event_node.get_parent() != self:
		event_node.reparent(self, true) if event_node.get_parent() != null else add_child(event_node)
	if event_node.get_parent() != self:
		return false
	event_node.position = _origin_to_local_position(instance.origin)
	event_node.size = Vector2(instance.get_size()) * cell_size
	event_node.custom_minimum_size = event_node.size
	for cell in cells:
		_event_grid_owner[cell] = event_node
	_events.append(event_node)
	event_node.refresh_display()
	return true


func move_event(event_node: BoardEvent, target_origin: Vector2i) -> bool:
	if not _is_valid_event_node(event_node) or not _events.has(event_node):
		return false
	var instance := event_node.event_instance
	var target_cells := get_event_cells(target_origin, instance.get_size())
	if target_cells.is_empty():
		return false
	if _has_card_conflict(target_cells):
		return false
	for cell in target_cells:
		var current_event := _event_grid_owner.get(cell) as BoardEvent
		if current_event != null and current_event != event_node:
			return false
	for buffer_cell in get_event_buffer_cells(target_origin, instance.get_size()):
		var buffered_event := _event_grid_owner.get(buffer_cell) as BoardEvent
		if buffered_event != null and buffered_event != event_node:
			return false

	for cell in _event_grid_owner.keys().duplicate():
		if _event_grid_owner[cell] == event_node:
			_event_grid_owner.erase(cell)
	instance.origin = target_origin
	event_node.position = _origin_to_local_position(target_origin)
	event_node.size = Vector2(instance.get_size()) * cell_size
	event_node.custom_minimum_size = event_node.size
	for cell in target_cells:
		_event_grid_owner[cell] = event_node
	event_node.refresh_display()
	return true


func remove_event(event_node: BoardEvent) -> bool:
	if not _is_valid_event_node(event_node) or not _events.has(event_node):
		return false
	for cell in _event_grid_owner.keys().duplicate():
		if _event_grid_owner[cell] == event_node:
			_event_grid_owner.erase(cell)
	_events.erase(event_node)
	if event_node.get_parent() == self:
		event_node.queue_free()
	return true


func get_overlapping_unresolved_event(card_cells: Array[Vector2i]) -> EventInstance:
	var matches: Array[BoardEvent] = []
	for cell in card_cells:
		var event_node := _event_grid_owner.get(cell) as BoardEvent
		if event_node == null or not is_instance_valid(event_node) or matches.has(event_node):
			continue
		var instance := event_node.event_instance
		if instance != null and is_instance_valid(instance) and not instance.is_resolved:
			matches.append(event_node)
	if matches.size() > 1:
		push_error("Card placement overlaps multiple unresolved events")
		return null
	return matches[0].event_instance if matches.size() == 1 else null


func _has_grid_source() -> bool:
	return grid_source != null and is_instance_valid(grid_source)


func _is_valid_event_instance(instance: EventInstance) -> bool:
	return (
		instance != null
		and is_instance_valid(instance)
		and instance.template != null
		and is_instance_valid(instance.template)
	)


func _is_valid_event_node(event_node: BoardEvent) -> bool:
	return event_node != null and is_instance_valid(event_node) and _is_valid_event_instance(event_node.event_instance)


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func _is_origin_size_in_bounds(origin: Vector2i, event_size: Vector2i) -> bool:
	if not _has_grid_source() or origin.x < 0 or origin.y < 0:
		return false
	return origin.x + event_size.x <= width and origin.y + event_size.y <= height


func _has_card_conflict(cells: Array[Vector2i]) -> bool:
	if card_zone == null or not is_instance_valid(card_zone):
		return false
	for cell in cells:
		if card_zone.get_card_at(cell) != null:
			return true
	return false


func _origin_to_local_position(origin: Vector2i) -> Vector2:
	if not _has_grid_source():
		return Vector2.ZERO
	return get_global_transform_with_canvas().affine_inverse() * grid_source.to_global(Vector2(origin) * cell_size)


func _prune_events() -> void:
	var valid_events: Array[BoardEvent] = []
	for event_node: BoardEvent in _events:
		if is_instance_valid(event_node):
			valid_events.append(event_node)
	_events = valid_events
	for cell in _event_grid_owner.keys().duplicate():
		var owner := _event_grid_owner[cell]
		if owner == null or not is_instance_valid(owner) or not _events.has(owner):
			_event_grid_owner.erase(cell)
