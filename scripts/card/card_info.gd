extends PanelContainer

const CardDetailStatSealScene = preload("res://scenes/card_view/card_detail_stat_seal.tscn")

var card_instance: CardInstance = null

@onready var meta_label: Label = $MarginContainer/Content/MetaLabel
@onready var title_label: Label = $MarginContainer/Content/TitleLabel
@onready var stats: HBoxContainer = $MarginContainer/Content/Stats
@onready var description_label: Label = $MarginContainer/Content/DescriptionLabel
@onready var tags: FlowContainer = $MarginContainer/Content/Tags


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card_instance:
		refresh_display()


func set_card(inst: CardInstance) -> void:
	card_instance = inst
	if is_node_ready():
		refresh_display()


func refresh_display() -> void:
	if not card_instance or not card_instance.card_data:
		return

	var data := card_instance.card_data
	meta_label.text = "%s · %s" % [
		CardDetailFormat.rarity_name(data.rarity),
		CardDetailFormat.card_type_name(data.card_type),
	]
	title_label.text = data.card_name
	_update_stats(data)
	_update_description(data.description)
	_update_tags(data.tags)


func _update_stats(data: CardData) -> void:
	_clear_children(stats)
	for entry in CardDetailFormat.stat_entries(data):
		var seal := CardDetailStatSealScene.instantiate() as CardDetailStatSeal
		stats.add_child(seal)
		seal.configure(entry["attribute"], entry["value"])
	stats.visible = not stats.get_child_count() == 0


func _update_description(text: String) -> void:
	var compact := CardDetailFormat.compact_description(text)
	description_label.text = compact
	description_label.visible = not compact.is_empty()


func _update_tags(card_tags: Array) -> void:
	_clear_children(tags)
	for tag in card_tags:
		tags.add_child(_create_tag_label(CardDetailFormat.tag_name(tag)))
	tags.visible = not tags.get_child_count() == 0


func _create_tag_label(label_text: String) -> Label:
	var tag_label := Label.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left = 6.0
	style.content_margin_top = 2.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 2.0
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
	tag_label.add_theme_font_size_override("font_size", 11)
	tag_label.add_theme_stylebox_override("normal", style)
	return tag_label


func _clear_children(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
