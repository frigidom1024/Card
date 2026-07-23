extends Node2D

@export var card_entity:Area2D
@export var cell_size: int = 80
@export var width: int = 10
@export var height: int = 8



var highlight_cells: Array[Vector2i] = []
var highlight_color := Color(1, 0.8, 0, 0.3)

var cards: Array[CardEntity] = []

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


	# 绘制卡牌预览
	for cell in highlight_cells:

		draw_rect(
			Rect2(
				cell.x * cell_size,
				cell.y * cell_size,
				cell_size,
				cell_size
			),
			highlight_color,
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

	var local_pos = to_local(center)

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
func preview_card(
	center:Vector2,
	rotation:float
):

	highlight_cells = get_card_cells(
		center,
		rotation
	)

	queue_redraw()



func clear_preview():
	highlight_cells.clear()
	queue_redraw()

# =========================
# 边界检查
# =========================

func can_place_card(
	cells:Array[Vector2i]
)->bool:
	for c in cells:

		if c.x < 0 or c.x >= width:
			return false

		if c.y < 0 or c.y >= height:
			return false

	return true
