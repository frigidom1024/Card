class_name Board
extends Node2D

const BoardPlacementResultScript = preload("res://scripts/game/board_placement_result.gd")

signal placement_committed(result)
signal card_return_requested(card: CardEntity)
# Temporary compatibility notifications. Exploration will consume placement_committed in task 4.
signal event_triggered(instance: EventInstance)
signal card_placed(card: CardEntity)

@export var cell_size: int = LayoutConfig.CELL_SIZE
@export var width: int = 10
@export var height: int = 8

@export var drop_detector: Area2D

var highlight_cells: Array[Vector2i] = []
var highlight_valid_color := Color(1, 0.8, 0, 0.3)      # 可放置
var highlight_invalid_color := Color(1, 0.2, 0.2, 0.4)  # 不可放置
var preview_valid: bool = true

var cards: Array[CardEntity] = []
var events: Array[BoardEvent] = []

# 格子占用表：Vector2i → CardEntity
var _grid_owner: Dictionary = {}
# 事件占用表：Vector2i → BoardEvent
var _event_grid_owner: Dictionary[Vector2i, BoardEvent] = {}

func _ready() -> void:
	var background := get_node_or_null("Sprite2D") as Sprite2D
	if background != null:
		background.z_index = RenderPriority.BOARD_BACKGROUND
	_apply_drop_detector_size()


## DropDetector 碰撞盒跟随 cell_size（当前未被拖拽逻辑调用，仅保持一致）
func _apply_drop_detector_size() -> void:
	var shape_node := get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var grid_size := Vector2(width * cell_size, height * cell_size)
	var shape := RectangleShape2D.new()
	shape.size = grid_size
	shape_node.shape = shape
	shape_node.position = grid_size / 2.0


func _draw():
	# 绘制棋盘
	for x in width:
		for y in height:
			draw_rect(
				Rect2(
					x * cell_size,
					y * cell_size,
					cell_size,
					cell_size
				),
				Color.GRAY,
				false
			)


	# 绘制卡牌预览（黄色=可放置  红色=不可放置）
	var preview_color = highlight_valid_color if preview_valid else highlight_invalid_color
	for cell in highlight_cells:
		draw_rect(
			Rect2(
				cell.x * cell_size,
				cell.y * cell_size,
				cell_size,
				cell_size
			),
			preview_color,
			true
		)





# =========================
# 坐标转换
# =========================


# 世界坐标 -> 棋盘坐标
func world_to_grid(world_pos: Vector2)->Vector2i:

	var local_pos = to_local(world_pos)

	return Vector2i(
		floori(local_pos.x / cell_size),
		floori(local_pos.y / cell_size)
	)



# 棋盘坐标 -> 世界中心
func grid_to_world_center(grid:Vector2i)->Vector2:

	var local_pos = Vector2(
		grid.x * cell_size + cell_size/2,
		grid.y * cell_size + cell_size/2
	)

	return to_global(local_pos)



# =========================
# 卡牌占用格
# =========================


# rotation 只判断方向
# 0/180 纵向
# 90/270 横向
func _get_rotation_direction(rotation_degrees: float) -> int:
	return posmod(int(round(rotation_degrees / 90.0)), 4)


func get_card_cells(
	center: Vector2,
	rotation: float
) -> Array[Vector2i]:


	var dir := _get_rotation_direction(rotation)
	var local_pos
	if dir%2==0:
		local_pos = to_local(center)-Vector2(0.5*cell_size,0)
	else:
		local_pos = to_local(center)-Vector2(0,0.5*cell_size)
		
	var grid_x = roundi(
		local_pos.x / cell_size
	)

	var grid_y = roundi(
		local_pos.y / cell_size
	)

	var cells:Array[Vector2i] = []

	# 竖向
	if dir%2==0:
		# 中心格
		grid_x = clampi(
			grid_x,
			0,
			width - 1
		)

		grid_y = clampi(
			grid_y,
			1,
			height - 1
		)

		cells.append(
			Vector2i(
				grid_x,
				grid_y - 1
			)
		)

		cells.append(
			Vector2i(
				grid_x,
				grid_y
			)
		)

	# 横向
	else:

		grid_x = clampi(
			grid_x,
			1,
			width - 1
		)

		grid_y = clampi(
			grid_y,
			0,
			height - 1
		)

		cells.append(
			Vector2i(
				grid_x - 1,
				grid_y
			)
		)

		cells.append(
			Vector2i(
				grid_x,
				grid_y
			)
		)

	return cells


# =========================
# 卡牌吸附
# =========================
func snap_card_position(
	center:Vector2,
	rotation:float
)->Vector2:

	var cells = get_card_cells(
		center,
		rotation
	)

	if cells.is_empty():
		return center

	var center_pos := Vector2.ZERO

	for c in cells:

		center_pos += grid_to_world_center(c)

	center_pos /= cells.size()

	return center_pos


