class_name RootOptionEntry
extends PanelContainer

signal pressed(entry: RootOptionEntry)

@onready var _button: Button = $Button

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
		_button.text = "配置无效"
		_button.disabled = true
		return

	var status := "未解锁" if is_locked else "可用"
	_button.text = "%s\n%s · %s" % [preset.display_name, ", ".join(preset.playstyle_tags), status]
	_button.disabled = false


func set_selected(value: bool) -> void:
	if not is_node_ready():
		return
	_button.button_pressed = value


func _on_button_pressed() -> void:
	pressed.emit(self)

