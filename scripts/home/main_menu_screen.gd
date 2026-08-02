class_name MainMenuScreen
extends Control

signal start_game_requested

@onready var _start_game_button: Button = $SafeArea/Layout/ActionBlock/StartGameButton

var _transition_requested := false


func _ready() -> void:
	if not _start_game_button.pressed.is_connected(_on_start_game_pressed):
		_start_game_button.pressed.connect(_on_start_game_pressed)
	_start_game_button.grab_focus()


func _on_start_game_pressed() -> void:
	if _transition_requested:
		return

	_transition_requested = true
	_start_game_button.disabled = true
	start_game_requested.emit()
