@tool
class_name HandTray
extends Control

@export_group("Layout")
@export_range(0.76, 0.82, 0.01) var width_ratio := 0.80:
	set(value):
		width_ratio = value
		_apply_visuals()
@export_range(210.0, 240.0, 1.0) var tray_height := 224.0:
	set(value):
		tray_height = value
		_apply_visuals()
@export_range(0.0, 48.0, 1.0) var bottom_bleed := 20.0:
	set(value):
		bottom_bleed = value
		_apply_visuals()

@export_group("Palette")
@export var tray_color := Color("0a1220d9"):
	set(value):
		tray_color = value
		_apply_visuals()
@export var lining_color := Color("9b90736b"):
	set(value):
		lining_color = value
		_apply_visuals()
@export var trim_color := Color("b7964f99"):
	set(value):
		trim_color = value
		_apply_visuals()
@export var show_side_ornaments := true:
	set(value):
		show_side_ornaments = value
		_apply_visuals()


func _ready() -> void:
	_apply_visuals()


func set_hand_count(current_count: int, max_count: int) -> void:
	($HandCount as Label).text = "HAND · %d / %d" % [current_count, max_count]


func _apply_visuals() -> void:
	var design_size := LayoutConfig.DESIGN_VIEWPORT_SIZE
	var tray_width := design_size.x * width_ratio
	size = Vector2(tray_width, tray_height)
	position = Vector2((design_size.x - tray_width) * 0.5, design_size.y - tray_height + bottom_bleed)
	_set_mouse_transparent(self)

	var outer_tray := get_node_or_null("OuterTray") as Panel
	if outer_tray != null:
		outer_tray.position = Vector2.ZERO
		outer_tray.size = size
		outer_tray.add_theme_stylebox_override("panel", _make_panel_style(tray_color, 12, trim_color))

	var inner_lining := get_node_or_null("InnerLining") as Panel
	if inner_lining != null:
		inner_lining.position = Vector2(48.0, 34.0)
		inner_lining.size = Vector2(tray_width - 96.0, tray_height - 58.0)
		inner_lining.add_theme_stylebox_override("panel", _make_panel_style(lining_color, 10, Color.TRANSPARENT))

	var top_trim := get_node_or_null("TopTrim") as ColorRect
	if top_trim != null:
		top_trim.position = Vector2(48.0, 20.0)
		top_trim.size = Vector2(tray_width - 96.0, 3.0)
		top_trim.color = trim_color

	var left_clasp := get_node_or_null("LeftClasp") as ColorRect
	if left_clasp != null:
		left_clasp.position = Vector2(28.0, 14.0)
		left_clasp.size = Vector2(12.0, 24.0)
		left_clasp.color = trim_color
		left_clasp.visible = show_side_ornaments

	var right_clasp := get_node_or_null("RightClasp") as ColorRect
	if right_clasp != null:
		right_clasp.position = Vector2(tray_width - 40.0, 14.0)
		right_clasp.size = Vector2(12.0, 24.0)
		right_clasp.color = trim_color
		right_clasp.visible = show_side_ornaments

	var hand_count := get_node_or_null("HandCount") as Label
	if hand_count != null:
		hand_count.position = Vector2(48.0, 32.0)
		hand_count.size = Vector2(tray_width - 96.0, 24.0)

	var future_info_anchor := get_node_or_null("FutureInfoAnchor") as Control
	if future_info_anchor != null:
		future_info_anchor.position = Vector2(tray_width - 48.0, 32.0)


func _make_panel_style(background_color: Color, radius: int, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_color = border_color
	return style


func _set_mouse_transparent(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_transparent(child)
