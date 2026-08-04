class_name CardInfoOverlay
extends CanvasLayer

const GAP := 8.0
const VIEWPORT_MARGIN := 12.0

@onready var _card_info = $CardInfo

var _active_card


func _ready() -> void:
	layer = RenderPriority.CARD_INFO_OVERLAY
	_card_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_info.hide()


func show_for_card(card) -> void:
	if card == null or card.card_instance == null or card.card_instance.card_data == null:
		return

	_active_card = card
	_card_info.set_card(card.card_instance)
	_card_info.show()
	await get_tree().process_frame

	if _active_card != card or not is_instance_valid(card):
		return

	_card_info.position = calculate_panel_position(
		card.get_card_view_screen_rect(),
		_card_info.size,
		get_viewport().get_visible_rect().size
	)


func hide_for_card(card) -> void:
	if _active_card != card:
		return

	_active_card = null
	_card_info.hide()


func calculate_panel_position(
	card_rect: Rect2,
	panel_size: Vector2,
	viewport_size: Vector2
) -> Vector2:
	var right_position := card_rect.position + Vector2(card_rect.size.x + GAP, -4.0)
	var left_position := Vector2(card_rect.position.x - GAP - panel_size.x, right_position.y)
	var position := right_position if right_position.x + panel_size.x <= viewport_size.x - VIEWPORT_MARGIN else left_position
	position.x = clampf(position.x, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, viewport_size.x - VIEWPORT_MARGIN - panel_size.x))
	position.y = clampf(position.y, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, viewport_size.y - VIEWPORT_MARGIN - panel_size.y))
	return position