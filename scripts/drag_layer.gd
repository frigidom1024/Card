class_name DragLayer
extends Node2D

var board: Board
var hand_area: HandArea

var _dragged_card: CardEntity = null


func on_card_drag_start(card: CardEntity) -> void:
	_dragged_card = card

	# 如果卡牌在棋盘上，先释放格子
	if board and card in board.cards:
		board.remove_card(card)
	# 如果卡牌在手牌区，先从手牌区移除
	if hand_area and card in hand_area.cards:
		hand_area.remove_card(card, false)

	card.reparent(self)
	card.z_index = 100


func on_card_drag_end(card: CardEntity) -> void:
	_dragged_card = null
	board.clear_preview()

	# 平滑缩放到正常大小（手牌区可能有缩放残留）
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.15)

	var pos = card.global_position

	# 1) 尝试放置到棋盘
	if _is_over_board(pos):
		if board.add_card(card):
			return

	# 2) 回手牌 — 重置旋转保证手牌视觉一致
	card.rotation_degrees = 0
	if card.card_instance:
		card.card_instance.direction = 0
	hand_area.add_card(card)


func _process(_delta: float) -> void:
	# 拖拽过程中实时更新棋盘预览
	if _dragged_card and board:
		var pos = _dragged_card.global_position
		if _is_over_board(pos):
			board.preview_card(pos, _dragged_card.rotation_degrees)
		else:
			board.clear_preview()


func _is_over_board(pos: Vector2) -> bool:
	if not board:
		return false

	var local_pos = board.to_local(pos)
	var grid_w = board.width * board.cell_size
	var grid_h = board.height * board.cell_size
	var board_rect = Rect2(0, 0, grid_w, grid_h)
	return board_rect.has_point(local_pos)
