class_name LayoutConfig
extends RefCounted

## 全局布局唯一尺寸基准（桌面 16:9）。改这一个文件即可调整所有比例。

const CELL_SIZE    := 86
const CARD_MARGIN  := 6
const CARD_W       := CELL_SIZE - CARD_MARGIN
const CARD_H       := CELL_SIZE * 2 - CARD_MARGIN
const HAND_SPACING := int(CELL_SIZE * 0.35)
const HAND_STEP    := CARD_W + HAND_SPACING
const BOARD_TOP_MARGIN    := 16.0
const HAND_BOTTOM_MARGIN  := 96.0


## 卡面在卡牌实体局部坐标下的矩形（以两格中心为原点）
static func card_view_rect(cell_size: int) -> Rect2:
	var w := cell_size - CARD_MARGIN
	var h := cell_size * 2 - CARD_MARGIN
	return Rect2(-w / 2.0, -h / 2.0, w, h)


## 棋盘节点原点：水平居中，垂直方向让出底部手牌区
static func board_origin(
	view_size: Vector2, grid_cols: int, grid_rows: int, cell_size: int
) -> Vector2:
	return Vector2((view_size.x - grid_cols * cell_size) / 2.0, BOARD_TOP_MARGIN)


## 手牌节点原点：水平居中，中心距屏幕底部 HAND_BOTTOM_MARGIN
static func hand_origin(view_size: Vector2) -> Vector2:
	return Vector2(view_size.x / 2.0, view_size.y - HAND_BOTTOM_MARGIN)
