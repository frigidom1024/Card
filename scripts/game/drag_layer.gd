class_name DragLayer
extends Node2D

## Emitted once after the player deliberately retracts one placed card and its followers.
signal manual_chain_retracted(removed_card: CardEntity, following_card_count: int)

var board: Board
var hand_area: HandArea

var _dragged_card: CardEntity = null
var interaction_locked := false

var _drag_origin_parent: Node = null
var _drag_origin_global_position := Vector2.ZERO
var _drag_origin_rotation_degrees := 0.0
var _drag_origin_direction := 0
var _drag_origin_was_on_board := false
var _drag_origin_hand_area: HandArea = null
var _interaction_lock_recovery_container: Node2D = null

# 提示标签
var _hint_label: Label = null
var _hint_tween: Tween = null


func is_interaction_locked() -> bool:
	return interaction_locked


func set_interaction_locked(locked: bool) -> void:
	if interaction_locked == locked:
		return
	interaction_locked = locked
	if interaction_locked and _dragged_card:
		_cancel_active_drag()


func can_start_drag(card: CardEntity) -> bool:
	if interaction_locked or card == null:
		return false
	return true


func on_card_drag_start(card: CardEntity) -> void:
	if interaction_locked or card == null:
		return
	_dragged_card = card
	_drag_origin_parent = card.get_parent()
	_drag_origin_global_position = card.global_position
	_drag_origin_rotation_degrees = card.rotation_degrees
	_drag_origin_direction = card.card_instance.direction if card.card_instance else 0
	_drag_origin_was_on_board = board != null and card in board.cards
	_drag_origin_hand_area = hand_area if hand_area and card in hand_area.cards else null


	# 如果卡牌在棋盘上，释放格子 + 撤回后续卡牌
	if _drag_origin_was_on_board:
		var following = board.get_following_cards(card)
		board.remove_card(card)
		# 按顺序撤回后续卡牌
		for c in following:
			board.remove_card(c)
			c.rotation_degrees = 0
			if c.card_instance:
				c.card_instance.direction = 0
			if hand_area:
				hand_area.add_card(c)
		manual_chain_retracted.emit(card, following.size())
	# 如果卡牌在手牌区，先从手牌区移除
	if _drag_origin_hand_area:
		_drag_origin_hand_area.remove_card(card, false)

	card.reparent(self)
	card.z_index = RenderPriority.CARD_DRAGGING


func on_card_drag_end(card: CardEntity) -> void:
	if interaction_locked:
		return
	_dragged_card = null
	_clear_drag_origin()
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


func _cancel_active_drag() -> void:
	var card := _dragged_card
	_dragged_card = null
	if board:
		board.clear_preview()
	if card == null or not is_instance_valid(card):
		_clear_drag_origin()
		return

	card.cancel_drag_for_interaction_lock()
	_restore_drag_origin_transform(card)
	if _drag_origin_was_on_board:
		if board and board.add_card(card):
			_clear_drag_origin()
			return
		push_error("Failed to restore Board card after interaction lock")
		_restore_failed_board_card_to_hand(card)
	else:
		_restore_card_to_origin_parent(card)
	_clear_drag_origin()


func _restore_drag_origin_transform(card: CardEntity) -> void:
	card.global_position = _drag_origin_global_position
	card.rotation_degrees = _drag_origin_rotation_degrees
	if card.card_instance:
		card.card_instance.direction = _drag_origin_direction


func _restore_failed_board_card_to_hand(card: CardEntity) -> void:
	if _return_card_to_hand_for_interaction_recovery(card):
		return
	push_error("Unable to return failed Board restore to HandArea; holding card for recovery")
	_hold_card_for_interaction_recovery(card)


func _return_card_to_hand_for_interaction_recovery(card: CardEntity) -> bool:
	if hand_area == null or not is_instance_valid(hand_area):
		return false

	# A lock cancellation returns an existing player card; it is not a capacity-limited reward.
	var original_max_hand_size := hand_area.max_hand_size
	if hand_area.cards.size() >= hand_area.max_hand_size:
		hand_area.max_hand_size = hand_area.cards.size() + 1
	var restored := hand_area.add_card(card, false)
	hand_area.max_hand_size = original_max_hand_size
	return restored


func _hold_card_for_interaction_recovery(card: CardEntity) -> void:
	var container := _get_or_create_interaction_lock_recovery_container()
	if card.get_parent():
		card.reparent(container)
	else:
		container.add_child(card)


func _get_or_create_interaction_lock_recovery_container() -> Node2D:
	if _interaction_lock_recovery_container and is_instance_valid(_interaction_lock_recovery_container):
		return _interaction_lock_recovery_container

	_interaction_lock_recovery_container = Node2D.new()
	_interaction_lock_recovery_container.name = "InteractionLockRecovery"
	_interaction_lock_recovery_container.visible = false
	add_child(_interaction_lock_recovery_container)
	return _interaction_lock_recovery_container


func _restore_card_to_origin_parent(card: CardEntity) -> void:
	if _drag_origin_hand_area:
		if not _drag_origin_hand_area.add_card(card, false):
			push_error("Failed to restore hand card after interaction lock")
		return
	if not _drag_origin_was_on_board and _drag_origin_parent and is_instance_valid(_drag_origin_parent):
		card.reparent(_drag_origin_parent)
		_restore_drag_origin_transform(card)


func _clear_drag_origin() -> void:
	_drag_origin_parent = null
	_drag_origin_global_position = Vector2.ZERO
	_drag_origin_rotation_degrees = 0.0
	_drag_origin_direction = 0
	_drag_origin_was_on_board = false
	_drag_origin_hand_area = null


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
	canvas.layer = RenderPriority.DRAG_HINT
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
