extends Node2D

const MAIN_MENU_SCENE := preload("res://scenes/menu.tscn")
const ROOT_SELECTION_SCENE := preload("res://scenes/home/root_selection_screen.tscn")
const GAME_MANAGER_SCENE := preload("res://scenes/game/game_manager.tscn")

@export var starting_decks: Array[StartingDeckData] = []
@export var debug_start_into_game := true
@export var debug_starting_deck: StartingDeckData

@onready var background_fill: ColorRect = $BackgroundLayer/BackgroundFill
@onready var screen_layer: CanvasLayer = $ScreenLayer

var _active_screen: Control
var _active_game: Node


func _ready() -> void:
	DisplayServer.window_set_min_size(LayoutConfig.MIN_WINDOW_SIZE)
	_fit_background_to_viewport()

	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_fit_background_to_viewport):
		viewport.size_changed.connect(_fit_background_to_viewport)
	if OS.is_debug_build() and debug_start_into_game and debug_starting_deck != null:
		_start_exploration(debug_starting_deck)
		return
	_show_main_menu()


func _show_main_menu() -> void:
	_clear_active_content()
	var menu := MAIN_MENU_SCENE.instantiate() as Control
	menu.name = "Menu"
	menu.connect("start_game_requested", _show_root_selection)
	screen_layer.add_child(menu)
	_active_screen = menu


func _show_root_selection() -> void:
	_clear_active_content()
	var screen := ROOT_SELECTION_SCENE.instantiate() as Control
	screen.name = "RootSelectionScreen"
	screen.call("configure", starting_decks)
	screen.connect("back_requested", _show_main_menu)
	screen.connect("exploration_requested", _start_exploration)
	screen_layer.add_child(screen)
	_active_screen = screen


func _start_exploration(preset: StartingDeckData) -> void:
	if preset == null or not preset.is_unlocked or not preset.validate().is_empty():
		_show_main_menu()
		return

	_clear_active_content()
	var game := GAME_MANAGER_SCENE.instantiate()
	if not game.call("configure_run", preset):
		game.free()
		_show_main_menu()
		return

	game.connect("run_initialization_failed", _on_run_initialization_failed.bind(game))
	game.connect("run_finished", _on_run_finished.bind(game))
	add_child(game)
	_active_game = game


func _clear_active_content() -> void:
	if is_instance_valid(_active_screen):
		_active_screen.queue_free()
	_active_screen = null

	if is_instance_valid(_active_game):
		_active_game.queue_free()
	_active_game = null


func _on_run_initialization_failed(_reason: String, game: Node) -> void:
	if game != _active_game:
		return
	_show_main_menu()


func _on_run_finished(game: Node) -> void:
	if game != _active_game:
		return
	_show_main_menu()


## 背景独立于 GameplayCanvas：始终覆盖当前窗口，而玩法内容仍保持等比缩放。
func _fit_background_to_viewport() -> void:
	background_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
