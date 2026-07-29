class_name BoardEvent
extends Control

signal event_selected(instance: EventInstance)

const PREVIEW_EVENT: EventData = preload("res://data/event/events/forest_wolf_event.tres")
const PREVIEW_ORIGIN := Vector2i(1, 1)
const PREVIEW_CELL_SIZE := 80

@onready var background: Panel = $Background
@onready var icon: TextureRect = $Icon
@onready var type_label: Label = $TypeLabel
@onready var name_label: Label = $NameLabel
@onready var resolved_overlay: ColorRect = $ResolvedOverlay
@onready var select_button: Button = $SelectButton

var event_instance: EventInstance
var _cell_size := 80

func setup(instance: EventInstance, cell_size: int) -> void:
	event_instance = instance
	_cell_size = cell_size
	position = Vector2(instance.origin * cell_size)
	size = Vector2(instance.get_size() * cell_size)
	custom_minimum_size = size
	if is_node_ready():
		_refresh()

func _ready() -> void:
	if event_instance == null:
		setup(PREVIEW_EVENT.create_instance(PREVIEW_ORIGIN), PREVIEW_CELL_SIZE)
	else:
		_refresh()

func _refresh() -> void:
	var data := event_instance.template if event_instance else null
	var is_resolved := event_instance != null and event_instance.is_resolved
	var style := StyleBoxFlat.new()
	style.bg_color = _get_type_color(data.event_type) if data else Color("4b5563")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	background.add_theme_stylebox_override("panel", style)
	icon.texture = data.icon if data else null
	icon.visible = icon.texture != null
	type_label.visible = not icon.visible
	type_label.text = _get_type_marker(data.event_type) if data else "?"
	name_label.text = _get_display_name(data)
	resolved_overlay.visible = is_resolved
	select_button.disabled = event_instance == null or is_resolved

func _on_select_button_pressed() -> void:
	if event_instance and not event_instance.is_resolved:
		event_selected.emit(event_instance)

func _get_type_color(event_type: EventData.EventType) -> Color:
	match event_type:
		EventData.EventType.SHOP:
			return Color("2563eb")
		EventData.EventType.TREASURE:
			return Color("d97706")
		EventData.EventType.MONSTER:
			return Color("b91c1c")
		EventData.EventType.BOSS:
			return Color("7c3aed")
	return Color("4b5563")

func _get_type_marker(event_type: EventData.EventType) -> String:
	match event_type:
		EventData.EventType.SHOP:
			return "SHOP"
		EventData.EventType.TREASURE:
			return "CHEST"
		EventData.EventType.MONSTER:
			return "ENEMY"
		EventData.EventType.BOSS:
			return "BOSS"
	return "?"

func _get_display_name(data: EventData) -> String:
	if data == null:
		return "Unbound Event"
	var monster_content := data.content as EventMonsterContent
	if monster_content and monster_content.mob and not monster_content.mob.mob_name.is_empty():
		return monster_content.mob.mob_name
	return data.event_id.replace("_", " ").capitalize()
