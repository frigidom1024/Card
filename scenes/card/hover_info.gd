extends Control

const CARD_GAP := 16.0
const VIEWPORT_MARGIN := 12.0

@export var attr_label: PackedScene
@onready var attr_container: VBoxContainer = $Panel/MarginContainer/HBoxContainer

var card_inst: CardInstance
var _source_card: Control


func _ready() -> void:
	_set_mouse_filter_recursive(self)


func set_inst(value: CardInstance) -> void:
	card_inst = value


func refresh_info() -> void:
	for child in attr_container.get_children():
		attr_container.remove_child(child)
		child.queue_free()

	if card_inst == null:
		return

	_add_attr("point:%d armor:%d" % [card_inst.current_points, card_inst.current_armor])
	if card_inst.card_data == null:
		return
	for rule in card_inst.card_data.effect_rules:
		_add_attr(rule.description)


func show_for_card(source_card: Control, instance: CardInstance) -> void:
	_source_card = source_card
	set_inst(instance)
	refresh_info()
	visible = true
	_position_next_to_card(source_card)


func hide_for_card(source_card: Control) -> void:
	if _source_card != source_card:
		return
	visible = false
	_source_card = null


func _add_attr(content: String) -> void:
	var attr := attr_label.instantiate()
	attr_container.add_child(attr)
	attr.set_content(content)
	_set_mouse_filter_recursive(attr)


func _position_next_to_card(source_card: Control) -> void:
	var card_rect := _get_screen_rect(source_card)
	var viewport_size := get_viewport_rect().size
	var panel_size := size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = custom_minimum_size

	var screen_position := Vector2(card_rect.end.x + CARD_GAP, card_rect.position.y)
	if screen_position.x + panel_size.x > viewport_size.x - VIEWPORT_MARGIN:
		screen_position.x = card_rect.position.x - CARD_GAP - panel_size.x

	var maximum_position := Vector2(
		maxf(VIEWPORT_MARGIN, viewport_size.x - VIEWPORT_MARGIN - panel_size.x),
		maxf(VIEWPORT_MARGIN, viewport_size.y - VIEWPORT_MARGIN - panel_size.y),
	)
	screen_position = screen_position.clamp(
		Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN),
		maximum_position,
	)

	var parent_canvas := get_parent() as CanvasItem
	if parent_canvas == null:
		position = screen_position
		return
	position = (
		parent_canvas.get_global_transform_with_canvas().affine_inverse()
		* screen_position
	)


func _get_screen_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var corners := [
		transform * Vector2.ZERO,
		transform * Vector2(control.size.x, 0.0),
		transform * control.size,
		transform * Vector2(0.0, control.size.y),
	]
	var minimum := corners[0] as Vector2
	var maximum := corners[0] as Vector2
	for corner: Vector2 in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _set_mouse_filter_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_filter_recursive(child)
