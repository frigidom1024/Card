class_name DragLayer
extends Node2D

var board: Board
var hand_area: HandArea

var _dragged_card: CardEntity = null
var interaction_locked := false

# 提示标签
var _hint_label: Label = null
var _hint_tween: Tween = null


func set_interaction_locked(locked: bool) -> void:
	interaction_locked = locked


func on_card_drag_start(card: CardEntity) -> void:
	if interaction_locked:
		return
	_dragged_card = card

	# 如果卡牌在棋盘上，释放格子 + 撤回后续卡牌
	if board and card in board.cards:
		var following = board.get_following_cards(card)
		board.remove_card(card)
		# 按顺序撤回后续卡牌
		for c in following:
			board.remove_card(c)
			c.rotation_degrees = 0
			if c.card_instance:
				c.card_instance.direction = 0
			hand_area.add_card(c)
	# 如果卡牌在手牌区，先从手牌区移除
	if hand_area and card in hand_area.cards:
		hand_area.remove_card(card, false)

	card.reparent(self)
	card.z_index = 100


func on_card_drag_end(card: CardEntity) -> void:
	if interaction_locked:
		return
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
		var cells = board.get_card_cells(pos, card.rotation_degrees)
		if board.add_card(card):
			return
		else:
			# 放置失败 → 显示提示
			var hint = board.get_placement_hint(cells, card)
			_show_hint(hint)

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
			board.preview_card(_dragged_card)
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


# 显示浮动提示
func _show_hint(text: String) -> void:
	if text.is_empty():
		return

	# 移除旧提示
	if _hint_label:
		_hint_label.queue_free()
	if _hint_tween:
		_hint_tween.kill()

	_hint_label = Label.new()
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.position = get_viewport().get_visible_rect().size / 2 - Vector2(100, 0)
	_hint_label.size = Vector2(200, 40)

	# 添加到顶层 CanvasLayer
	var canvas = CanvasLayer.new()
	canvas.layer = 256
	canvas.name = "DragHintCanvas"
	add_child(canvas)
	canvas.add_child(_hint_label)

	# 淡出动画（显示 2.5 秒后淡出）
	_hint_tween = create_tween()
	_hint_tween.set_parallel(true)
	_hint_tween.tween_interval(2.5)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.5)
	_hint_tween.finished.connect(func():
		if _hint_label:
			_hint_label.queue_free()
			_hint_label = null
		if canvas:
			canvas.queue_free()
	)
