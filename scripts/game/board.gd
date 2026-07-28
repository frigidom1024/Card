class_name Board
extends Node2D

@export var cell_size: int = 80
@export var width: int = 10
@export var height: int = 8

@export var drop_detector: Area2D

var highlight_cells: Array[Vector2i] = []
var highlight_valid_color := Color(1, 0.8, 0, 0.3)      # 可放置
var highlight_invalid_color := Color(1, 0.2, 0.2, 0.4)  # 不可放置
var preview_valid: bool = true

var cards: Array[CardEntity] = []

# 格子占用表：Vector2i → CardEntity
var _grid_owner: Dictionary = {}



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

func get_card_cells(
	center: Vector2,
	rotation: float
) -> Array[Vector2i]:


	var dir = int(round(rotation / 90.0)) % 4
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
# 预览
# =========================
func preview_card(card: CardEntity):
	var cells = get_card_cells(card.global_position, card.rotation_degrees)
	highlight_cells = cells

	# 检查是否可放置
	var cells_in_bounds = true
	for c in cells:
		if c.x < 0 or c.x >= width or c.y < 0 or c.y >= height:
			cells_in_bounds = false
			break
	var no_conflict = not has_conflict(cells)
	var placement_ok = can_place_card(cells, card)

	preview_valid = cells_in_bounds and no_conflict and placement_ok

	queue_redraw()


# 获取放置失败的原因文字
func get_placement_hint(cells: Array[Vector2i], card: CardEntity) -> String:
	for c in cells:
		if c.x < 0 or c.x >= width or c.y < 0 or c.y >= height:
			return "超出棋盘边界"
	if has_conflict(cells):
		return "该位置已被占用"
	if card and not _is_root_card(card):
		if cards.is_empty():
			return "棋盘上还没有可连接的卡牌"
		return "需放置在上一张卡的顶部朝向方向"
	return ""



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
	for c in cells:
		if c.x < 0 or c.x >= width:
			return false
		if c.y < 0 or c.y >= height:
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
	var dir = int(round(card.rotation_degrees / 90.0)) % 4
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

	# 重新父节点到棋盘
	card.reparent(self)
	card.z_index = len(cards)


	# 记录占用
	cards.append(card)
	for c in cells:
		_grid_owner[Vector2i(c.x, c.y)] = card

	clear_preview()
	return true

func remove_card(card: CardEntity) -> bool:
	if card not in cards:
		return false

	# 释放占用的格子
	var keys := _grid_owner.keys()
	for k in keys:
		if _grid_owner[k] == card:
			_grid_owner.erase(k)

	cards.erase(card)
	return true


# 获取某张卡牌之后的所有卡牌（按连接顺序）
func get_following_cards(card: CardEntity) -> Array[CardEntity]:
	if card not in cards:
		return []
	var idx = cards.find(card)
	if idx < 0 or idx >= cards.size() - 1:
		return []
	return cards.slice(idx + 1, cards.size())