# =========================
# 事件占格 / 挂载
# =========================
func get_event_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in event_size.x:
		for y in event_size.y:
			cells.append(origin + Vector2i(x, y))
	return cells


func _are_cells_in_bounds(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
			return false
	return true


func get_event_buffer_cells(origin: Vector2i, event_size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(origin.x - 1, origin.x + event_size.x + 1):
		for y in range(origin.y - 1, origin.y + event_size.y + 1):
			var cell := Vector2i(x, y)
			if _are_cells_in_bounds([cell]):
				result.append(cell)
	return result


func can_attach_event(instance: EventInstance) -> bool:
	if instance == null or instance.template == null:
		return false
	var cells := get_event_cells(instance.origin, instance.get_size())
	if cells.is_empty() or not _are_cells_in_bounds(cells):
		return false
	for cell in cells:
		if _grid_owner.has(cell):
			return false
	for buffer_cell in get_event_buffer_cells(instance.origin, instance.get_size()):
		if _event_grid_owner.has(buffer_cell):
			return false
	return true


## Moves an existing ordinary BoardEvent without changing event interaction semantics.
func move_event(event_node: BoardEvent, target_origin: Vector2i) -> bool:
	if event_node == null or event_node not in events or event_node.event_instance == null:
		return false
	var instance := event_node.event_instance
	var target_cells := get_event_cells(target_origin, instance.get_size())
	if target_cells.is_empty() or not _are_cells_in_bounds(target_cells):
		return false
	for cell in target_cells:
		if _grid_owner.has(cell):
			return false
		var current_event := _event_grid_owner.get(cell) as BoardEvent
		if current_event != null and current_event != event_node:
			return false
	for buffer_cell in get_event_buffer_cells(target_origin, instance.get_size()):
		var buffered_event := _event_grid_owner.get(buffer_cell) as BoardEvent
		if buffered_event != null and buffered_event != event_node:
			return false
	for cell in _event_grid_owner.keys():
		if _event_grid_owner[cell] == event_node:
			_event_grid_owner.erase(cell)
	instance.origin = target_origin
	event_node.position = Vector2(target_origin * cell_size)
	for cell in target_cells:
		_event_grid_owner[cell] = event_node
	return true


func get_overlapping_unresolved_event(cells: Array[Vector2i]) -> EventInstance:
	var matches: Array[BoardEvent] = []
	for cell in cells:
		var event_node := _event_grid_owner.get(cell) as BoardEvent
		if event_node and event_node.event_instance and not event_node.event_instance.is_resolved and event_node not in matches:
			matches.append(event_node)
	if matches.size() > 1:
		push_error("Card placement overlaps multiple unresolved events")
		return null
	return matches[0].event_instance if matches.size() == 1 else null


func attach_event(event_node: BoardEvent) -> bool:
	if event_node == null or not is_instance_valid(event_node):
		return false
	if event_node.get_parent() != null:
		return false
	var instance := event_node.event_instance
	if instance == null or not is_instance_valid(instance) or not can_attach_event(instance):
		return false
	var cells := get_event_cells(instance.origin, instance.get_size())
	add_child(event_node)
	if event_node.get_parent() != self:
		return false
	for cell in cells:
		_event_grid_owner[cell] = event_node
	events.append(event_node)
	return true


func remove_event(event_node: BoardEvent) -> bool:
	if event_node == null or event_node not in events:
		return false
	var cells := get_event_cells(event_node.event_instance.origin, event_node.event_instance.get_size())
	for cell in cells:
		if _event_grid_owner.get(cell) == event_node:
			_event_grid_owner.erase(cell)
	events.erase(event_node)
	event_node.queue_free()
	return true


# =========================
# 预览
# =========================
func preview_card(card: CardEntity):
	var cells = get_card_cells(card.global_position, card.rotation_degrees)
	highlight_cells = cells

	# 检查是否可放置
	var cells_in_bounds = _are_cells_in_bounds(cells)
	var no_conflict = not has_conflict(cells)
	var placement_ok = can_place_card(cells, card)

	preview_valid = cells_in_bounds and no_conflict and placement_ok

	queue_redraw()


# 获取放置失败的原因文字
func get_placement_hint(cells: Array[Vector2i], card: CardEntity) -> String:
	var hint := _get_placement_failure_reason(cells, card)
	_log_placement_failure(cells, card, hint)
	return hint


func _get_placement_failure_reason(cells: Array[Vector2i], card: CardEntity) -> String:
	for cell in cells:
		if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
			return "超出棋盘边界"
	if has_conflict(cells):
		return "该位置已被占用"
	if card and not _is_root_card(card):
		if cards.is_empty():
			return "棋盘上还没有可连接的卡牌"
		return "需放置在上一张卡的顶部朝向方向"
	return ""


## 仅用于定位拖拽放置失败。输出候选卡、链尾卡、连接目标及占格现场。
func _log_placement_failure(cells: Array[Vector2i], card: CardEntity, hint: String) -> void:
	print("=== CARD PLACEMENT FAILED ===")
	print("reason=", hint)
	print("candidate=", _card_debug_label(card))
	print("candidate_global=", card.global_position if card else Vector2.ZERO)
	print("candidate_local=", to_local(card.global_position) if card else Vector2.ZERO)
	print("candidate_rotation=", card.rotation_degrees if card else 0.0)
	print("candidate_cells=", cells)
	print("candidate_cells_in_bounds=", _are_cells_in_bounds(cells))
	print("candidate_forward_cell=", get_placement_cell(card) if card else Vector2i(-1, -1))

	for cell in cells:
		var owner := _grid_owner.get(cell) as CardEntity
		if owner != null:
			print("candidate_cell_owner[", cell, "]=", _card_debug_label(owner))

	if cards.is_empty():
		print("chain_tail=<none>")
	else:
		var tail = cards.back()
		var required_connection_cell := get_placement_cell(tail)
		print("chain_count=", cards.size())
		print("chain_tail=", _card_debug_label(tail))
		print("tail_global=", tail.global_position)
		print("tail_local=", to_local(tail.global_position))
		print("tail_rotation=", tail.rotation_degrees)
		print("tail_cells=", get_card_cells(tail.global_position, tail.rotation_degrees))
		print("required_connection_cell=", required_connection_cell)
		print("candidate_contains_required_cell=", required_connection_cell in cells)
		print("required_cell_in_bounds=", _are_cells_in_bounds([required_connection_cell]))
		var required_owner := _grid_owner.get(required_connection_cell) as CardEntity
		print("required_cell_owner=", _card_debug_label(required_owner))

	print("grid_owners=")
	for occupied_cell in _grid_owner.keys():
		print("  ", occupied_cell, " -> ", _card_debug_label(_grid_owner[occupied_cell] as CardEntity))
	print("=== END CARD PLACEMENT FAILED ===")


func _card_debug_label(card: CardEntity) -> String:
	if card == null:
		return "<empty>"
	var card_data := card.card_instance.card_data if card.card_instance else null
	var card_name := card_data.card_name if card_data and not card_data.card_name.is_empty() else "unnamed"
	var instance_direction := card.card_instance.direction if card.card_instance else -1
	var battlefield_pos := card.card_instance.battlefield_pos if card.card_instance else Vector2i(-1, -1)
	return "%s(id=%s, instance_dir=%s, battlefield_pos=%s)" % [
		card_name,
		card.get_instance_id(),
		instance_direction,
		battlefield_pos,
	]



func clear_preview():
	highlight_cells.clear()
	queue_redraw()

# =========================
# 边界检查
# =========================

func can_place_card(
	cells: Array[Vector2i],
	card: CardEntity = null
) -> bool:
	# 边界检查
	if not _are_cells_in_bounds(cells):
		return false

	# ROOT 类型无其他限制
	if card and _is_root_card(card):
		return true

	# 非 ROOT 卡必须相邻上一张卡（无上一张卡则无法放置）
	if card and not cards.is_empty():
		var placement_cell = get_placement_cell(cards.back())
		for c in cells:
			if c == placement_cell:
				return true

	return false

# =========================
# 放置规则
# =========================

# 判断卡牌是否为 ROOT 类型
func _is_root_card(card: CardEntity) -> bool:
	return card.card_instance \
		and card.card_instance.card_data \
		and card.card_instance.card_data.card_type == CardData.CardType.ROOT


# 获取指定卡牌"顶部朝向"的相邻放置格
func get_placement_cell(card: CardEntity) -> Vector2i:
	var dir := _get_rotation_direction(card.rotation_degrees)
	var cells = get_card_cells(card.global_position, card.rotation_degrees)
	if cells.is_empty():
		return Vector2i(-1, -1)

	# 根据方向确定"顶部"的格子
	# 方向: 0=上, 1=右, 2=下, 3=左
	var forward_cell: Vector2i
	match dir:
		0: forward_cell = cells[0]  # 朝上 → 上方格
		1: forward_cell = cells[1]  # 朝右 → 右方格
		2: forward_cell = cells[1]  # 朝下 → 下方格
		3: forward_cell = cells[0]  # 朝左 → 左方格

	var offsets = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	return forward_cell + offsets[dir]

# =========================
# 卡牌放置 / 移除
# =========================

# 检查格子是否被占用（可排除指定卡牌，用于卡牌自身移动时检测）
func has_conflict(cells: Array[Vector2i], exclude: CardEntity = null) -> bool:
	for c in cells:
		var key := Vector2i(c.x, c.y)
		if _grid_owner.has(key) and _grid_owner[key] != exclude:
			return true
	return false

func add_card(card: CardEntity) -> bool:
	if not card or card in cards:
		return false

	var cells = get_card_cells(
		card.global_position,
		card.rotation_degrees
	)

	if not can_place_card(cells, card):
		return false

	if has_conflict(cells):
		return false

	# 吸附到格子
	card.global_position = snap_card_position(
		card.global_position,
		card.rotation_degrees
	)

	# GUIDE 卡沿用普通卡牌的校验和吸附，但不加入牌链；
	# 它会把当前牌链整体向前移动，并由上层负责回收到手牌。
	if _is_guide_card(card):
		_add_guide_card(card, cells)
		clear_preview()
		return true

	# 重新父节点到棋盘
	card.reparent(self)
	card.set_on_board(true)
	card.z_index = RenderPriority.CARD_BASE + len(cards)


	# 记录占用
	cards.append(card)
	for c in cells:
		_grid_owner[Vector2i(c.x, c.y)] = card

	var overlapping_event := get_overlapping_unresolved_event(cells)
	var result = BoardPlacementResultScript.new(
		BoardPlacementResultScript.Kind.CHAIN_EXTENDED,
		card,
		cards.back(),
		[card],
		cells,
		overlapping_event
	)

	clear_preview()
	_publish_placement(result)
	return true


## Publishes the completed spatial transaction. ExplorationCoordinator decides when an event is requested.
func _publish_placement(result: BoardPlacementResult) -> void:
	placement_committed.emit(result)

func _is_guide_card(card: CardEntity) -> bool:
	return card.card_instance \
		and card.card_instance.card_data \
		and card.card_instance.card_data.card_type == CardData.CardType.GUIDE


func _get_card_direction(card: CardEntity) -> int:
	if card.card_instance != null:
		return card.card_instance.direction
	return _get_rotation_direction(card.rotation_degrees)


func _add_guide_card(card: CardEntity, guide_cells: Array[Vector2i]) -> void:
	var chain_snapshots: Array[Dictionary] = []
	for chain_card in cards:
		chain_snapshots.append({
			"position": chain_card.global_position,
			"rotation": chain_card.rotation_degrees,
			"direction": _get_card_direction(chain_card),
		})

	var guide_snapshot := {
		"position": card.global_position,
		"rotation": card.rotation_degrees,
		"direction": _get_card_direction(card),
	}

	# 先挂到棋盘，确保回手信号的接收方可以安全地重新挂载它。
	card.reparent(self)
	card.set_on_board(true)
	card.z_index = RenderPriority.CARD_BASE + cards.size()

	for index in range(cards.size()):
		var target_snapshot: Dictionary = guide_snapshot
		if index + 1 < chain_snapshots.size():
			target_snapshot = chain_snapshots[index + 1]

		var chain_card := cards[index]
		chain_card.global_position = target_snapshot["position"]
		chain_card.rotation_degrees = target_snapshot["rotation"]
		if chain_card.card_instance != null:
			chain_card.card_instance.direction = target_snapshot["direction"]

	_rebuild_grid_owner()

	var overlapping_event := get_overlapping_unresolved_event(guide_cells)
	var result := BoardPlacementResultScript.new(
		BoardPlacementResultScript.Kind.GUIDE_RESOLVED,
		card,
		cards.back(),
		cards.duplicate(),
		guide_cells,
		overlapping_event
	)
	_publish_placement(result)
	card_return_requested.emit(card)


func _rebuild_grid_owner() -> void:
	_grid_owner.clear()
	for chain_card in cards:
		var chain_cells := get_card_cells(
			chain_card.global_position,
			chain_card.rotation_degrees
		)
		for cell in chain_cells:
			_grid_owner[cell] = chain_card

func get_combat_card_chain() -> Array[CardInstance]:
	var chain: Array[CardInstance] = []
	for card in cards:
		if is_instance_valid(card) and card.card_instance != null:
			chain.append(card.card_instance)
	return chain

func remove_card(card: CardEntity) -> bool:
	if card not in cards:
		return false

	# 释放占用的格子
	var keys := _grid_owner.keys()
	for k in keys:
		if _grid_owner[k] == card:
			_grid_owner.erase(k)

	cards.erase(card)
	card.set_on_board(false)
	return true


# 获取某张卡牌之后的所有卡牌（按连接顺序）
func get_following_cards(card: CardEntity) -> Array[CardEntity]:
	if card not in cards:
		return []
	var idx = cards.find(card)
	if idx < 0 or idx >= cards.size() - 1:
		return []
	return cards.slice(idx + 1, cards.size())
