class_name CardDisplayController
extends Node

## Owns CardView-only display updates. Interaction and game state remain outside
## this controller so visual changes never decide card gameplay behavior.

var _card_view: Control


func configure(card_view: Control) -> void:
	_card_view = card_view


func bind_instance(instance: CardInstance) -> void:
	if _card_view == null:
		return
	_card_view.set_value(instance)
	_card_view.refresh_display()


func set_on_board(value: bool) -> void:
	if _card_view == null:
		return
	_card_view.set_head_indicator_visible(value)


func set_interaction_highlight(active: bool) -> void:
	if _card_view == null:
		return
	_card_view.modulate = Color(1.1, 1.1, 1.1) if active else Color.WHITE


func set_drag_highlight(active: bool) -> void:
	if _card_view == null:
		return
	_card_view.modulate = Color(1.2, 1.2, 1.0) if active else Color.WHITE


func apply_layout(cell_size: float) -> Rect2:
	if _card_view == null:
		return Rect2()
	var rect := LayoutConfig.card_view_rect(cell_size)
	_card_view.offset_left = rect.position.x
	_card_view.offset_top = rect.position.y
	_card_view.offset_right = rect.position.x + rect.size.x
	_card_view.offset_bottom = rect.position.y + rect.size.y
	return rect


func get_screen_rect() -> Rect2:
	if _card_view == null:
		return Rect2()
	var transform := _card_view.get_global_transform_with_canvas()
	var screen_rect := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for corner in [
		Vector2.ZERO,
		Vector2(_card_view.size.x, 0.0),
		Vector2(0.0, _card_view.size.y),
		_card_view.size,
	]:
		screen_rect = screen_rect.expand(transform * corner)
	return screen_rect
