class_name MenuScreen
extends Panel

signal start_game_requested

@onready var _start_button: Button = $MarginContainer/Panel/BtnStart

var _transition_requested := false


func _ready() -> void:
	if not _start_button.pressed.is_connected(_on_start_button_pressed):
		_start_button.pressed.connect(_on_start_button_pressed)


func _on_start_button_pressed() -> void:
	if _transition_requested:
		return

	_transition_requested = true
	_start_button.disabled = true
	start_game_requested.emit()
