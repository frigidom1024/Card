extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/home/main_menu_screen.tscn"

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_main_menu_structure_and_single_start_request()
	quit(1 if _failure_count > 0 else 0)


func _test_main_menu_structure_and_single_start_request() -> void:
	var packed_scene := load(MAIN_MENU_SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "main menu scene loads")
	if packed_scene == null:
		return

	var menu := packed_scene.instantiate() as Control
	_expect(menu != null, "main menu scene instantiates as Control")
	if menu == null:
		return

	root.add_child(menu)
	await process_frame

	var logo := menu.get_node_or_null("SafeArea/Layout/LogoBlock/GameLogo") as Label
	var start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/StartGameButton") as Button
	var version := menu.get_node_or_null("SafeArea/Layout/FooterBlock/VersionLabel") as Label
	_expect(logo != null and logo.text == "MONOCARD", "menu exposes top logo")
	_expect(start != null and start.text == "开始游戏", "menu exposes the only action")
	_expect(version != null and not version.text.is_empty(), "menu exposes version footer")

	var calls := {"count": 0}
	_expect(menu.has_signal("start_game_requested"), "main menu exposes start_game_requested signal")
	if menu.has_signal("start_game_requested"):
		menu.connect("start_game_requested", func() -> void: calls["count"] += 1)
	if start != null:
		start.emit_signal("pressed")
		start.emit_signal("pressed")
	_expect(calls["count"] == 1 and start.disabled, "start request is emitted once and disables button")

	menu.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
