extends PanelContainer

const CardViewScene = preload("res://scenes/card_view/card_view.tscn")
const CardDetailStatSealScene = preload("res://scenes/card_view/card_detail_stat_seal.tscn")

var card_inst: CardInstance

@onready var card_preview_host: CenterContainer = $SheetMargin/Sheet/ContentRow/CardPreviewHost
@onready var meta_label: Label = $SheetMargin/Sheet/ContentRow/DetailColumn/MetaLabel
@onready var title_label: Label = $SheetMargin/Sheet/ContentRow/DetailColumn/TitleLabel
@onready var card_id_label: Label = $SheetMargin/Sheet/ContentRow/DetailColumn/CardIdLabel
@onready var stats: HBoxContainer = $SheetMargin/Sheet/ContentRow/DetailColumn/Stats
@onready var description_label: Label = $SheetMargin/Sheet/ContentRow/DetailColumn/DescriptionLabel
@onready var tags: FlowContainer = $SheetMargin/Sheet/ContentRow/DetailColumn/Tags


func _ready() -> void:
	if not card_inst:
		card_inst = CardInstance.create_debug_card()
	refresh_display()


func set_data(card_instance: CardInstance) -> void:
	card_inst = card_instance
	if is_node_ready():
		refresh_display()


func refresh_display() -> void:
	if not card_inst or not card_inst.card_data:
		return

	var data := card_inst.card_data
	_update_preview()
	meta_label.text = "%s · %s" % [
		CardDetailFormat.rarity_name(data.rarity),
		CardDetailFormat.card_type_name(data.card_type),
	]
	title_label.text = data.card_name
	card_id_label.text = "RECORD %03d" % data.card_id
	_update_stats(data)
	description_label.text = data.description
	description_label.visible = not data.description.strip_edges().is_empty()
	_update_tags(data.tags)


func _update_preview() -> void:
	var preview := card_preview_host.get_node_or_null("CardPreview") as Control
	if not preview:
		preview = CardViewScene.instantiate() as Control
		preview.name = "CardPreview"
		card_preview_host.add_child(preview)
	preview.custom_minimum_size = Vector2(252, 378)
	preview.size = Vector2(252, 378)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.set_value(card_inst)
	preview.refresh_display()


func _update_stats(data: CardData) -> void:
	_clear_children(stats)
	for entry in CardDetailFormat.stat_entries(data):
		var seal := CardDetailStatSealScene.instantiate() as CardDetailStatSeal
		stats.add_child(seal)
		seal.configure(entry["attribute"], entry["value"])
	stats.visible = stats.get_child_count() > 0


func _update_tags(card_tags: Array) -> void:
	_clear_children(tags)
	for tag in card_tags:
		tags.add_child(_create_tag_label(CardDetailFormat.tag_name(tag)))
	tags.visible = tags.get_child_count() > 0


func _create_tag_label(label_text: String) -> Label:
	var tag_label := Label.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left = 7.0
	style.content_margin_top = 3.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 3.0
	style.bg_color = Color("111c28")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("4b6174")
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	tag_label.text = label_text
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_label.add_theme_color_override("font_color", Color("cfc4a8"))
	tag_label.add_theme_font_size_override("font_size", 12)
	tag_label.add_theme_stylebox_override("normal", style)
	return tag_label


func _clear_children(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()