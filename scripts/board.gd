extends Node2D

var size = 80
var width = 8
var height = 8

# 高亮区域（宽>0 时显示）
var _highlight_rect: Rect2 = Rect2(-1, -1, 0, 0)
var _highlight_color: Color = Color(1, 0.8, 0, 0.3)


func _draw():
	# 绘制网格线
	for x in width:
		for y in height:
			draw_rect(
				Rect2(x * size, y * size, size, size),
				Color.GRAY,
				false
			)

	# 绘制高亮区域（卡牌落地预览）
	if _highlight_rect.size.x > 0 and _highlight_rect.size.y > 0:
		draw_rect(_highlight_rect, _highlight_color, true)


# ----- 格子坐标 -----

## 世界坐标 → 格子坐标 (列, 行)
func get_grid_pos(world_pos: Vector2) -> Vector2i:
	var col = floori(world_pos.x / size)
	var row = floori(world_pos.y / size)
	col = clampi(col, 0, width - 1)
	row = clampi(row, 0, height - 1)
	return Vector2i(col, row)


## 格子左上角 → 世界坐标
func get_cell_topleft(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * size, grid_pos.y * size)


## 格子中心 → 世界坐标
func get_cell_center(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * size + size * 0.5,
		grid_pos.y * size + size * 0.5
	)


## 世界坐标是否在网格范围内
func is_in_grid(world_pos: Vector2) -> bool:
	return world_pos.x >= 0 \
		and world_pos.x < width * size \
		and world_pos.y >= 0 \
		and world_pos.y < height * size


# ----- 1×2 卡牌块吸附（两个格子中间）-----

## 世界坐标 → 卡牌占用的顶部格子 (col, top_row)
## 卡牌占 (col, top_row) 和 (col, top_row+1) 两格
func get_card_block(world_pos: Vector2) -> Vector2i:
	var col = roundi(world_pos.x / size - 0.5)
	var top_row = roundi(world_pos.y / size - 1)
	col = clampi(col, 0, width - 1)
	top_row = clampi(top_row, 0, height - 2)
	return Vector2i(col, top_row)


## 1×2 块的中心世界坐标（卡牌中心 = 两格中间）
func get_block_center(block_pos: Vector2i) -> Vector2:
	return Vector2(
		block_pos.x * size + size * 0.5,
		block_pos.y * size + size
	)


## 吸附到最近的 1×2 格块中心
func snap_to_block_center(world_pos: Vector2) -> Vector2:
	var block = get_card_block(world_pos)
	return get_block_center(block)


# ----- 卡牌落地预览高亮 -----

## 高亮卡牌占用的两格区域
func highlight_card_block(block_pos: Vector2i) -> void:
	_highlight_rect = Rect2(
		block_pos.x * size,
		block_pos.y * size,
		size,
		size * 2
	)
	queue_redraw()


## 清除高亮
func clear_highlight() -> void:
	if _highlight_rect.size.x > 0:
		_highlight_rect = Rect2(-1, -1, 0, 0)
		queue_redraw()


func set_grid(cell_size: int, cols: int, rows: int) -> void:
	size = cell_size
	width = cols
	height = rows
	queue_redraw()
