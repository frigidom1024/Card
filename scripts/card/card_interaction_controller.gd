class_name CardInteractionController
extends Node

## Owns pointer state, drag lifecycle and rotation. CardEntity remains the
## compatibility facade used by HandArea/Board and receives the public signals.

var _card
var _card_view: Control
var _dragging := false
var _consume_next_left_release := false


func configure(card, card_view: Control) -> void:
	_card = card
	_card_view = card_view
	if _card_view == null:
		return
	if not _card_view.mouse_entered.is_connected(_on_card_view_mouse_entered):
		_card_view.mouse_entered.connect(_on_card_view_mouse_entered)
	if not _card_view.mouse_exited.is_connected(_on_card_view_mouse_exited):
		_card_view.mouse_exited.connect(_on_card_view_mouse_exited)
	if not _card_view.gui_input.is_connected(_on_card_view_gui_input):
		_card_view.gui_input.connect(_on_card_view_gui_input)


func configure_pointer_input(display_only: bool, market_offer: bool, info_enabled: bool, zoom_enabled: bool) -> void:
	if _card_view == null:
		return
	var accepts_preview_pointer_input := (display_only or market_offer) and (info_enabled or zoom_enabled)
	_card_view.mouse_filter = Control.MOUSE_FILTER_STOP if accepts_preview_pointer_input else Control.MOUSE_FILTER_IGNORE


func is_dragging() -> bool:
	return _dragging


func set_dragging(value: bool) -> void:
	_dragging = value
	if _card == null:
		return
	# DragLayer and legacy gameplay callers still read CardEntity._dragging.
	# Keep that compatibility state synchronized while this controller owns it.
	_card._set_dragging_state(value)
	_card.set_process(value)


func on_mouse_entered() -> void:
	if _card == null:
		return
	if _card.drag_layer and _card.drag_layer.is_drag_active():
		return
	if _card._display_only:
		if _card._display_info_enabled:
			_card._show_info(true)
		return
	if _card.state == CardEntity.State.DRAGGING or _card.state == CardEntity.State.ZOOMED:
		return
	_card._set_card_state(CardEntity.State.HOVER)
	_card._show_info(true)
	_card._set_visual_highlight(true)
	_card.hovered.emit(_card)


func on_mouse_exited() -> void:
	if _card == null:
		return
	if _card._display_only:
		if _card._display_info_enabled:
			_card._show_info(false)
		return
	if _card.state == CardEntity.State.HOVER:
		_card._set_card_state(CardEntity.State.NORMAL)
		_card._show_info(false)
		_card._set_visual_highlight(false)
		_card.unhovered.emit(_card)


func on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _card == null or not event is InputEventMouseButton:
		return

	if _card._market_offer:
		_handle_market_input(event)
		return
	if _card._display_only:
		if _card._display_zoom_enabled and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_card._show_info(false)
			_card._show_zoom()
		return

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_drag()
			elif _card.drag_layer and _card.drag_layer.is_interaction_locked():
				_consume_next_left_release = false
			elif _consume_next_left_release:
				_consume_next_left_release = false
			elif _dragging:
				end_drag()
			else:
				_card.clicked.emit(_card)
		MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				return
			_card._show_info(false)
			if _dragging:
				rotate_while_dragging()
			elif _card.state != CardEntity.State.ZOOMED and _card.state != CardEntity.State.DRAGGING:
				if _card.drag_layer and _card.drag_layer._dragged_card != null:
					return
				_card._show_zoom()


func start_drag() -> bool:
	if _card == null:
		return false
	if _card._display_only and not _card._market_offer:
		return false
	if _card.drag_layer and _card.drag_layer.is_interaction_locked():
		return false
	if _card.drag_layer and not _card.drag_layer.can_start_drag(_card):
		return false
	set_dragging(true)
	_card._set_card_state(CardEntity.State.DRAGGING)
	_card._set_drag_highlight(true)
	_card._show_info(false)
	if _card.drag_layer:
		_card.drag_layer.on_card_drag_start(_card)
	return true


func end_drag() -> bool:
	if _card == null:
		return false
	if _card.drag_layer and _card.drag_layer.is_interaction_locked():
		return false
	set_dragging(false)
	_card._set_card_state(CardEntity.State.NORMAL)
	_card._set_drag_highlight(false)
	if _card.drag_layer:
		_card.drag_layer.on_card_drag_end(_card)
	return true


func cancel_drag_for_interaction_lock() -> void:
	_consume_next_left_release = true
	cancel_drag()


func cancel_drag() -> void:
	set_dragging(false)
	_card._set_card_state(CardEntity.State.NORMAL)
	_card._set_drag_highlight(false)


func rotate_while_dragging() -> bool:
	if _card == null or _card._market_offer or not _dragging:
		return false
	_card._show_info(false)
	if _card._display_only or _card._market_offer or _card.card_instance == null:
		return false
	_card.card_instance.direction = (_card.card_instance.direction + 1) % 4
	_card.rotation_degrees = _card.card_instance.direction * 90.0
	_card._position_combat_tags()
	return true


func _process(_delta: float) -> void:
	if not _dragging or _card == null:
		return
	_card.global_position = _card.get_global_mouse_position()
	_card._position_combat_tags()


func _on_card_view_mouse_entered() -> void:
	on_mouse_entered()


func _on_card_view_mouse_exited() -> void:
	on_mouse_exited()


func _on_card_view_gui_input(event: InputEvent) -> void:
	on_input_event(_card.get_viewport(), event, 0)


func _handle_market_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			start_drag()
		elif _dragging:
			end_drag()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_card._show_info(false)
		_card._show_zoom()
