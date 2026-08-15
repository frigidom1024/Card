extends Control

const CARD_GAP := 16.0
const VIEWPORT_MARGIN := 12.0
const PANEL_WIDTH := 440.0
const PIXEL_FONT := preload("res://assert/font/press_start_2p/PressStart2P.ttf")

const RARITY_NAMES := {
	CardData.Rarity.COMMON: "COMMON",
	CardData.Rarity.RARE: "RARE",
	CardData.Rarity.EPIC: "EPIC",
	CardData.Rarity.LEGENDARY: "LEGENDARY",
}
const RARITY_COLORS := {
	CardData.Rarity.COMMON: Color("c6c2bd"),
	CardData.Rarity.RARE: Color("58a6ff"),
	CardData.Rarity.EPIC: Color("b058f7"),
	CardData.Rarity.LEGENDARY: Color("f5ad42"),
}
const CATEGORY_TAGS := [
	CardData.CardTag.LOCATION,
	CardData.CardTag.CREATURE,
	CardData.CardTag.ITEM,
	CardData.CardTag.EVENT,
]
const CATEGORY_NAMES := {
	CardData.CardTag.LOCATION: "LOCATION",
	CardData.CardTag.CREATURE: "CREATURE",
	CardData.CardTag.ITEM: "ITEM",
	CardData.CardTag.EVENT: "EVENT",
}
const CARD_TYPE_NAMES := {
	CardData.CardType.ROOT: "ROOT",
	CardData.CardType.NORMAL: "NORMAL",
	CardData.CardType.GUIDE: "GUIDE",
}

@onready var panel: PanelContainer = $Panel
@onready var rarity_badge: PanelContainer = $Panel/Margin/Layout/BadgeRow/RarityBadge
@onready var rarity_label: Label = $Panel/Margin/Layout/BadgeRow/RarityBadge/RarityLabel
@onready var category_label: Label = $Panel/Margin/Layout/BadgeRow/CategoryBadge/CategoryLabel
@onready var title_label: Label = $Panel/Margin/Layout/TitlePanel/TitleLabel
@onready var description_label: Label = $Panel/Margin/Layout/DescriptionLabel
@onready var point_value_label: Label = $Panel/Margin/Layout/Stats/PointRow/ValueLabel
@onready var armor_value_label: Label = $Panel/Margin/Layout/Stats/ArmorRow/ValueLabel
@onready var rules_container: VBoxContainer = $Panel/Margin/Layout/Stats/Rules

var card_inst: CardInstance
var _source_card: Control


func _ready() -> void:
	_set_mouse_filter_recursive(self)
	call_deferred("_fit_to_content")


func set_inst(value: CardInstance) -> void:
	card_inst = value


func refresh_info() -> void:
	_clear_rules()

	if card_inst == null:
		_clear_card_content()
		return

	point_value_label.text = str(card_inst.current_points)
	armor_value_label.text = str(card_inst.current_armor)

	var card_data := card_inst.card_data
	if card_data == null:
		_clear_card_content()
		point_value_label.text = str(card_inst.current_points)
		armor_value_label.text = str(card_inst.current_armor)
		return

	rarity_label.text = RARITY_NAMES.get(card_data.rarity, "COMMON")
	category_label.text = _get_category_name(card_data)
	title_label.text = card_data.card_name if not card_data.card_name.is_empty() else "UNKNOWN CARD"
	description_label.text = card_data.description
	description_label.visible = not card_data.description.is_empty()
	_update_rarity_badge(card_data.rarity)

	for rule in card_data.effect_rules:
		if rule == null or rule.description.strip_edges().is_empty():
			continue
		_add_rule(rule.description)

	rules_container.visible = rules_container.get_child_count() > 0
	call_deferred("_fit_to_content")


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


func _clear_card_content() -> void:
	rarity_label.text = "COMMON"
	category_label.text = "NORMAL"
	title_label.text = "UNKNOWN CARD"
	description_label.text = ""
	description_label.visible = false
	rules_container.visible = false
	_update_rarity_badge(CardData.Rarity.COMMON)
	call_deferred("_fit_to_content")


func _clear_rules() -> void:
	for child in rules_container.get_children():
		rules_container.remove_child(child)
		child.queue_free()


func _add_rule(content: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var icon := Label.new()
	icon.custom_minimum_size = Vector2(28.0, 0.0)
	icon.text = "+"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_color_override("font_color", Color("b86cff"))
	icon.add_theme_font_override("font", PIXEL_FONT)
	icon.add_theme_font_size_override("font_size", 16)
	row.add_child(icon)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("eceae3"))
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	rules_container.add_child(row)
	_set_mouse_filter_recursive(row)


func _get_category_name(card_data: CardData) -> String:
	for tag in CATEGORY_TAGS:
		if card_data.tags.has(tag):
			return CATEGORY_NAMES.get(tag, "NORMAL")
	return CARD_TYPE_NAMES.get(card_data.card_type, "NORMAL")


func _update_rarity_badge(rarity: int) -> void:
	var rarity_color: Color = RARITY_COLORS.get(rarity, RARITY_COLORS[CardData.Rarity.COMMON])
	rarity_label.add_theme_color_override("font_color", rarity_color)
	var badge_style := rarity_badge.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if badge_style == null:
		return
	badge_style.border_color = rarity_color
	rarity_badge.add_theme_stylebox_override("panel", badge_style)


func _fit_to_content() -> void:
	var minimum_size := get_combined_minimum_size()
	size = Vector2(PANEL_WIDTH, minimum_size.y)
	if _source_card != null and is_instance_valid(_source_card):
		_position_next_to_card(_source_card)


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
