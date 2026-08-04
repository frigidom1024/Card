@tool
class_name PilgrimCrestHud
extends Control

@export_group("Content")
@export var pilgrim_title := "PILGRIM":
	set(value):
		pilgrim_title = value
		_apply_visuals()
@export var pilgrim_subtitle := "LAST KNIGHT":
	set(value):
		pilgrim_subtitle = value
		_apply_visuals()
@export var map_name := "RIBWOOD":
	set(value):
		map_name = value
		_apply_visuals()
@export var crest_glyph := "✦":
	set(value):
		crest_glyph = value
		_apply_visuals()

@export_group("Layout")
@export var outer_margin := Vector2(40, 36):
	set(value):
		outer_margin = value
		_apply_visuals()
@export_range(250.0, 290.0, 1.0) var plaque_width := 270.0:
	set(value):
		plaque_width = value
		_apply_visuals()
@export_range(210.0, 250.0, 1.0) var compact_height := 224.0:
	set(value):
		compact_height = value
		_apply_visuals()
@export_range(20.0, 56.0, 1.0) var status_height := 34.0:
	set(value):
		status_height = value
		_apply_visuals()

@export_group("Palette")
@export var plaque_color := Color("0a1220e6"):
	set(value):
		plaque_color = value
		_apply_visuals()
@export var inset_color := Color("77726033"):
	set(value):
		inset_color = value
		_apply_visuals()
@export var trim_color := Color("b7964fbf"):
	set(value):
		trim_color = value
		_apply_visuals()
@export var text_color := Color("e9dfc8"):
	set(value):
		text_color = value
		_apply_visuals()
@export var muted_text_color := Color("b8ad91"):
	set(value):
		muted_text_color = value
		_apply_visuals()
@export var vitality_fill_color := Color("8c3137"):
	set(value):
		vitality_fill_color = value
		_apply_visuals()
@export var vitality_track_color := Color("201c24"):
	set(value):
		vitality_track_color = value
		_apply_visuals()
@export var status_color := Color("9b5d48"):
	set(value):
		status_color = value
		_apply_visuals()

var _current_hp := 0
var _max_hp := 1
var _current_faith := 0
var _temporary_status := ""


func _ready() -> void:
	_apply_visuals()
	set_vitality(_current_hp, _max_hp)
	set_faith(_current_faith)
	set_temporary_status(_temporary_status)


func set_display_context(title: String, subtitle: String, location_name: String) -> void:
	pilgrim_title = title
	pilgrim_subtitle = subtitle
	map_name = location_name
	_apply_visuals()


func set_vitality(current_hp: int, max_hp: int) -> void:
	_current_hp = current_hp
	_max_hp = max(1, max_hp)
	var vitality_value := get_node_or_null("VitalityValue") as Label
	if vitality_value != null:
		vitality_value.text = "%d / %d" % [_current_hp, _max_hp]
	var vitality_bar := get_node_or_null("VitalityBar") as ProgressBar
	if vitality_bar != null:
		vitality_bar.max_value = _max_hp
		vitality_bar.value = clampi(_current_hp, 0, _max_hp)


func set_faith(current_faith: int) -> void:
	_current_faith = current_faith
	var faith_value := get_node_or_null("FaithSeal/FaithValue") as Label
	if faith_value != null:
		faith_value.text = "FAITH · %d" % _current_faith


func set_temporary_status(status_text: String) -> void:
	_temporary_status = status_text.strip_edges()
	var status_row := get_node_or_null("StatusRow") as Control
	if status_row != null:
		status_row.visible = not _temporary_status.is_empty()
	var status_label := get_node_or_null("StatusRow/StatusLabel") as Label
	if status_label != null:
		status_label.text = _temporary_status
	_apply_visuals()


