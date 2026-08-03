class_name RootOptionEntry
extends Control

signal pressed(entry: RootOptionEntry)

@onready var _button: Button = $Button
@onready var _name_label: Label = $Content/Layout/NameLabel
@onready var _tag_badge: PanelContainer = $Content/Layout/MetaRow/TagBadge
@onready var _tag_label: Label = $Content/Layout/MetaRow/TagBadge/TagLabel
@onready var _status_label: Label = $Content/Layout/MetaRow/StatusLabel

var preset: StartingDeckData
var is_locked := false


func _ready() -> void:
	if not _button.pressed.is_connected(_on_button_pressed):
		_button.pressed.connect(_on_button_pressed)
	if preset != null:
		configure(preset)


func configure(value: StartingDeckData, validation_error := "") -> void:
	preset = value
	is_locked = preset != null and not preset.is_unlocked
	if not is_node_ready():
		return

	if not validation_error.is_empty() or preset == null or preset.get_root_card() == null:
		_name_label.text = "INVALID PRESET"
		_tag_badge.hide()
		_status_label.hide()
		_button.disabled = true
		return

	_name_label.text = preset.display_name
	_tag_label.text = " · ".join(preset.playstyle_tags)
	_tag_badge.visible = not preset.playstyle_tags.is_empty()
	_status_label.text = "LOCKED" if is_locked else "AVAILABLE"
	_status_label.show()
	_button.disabled = false


func set_selected(value: bool) -> void:
	if not is_node_ready():
		return
	_button.button_pressed = value


func _on_button_pressed() -> void:
	pressed.emit(self)

