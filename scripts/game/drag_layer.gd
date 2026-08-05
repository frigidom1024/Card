class_name DragLayer
extends Node2D

## Emitted once after the player deliberately retracts one placed card and its followers.
signal manual_chain_retracted(removed_card: CardEntity, following_card_count: int)
signal market_purchase_requested(card: CardEntity, slot_index: int)
signal market_reclaim_requested(card: CardEntity)

var board: Board
var hand_area: HandArea
var persistent_market
var purchase_drop_target: Control

var _dragged_card: CardEntity = null
var interaction_locked := false

var _drag_origin_parent: Node = null
var _drag_origin_global_position := Vector2.ZERO
var _drag_origin_rotation_degrees := 0.0
var _drag_origin_direction := 0
var _drag_origin_was_on_board := false
var _drag_origin_hand_area: HandArea = null
var _drag_origin_market_slot := -1
var _drag_origin_is_market_offer := false
var _interaction_lock_recovery_container: Node2D = null
var _completed_market_reclaims: Array[CardEntity] = []

# 提示标签
var _hint_label: Label = null
var _hint_tween: Tween = null



func set_market_context(market, hand_drop_target: Control) -> void:
	persistent_market = market
	purchase_drop_target = hand_drop_target
	if persistent_market != null and persistent_market.has_method("set_drag_layer"):
		persistent_market.call("set_drag_layer", self)

func is_interaction_locked() -> bool:
	return interaction_locked


func is_drag_active() -> bool:
	return _dragged_card != null


func _input(event: InputEvent) -> void:
	if interaction_locked or _dragged_card == null:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	if _dragged_card.rotate_while_dragging():
		get_viewport().set_input_as_handled()


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
	_drag_origin_is_market_offer = card.is_market_offer() if card.has_method("is_market_offer") else false
	_drag_origin_market_slot = persistent_market.get_offer_slot_for_card(card) if _drag_origin_is_market_offer and persistent_market != null else -1
	_drag_origin_was_on_board = board != null and card in board.cards
	_drag_origin_hand_area = hand_area if hand_area and card in hand_area.cards else null

	if _drag_origin_is_market_offer:
		card.reparent(self)
		card.z_index = RenderPriority.CARD_DRAGGING
		return

	if _drag_origin_was_on_board:
		var following = board.get_following_cards(card)
		board.remove_card(card)
		for following_card in following:
			board.remove_card(following_card)
			following_card.rotation_degrees = 0
			if following_card.card_instance:
				following_card.card_instance.direction = 0
			if hand_area:
				hand_area.add_card(following_card)
		manual_chain_retracted.emit(card, following.size())
	if _drag_origin_hand_area:
		_drag_origin_hand_area.remove_card(card, false)

	card.reparent(self)
	card.z_index = RenderPriority.CARD_DRAGGING


func on_card_drag_end(card: CardEntity) -> void:
	if interaction_locked or card == null:
		return

	var was_market_offer := _drag_origin_is_market_offer
	var market_slot := _drag_origin_market_slot
	var origin_hand := _drag_origin_hand_area
	var pos := card.global_position
	if board:
		board.clear_preview()

	_dragged_card = null
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.15)

	if was_market_offer:
		if _is_over_purchase_target(pos) and market_slot >= 0:
			market_purchase_requested.emit(card, market_slot)
		if is_instance_valid(card) and card.get_parent() == self:
			_restore_card_to_origin_parent(card)
		_clear_drag_origin()
		return

	if persistent_market != null and persistent_market.has_method("is_over_reclaim_target") and persistent_market.call("is_over_reclaim_target", pos):
		market_reclaim_requested.emit(card)
		if _completed_market_reclaims.has(card):
			_completed_market_reclaims.erase(card)
			card.queue_free()
			_clear_drag_origin()
			return
		if is_instance_valid(card) and card.get_parent() == self and origin_hand != null:
			_restore_card_to_origin_parent(card)
		_clear_drag_origin()
		return

	if _is_over_board(pos):
		var cells = board.get_card_cells(pos, card.rotation_degrees)
		if board.add_card(card):
			_clear_drag_origin()
			return
		_show_hint(board.get_placement_hint(cells, card))

	card.rotation_degrees = 0
	if card.card_instance:
		card.card_instance.direction = 0
	if hand_area:
		hand_area.add_card(card)
	_clear_drag_origin()


func _is_over_purchase_target(global_position: Vector2) -> bool:
	return purchase_drop_target != null and purchase_drop_target.get_global_rect().has_point(global_position)

func confirm_market_reclaim(card: CardEntity) -> void:
	if card != null and not _completed_market_reclaims.has(card):
		_completed_market_reclaims.append(card)

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
	_drag_origin_market_slot = -1
	_drag_origin_is_market_offer = false

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