func _apply_visuals() -> void:
	var active_status := not _temporary_status.is_empty()
	size = Vector2(plaque_width, compact_height + (status_height if active_status else 0.0))
	position = outer_margin
	_set_mouse_transparent(self)

	var outer_plaque := get_node_or_null("OuterPlaque") as Panel
	if outer_plaque != null:
		outer_plaque.position = Vector2.ZERO
		outer_plaque.size = size
		outer_plaque.add_theme_stylebox_override("panel", _make_panel_style(plaque_color, 10, trim_color, 1))

	var bone_inset := get_node_or_null("BoneInset") as Panel
	if bone_inset != null:
		bone_inset.position = Vector2(14, 14)
		bone_inset.size = Vector2(plaque_width - 28, compact_height - 28)
		bone_inset.add_theme_stylebox_override("panel", _make_panel_style(inset_color, 7, Color("ffffff18"), 1))

	var crest := get_node_or_null("CrestGlyph") as Label
	if crest != null:
		crest.position = Vector2(24, 22)
		crest.size = Vector2(30, 26)
		crest.text = crest_glyph
		crest.add_theme_color_override("font_color", trim_color)

	var identity := get_node_or_null("IdentityLabel") as Label
	if identity != null:
		identity.position = Vector2(58, 18)
		identity.size = Vector2(plaque_width - 82, 26)
		identity.text = pilgrim_title
		identity.add_theme_color_override("font_color", text_color)

	var subtitle := get_node_or_null("SubtitleLabel") as Label
	if subtitle != null:
		subtitle.position = Vector2(58, 45)
		subtitle.size = Vector2(plaque_width - 82, 20)
		subtitle.text = pilgrim_subtitle
		subtitle.add_theme_color_override("font_color", muted_text_color)

	var map_label := get_node_or_null("MapLabel") as Label
	if map_label != null:
		map_label.position = Vector2(24, 70)
		map_label.size = Vector2(plaque_width - 48, 20)
		map_label.text = map_name
		map_label.add_theme_color_override("font_color", trim_color)

	var divider := get_node_or_null("HeaderDivider") as ColorRect
	if divider != null:
		divider.position = Vector2(24, 94)
		divider.size = Vector2(plaque_width - 48, 1)
		divider.color = trim_color

	var vitality_title := get_node_or_null("VitalityTitle") as Label
	if vitality_title != null:
		vitality_title.position = Vector2(24, 111)
		vitality_title.size = Vector2(80, 18)
		vitality_title.add_theme_color_override("font_color", muted_text_color)

	var vitality_value := get_node_or_null("VitalityValue") as Label
	if vitality_value != null:
		vitality_value.position = Vector2(24, 130)
		vitality_value.size = Vector2(plaque_width - 48, 42)
		vitality_value.add_theme_color_override("font_color", text_color)

	var vitality_bar := get_node_or_null("VitalityBar") as ProgressBar
	if vitality_bar != null:
		vitality_bar.position = Vector2(24, 177)
		vitality_bar.size = Vector2(plaque_width - 48, 10)
		vitality_bar.add_theme_stylebox_override("background", _make_panel_style(vitality_track_color, 4, Color.TRANSPARENT, 0))
		vitality_bar.add_theme_stylebox_override("fill", _make_panel_style(vitality_fill_color, 4, Color("c87b60"), 1))

	var faith_seal := get_node_or_null("FaithSeal") as Panel
	if faith_seal != null:
		faith_seal.position = Vector2(24, 194)
		faith_seal.size = Vector2(124, 26)
		faith_seal.add_theme_stylebox_override("panel", _make_panel_style(Color("352d20"), 4, trim_color, 1))

	var faith_value := get_node_or_null("FaithSeal/FaithValue") as Label
	if faith_value != null:
		faith_value.position = Vector2.ZERO
		faith_value.size = faith_seal.size if faith_seal != null else Vector2(124, 26)
		faith_value.add_theme_color_override("font_color", trim_color)

	var status_row := get_node_or_null("StatusRow") as Panel
	if status_row != null:
		status_row.position = Vector2(14, compact_height - 4)
		status_row.size = Vector2(plaque_width - 28, status_height - 10)
		status_row.visible = active_status
		status_row.add_theme_stylebox_override("panel", _make_panel_style(Color("2e1d20d9"), 4, status_color, 1))

	var status_label := get_node_or_null("StatusRow/StatusLabel") as Label
	if status_label != null:
		status_label.position = Vector2(10, 0)
		status_label.size = Vector2(plaque_width - 48, status_height - 10)
		status_label.add_theme_color_override("font_color", Color("ddb69a"))


func _make_panel_style(background_color: Color, radius: int, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_width_left = border_width
	style.border_color = border_color
	return style


func _set_mouse_transparent(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_transparent(child)
